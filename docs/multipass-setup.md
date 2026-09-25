# Local setup with Multipass (macOS, Apple Silicon)

Provision the 6-VM HA cluster on a Mac using Multipass. Multipass runs **native ARM64**
Ubuntu VMs through Apple's Virtualization framework, so there's no emulation overhead.

Verified target: Apple M3 Pro, 12 cores, 36 GB RAM, macOS 26.

## Why Multipass instead of VirtualBox

VirtualBox 7.2 does run on Apple Silicon, but for a 5-node cluster it has two problems:

- **VM networking.** A fresh VirtualBox VM uses NAT, which isolates guests from each
  other — nodes can reach the internet but not their peers, so a cluster cannot form.
  You must manually create a host-only network first.
- **Provisioning.** There is no first-class cloud-init path, so each of 5 VMs needs a
  manual Ubuntu install.

Multipass gives every instance an IP on a shared bridge (`192.168.64.0/24`) where all
instances can reach each other, and takes `--cloud-init` directly.

## Resource budget

| Role | Count | CPU | RAM | Disk |
|---|---|---|---|---|
| `lb-1` | 1 | 1 | 1 GB | 10 GB |
| `cp-1..3` | 3 | 2 | 3 GB | 20 GB |
| `worker-1..2` | 2 | 2 | 2 GB | 20 GB |
| **Total** | **6** | **12** | **14 GB** | **110 GB** |

Control planes get 2 CPU because **kubeadm refuses to init with less**.

---

## Step 1 — Install Multipass

⚠️ **Run this yourself** — it installs a `.pkg` and will prompt for your macOS admin
password:

```bash
brew install --cask multipass
```

Verify:

```bash
multipass version
multipass launch 24.04 --name smoke --cpus 1 --memory 1G --disk 5G
multipass exec smoke -- uname -m     # expect: aarch64
multipass delete smoke --purge
```

## Step 2 — Provision all 6 VMs

```bash
cd ~/irshadproject
chmod +x scripts/*.sh
./scripts/provision.sh
```

This launches every VM and applies [`cloud-init/k8s-node.yaml`](../cloud-init/k8s-node.yaml)
to the 5 Kubernetes nodes, which automates all of README **Step 1**: swap off (plus the
`/etc/fstab` edit so it survives reboot), `overlay`/`br_netfilter`, the three sysctls,
containerd with `SystemdCgroup = true`, and `kubeadm`/`kubelet`/`kubectl` v1.37 pinned
with `apt-mark hold`.

Takes roughly 10–15 minutes; the script waits on `cloud-init status --wait` per node.

Confirm prep actually landed — don't trust it silently:

```bash
multipass exec cp-1 -- kubeadm version
multipass exec cp-1 -- swapon --show                                  # must print NOTHING
multipass exec cp-1 -- grep SystemdCgroup /etc/containerd/config.toml  # must be true
```

## Step 3 — Load balancer

```bash
./scripts/setup-haproxy.sh
```

Reads the live Multipass IPs, so nothing is hardcoded. It prints the exact `kubeadm init`
command with your real LB IP filled in.

> Backends show **DOWN** until `kubeadm init` runs. That's correct — there's no apiserver
> listening yet.

⚠️ **This LB is a single point of failure.** One HAProxy VM with no keepalived peer means
the control plane is HA but its *endpoint* is not. Fine for learning; for production
you'd run two LBs sharing a VRRP virtual IP (see the main README's Step 0).

## Step 4 — Build the cluster

From here, follow the main [README](../README.md) Steps 2–5, running commands inside the
VMs. Skip Step 1 — cloud-init already did it.

```bash
multipass shell cp-1
```

Use the LB IP that `setup-haproxy.sh` printed as `--control-plane-endpoint`.

## Optional — drive the cluster from macOS

Instead of `multipass shell` every time, copy the kubeconfig to your Mac:

```bash
multipass exec cp-1 -- sudo cat /etc/kubernetes/admin.conf > ~/.kube/irshadproject.conf
export KUBECONFIG=~/.kube/irshadproject.conf
kubectl get nodes
```

You already have `kubectl` installed via Homebrew. The kubeconfig's server address is the
LB IP, which is reachable from the host — so this works without extra port forwarding.

---

## Managing the VMs

```bash
multipass list                      # names, states, IPs
multipass stop  cp-1 cp-2 cp-3 worker-1 worker-2 lb-1
multipass start cp-1 cp-2 cp-3 worker-1 worker-2 lb-1
multipass shell cp-1
multipass exec cp-1 -- kubectl get nodes
```

Stop the VMs when you're done — 14 GB of RAM otherwise stays committed.

### Testing failover

The point of 3 control planes. Stop one and confirm the API still answers:

```bash
multipass stop cp-1
kubectl get nodes                   # must still work, via the LB
multipass start cp-1                # rejoins on its own
```

Stopping **two** control planes breaks etcd quorum (2 of 3 needed) and the cluster
goes read-only until one returns. That's expected behaviour, not a bug — worth doing once
so the failure mode is familiar.

### Full reset

```bash
multipass delete lb-1 cp-1 cp-2 cp-3 worker-1 worker-2 --purge
```

Then re-run `./scripts/provision.sh`. Faster and more reliable than `kubeadm reset` when
an attempt goes wrong, since it also clears leftover iptables and CNI state.

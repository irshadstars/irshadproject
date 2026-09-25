# kind vs Multipass — which to use

This repo supports both. They are not competitors; they cover different halves of the
CKA syllabus.

## Comparison

| | **kind** | **Multipass** |
|---|---|---|
| A "node" is | a Docker container | a real ARM64 VM |
| Cluster ready in | ~2 min | ~15 min |
| RAM for 5 nodes | ~4 GB | ~14 GB |
| Rebuild after breaking it | ~90 sec | ~15 min |
| 3-control-plane HA | ✅ auto-creates an HAProxy container | ✅ you build the LB yourself |
| Run `kubeadm init` / `join` yourself | ❌ kind does it internally | ✅ every step is yours |
| `journalctl -u kubelet`, `systemctl` | ⚠️ unrealistic | ✅ real systemd |
| Node reboot, swap, containerd config | ❌ not practisable | ✅ real |
| `kubeadm upgrade`, etcd backup/restore | ⚠️ partial / awkward | ✅ authentic |
| Fast kubectl + YAML drilling | ✅ excellent | fine, just slower |

## Recommendation for CKA: Multipass primary, kind as scratchpad

Not because Multipass is pleasanter — it's heavier and slower. Because of exam weighting:

- **Cluster Architecture, Installation & Configuration — ~25%**
- **Troubleshooting — ~30%**

That's roughly **55% of the exam** resting on skills kind structurally cannot teach.
`kubeadm init --upload-certs`, expired join tokens, the 2-hour certificate-key window,
etcd backup/restore, upgrading one minor version at a time, and above all **debugging a
dead kubelet through journalctl** all need a node with real systemd. In kind the node
*is* a container, so that entire layer is absent or faked.

> Re-check the current weights at the
> [CNCF CKA curriculum](https://github.com/cncf/curriculum) — they change between exam versions.

Where kind wins is the iteration loop. For Workloads, Services, and Storage practice —
"write a Deployment with a nodeSelector and a PVC" — a 90-second rebuild beats 15 minutes.
Break it, delete it, start again, at no cost.

**The split that works:**

| Use | For |
|---|---|
| **Multipass** ([setup](multipass-setup.md)) | install, upgrade, etcd, node troubleshooting. Build once, keep stopped, start when practising those. |
| **kind** ([config](../kind/ha-cluster.yaml)) | daily kubectl reps. Disposable. |

## One thing kind gets more right than people assume

kind provisions its nodes **with kubeadm**, so etcd quorum, the join flow, and
control-plane failover are genuine. Killing a control-plane container really does test
quorum:

```bash
docker stop irshadproject-control-plane
kubectl get nodes          # still works, via kind's HAProxy container
docker start irshadproject-control-plane
```

Stopping **two** of three breaks quorum and the cluster goes read-only — the same
behaviour as the Multipass cluster. What kind can't give you is the layer *below*
Kubernetes.

## Version caveat

kind pins a default node image per kind release, so its Kubernetes version may lag the
`v1.37` this repo's kubeadm docs target. Check with `kubectl version` after creating the
cluster. For version-specific practice, pin explicitly:

```bash
kind create cluster --config kind/ha-cluster.yaml --image kindest/node:v1.37.1
```

That image tag must actually exist for your kind version — verify on the
[kind releases page](https://github.com/kubernetes-sigs/kind/releases) before relying on it.

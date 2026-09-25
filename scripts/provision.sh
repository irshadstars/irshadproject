#!/usr/bin/env bash
# Launch the 6 VMs for the HA cluster: 1 load balancer + 3 control planes + 2 workers.
# Idempotent — skips any instance that already exists.
#
#   ./scripts/provision.sh
#
# Total footprint: 14 GB RAM, 110 GB disk.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLOUD_INIT="${REPO_ROOT}/cloud-init/k8s-node.yaml"
RELEASE="24.04"

command -v multipass >/dev/null || { echo "multipass not installed. brew install --cask multipass"; exit 1; }
[[ -f "$CLOUD_INIT" ]] || { echo "missing $CLOUD_INIT"; exit 1; }

exists() { multipass info "$1" >/dev/null 2>&1; }

# launch <name> <cpus> <memory> <disk> [cloud-init]
launch() {
  local name=$1 cpus=$2 mem=$3 disk=$4 ci=${5:-}
  if exists "$name"; then
    echo "==> $name already exists, skipping"
    return
  fi
  echo "==> launching $name (${cpus} cpu, ${mem} ram, ${disk} disk)"
  if [[ -n "$ci" ]]; then
    multipass launch "$RELEASE" --name "$name" --cpus "$cpus" --memory "$mem" --disk "$disk" --cloud-init "$ci"
  else
    multipass launch "$RELEASE" --name "$name" --cpus "$cpus" --memory "$mem" --disk "$disk"
  fi
}

# Load balancer: no Kubernetes components needed, just HAProxy later.
launch lb-1 1 1G 10G

# Control planes: kubeadm REQUIRES 2 CPU minimum. 3G gives etcd headroom.
for i in 1 2 3; do
  launch "cp-$i" 2 3G 20G "$CLOUD_INIT"
done

# Workers
for i in 1 2; do
  launch "worker-$i" 2 2G 20G "$CLOUD_INIT"
done

echo
echo "==> waiting for cloud-init to finish on all Kubernetes nodes"
for n in cp-1 cp-2 cp-3 worker-1 worker-2; do
  printf '    %-10s ' "$n"
  multipass exec "$n" -- cloud-init status --wait >/dev/null 2>&1 && echo "ready" || echo "CHECK MANUALLY"
done

echo
multipass list
echo
echo "Verify prep landed on a node:"
echo "  multipass exec cp-1 -- kubeadm version"
echo "  multipass exec cp-1 -- swapon --show          # must print nothing"
echo "  multipass exec cp-1 -- grep SystemdCgroup /etc/containerd/config.toml"
echo
echo "Next: ./scripts/setup-haproxy.sh"

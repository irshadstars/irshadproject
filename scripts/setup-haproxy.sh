#!/usr/bin/env bash
# Install and configure HAProxy on lb-1, fronting the three control planes on :6443.
# Reads the LIVE Multipass IPs, so nothing is hardcoded.
#
#   ./scripts/setup-haproxy.sh

set -euo pipefail

command -v multipass >/dev/null || { echo "multipass not installed"; exit 1; }

ip_of() {
  multipass info "$1" --format csv 2>/dev/null | awk -F, 'NR==2 {print $3}'
}

LB_IP=$(ip_of lb-1)
[[ -n "$LB_IP" ]] || { echo "lb-1 not found or has no IP. Run ./scripts/provision.sh first."; exit 1; }

declare -a BACKEND
for i in 1 2 3; do
  ip=$(ip_of "cp-$i")
  [[ -n "$ip" ]] || { echo "cp-$i has no IP yet"; exit 1; }
  BACKEND+=("    server cp-$i ${ip}:6443 check fall 3 rise 2")
  echo "cp-$i -> $ip"
done
echo "lb-1 -> $LB_IP"

CFG=$(cat <<EOF
global
    log /dev/log local0
    maxconn 4096

defaults
    log     global
    mode    tcp
    option  tcplog
    timeout connect 10s
    timeout client  30s
    timeout server  30s

frontend kubernetes-api
    bind *:6443
    default_backend kubernetes-controlplane

backend kubernetes-controlplane
    option tcp-check
    balance roundrobin
$(printf '%s\n' "${BACKEND[@]}")
EOF
)

echo "==> installing haproxy on lb-1"
multipass exec lb-1 -- sudo apt-get update -qq
multipass exec lb-1 -- sudo apt-get install -y -qq haproxy

echo "==> writing /etc/haproxy/haproxy.cfg"
printf '%s\n' "$CFG" | multipass exec lb-1 -- sudo tee /etc/haproxy/haproxy.cfg >/dev/null

multipass exec lb-1 -- sudo haproxy -c -f /etc/haproxy/haproxy.cfg
multipass exec lb-1 -- sudo systemctl enable --now haproxy
multipass exec lb-1 -- sudo systemctl restart haproxy

echo
echo "==> HAProxy is up on ${LB_IP}:6443"
echo
echo "Backends will show as DOWN until kubeadm init runs — that is expected."
echo
echo "Use this as your control-plane endpoint:"
echo
echo "  sudo kubeadm init \\"
echo "    --control-plane-endpoint \"${LB_IP}:6443\" \\"
echo "    --upload-certs \\"
echo "    --pod-network-cidr=10.244.0.0/16 \\"
echo "    --kubernetes-version v1.37.1"
echo
echo "Run it on cp-1:  multipass shell cp-1"

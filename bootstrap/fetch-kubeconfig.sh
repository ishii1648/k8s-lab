#!/usr/bin/env bash
# Fetches the k3s kubeconfig from the Lima VM and merges it into the host ~/.kube/config
# under the context name `k3s-lab`. The server URL is rewritten to 127.0.0.1:6443
# (which Lima forwards to the guest's k3s API).

set -euo pipefail

VM_NAME="${VM_NAME:-k3s-lab}"
CONTEXT_NAME="${CONTEXT_NAME:-k3s-lab}"
HOST_KUBECONFIG="${KUBECONFIG:-$HOME/.kube/config}"

if ! command -v limactl >/dev/null 2>&1; then
  echo "ERROR: limactl not found in PATH" >&2
  exit 1
fi

if ! limactl list --quiet | grep -qx "$VM_NAME"; then
  echo "ERROR: Lima VM '$VM_NAME' does not exist. Run 'make up' first." >&2
  exit 1
fi

tmp_kubeconfig="$(mktemp)"
trap 'rm -f "$tmp_kubeconfig"' EXIT

# Read kubeconfig from inside the VM, rewrite cluster/context/user names, and point
# the server at the host-side forwarded port.
limactl shell "$VM_NAME" -- sudo cat /etc/rancher/k3s/k3s.yaml \
  | sed \
      -e "s/: default$/: ${CONTEXT_NAME}/g" \
      -e "s/name: default$/name: ${CONTEXT_NAME}/g" \
  > "$tmp_kubeconfig"

mkdir -p "$(dirname "$HOST_KUBECONFIG")"
touch "$HOST_KUBECONFIG"

# Merge: existing entries with the same name are overwritten by the new ones.
KUBECONFIG="$HOST_KUBECONFIG:$tmp_kubeconfig" kubectl config view --flatten \
  > "${HOST_KUBECONFIG}.merged"
mv "${HOST_KUBECONFIG}.merged" "$HOST_KUBECONFIG"
chmod 600 "$HOST_KUBECONFIG"

kubectl config use-context "$CONTEXT_NAME" >/dev/null

echo "Kubeconfig merged. Current context: $(kubectl config current-context)"
kubectl get nodes

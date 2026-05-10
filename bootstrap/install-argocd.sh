#!/usr/bin/env bash
# Installs ArgoCD into the k3s cluster and applies the root Application
# (app-of-apps pattern) so the cluster begins reconciling from this Git repository.

set -euo pipefail

ARGOCD_NAMESPACE="${ARGOCD_NAMESPACE:-argocd}"
ARGOCD_VERSION="${ARGOCD_VERSION:-stable}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

require() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "ERROR: '$1' not found in PATH" >&2
    exit 1
  fi
}

require kubectl

echo "==> Verifying cluster reachability"
kubectl cluster-info >/dev/null

echo "==> Creating namespace ${ARGOCD_NAMESPACE}"
kubectl apply -f "${REPO_ROOT}/infra/argocd/namespace.yaml"

echo "==> Installing ArgoCD (${ARGOCD_VERSION})"
# Server-side apply avoids the 262144-byte limit that client-side apply hits
# on large ArgoCD CRDs (notably applicationsets.argoproj.io).
kubectl apply --server-side --force-conflicts -n "${ARGOCD_NAMESPACE}" \
  -f "https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml"

echo "==> Waiting for ArgoCD components to become available"
kubectl -n "${ARGOCD_NAMESPACE}" wait --for=condition=Available --timeout=300s \
  deployment/argocd-server \
  deployment/argocd-repo-server \
  deployment/argocd-redis \
  deployment/argocd-applicationset-controller \
  deployment/argocd-notifications-controller \
  deployment/argocd-dex-server

echo "==> Applying argocd-cmd-params-cm (server.insecure=true for Traefik TLS termination)"
kubectl apply -f "${REPO_ROOT}/infra/argocd/argocd-cmd-params-cm.yaml"
kubectl -n "${ARGOCD_NAMESPACE}" rollout restart deployment/argocd-server
kubectl -n "${ARGOCD_NAMESPACE}" rollout status  deployment/argocd-server --timeout=120s

echo "==> Applying Traefik IngressRoute for argocd.lab.local"
echo "    NOTE: requires Secret 'argocd-tls' in namespace ${ARGOCD_NAMESPACE}."
echo "          See infra/argocd/README.md for the mkcert setup."
kubectl apply -f "${REPO_ROOT}/infra/argocd/ingressroute.yaml"

echo "==> Applying root Application (app-of-apps)"
kubectl apply -f "${REPO_ROOT}/infra/root-app/root-application.yaml"

echo
echo "ArgoCD is installed. To view the admin password:"
echo "  kubectl -n ${ARGOCD_NAMESPACE} get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo"
echo
echo "Access the UI:  https://argocd.lab.local:8443  (user: admin)"
echo "  Requires: SSH tunnel up (LocalForward 8443) + argocd-tls Secret + /etc/hosts entry."
echo "  See README.md (\"ArgoCD UI\" section) for the one-time setup."

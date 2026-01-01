.PHONY: help check create-cluster delete-cluster install-gateway-api install-istio uninstall-istio status all

CLUSTER_NAME := k8s-lab
KIND_CONFIG := kind/kind-config.yaml
HELMFILE_DIR := helmfile
GATEWAY_API_VERSION := v1.2.0

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

check: ## Check prerequisites
	@./scripts/check-prerequisites.sh

create-cluster: ## Create kind cluster
	kind create cluster --config $(KIND_CONFIG)
	@echo "Waiting for cluster to be ready..."
	kubectl wait --for=condition=Ready nodes --all --timeout=120s
	@echo "Cluster $(CLUSTER_NAME) is ready!"

delete-cluster: ## Delete kind cluster
	kind delete cluster --name $(CLUSTER_NAME)

install-gateway-api: ## Install Kubernetes Gateway API CRDs
	kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/$(GATEWAY_API_VERSION)/standard-install.yaml
	@echo "Gateway API CRDs installed!"

install-istio: install-gateway-api ## Install Istio Ambient Mesh using helmfile
	cd $(HELMFILE_DIR) && helmfile sync

uninstall-istio: ## Uninstall Istio using helmfile
	cd $(HELMFILE_DIR) && helmfile destroy

status: ## Show cluster and Istio status
	@echo "=== Cluster Info ==="
	@kubectl cluster-info 2>/dev/null || echo "Cluster not running"
	@echo ""
	@echo "=== Nodes ==="
	@kubectl get nodes 2>/dev/null || echo "No nodes found"
	@echo ""
	@echo "=== Istio System ==="
	@kubectl get pods -n istio-system 2>/dev/null || echo "istio-system namespace not found"
	@echo ""
	@echo "=== ztunnel (Ambient Mode) ==="
	@kubectl get daemonset -n istio-system ztunnel 2>/dev/null || echo "ztunnel not found"
	@echo ""
	@echo "=== Istio Ingress ==="
	@kubectl get pods -n istio-ingress 2>/dev/null || echo "istio-ingress namespace not found"
	@echo ""
	@echo "=== Ingress Gateway Service ==="
	@kubectl get svc -n istio-ingress 2>/dev/null || echo "No services in istio-ingress"

all: check create-cluster install-istio status ## Run all steps

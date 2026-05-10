.PHONY: help check up kubeconfig bootstrap install-argocd status down destroy argocd-password argocd-ui all

VM_NAME       ?= k3s-lab
LIMA_TEMPLATE ?= lima/k3s.yaml

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-18s\033[0m %s\n", $$1, $$2}'

check: ## Verify host prerequisites (limactl, kubectl)
	@./scripts/check-prerequisites.sh

up: ## Start the Lima VM and provision k3s
	@if limactl list --quiet | grep -qx "$(VM_NAME)"; then \
		echo "VM '$(VM_NAME)' already exists; starting if stopped..."; \
		limactl start $(VM_NAME); \
	else \
		echo "Creating VM '$(VM_NAME)' from $(LIMA_TEMPLATE)..."; \
		limactl start --name=$(VM_NAME) --tty=false $(LIMA_TEMPLATE); \
	fi

kubeconfig: ## Merge the k3s kubeconfig into ~/.kube/config (context: k3s-lab)
	@./bootstrap/fetch-kubeconfig.sh

bootstrap: install-argocd ## Install ArgoCD and apply the root Application

install-argocd: ## Install ArgoCD into the cluster
	@./bootstrap/install-argocd.sh

status: ## Show VM, cluster, ArgoCD, and app status
	@echo "=== Lima VM ==="
	@limactl list $(VM_NAME) 2>/dev/null || echo "VM not found"
	@echo
	@echo "=== Nodes ==="
	@kubectl get nodes 2>/dev/null || echo "Cluster not reachable"
	@echo
	@echo "=== ArgoCD ==="
	@kubectl -n argocd get pods 2>/dev/null || echo "argocd namespace not found"
	@echo
	@echo "=== ArgoCD Applications ==="
	@kubectl -n argocd get applications 2>/dev/null || echo "no applications"
	@echo
	@echo "=== hello-world ==="
	@kubectl -n hello-world get all 2>/dev/null || echo "hello-world namespace not found"

argocd-password: ## Print the initial ArgoCD admin password
	@kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo

argocd-ui: ## Port-forward ArgoCD UI to https://localhost:8080
	@echo "Open https://localhost:8080  (user: admin)"
	@kubectl -n argocd port-forward svc/argocd-server 8080:443

down: ## Stop the Lima VM (keep data)
	limactl stop $(VM_NAME)

destroy: ## Delete the Lima VM (data is lost)
	limactl stop $(VM_NAME) || true
	limactl delete $(VM_NAME)

all: check up kubeconfig bootstrap status ## Run check, up, kubeconfig, bootstrap, status in order

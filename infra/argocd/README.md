# infra/argocd

ArgoCD 自身のインストールリソース。

`bootstrap/install-argocd.sh` から以下を順に適用する:

1. `namespace.yaml` (このディレクトリ)
2. ArgoCD 公式 install manifest (`https://raw.githubusercontent.com/argoproj/argo-cd/<version>/manifests/install.yaml`)
3. `infra/root-app/root-application.yaml` (root app-of-apps)

ArgoCD 自身は ArgoCD で管理しない (chicken-and-egg を避ける)。
バージョン更新は `bootstrap/install-argocd.sh` の `ARGOCD_VERSION` を上げて再実行する。

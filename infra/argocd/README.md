# infra/argocd

ArgoCD 自身のインストールリソース。

`bootstrap/install-argocd.sh` から以下を順に適用する:

1. `namespace.yaml`
2. ArgoCD 公式 install manifest (`https://raw.githubusercontent.com/argoproj/argo-cd/<version>/manifests/install.yaml`)
3. `argocd-cmd-params-cm.yaml` (server.insecure=true)
4. `ingressroute.yaml` (Traefik IngressRoute for `argocd.lab.local`)
5. `infra/root-app/root-application.yaml` (root app-of-apps)

ArgoCD 自身は ArgoCD で管理しない (chicken-and-egg を避ける)。
バージョン更新は `bootstrap/install-argocd.sh` の `ARGOCD_VERSION` を上げて再実行する。

## TLS 証明書 (`argocd-tls` Secret)

`ingressroute.yaml` は `secretName: argocd-tls` を参照する。秘密鍵を含むためリポジトリには置かず、各クライアントマシンで mkcert で発行して Secret 化する。

```fish
brew install mkcert nss
mkcert -install
mkcert -cert-file /tmp/argocd.pem -key-file /tmp/argocd-key.pem argocd.lab.local
kubectl -n argocd create secret tls argocd-tls \
  --cert=/tmp/argocd.pem --key=/tmp/argocd-key.pem \
  --dry-run=client -o yaml | kubectl apply -f -
rm /tmp/argocd*.pem
```

> Secret が無い状態で IngressRoute を apply しても Traefik はデフォルト自己署名証明書で応答してしまい警告が出る。Secret 作成後に Traefik が再読込するまで数秒待つ。

## なぜ `server.insecure: "true"` か

Traefik で TLS 終端する場合、`argocd-server` への backend 通信は HTTP のままにするのが標準。ArgoCD のデフォルト (TLS 自己署名) のままだと Traefik → argocd-server も HTTPS になり、証明書検証エラーになる。

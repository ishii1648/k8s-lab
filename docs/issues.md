# k8s-lab restructure: k3s on Lima + ArgoCD

## 背景

Mac mini M4 (24GB RAM) 上の Homelab で個人アプリを常駐運用する目的で、
従来の `kind + Istio Ambient Mesh` 構成を `k3s on Lima + ArgoCD` 構成に作り直す。

過去の検討で却下された選択肢:

- Vagrant + VirtualBox: Apple Silicon で不安定
- kind + Karpenter(kwok): kwok 偽ノードでは実アプリが動かない
- kind 単体: VM 永続化が弱く、Mac 再起動で復元の手間が大きい

採用構成:

- Lima VM × 1 (Ubuntu, 4 vCPU / 6 GB / 40 GB)
- k3s single-node (traefik / metrics-server / local-path-provisioner 同梱)
- ArgoCD HA なし最小構成、app-of-apps パターン
- ingress / TLS は今回スコープ外（後続タスク）

メモリ見積:

| 項目 | 想定 RAM |
|---|---|
| Lima VM オーバーヘッド | ~200-400 MB |
| k3s + 同梱コンポーネント | ~600-900 MB |
| ArgoCD (server / repo-server / application-controller / redis) | ~700-900 MB |
| 個人アプリ用バッファ | ~3.5-4 GB |

## 受け入れ条件

### 必須

- [ ] `make check` で `limactl` / `kubectl` の存在を確認できる
- [ ] `make up` で Lima VM が起動し、内部に k3s がインストールされる
- [ ] `make kubeconfig` で `~/.kube/config` に `k3s-lab` コンテキストが merge される
- [ ] `make bootstrap` で ArgoCD がインストールされ、root Application が適用される
- [ ] root Application が `apps/` 配下を自動 sync する (app-of-apps パターン)
- [ ] サンプルアプリ `hello-world` が ArgoCD 経由で Deploy される
- [ ] `kubectl port-forward` 経由で hello-world の echo レスポンスが確認できる
- [ ] `make down` で VM が停止する (データは残る)
- [ ] `make destroy` で VM が削除される
- [ ] README.md にセットアップ手順と運用 Tips が記載されている
- [ ] 旧 kind / Istio ファイル一式が削除されている (kind/, helmfile/)

### 非必須 (将来の追加)

- [ ] cert-manager の導入 (Let's Encrypt 用)
- [ ] ingress 構成 (traefik IngressRoute or Istio Ambient Mesh)
- [ ] ArgoCD UI 用の安定アクセス手段 (NodePort or ingress)
- [ ] バックアップ戦略 (etcd / local-path PV のスナップショット)

## 構成図

```
Mac mini (host)
  └─ Lima VM (Ubuntu, 4 vCPU / 6GB / 40GB)
     └─ k3s (single-node)
        ├─ traefik (k3s 同梱、今回は使用しない)
        ├─ metrics-server
        ├─ local-path-provisioner
        ├─ argocd (namespace: argocd)
        │  └─ root Application → apps/
        └─ apps
           └─ hello-world (echo server)
```

## ディレクトリ構成

```
k8s-lab/
├── README.md
├── Makefile                     # make up / down / bootstrap 等
├── .gitignore
├── docs/
│   └── issues.md                # 本ファイル
├── lima/
│   └── k3s.yaml                 # Lima VM 定義
├── bootstrap/
│   ├── fetch-kubeconfig.sh      # kubeconfig をホストへ merge
│   └── install-argocd.sh        # ArgoCD + root Application 適用
├── infra/
│   ├── argocd/
│   │   ├── namespace.yaml
│   │   └── install.yaml         # 公式 install.yaml の参照
│   └── root-app/
│       └── root-application.yaml
├── apps/
│   ├── README.md
│   └── hello-world/
│       ├── application.yaml
│       └── manifests/
│           ├── deployment.yaml
│           └── service.yaml
└── scripts/
    └── check-prerequisites.sh
```

## 検証手順

```fish
make check
make up
make kubeconfig
make bootstrap

# ArgoCD が hello-world を sync するまで待つ
kubectl -n argocd wait --for=condition=Synced application/root --timeout=300s
kubectl -n hello-world wait --for=condition=Available deployment/hello-world --timeout=120s

# 動作確認
kubectl -n hello-world port-forward svc/hello-world 8080:80 &
curl http://localhost:8080
# → "hello from k3s on lima" が返る

# 後片付け
make down
```

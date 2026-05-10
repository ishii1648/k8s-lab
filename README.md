# k8s-lab

Mac mini (Apple Silicon) 上で個人アプリを常駐運用する Homelab Kubernetes 環境。

- **VM**: Lima (Apple Virtualization.framework, 4 vCPU / 6 GiB / 40 GiB)
- **Cluster**: k3s single-node (traefik / metrics-server / local-path-provisioner 同梱)
- **GitOps**: ArgoCD (HA なし最小構成、app-of-apps)

## 前提条件

```fish
brew install lima kubectl
```

`make check` で確認できる。

## クイックスタート

```fish
make check        # ツール存在確認
make up           # Lima VM 起動 + k3s 自動インストール
make kubeconfig   # ~/.kube/config に k3s-lab コンテキストを merge
make bootstrap    # ArgoCD インストール + root Application 適用
make status       # 全体ステータス確認
```

`make all` は上記を順に流す。

サンプルアプリの動作確認:

```fish
kubectl -n hello-world wait --for=condition=Available deployment/hello-world --timeout=120s
kubectl -n hello-world port-forward svc/hello-world 8080:80
# 別ターミナルで
curl http://localhost:8080
# → "hello from k3s on lima"
```

## ArgoCD UI

```fish
make argocd-password   # 初期 admin パスワードを表示
make argocd-ui         # https://localhost:8080 で port-forward
```

ブラウザで `https://localhost:8080` を開き、`admin` + 上記パスワードでログイン。

## リモートマシンから kubectl する (SSH トンネル)

k3s API server は Lima の `portForwards` で `hostIP: "127.0.0.1"` に bind しているため、Mac mini ローカル以外からは直接届かない。リモートマシンから操作したい場合は以下の選択肢がある。

| 方法 | 安全性 | 手間 | 備考 |
|---|---|---|---|
| SSH トンネル | 高 (既存 sshd 経由) | 軽 | 推奨。LAN/WAN どちらでも可 |
| Lima を LAN 公開 | 中 (要 IP 制限) | 中 | `hostIP: "0.0.0.0"` に変更し TLS SAN を追加 |
| VPN (Tailscale 等) | 高 | 重 | 既に VPN を運用しているなら自然 |

以下は SSH トンネルの手順。`<Mac mini host>` は実機の到達可能なホスト名に置換する (例: Bonjour 名 / LAN IP)。

### 1. kubeconfig をリモート側に取得

```fish
scp <Mac mini host>:~/.kube/config ~/.kube/config-k3s-lab
chmod 600 ~/.kube/config-k3s-lab
```

### 2. リモート側 `~/.ssh/config` に常用エントリを追加

`Host` 名は任意のエイリアス。ここでは短く `lab-k8s` とする。

```fish
printf '%s\n' \
  '' \
  'Host lab-k8s' \
  '  HostName <Mac mini host>' \
  '  User <your user>' \
  '  LocalForward 6443 127.0.0.1:6443' \
  '  ServerAliveInterval 30' \
  '  ExitOnForwardFailure yes' \
  | tee -a ~/.ssh/config
```

### 3. トンネル起動

```fish
ssh -N lab-k8s        # フォアグラウンド (Ctrl-C で停止)
# or
ssh -fN lab-k8s       # バックグラウンド
```

### 4. kubectl 実行

```fish
set -x KUBECONFIG ~/.kube/config-k3s-lab
kubectl get nodes
```

### ローカル 6443 が他で使われている場合

`LocalForward` のホスト側ポートを別に振り、kubeconfig の `server` も合わせる:

```fish
# ~/.ssh/config の LocalForward を以下に変更
#   LocalForward 16443 127.0.0.1:6443

# kubeconfig の server を書き換え
sed -i '' 's|server: https://127.0.0.1:6443|server: https://127.0.0.1:16443|' ~/.kube/config-k3s-lab
```

## ライフサイクル

| 操作 | コマンド | 影響 |
|---|---|---|
| 一時停止 (Mac 再起動など) | `make down` | VM 停止のみ。data 保持 |
| 再開 | `make up` | 既存 VM を起動、k3s も自動再起動 |
| 完全破棄 | `make destroy` | VM とその中の全データを削除 |

## ディレクトリ構成

```
.
├── Makefile                    # 主要操作 (make help で一覧)
├── README.md
├── docs/
│   └── issues.md               # 受け入れ条件と検証手順
├── lima/
│   └── k3s.yaml                # Lima VM 定義
├── bootstrap/
│   ├── fetch-kubeconfig.sh     # kubeconfig をホストへ merge
│   └── install-argocd.sh       # ArgoCD + root Application 適用
├── infra/
│   ├── argocd/                 # ArgoCD 自身 (ArgoCD では管理しない)
│   │   ├── README.md
│   │   └── namespace.yaml
│   └── root-app/
│       └── root-application.yaml   # apps/ を再帰 sync
├── apps/
│   ├── README.md
│   └── hello-world/            # サンプル個人アプリ (echo server)
│       ├── application.yaml
│       └── manifests/
│           ├── deployment.yaml
│           └── service.yaml
└── scripts/
    └── check-prerequisites.sh
```

## 新しいアプリを追加する

1. `apps/<app-name>/manifests/` に Kubernetes リソースを置く
2. `apps/<app-name>/application.yaml` で ArgoCD Application を宣言 (`apps/hello-world/application.yaml` をコピーして書き換えるのが速い)
3. `git push` する

root Application が自動で検出して sync する。

## 設計上の判断

| 決定 | 理由 |
|---|---|
| Lima を選択 (Vagrant/VirtualBox 不採用) | Apple Silicon ネイティブで安定動作。Mac 再起動でも VM 永続化 |
| k3s 単独 (kind 不採用) | VM 永続性 + 単一バイナリの軽量さ。idle ~600-900 MB |
| Karpenter/kwok 不採用 | 個人アプリ用途ではノードオートスケール不要。kwok 偽ノードは実アプリが動かない |
| ArgoCD HA なし | 冗長化のメリットより RAM 節約を優先 |
| ingress / cert-manager なし (現時点) | 当面 `kubectl port-forward` で十分。必要になれば後追加 |

## メモリ見積

| 項目 | 想定 RAM |
|---|---|
| Lima VM オーバーヘッド | ~200-400 MB |
| k3s + 同梱コンポーネント | ~600-900 MB |
| ArgoCD (server/repo-server/application-controller/redis 等) | ~700-900 MB |
| 個人アプリ用バッファ | ~3.5-4 GB |

## トラブルシューティング

### `make up` で VM が起動しない

```fish
limactl list                         # 状態確認
limactl shell k3s-lab -- journalctl -u k3s --no-pager | tail -100
```

`vmType: vz` が動かない場合は `lima/k3s.yaml` の `vmType` を `qemu` に変更して再作成。

### kubectl が `dial tcp 127.0.0.1:6443: connect: connection refused`

VM が止まっている可能性。`make up` で起動。
それでもダメなら `limactl shell k3s-lab -- sudo systemctl status k3s` で k3s デーモンを確認。

### ArgoCD が apps を sync しない

```fish
kubectl -n argocd get applications
kubectl -n argocd describe application root
```

`repoURL` の到達性、認証 (private repo の場合は別途設定が必要) を確認する。

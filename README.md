# k8s-lab

## 前提条件

以下のツールがインストールされている必要があります：

- [kind](https://kind.sigs.k8s.io/) - Kubernetes in Docker
- [kubectl](https://kubernetes.io/docs/tasks/tools/) - Kubernetes CLI
- [helm](https://helm.sh/) - Kubernetes package manager
- [helmfile](https://helmfile.readthedocs.io/) - Declarative spec for Helm charts

### インストール（Homebrew）

```bash
brew install kind kubectl helm helmfile
```

## クイックスタート

```bash
# 前提条件の確認
make check

# クラスター作成
make create-cluster

# Istioインストール（Gateway API CRDsも自動インストール）
make install-istio

# ステータス確認
make status
```

## Ambient Meshの有効化

namespace単位でAmbient Meshを有効化します：

```bash
kubectl label namespace default istio.io/dataplane-mode=ambient
```

## ポートマッピング

| サービス | ホストポート | NodePort | 用途 |
|---------|------------|----------|------|
| HTTP    | 8080       | 30080    | Istio Ingress Gateway HTTP |
| HTTPS   | 8443       | 30443    | Istio Ingress Gateway HTTPS |
| Status  | 15021      | 30021    | Istio ヘルスチェック |

## コマンド一覧

```bash
make help              # ヘルプ表示
make check             # 前提条件確認
make create-cluster    # クラスター作成
make delete-cluster    # クラスター削除
make install-gateway-api # Gateway API CRDsインストール
make install-istio     # Istioインストール
make uninstall-istio   # Istioアンインストール
make status            # ステータス確認
make all               # 全ステップ実行
```

## ディレクトリ構造

```
k8s-lab/
├── README.md
├── Makefile
├── scripts/
│   └── check-prerequisites.sh
├── kind/
│   └── kind-config.yaml
└── helmfile/
    ├── helmfile.yaml
    └── values/
        ├── istio-base.yaml
        ├── istio-cni.yaml
        ├── istio-gateway.yaml
        ├── istiod.yaml
        └── ztunnel.yaml
```

## コンポーネント

| コンポーネント | 説明 |
|---------------|------|
| istio-base | Istio CRDs |
| istiod | コントロールプレーン（Ambient mode） |
| istio-cni | CNIプラグイン（Ambient mode必須） |
| ztunnel | L4ノードプロキシ（DaemonSet） |
| istio-ingressgateway | Ingress Gateway |

## トラブルシューティング

### ポート8080/8443が使用中の場合

他のサービスがポートを使用している場合は、`kind/kind-config.yaml`の`hostPort`を変更してください。

### Istioが起動しない場合

リソース不足の可能性があります。Docker Desktopのメモリ設定を確認してください（推奨: 8GB以上）。

### クラスターの再作成

```bash
make delete-cluster
make create-cluster
make install-istio
```

### ztunnelの確認

```bash
kubectl get daemonset -n istio-system ztunnel
kubectl logs -n istio-system -l app=ztunnel
```

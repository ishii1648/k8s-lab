# agent-telemetry

[ishii1648/agent-telemetry](https://github.com/ishii1648/agent-telemetry) のサーバ送信受け口
（[setup-server.md §4 Grafana 同居版](https://github.com/ishii1648/agent-telemetry/blob/main/docs/setup-server.md)）。

複数マシンの `agent-telemetry push` を集約する SQLite ベースのサーバと、その可視化 Grafana を
**同 Pod の sidecar として同居** させ、`ReadWriteOnce` PVC 1 個で SQLite ファイルを共有する。

## なぜ同 Pod sidecar なのか

Grafana 側 datasource は `frser-sqlite-datasource`（SQLite ファイル直読み）。
別 Deployment に分離するには RWX PVC か上流への HTTP query API 追加が必要なため、
現時点では setup-server.md §4 通りの sidecar 構成を採用する。

## 構成

| リソース | 種類 | 備考 |
|---|---|---|
| Namespace `agent-telemetry` | (ArgoCD 自動作成) | `CreateNamespace=true` |
| Secret `agent-telemetry-server-token` | **手動作成** | git にコミットしない (下記参照) |
| PVC `agent-telemetry-data` | 5Gi / `local-path` / RWO | SQLite DB + Grafana state を相乗り |
| ConfigMap `agent-telemetry-grafana-provisioning` | datasource + dashboard provider 定義 | 上流 `grafana/provisioning/` のコピー |
| ConfigMap `agent-telemetry-grafana-dashboards` | dashboard JSON 本体 | 上流 `grafana/dashboards/agent-telemetry.json` のコピー (16 KB) |
| Deployment `agent-telemetry` | replicas=1 / Recreate / 2 container | server + grafana sidecar |
| Service `agent-telemetry` | ClusterIP :8443 (ingest) / :3000 (grafana) | 外部公開は別途 IngressRoute |

## 初回セットアップ

ArgoCD が同期する前に Secret を手動作成する。Pod は Secret が無いと起動できないため、
sync で Namespace が出来てから手で `kubectl create secret` する流れ:

```fish
# 1. token 生成 (クライアント ~/.claude/agent-telemetry.toml の [server] token と同値)
set token (openssl rand -hex 32)

# 2. namespace を先に作る (ArgoCD 同期を待たずに進めたいとき)
kubectl create namespace agent-telemetry --dry-run=client -o yaml | kubectl apply -f -

# 3. Secret を作成
kubectl -n agent-telemetry create secret generic agent-telemetry-server-token \
  --from-literal=token=$token \
  --dry-run=client -o yaml | kubectl apply -f -

# 4. token をクライアント側に控える
echo $token
```

`git push` で `application.yaml` が root から sync されると、Deployment は Secret を読んで起動する。
Secret 未作成のまま sync すると Pod は `CreateContainerConfigError` で再試行するので、Secret を作れば自動復旧する。

## 動作確認

```fish
kubectl -n agent-telemetry rollout status deployment/agent-telemetry

# server 側 (ingest endpoint)
kubectl -n agent-telemetry port-forward svc/agent-telemetry 8443:8443
# 別ターミナルで
curl -k https://localhost:8443/healthz   # → ok

# grafana 側 (dashboard 閲覧)
kubectl -n agent-telemetry port-forward svc/agent-telemetry 3000:3000
open http://localhost:3000               # 匿名 Viewer 権限で開く
```

dashboard `agent-telemetry/Coding agent token 効率ダッシュボード` が provisioning から自動登録される。

## クライアント設定

リモートマシンの `~/.claude/agent-telemetry.toml` に:

```toml
[server]
endpoint = "https://telemetry.lab.local:8443"   # 後述の IngressRoute を作った場合
token    = "<上で生成した token>"
```

ローカル単独利用なら `[server]` を書かなければ従来どおり動作する (warning + exit 0)。

## 外部公開 (任意)

クラスタ内からしか push できない構成のため、Mac mini 以外から push したい場合は
argocd と同じ Traefik IngressRoute + mkcert + SSH トンネル方式で公開する:

```fish
# 証明書発行
mkcert -cert-file /tmp/telemetry.pem -key-file /tmp/telemetry-key.pem telemetry.lab.local
kubectl -n agent-telemetry create secret tls agent-telemetry-tls \
  --cert=/tmp/telemetry.pem --key=/tmp/telemetry-key.pem \
  --dry-run=client -o yaml | kubectl apply -f -
rm /tmp/telemetry*.pem
echo '127.0.0.1 telemetry.lab.local' | sudo tee -a /etc/hosts

# IngressRoute は manifests/ に追加 (ファイル例は infra/argocd/ingressroute.yaml 参照)
# SSH config の LocalForward に 8443 を追加して ssh -fN lab-k8s
```

`agent-telemetry-server` は HTTP listener なので Traefik 側で TLS 終端する点は argocd と同じ構成
（HTTP backend + `tls.secretName` で websecure entrypoint 終端）。

## ConfigMap の更新

dashboard JSON / provisioning yaml は上流リポジトリのファイルから手動コピー。
上流が更新されたら以下で同期する:

```fish
# datasource + dashboard provider
gh api repos/ishii1648/agent-telemetry/contents/grafana/provisioning/datasources/agent-telemetry-docker.yaml \
  --jq '.content' | base64 -d > /tmp/datasources.yaml
gh api repos/ishii1648/agent-telemetry/contents/grafana/provisioning/dashboards/agent-telemetry-docker.yaml \
  --jq '.content' | base64 -d > /tmp/dashboards.yaml
# → manifests/configmap-grafana-provisioning.yaml の data: 部分を差し替え

# dashboard 本体
gh api repos/ishii1648/agent-telemetry/contents/grafana/dashboards/agent-telemetry.json \
  --jq '.content' | base64 -d > /tmp/agent-telemetry.json
# → manifests/configmap-grafana-dashboards.yaml の data: 部分を差し替え
```

ConfigMap サイズ上限は etcd の 1 MiB。dashboard JSON が肥大化したら別アプローチに切り替える
（initContainer git clone / Grafana sidecar dashboards loader 等）。

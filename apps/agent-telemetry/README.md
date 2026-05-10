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
| Secret `agent-telemetry-server-token` | SopsSecret 経由で sops-secrets-operator が生成 | git に暗号化済 `secret.enc.yaml` をコミット (下記参照) |
| Secret `agent-telemetry-tls` | SopsSecret 経由 (mkcert で発行した cert/key を SOPS 暗号化) | telemetry 外部公開時のみ。`tls.enc.yaml` をコミット ([外部公開](#外部公開-任意) 参照) |
| Secret `agent-telemetry-grafana-tls` | SopsSecret 経由 (mkcert で発行した cert/key を SOPS 暗号化) | grafana 外部公開時のみ。`grafana-tls.enc.yaml` をコミット ([Grafana 外部公開](#grafana-外部公開-任意) 参照) |
| Secret `agent-telemetry-grafana-admin` | SopsSecret 経由 (admin user / password を SOPS 暗号化) | grafana 外部公開時のみ。`grafana-admin.enc.yaml` をコミット |
| PVC `agent-telemetry-data` | 5Gi / `local-path` / RWO | SQLite DB + Grafana state を相乗り |
| ConfigMap `agent-telemetry-grafana-provisioning` | datasource + dashboard provider 定義 | 上流 `grafana/provisioning/` のコピー |
| ConfigMap `agent-telemetry-grafana-dashboards` | dashboard JSON 本体 | 上流 `grafana/dashboards/agent-telemetry.json` のコピー (16 KB) |
| Deployment `agent-telemetry` | replicas=1 / Recreate / 2 container | server + grafana sidecar |
| Service `agent-telemetry` | ClusterIP :8443 (ingest) / :3000 (grafana) | 外部公開は別途 IngressRoute |

## 初回セットアップ

Secret は SOPS + age で暗号化した `SopsSecret` を git にコミットし、クラスタ内の
`sops-secrets-operator` が解読して通常の Secret を生成する。クラスタ全体の age 鍵セットアップは
ルート [README.md](../../README.md#sops--age-による-secret-管理) を参照。

このアプリ固有の手順:

```fish
# 1. テンプレを manifests/ にコピー
cp apps/agent-telemetry/secret.enc.yaml.tmpl apps/agent-telemetry/manifests/secret.enc.yaml

# 2. token を生成して埋め込む
set token (openssl rand -hex 32)
sed -i '' "s/REPLACE_WITH_OPENSSL_RAND_HEX_32/$token/" apps/agent-telemetry/manifests/secret.enc.yaml

# 3. SOPS で暗号化 (リポジトリ root の .sops.yaml に従う)
sops --encrypt --in-place apps/agent-telemetry/manifests/secret.enc.yaml

# 4. token をクライアント側に控える
echo $token

# 5. commit & push
git add apps/agent-telemetry/manifests/secret.enc.yaml
git commit -m "feat(agent-telemetry): add encrypted server token"
git push
```

push 後、ArgoCD が `SopsSecret` を sync → operator が `agent-telemetry-server-token` Secret を生成 →
Deployment が起動する。`secret.enc.yaml` が無い間は Pod が `CreateContainerConfigError` で再試行する。

## 動作確認

Pod の sync / health は ArgoCD UI (`https://argocd.lab.local:8443`) で確認する。
外部からの動作確認は [外部公開](#外部公開-任意) が完了している前提で:

```fish
curl -k https://telemetry.lab.local:8443/healthz   # → ok
```

dashboard `agent-telemetry/Coding agent token 効率ダッシュボード` は provisioning から自動登録される
(Grafana は IngressRoute から閲覧)。

## クライアント設定

リモートマシンの `~/.config/agent-telemetry/config.toml` (XDG 準拠、mode 0600 推奨) に:

```toml
[server]
endpoint = "https://telemetry.lab.local:8443"   # 後述の IngressRoute を作った場合
token    = "<上で生成した token>"
```

ローカル単独利用なら `[server]` を書かなければ従来どおり動作する (warning + exit 0)。

## 外部公開 (任意)

クラスタ内からしか push できない構成のため、Mac mini 以外から push したい場合は
argocd と同じ Traefik IngressRoute + mkcert + SSH トンネル方式で公開する。

`manifests/ingressroute.yaml` (`telemetry.lab.local` → svc:8443、`agent-telemetry-tls` で TLS 終端)
は ArgoCD が自動 sync する。TLS Secret も `manifests/tls.enc.yaml` (SopsSecret) で git 管理されるので、
クライアント側の `kubectl create` は不要。リモートクライアント側で一度だけ:

```fish
# 1. mkcert で証明書発行 (CA は -install 済み前提)
mkcert -cert-file /tmp/telemetry.pem -key-file /tmp/telemetry-key.pem telemetry.lab.local

# 2. テンプレに PEM を埋め込み → 暗号化してコミット
cp apps/agent-telemetry/tls.enc.yaml.tmpl apps/agent-telemetry/manifests/tls.enc.yaml
$EDITOR apps/agent-telemetry/manifests/tls.enc.yaml   # REPLACE_WITH_TLS_*_PEM を /tmp/telemetry*.pem の中身に置換
sops --encrypt --in-place apps/agent-telemetry/manifests/tls.enc.yaml
rm /tmp/telemetry*.pem

# 3. hostname 解決 (SSH トンネルの local 端へ寄せる)
echo '127.0.0.1 telemetry.lab.local' | sudo tee -a /etc/hosts

# 4. commit & push (ArgoCD が SopsSecret を sync → operator が agent-telemetry-tls Secret を生成)
git add apps/agent-telemetry/manifests/tls.enc.yaml
git commit -m "feat(agent-telemetry): add encrypted TLS secret"
git push

# 5. SSH トンネル (argocd と同じ LocalForward 8443 を流用するので追加設定不要)
#    ※ argocd 用に既に LocalForward 8443 127.0.0.1:8443 を入れていればそのまま使える
```

`agent-telemetry-server` は HTTP listener なので Traefik 側で TLS 終端する点は argocd と同じ構成
（HTTP backend + `tls.secretName` で websecure entrypoint 終端）。Lima portForward `443→8443` と
SSH `LocalForward 8443 127.0.0.1:8443` の組み合わせで、リモートから `https://telemetry.lab.local:8443` に到達する。

## Grafana 外部公開 (任意)

dashboard 編集や常時閲覧用に Grafana sidecar (`:3000`) を `https://grafana.lab.local:8443` で
外部公開する。telemetry と同じ Traefik :8443 + SSH `LocalForward 8443` を共有 (Host ヘッダで分岐)
するので SSH トンネルの追加設定は不要。

`manifests/ingressroute-grafana.yaml` (`grafana.lab.local` → svc:3000、`agent-telemetry-grafana-tls`
で TLS 終端) は ArgoCD が自動 sync する。匿名 Viewer (`GF_AUTH_ANONYMOUS_ENABLED=true`) は維持し、
dashboard 編集時のみ admin login を併用する構成にしてある。

リモートクライアント側で一度だけ:

```fish
# 1. mkcert で grafana 用証明書発行 (CA は -install 済み前提)
mkcert -cert-file /tmp/grafana.pem -key-file /tmp/grafana-key.pem grafana.lab.local

# 2. テンプレに PEM を埋め込み → 暗号化してコミット
cp apps/agent-telemetry/grafana-tls.enc.yaml.tmpl apps/agent-telemetry/manifests/grafana-tls.enc.yaml
$EDITOR apps/agent-telemetry/manifests/grafana-tls.enc.yaml   # REPLACE_WITH_TLS_*_PEM を /tmp/grafana*.pem の中身に置換
sops --encrypt --in-place apps/agent-telemetry/manifests/grafana-tls.enc.yaml
rm /tmp/grafana*.pem

# 3. admin password を生成 → 暗号化してコミット (1Password などに password を控える)
cp apps/agent-telemetry/grafana-admin.enc.yaml.tmpl apps/agent-telemetry/manifests/grafana-admin.enc.yaml
set pw (openssl rand -hex 24)
sed -i '' "s/REPLACE_WITH_OPENSSL_RAND_HEX_24/$pw/" apps/agent-telemetry/manifests/grafana-admin.enc.yaml
echo $pw   # 1Password に保管
sops --encrypt --in-place apps/agent-telemetry/manifests/grafana-admin.enc.yaml

# 4. hostname 解決
echo '127.0.0.1 grafana.lab.local' | sudo tee -a /etc/hosts
sudo killall -HUP mDNSResponder

# 5. commit & push (ArgoCD が SopsSecret を sync → operator が grafana-tls / grafana-admin Secret を生成)
git add apps/agent-telemetry/manifests/grafana-tls.enc.yaml apps/agent-telemetry/manifests/grafana-admin.enc.yaml
git commit -m "feat(agent-telemetry): add encrypted grafana TLS + admin secrets"
git push
```

ブラウザで `https://grafana.lab.local:8443` にアクセスすると mkcert CA で TLS 検証が通り、
匿名 Viewer として dashboard を閲覧できる。右上から `admin` / `<生成した password>` で login すれば
編集権限が得られる。

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

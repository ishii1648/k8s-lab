# Repository conventions for Claude Code

このリポジトリ全体は **ArgoCD (app-of-apps) で GitOps 管理されている**。
Claude が編集・運用する時は以下を前提にする。

## apps/ は ArgoCD が sync する領域

- root Application (`infra/root-app/root-application.yaml`) が `apps/**/application.yaml` を
  再帰的に検出して sync する。各アプリは
  `apps/<name>/application.yaml` (ArgoCD `Application`) と
  `apps/<name>/manifests/` (実 kubernetes リソース) のペアで構成する
- **`apps/` のリソースを直接 `kubectl apply` / `kubectl edit` で変更しない**。
  selfHeal が手動変更を巻き戻すので意味がない上、状態が git と乖離する。
  変更は git commit → push して ArgoCD に reconcile させる
- **動作確認は `kubectl rollout status` ではなく ArgoCD UI** (`https://argocd.lab.local:8443`)
  で sync / health を見る。read-only な `kubectl get` / `kubectl logs` / `kubectl describe` /
  `kubectl exec` は通常通り使ってよい
- 外部 HTTP 動作確認は Traefik IngressRoute + SSH トンネル経由 (`*.lab.local:8443`)。
  `kubectl port-forward` は最終手段にする

新しいアプリを追加する時は `apps/hello-world/` をテンプレに `application.yaml` + `manifests/` を
作って push するだけで root が拾う。

## Secret は平文で git に置かない

すべての Secret は SOPS + age + `sops-secrets-operator` (CRD `isindir.github.com/v1alpha3/SopsSecret`)
で管理する。

- 暗号化済ファイルは `apps/<name>/manifests/secret.enc.yaml` の命名規約 (ルートの `.sops.yaml` が
  `*.enc.yaml` を `data` / `stringData` フィールド単位で暗号化するルールを定義)
- 平文テンプレは `apps/<name>/secret.enc.yaml.tmpl` として `manifests/` の外に置く
  (ArgoCD に拾われない位置)
- 唯一手動作成が必要な Secret は `sops-secrets-operator/sops-age` (operator が解読に使う age
  private key)。これは git では管理しない
- 詳細手順: [README.md "SOPS + age による Secret 管理"](README.md#sops--age-による-secret-管理)

## ArgoCD 管理外の領域

- `infra/argocd/` `infra/root-app/` … ArgoCD 自身と root Application。
  `bootstrap/install-argocd.sh` が `kubectl apply` で入れる。**ここを変えたら手で再 apply が要る**
- `bootstrap/` `lima/` `scripts/` `Makefile` … クラスタ外の運用スクリプト

## 環境前提

- シェルは **fish** (heredoc 不可。`printf '%s\n' ... | tee` で代替する)
- クラスタは Mac mini 上の Lima VM 内 k3s 1 ノード。`make up` / `make status` / `make destroy`
- リモートマシンから kubectl する時は SSH トンネル経由 (`~/.ssh/config` の `Host lab-k8s`)

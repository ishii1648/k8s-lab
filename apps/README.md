# apps/

個人アプリの ArgoCD Application 定義置き場。

`infra/root-app/root-application.yaml` がここを再帰的に走査し、各サブディレクトリ配下の
`application.yaml` を ArgoCD Application として登録する。

## 新しいアプリを追加する

```
apps/<app-name>/
├── application.yaml         # ArgoCD Application (path は manifests/ を指す)
└── manifests/               # 実 K8s リソース
    ├── deployment.yaml
    └── service.yaml
```

`application.yaml` に最低限必要なフィールドは `apps/hello-world/application.yaml` を参照。

git push すれば root Application の自動 sync で取り込まれる。

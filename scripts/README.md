# scripts/

このリポジトリ自身のテンプレート同期と検証だけを置く。

- `sync-workflow-callers.sh`: `templates/` から自己利用用のローカル参照版を生成する。
- `check-workflow-templates.sh`: Reusable Workflow、テンプレート、個別仕様、生成結果の対応を検証する。

他リポジトリへの配布、GitHub 設定、Label Sync の起動は `hasegawa496/repo-ops` の `repos apply` が担当する。

# scripts/

手元実行用の補助スクリプトです（`bash` 前提）。

## 一覧

- `setup.sh`: 標準構成のまとめ実行（設定 → ラベル同期、引数なし）
- `setup-repo-settings.sh`: リポジトリ設定の初期化（ブランチ自動削除など、引数なし）
- `setup-label-sync.sh`: ラベル同期 workflow を導入/更新し、起動（引数なし）
- `setup-triage-project-fields.sh`: Issue トリアージ workflow を導入/更新（引数なし）
- `sync-workflow-callers.sh`: `workflow-templates/` を元に `.github/workflows/` の呼び出し側 workflow を同期
- `check-workflow-templates.sh`: `workflow-templates/` の簡易検証（ローカル参照の混在チェック、`@main` の有無など）
- `lib/common.sh`: 共通関数（`cd_repo_root`, `ensure_gh_auth`, `ensure_actions_enabled` など）

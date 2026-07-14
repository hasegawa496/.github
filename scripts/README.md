# scripts/

手元実行用の補助スクリプトです（`bash` 前提）。

## 一覧

- `setup.sh`: 標準構成のまとめ実行（設定 → Dependabot → ラベル同期 → Dependabot自動マージ、引数なし。`hasegawa496/repo-ops` の `scripts/repos apply`/`init`/`create` から呼ばれる）
- `setup-repo-settings.sh`: リポジトリ設定の初期化（ブランチ自動削除など、引数なし）
- `setup-dependabot.sh`: Dependabot 設定を導入/更新し、PR を自動マージ（引数なし）
- `setup-label-sync.sh`: ラベル同期 workflow を導入/更新し、起動（引数なし）
- `setup-triage-project-fields.sh`: Issue トリアージ workflow を導入/更新（引数なし）
- `setup-dependabot-automerge.sh`: Dependabot 自動マージ workflow を導入/更新し、PR を自動マージ（引数なし、`CI_WORKFLOW_NAME` 環境変数で監視対象の CI workflow 名を指定。既定値 `CI`）
- `sync-workflow-callers.sh`: `workflow-templates/` を元に `.github/workflows/` の呼び出し側 workflow を同期
- `check-workflow-templates.sh`: `workflow-templates/` の簡易検証（ローカル参照の混在チェック、`@v1` の有無など）
- `lib/common.sh`: 共通関数（`cd_repo_root`, `ensure_gh_auth`, `ensure_actions_enabled` など）

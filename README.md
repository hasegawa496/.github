# .github

`hasegawa496` 配下リポジトリ向けの共通資産を管理するリポジトリです。

## このリポジトリで管理するもの

- Community health files
  - `.github/ISSUE_TEMPLATE/*.yml`
  - `.github/PULL_REQUEST_TEMPLATE.md`
- ラベル定義
  - `.github/labels.yml`
  - `.github/type-labels.txt`
- Reusable Workflow
  - `.github/workflows/label-sync-reusable.yml`
  - `.github/workflows/shellcheck-reusable.yml`
  - `.github/workflows/triage-reusable.yml`
  - `.github/workflows/dependabot-automerge-reusable.yml`
- 配布テンプレート
  - `templates/.github/**`
- 自己利用の同期・検証スクリプト
  - `scripts/sync-workflow-callers.sh`
  - `scripts/check-workflow-templates.sh`
- 運用ドキュメント
  - `docs/github-workflow-operations.md`
  - `docs/reusable-workflows.md`
  - `docs/reusable-workflows/`

## 参照先

他リポジトリから Reusable Workflow を利用する場合は以下を参照します。

- `uses: hasegawa496/.github/.github/workflows/<file>-reusable.yml@main`

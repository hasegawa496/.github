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
  - `.github/workflows/label-sync-wc.yml`
  - `.github/workflows/shellcheck-wc.yml`
  - `.github/workflows/triage-wc.yml`
- 配布テンプレート
  - `workflow-templates/*.yml`
- 導入/同期スクリプト
  - `scripts/`
- 運用ドキュメント
  - `docs/github-workflow-operations.md`

## 参照先

他リポジトリから Reusable Workflow を利用する場合は以下を参照します。

- `uses: hasegawa496/.github/.github/workflows/<file>.yml@v1`

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
  - `.github/workflows/triage-reusable.yml`
  - `.github/workflows/dependabot-automerge-reusable.yml`
- composite action
  - `actions/shellcheck/action.yml`
- 配布テンプレート
  - `templates/.github/**`
- hk 共通フック設定
  - `hk/Shared.pkl`
  - 配布専用のベースモジュール。`templates/.github/**` のように配布先へコピーされるのではなく、各管理対象リポジトリの `hk.pkl` から `amends` でリモート参照される
  - `main` へのマージが即座に全リポジトリへ波及するため、内容は言語非依存の共通ルールに限定する
- 自己利用の同期・検証スクリプト
  - `scripts/sync-workflow-callers.sh`
  - `scripts/check-workflow-templates.sh`
- 運用ドキュメント
  - `docs/github-workflow-operations.md`
  - `docs/reusable-workflows.md`
  - `docs/reusable-workflows/`
  - `docs/actions/`

## 参照先

他リポジトリから Reusable Workflow を利用する場合は以下を参照します。

- `uses: hasegawa496/.github/.github/workflows/<file>-reusable.yml@main`

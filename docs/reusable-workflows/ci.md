# CI

## 目的

標準 CI として最低限 ShellCheck を実行する。マージ可否の gate ではなく、Dependabot Auto-merge の `workflow_run`（監視対象 `CI`）を必ず発火させるトリガー保証を兼ねる。マージ可否は [Dependabot Auto-merge](dependabot-automerge.md) 側の全チェック確認が判定する。

## 実行条件

`pull_request` でのみ実行する。`push: main` では発火しない（[ADR 0003](../adr/0003-consolidate-verification-into-single-job.md) 決定5）。release-please 系の workflow はこの対象外であり、main への push を起点に動く。

## 入力と権限

- 入力: なし。
- 権限: `contents: read`。

## 挙動

checkout の後、[ShellCheck composite action](../actions/shellcheck.md) を呼ぶ。`.sh` ファイルがない場合は成功として終了する。

## 位置づけ

- Reusable Workflow ではなく、配布テンプレート `templates/.github/workflows/ci.yml` のみを持つ命名規約の例外である（経緯は [ADR 0002](../adr/0002-template-distribution-and-ci-name.md)）。
- `repo-ops` の `apply` は、`name: CI` を持つ workflow が存在しないリポジトリにだけ配布する。既存の `CI` は実検証を含みリポジトリ固有になるため上書きしない（[ADR 0003](../adr/0003-consolidate-verification-into-single-job.md) 決定7）。

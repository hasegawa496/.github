# CI（ダミー）

## 目的

CI が未整備のリポジトリでも、Dependabot Auto-merge の `workflow_run`（監視対象 `CI`）を必ず発火させる。マージ可否の gate ではなく、トリガー保証である。マージ可否は [Dependabot Auto-merge](dependabot-automerge.md) 側の全チェック確認が判定する。

## 実行条件

`pull_request` と `main` への `push` で実行し、常に成功する。

## 入力と権限

- 入力: なし。
- 権限: `contents: read`。

## 位置づけ

- Reusable Workflow ではなく、配布テンプレート `templates/.github/workflows/ci.yml` のみを持つ命名規約の例外である（経緯は [ADR 0002](../adr/0002-template-distribution-and-ci-name.md)）。
- `repo-ops` の `apply` は、`name: CI` を持つ workflow が存在しないリポジトリだけに配布する。既存の `CI` はダミーで上書きしない。

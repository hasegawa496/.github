# Dependabot Auto-merge

## 目的

Dependabot が作成した PR を、head SHA 上のすべてのチェックが成功した場合だけ squash merge する。

## 実行条件

配布する `dependabot-automerge.yml` は `workflow_run` を受け取り、発火用の監視対象を `CI` に固定する。`CI` は発火のトリガーであり、マージ可否の gate ではない（[CI（ダミー）](ci.md)）。

## 入力と権限

- 入力: なし。
- 権限: `contents: write`、`pull-requests: write`、`actions: read`、`checks: read`、`statuses: read`。
- 呼び出し元は `secrets: inherit` を指定する。

## 安全条件

- 実行結果が成功で、起動者が `dependabot[bot]` の場合だけ対象にする。
- マージ前に head SHA 上のすべてのチェックを確認する。対象は Actions の workflow run、外部 CI（GitHub App）の check run、commit status で、未完了が残る間はポーリングで完結を待つ（間隔30秒、上限30分）。
- すべてのチェックが成功（check run は `success` / `neutral` / `skipped`、workflow run は `success` / `skipped`、commit status は 0 件または `success`）の場合だけマージする。失敗があればマージせず終了し、タイムアウト時は workflow を失敗させる。
- 自分自身の実行と、同名 workflow（並行する Auto-merge）の実行は完結判定から除外する。
- 全チェックを確認した head SHA と現在の PR head SHA が一致する場合だけマージする。

## 運用ノート（権限追加時の再配布）

Reusable Workflow が要求する権限（`actions: read` / `checks: read` / `statuses: read` など）を追加した場合、GITHUB_TOKEN の権限は呼び出し元テンプレート側の `permissions:` 宣言で決まり、Reusable Workflow 側では昇格できない。そのため、この権限追加は次の順で反映する。

1. `templates/.github/workflows/dependabot-automerge.yml` の権限を更新する。
2. マージ後、速やかに `repos apply` で全配布先の呼び出し側を再配布する。

再配布が完了するまでの間、配布済みの旧テンプレートを使うリポジトリでは、権限不足により automerge が失敗する（マージはしない、fail-closed）。

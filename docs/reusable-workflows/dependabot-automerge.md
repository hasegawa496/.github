# Dependabot Auto-merge

## 目的

Dependabot が作成した PR を、`CI` Workflow の成功後に squash merge する。

## 実行条件

配布する `dependabot-automerge.yml` は `workflow_run` を受け取り、監視対象を `CI` に固定する。

## 入力と権限

- 入力: なし。
- 権限: `contents: write`、`pull-requests: write`。
- 呼び出し元は `secrets: inherit` を指定する。

## 安全条件

実行結果が成功で、起動者が `dependabot[bot]` の場合だけ対象にする。CI が確認した head SHA と現在の PR head SHA が一致する場合だけマージする。

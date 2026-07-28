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
- マージ前に head SHA 上のすべてのチェックを確認する。対象は Actions の workflow run、外部 CI（GitHub App）の check run、commit status で、未完了が残る間はポーリングで完結を待つ（間隔5秒、上限はステップ先頭から45秒）。
- 待機中もランナーを保持して課金され、課金は1分未満を切り上げる。ジョブ全体が60秒以内なら追加課金は発生せず、1秒でも超えると2分になる。そのため上限は「待機ループの開始」ではなく「ステップ先頭」を起点に測り、ランナー起動と最後のマージ処理を含めても1分の枠に収まるようにしている。
- 2026-07 実測では、課金された25 run のうち24 run が40秒以内に完了しており、60秒を超えたのは1 run だけだった。上限に達した場合はマージせず失敗するので、手動でマージすればよい。
- すべてのチェックが成功（check run は `success` / `neutral` / `skipped`、workflow run は `success` / `skipped`、commit status は 0 件または `success`）の場合だけマージする。失敗があればマージせず終了し、タイムアウト時は workflow を失敗させる。
- ランナーは `ubuntu-slim` を使う。`gh` と `jq` しか使わないためである。job の `timeout-minutes` は 2 分とし、待機ループ自体が止まった場合の課金上限とする（通常は50秒前後で終わる）。
- 自分自身の実行と、同名 workflow（並行する Auto-merge）の実行は完結判定から除外する。
- 全チェックを確認した head SHA と現在の PR head SHA が一致する場合だけマージする。

## 運用ノート（権限追加時の再配布）

Reusable Workflow が要求する権限（`actions: read` / `checks: read` / `statuses: read` など）を追加した場合、GITHUB_TOKEN の権限は呼び出し元テンプレート側の `permissions:` 宣言で決まり、Reusable Workflow 側では昇格できない。そのため、この権限追加は次の順で反映する。

1. `templates/.github/workflows/dependabot-automerge.yml` の権限を更新する。
2. マージ後、速やかに `repos apply` で全配布先の呼び出し側を再配布する。

再配布が完了するまでの間、配布済みの旧テンプレートを使うリポジトリでは、権限不足により automerge が失敗する（マージはしない、fail-closed）。

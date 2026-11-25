# hk チェック

PR のマージコミットと第1親の差分を `hk check --check` で検査する。gitleaks はこの範囲のコミットを検査し、PR の途中で追加して削除した内容も対象にする。

呼び出し元は `pull_request` で起動し、`actions/checkout` でマージコミットと全履歴（`fetch-depth: 0`）を取得する。権限は `contents: read` で足りる。

`tools` には repo-ops の `hk-tool-versions.json` に基づく `ツール名@バージョン` の一覧を渡す。mise のキャッシュを利用する。

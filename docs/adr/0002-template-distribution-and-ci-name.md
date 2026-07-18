# ADR 0002: templates/ 配布と CI 名の統一

## ステータス

採用。

## 背景

Workflow ごとの setup スクリプトは配布経路、自己利用の例外、CI 名の置換を増やした。`CI_WORKFLOW_NAME` は設定元がなく、`.github` 自身だけ `ShellCheck` を直書きしていた。CI を持たないリポジトリでは Auto-merge の待機先も定義できなかった。

## 決定

- 配布対象は `templates/.github/` に置き、`repo-ops` が相対パスを保って配布する。
- `.github` 自身も配布対象とし、Reusable Workflow の参照だけをローカル参照へ変換する。
- Auto-merge は常に workflow 名 `CI` を待機する。リポジトリに `CI` がなければ成功のみ返すダミーを追加する。
- 既存の `CI` はダミーで上書きしない。Label Sync はテンプレート配布後に `repo-ops` が起動する。

## 理由

配布対象をディレクトリ構造で表すことで、Workflow の追加時に配布定義や個別 setup を増やさずに済む。CI 名を固定すれば Auto-merge にリポジトリ別の設定値を持たせる必要がない。

## 結果

- 新規登録を含む全リポジトリで CI が必ず存在する。
- 既存の検証 workflow は段階的に `CI` へ統合する。
- 配布の実行責務は `repo-ops`、資産の定義責務は `.github` になる。

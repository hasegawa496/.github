# Label Sync

## 目的

`labels.yml` を正本として、呼び出し元リポジトリの Issue ラベルを同期する。

## 実行条件

配布する `label-sync.yml` を手動実行する。

## 入力と権限

- 入力: なし。
- 権限: `contents: read`、`issues: write`。
- ラベル定義: `hasegawa496/.github/.github/labels.yml`。

## 挙動と注意点

未定義のラベルを削除する strict 同期である。残すラベルは必ず `labels.yml` に定義する。

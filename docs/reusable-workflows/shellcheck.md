# ShellCheck

## 目的

呼び出し元リポジトリの `.sh` ファイルを ShellCheck で検査する。

## 実行条件

配布する `shellcheck.yml` は pull request と `main` への push で実行する。

## 入力と権限

- 入力: なし。
- 権限: `contents: read`。

## 挙動

対象の `.sh` ファイルがない場合は成功として終了する。対象がある場合は ShellCheck の結果をそのまま返す。

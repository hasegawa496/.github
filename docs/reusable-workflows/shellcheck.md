# ShellCheck（廃止予定）

## 目的

呼び出し元リポジトリの `.sh` ファイルを ShellCheck で検査する。composite action の [ShellCheck](../actions/shellcheck.md) へ置き換え中であり、新規の配布は行わない（[ADR 0003](../adr/0003-consolidate-verification-into-single-job.md) 決定1）。

## 実行条件

配布テンプレートは削除済みである。既に配布された各リポジトリの `.github/workflows/shellcheck.yml` だけが `@main` で参照しており、それらは pull request と `main` への push で実行する。参照が残る間は本体を変更せず維持し、全リポジトリの移行完了後に削除する（同 移行手順6）。

## 入力と権限

- 入力: なし。
- 権限: `contents: read`。

## 挙動

対象の `.sh` ファイルがない場合は成功として終了する。対象がある場合は ShellCheck の結果をそのまま返す。

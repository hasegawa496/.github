# ShellCheck（composite action）

## 目的

呼び出し元ジョブの中で `.sh` ファイルを ShellCheck で検査する。CI のジョブにステップとして同居させ、ジョブ本数を増やさない（[ADR 0003](../adr/0003-consolidate-verification-into-single-job.md)）。

## 実行条件

呼び出し元ジョブの中で `uses: hasegawa496/.github/actions/shellcheck@main` を呼ぶ。checkout 済みであることが前提であり、このアクション自体は checkout を行わない。ShellCheck 本体もランナーに同梱されているため、インストールも行わない。

## 入力と権限

- 入力: なし。
- 権限: 呼び出し元ジョブの権限をそのまま使う。

## 挙動

対象の `.sh` ファイルがない場合は成功として終了する。対象がある場合は ShellCheck の結果をそのまま返す。

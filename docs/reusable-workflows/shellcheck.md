# ShellCheck

## 目的

呼び出し元リポジトリの `.sh` ファイルを ShellCheck で検査する。

## 実行条件

配布する `shellcheck.yml` は pull request と `main` への push で、`**/*.sh` または
`.github/workflows/shellcheck.yml` に変更があった場合だけ実行する。`.sh` を変更しない
変更で発火させないことで、GitHub Actions の課金分数を抑える
（`repo-ops` の `docs/github-actions-cost-governance.md` 参照）。

この path フィルタがあるため、`shellcheck.yml` は Dependabot Auto-merge の待機先である
workflow 名 `CI` には使えない。`.github` 自身を含め、`CI` は常に発火するダミー
（[CI（ダミー）](ci.md)）か各リポジトリ固有の CI が担う。

## 入力と権限

- 入力: なし。
- 権限: `contents: read`。

## 挙動

対象の `.sh` ファイルがない場合は成功として終了する。対象がある場合は ShellCheck の結果をそのまま返す。

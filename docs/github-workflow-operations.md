# GitHub Actions 運用

## 配布

`templates/.github/` が、配布先リポジトリの `.github/` に対応する正本です。`hasegawa496/repo-ops` の `repos apply`、`repos init`、`repos create` が同じ経路で配布します。差分がある場合は対象リポジトリに PR を作成してマージし、その後 Label Sync を実行します。

`.github` 自身には同じテンプレートを配布するが、Reusable Workflow の参照だけをローカル参照へ変換します。`scripts/sync-workflow-callers.sh --write` はその生成結果を更新します。

## CI と Dependabot Auto-merge

- Auto-merge の待機対象は常に workflow 名 `CI` とする。
- `CI` がないリポジトリには、成功だけを返すダミー `CI` を配置する。
- 既に `name: CI` があるリポジトリではダミーを配置せず、既存の実 CI を保持する。
- `ShellCheck`、`Rust CI`、`Test` など既存検証を `CI` に統合する作業は、対象リポジトリごとの変更として進める。

## ランナーの選び方

GitHub Actions の課金は**ジョブ単位で 1 分未満を切り上げる**（[Actions runner pricing](https://docs.github.com/en/billing/reference/actions-runner-pricing)）。
数秒で終わるジョブでも 1 分課金されるため、無料枠の消費はジョブ本数でほぼ決まる。
無料枠を超過した後は分単価が効いてくるので、軽いジョブは低コストなランナーへ寄せる。

| ランナー | 単価 | 使いどころ |
| --- | --- | --- |
| `ubuntu-slim` | $0.002/分 | `gh` / `jq` / JS action だけで完結し、数秒で終わるジョブ |
| `ubuntu-latest` | $0.006/分 | ビルド・テストなど実処理があるジョブ |

`ubuntu-slim` を選ぶ前に次を確認する。

- **ジョブ実行上限が 15 分**である。これを超える可能性があるジョブには使わない。
  待機ループを持つワークフローは、待機上限と job の `timeout-minutes` を 15 分未満に保つ
- **非特権コンテナ**で動くため、`sudo` を伴う操作や Docker-in-Docker は使えない
- 導入済みツールは限られる。`gh` / `jq` / `git` / `node` / `python` / `shellcheck` は含まれる
  （[ubuntu-slim の導入ソフトウェア一覧](https://github.com/actions/runner-images/blob/main/images/ubuntu-slim/ubuntu-slim-Readme.md)）

コスト実測の根拠は `hasegawa496/repo-ops` の `docs/github-actions-cost-analysis-2026-07.md` を参照する。

## PROJECT_TOKEN

Triage は Projects v2 を更新するため `PROJECT_TOKEN` を使う。secret の一括設定はプロジェクト運用ルートの `scripts/setup-project-token-secrets.sh` が担当し、`repos.json` の有効な全リポジトリを対象とする。`.github` も Triage を配布するため、除外は残さない。

## 変更時の確認

```bash
scripts/sync-workflow-callers.sh --write
scripts/check-workflow-templates.sh
```

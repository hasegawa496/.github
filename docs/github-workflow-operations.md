# GitHub Actions 運用

## 配布

`templates/.github/` が、配布先リポジトリの `.github/` に対応する正本です。`hasegawa496/repo-ops` の `repos apply`、`repos init`、`repos create` が同じ経路で配布します。差分がある場合は対象リポジトリに PR を作成してマージし、その後 Label Sync を実行します。

`.github` 自身には同じテンプレートを配布するが、Reusable Workflow の参照だけをローカル参照へ変換します。`scripts/sync-workflow-callers.sh --write` はその生成結果を更新します。

## CI と Dependabot Auto-merge

- Auto-merge の待機対象は常に workflow 名 `CI` とする。
- `CI` がないリポジトリには、成功だけを返すダミー `CI` を配置する。
- 既に `name: CI` があるリポジトリではダミーを配置せず、既存の実 CI を保持する。
- `ShellCheck`、`Rust CI`、`Test` など既存検証を `CI` に統合する作業は、対象リポジトリごとの変更として進める。

## PROJECT_TOKEN

Triage は Projects v2 を更新するため `PROJECT_TOKEN` を使う。secret の一括設定はプロジェクト運用ルートの `scripts/setup-project-token-secrets.sh` が担当し、`repos.json` の有効な全リポジトリを対象とする。`.github` も Triage を配布するため、除外は残さない。

## 変更時の確認

```bash
scripts/sync-workflow-callers.sh --write
scripts/check-workflow-templates.sh
```

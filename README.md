# .github

`hasegawa496` 配下のリポジトリで共通利用する、GitHub の運用テンプレートとワークフロー（ラベル同期）をまとめたリポジトリです。

## できること

- Issue テンプレートの共通化: `.github/ISSUE_TEMPLATE/`
  - `bug` / `feature` / `task` / `improvement` / `documentation`
- PR テンプレートの共通化: `.github/PULL_REQUEST_TEMPLATE.md`
- ラベル定義の共通化: `.github/labels.yml`
- ラベル同期（Reusable Workflow）: `.github/workflows/sync-labels.yml`
  - `EndBug/label-sync@v2` を使い、`.github/labels.yml` を同期元として対象リポジトリのラベルを更新します
  - `delete-other-labels: true` のため、定義外ラベルは削除して定義のみ残します
- ShellCheck（Reusable Workflow）: `.github/workflows/shellcheck.yml`
  - `scripts/*.sh` などのシェルスクリプトを静的解析します

## 使い方

### 1) Issue/PR テンプレート

このリポジトリは GitHub の特別扱いリポジトリ（`<owner>/.github`）として、`hasegawa496` 配下の各リポジトリに対する「デフォルトの community health files」を提供する用途を想定しています。

- 反映ルール（重要）
  - 各リポジトリ側に同名のファイルがある場合は、各リポジトリ側が優先されます（この repo は「デフォルト」扱い）。
  - GitHub がデフォルトとして参照するファイル種別のみが対象です（例: Issue テンプレ、PR テンプレなど）。
  - 公開範囲や組織設定によって参照挙動が変わる場合があるため、実際に適用されているかは対象リポジトリで確認してください。

### 2) ラベル同期

対象リポジトリに、`workflow-templates/sync-labels.yml` を `.github/workflows/sync-labels.yml` としてコピーして push します。
その後、対象リポジトリの Actions から手動実行（`Sync Labels`）できます。

#### もっと簡単に（スクリプトで自動 push + 自動実行）

対象リポジトリのルートで `scripts/setup-label-sync.sh` 相当のスクリプトを実行すると、
ラベル同期用 workflow を追加して push し、そのまま `workflow_dispatch` を起動できます。

- スクリプト: `scripts/setup-label-sync.sh`
- 前提: `gh`（GitHub CLI）でログイン済み、かつそのリポジトリへ push できること

例（対象リポジトリで実行）:

```bash
# 1) スクリプトを持ってくる（例: raw を取得）
curl -fsSL https://raw.githubusercontent.com/hasegawa496/.github/main/scripts/setup-label-sync.sh \
  -o /tmp/setup-label-sync.sh

# 2) 実行
# - 専用ブランチ作成 -> PR 作成 -> マージ -> Actions 起動 まで「試みます」
# - 途中で失敗した場合は理由を表示し、手動での対応を促します
bash /tmp/setup-label-sync.sh
```

### 3) ShellCheck

対象リポジトリに、`workflow-templates/shellcheck.yml` を `.github/workflows/shellcheck.yml` としてコピーして push します。
PR / push で自動的に ShellCheck が走ります。

## 変更の目安

- ラベルを追加/変更したい: `.github/labels.yml` を編集 → 対象リポジトリでラベル同期を実行
- テンプレート文言を変えたい: `.github/ISSUE_TEMPLATE/*.yml` や `.github/PULL_REQUEST_TEMPLATE.md` を編集

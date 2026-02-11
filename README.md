# .github

`hasegawa496` 配下のリポジトリで共通利用する、GitHub の運用テンプレートとワークフロー（ラベル同期）をまとめたリポジトリです。

## できること

- Issue テンプレートの共通化: `.github/ISSUE_TEMPLATE/`
  - `bug` / `feature` / `task` / `improvement` / `documentation`
  - 作成時に Project（`hasegawa496/12`）へ自動追加（権限の都合で追加されない場合があります）
  - 共通項目: 優先度 / Estimate
- PR テンプレートの共通化: `.github/PULL_REQUEST_TEMPLATE.md`
- ラベル定義の共通化: `.github/labels.yml`
- ラベル同期（Reusable Workflow）: `.github/workflows/sync-labels.yml`
  - `EndBug/label-sync@v2` を使い、`.github/labels.yml` を同期元として対象リポジトリのラベルを更新します
  - `delete-other-labels: true` のため、定義外ラベルは削除して定義のみ残します
- ShellCheck（Reusable Workflow）: `.github/workflows/shellcheck.yml`
  - `scripts/*.sh` などのシェルスクリプトを静的解析します
- Issue を Project に自動追加し、優先度/Estimate を自動設定（Reusable Workflow）: `.github/workflows/triage-project-fields.yml`
  - Issue 作成/編集をトリガに、Issue フォームの入力内容を Projects v2 のフィールドへ反映します
  - 利用テンプレ: `workflow-templates/triage-project-fields-issues.yml`

## 使い方

### 1) Issue/PR テンプレート

このリポジトリは GitHub の特別扱いリポジトリ（`<owner>/.github`）として、`hasegawa496` 配下の各リポジトリに対する「デフォルトの community health files」を提供する用途を想定しています。

- 反映ルール（重要）
  - 各リポジトリ側に同名のファイルがある場合は、各リポジトリ側が優先されます（この repo は「デフォルト」扱い）。
  - GitHub がデフォルトとして参照するファイル種別のみが対象です（例: Issue テンプレ、PR テンプレなど）。
  - 公開範囲や組織設定によって参照挙動が変わる場合があるため、実際に適用されているかは対象リポジトリで確認してください。

### 2) ラベル同期

対象リポジトリに、`workflow-templates/sync-labels-manual.yml` を `.github/workflows/sync-labels-manual.yml` としてコピーして push します。
その後、対象リポジトリの Actions から手動実行（`Sync Labels (Manual)`）できます。

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

対象リポジトリに、`workflow-templates/shellcheck-ci.yml` を `.github/workflows/shellcheck-ci.yml` としてコピーして push します。
PR / push で自動的に ShellCheck が走ります。

## 運用ルール（配置・命名）

このリポジトリは「配布元（Reusable Workflow / community health files）」と「配布先へコピーするテンプレ」を同居させています。
同名ファイルがあっても役割が異なるため、内容が似ることがあります。

- `.github/workflows/*.yml`
  - **Reusable Workflow（`on: workflow_call`）** と、このリポジトリ自身の CI を置きます。
  - 他リポジトリからは `uses: hasegawa496/.github/.github/workflows/<file>.yml@<ref>` で参照されます。
- `workflow-templates/*.yml`
  - **配布先リポジトリへコピーして使う Workflow** を置きます（`workflow_dispatch` / `pull_request` など）。
  - `uses:` でこのリポジトリの Reusable Workflow を呼び出します。

### シンボリックリンクについて

GitHub Actions / テンプレ配布の都合上、`workflow-templates/` と `.github/workflows/` の間をシンボリックリンクで共通化する運用は推奨しません。
共通化したい場合は「テンプレを生成/検証するスクリプト」で担保します。

### テンプレの同期

配布テンプレ（`workflow-templates/`）を編集した場合、このリポジトリ自身の呼び出し側 workflow（`.github/workflows/*-ci.yml` 等）は同期してズレを防ぎます。

```bash
scripts/sync-workflow-callers.sh --write
scripts/check-workflow-templates.sh
```

### 命名規則（推奨）

- ファイル名は `kebab-case.yml`（ASCII）で統一します。
- Reusable Workflow とテンプレは、対応が分かるように **同じベース名**にします。
  - 例: `.github/workflows/shellcheck.yml`（Reusable） ↔ `workflow-templates/shellcheck-ci.yml`（配布先にコピーする側）
- このリポジトリ自身の CI 用 workflow は `*-ci.yml` を付けます（例: `.github/workflows/shellcheck-ci.yml`）。
  - 配布先へコピーするテンプレも、呼び出し側は `*-ci.yml` / `*-manual.yml` のように用途が分かる名前を推奨します。

## 変更の目安

- ラベルを追加/変更したい: `.github/labels.yml` を編集 → 対象リポジトリでラベル同期を実行
- テンプレート文言を変えたい: `.github/ISSUE_TEMPLATE/*.yml` や `.github/PULL_REQUEST_TEMPLATE.md` を編集

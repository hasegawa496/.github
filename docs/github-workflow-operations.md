# GitHub運用手順（ワークフロー）

この文書は、`hasegawa496/.github` における GitHub Actions 運用の手順書です。  
**手順の正本（SSOT）** として扱います。

対象一覧（どの workflow/tool を提供しているか）は README を参照してください。

## 導入手順（配布先リポジトリ）

### 1) ラベル同期

- `workflow-templates/label-sync.yml` を配布先の `.github/workflows/label-sync.yml` として配置
- Actions から `Label Sync` を実行

自動導入する場合:

- `scripts/setup-label-sync.sh` を配布先リポジトリのルートで実行

### 2) シェルスクリプト静的解析（ShellCheck）

- `workflow-templates/shellcheck.yml` を配布先の `.github/workflows/shellcheck.yml` として配置
- PR / push で自動実行

### 3) Issueトリアージ（Projectフィールド自動設定）

- `workflow-templates/triage.yml` を配布先の `.github/workflows/triage.yml` として配置
- スクリプト導入する場合は `scripts/setup-triage-project-fields.sh` を配布先ルートで実行

## 運用ルール（配置・命名）

- `.github/workflows/*.yml`
  - Reusable Workflow（`on: workflow_call`）と、このリポジトリ自身の CI を配置
  - 他リポジトリからは `uses: hasegawa496/.github/.github/workflows/<file>.yml@main` で参照
- `workflow-templates/*.yml`
  - 配布先へコピーして使う workflow を配置
  - `uses:` で Reusable Workflow を呼び出す

### シンボリックリンクは使わない

`workflow-templates/` と `.github/workflows/` の共通化に symlink は使わず、スクリプトで同期/検証します。

### テンプレ同期

```bash
scripts/sync-workflow-callers.sh --write
scripts/check-workflow-templates.sh
```

### 変更の目安

- ラベルを追加/変更: `.github/labels.yml` を更新し、対象リポジトリでラベル同期を実行
- Issue/PR テンプレ本文: `.github/ISSUE_TEMPLATE` / `.github/PULL_REQUEST_TEMPLATE.md` を更新

# hasegawa496/.github – Agent guide

このリポジトリは GitHub の特別扱いリポジトリ（`<owner>/.github`）として、配下の各リポジトリに対する **デフォルトの community health files**（Issue/PR テンプレ等）と、再利用可能な Workflow・運用スクリプトを管理します。

## 目的

- Issue / PR テンプレートの共通化
- ラベル定義・ラベル同期（Reusable Workflow + 手動実行テンプレ）
- ShellCheck（Reusable Workflow）
- セットアップ用スクリプトの提供（主に `gh` を使う）

## ディレクトリ概要

- `.github/ISSUE_TEMPLATE/*.yml`: Issue テンプレート
- `.github/PULL_REQUEST_TEMPLATE.md`: PR テンプレート
- `.github/labels.yml`: ラベル定義（同期元）
- `.github/workflows/*.yml`: Reusable Workflow / CI
- `workflow-templates/*.yml`: 対象リポジトリにコピーして使う Workflow テンプレ
- `scripts/*.sh`, `scripts/lib/*.sh`: セットアップ/運用スクリプト（bash）

## 変更ルール（重要）

- **互換性を壊さない**: この repo のパスや workflow 名は、他リポジトリから参照される “公開 API” です。
  - 例: `.github/workflows/sync-labels.yml`、`workflow-templates/sync-labels-manual.yml`、`.github/labels.yml`
  - 変更する場合は `README.md` と `scripts/` の参照箇所も必ず更新し、移行手順を追記すること。
- **配置と役割を混同しない**:
  - `.github/workflows/` は Reusable Workflow（`on: workflow_call`）と、このリポジトリ自身の CI を置く。
  - `workflow-templates/` は「配布先リポジトリへコピーして使う workflow」を置く（`uses:` で Reusable Workflow を呼ぶ）。
  - 同名ファイルが存在しても役割が違うため、内容が似ることがある。
- **シンボリックリンクは使わない**: GitHub Actions / テンプレ配布の都合上、`workflow-templates/` と `.github/workflows/` 間の共通化に symlink は使わない（必要ならスクリプトで生成/検証する）。
- **テンプレ同期**: `workflow-templates/` を編集したら `scripts/sync-workflow-callers.sh --write` を実行し、`scripts/check-workflow-templates.sh` で検証する。
- **命名規則（推奨）**:
  - `.yml` ファイル名は `kebab-case`（ASCII）で統一する。
  - Reusable Workflow と配布テンプレは同じベース名に揃える（対応関係を明確にする）。
  - このリポジトリ自身の CI は `*-ci.yml` を付ける。
  - 配布テンプレ側の「呼び出し側 workflow」も `*-ci.yml` / `*-manual.yml` のように用途が分かる名前を推奨する。
- **ラベル同期は破壊的**: `EndBug/label-sync` の `delete-other-labels: true` により、定義外ラベルは削除されます。
  - `.github/labels.yml` の変更は影響が大きいので、追加/変更/削除を明確にすること。
- **Workflow の安全性**: permissions は最小にする。外部 Action は原則 pinned（既存方針に合わせる）。
- **スクリプトは最小依存**: `bash` + `git` + `gh` 程度を基本にし、失敗時に中途半端な状態を残さない。
  - bash は原則 `set -euo pipefail` を使う（既存スクリプトに合わせる）。

## 作業の進め方（エージェント向け）

- 変更前に参照関係を確認する: `rg` で workflow 名/パスの利用箇所（`README.md`, `scripts/`, `workflow-templates/`）を必ず洗い出す。
- 可能ならローカルで最低限の静的チェックを行う:
  - `bash -n scripts/*.sh scripts/lib/*.sh`
  - `shellcheck scripts/*.sh scripts/lib/*.sh`（インストールされていれば）

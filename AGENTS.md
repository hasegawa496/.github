# hasegawa496/.github – Agent guide

このリポジトリは `hasegawa496` 配下向けの共通資産を管理します。

## 技術スタック

- GitHub Actions Workflow: YAML
- 導入・同期・検証: Bash、GitHub CLI
- 共有 Workflow の利用側: `templates/.github/` から配布する YAML

## 構成

- `.github/workflows/*-reusable.yml`: 他リポジトリから呼び出す Reusable Workflow
- `templates/.github/**`: 配布先へコピーする設定の正本
- `.github/workflows/<用途名>.yml`: このリポジトリ自身の生成済み呼び出し側
- `docs/reusable-workflows.md`: Reusable Workflow の横断設計正本
- `docs/reusable-workflows/*.md`: 各 Reusable Workflow の個別仕様

## 管理対象

- `.github/ISSUE_TEMPLATE/*.yml`
- `.github/PULL_REQUEST_TEMPLATE.md`
- `.github/labels.yml`
- `.github/type-labels.txt`
- `.github/workflows/*-reusable.yml`（Reusable Workflow）
- `templates/.github/**`（配布テンプレ）
- `scripts/sync-workflow-callers.sh` と `scripts/check-workflow-templates.sh`
- `docs/github-workflow-operations.md`
- `docs/reusable-workflows.md`
- `docs/reusable-workflows/*.md`

## 作業ルール

- 変更は互換性を壊さない最小差分で行う。
- 回答・コメント・ログは日本語を基本とする。
- Reusable Workflow、配布テンプレート、関連文書を変更・追加・レビューするときは `reusable-workflow-maintenance` Skill を適用する。
- `templates/` を正本として変更し、自己利用の設定は `scripts/sync-workflow-callers.sh --write` で同期する。
- スクリプトを変更した場合は `bash -n` と ShellCheck を実行する。
- ファイル・ディレクトリの移動・リネームには `git mv` を使う。
- `main` へ直接コミット・push せず、変更はブランチと PR でマージする。

## Review guidelines

- GitHub 上の Codex code review のレビューコメントは日本語で記載する。
- 指摘は P0 または P1 相当の重大な問題に限定する。
- セキュリティ、データ破壊、認証・認可の欠落、既存機能を壊す挙動変更を優先して確認する。
- 変更内容に対してテスト不足、ドキュメント不足、危険な挙動変更がある場合は、P0/P1 に該当するときだけ指摘する。
- typo や書式だけの指摘は、原則としてレビューコメントにしない。
- 指摘には、問題の理由、影響範囲、再現または修正の方向を含める。問題がない場合は無理にコメントしない。

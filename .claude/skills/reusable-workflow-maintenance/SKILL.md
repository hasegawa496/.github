---
name: reusable-workflow-maintenance
description: このリポジトリの Reusable Workflow、配布テンプレート、関連文書を変更・追加・レビューするときに使う。一般的な GitHub Actions の変更だけには使わない。
---

# Reusable Workflow の保守

## 対象

`docs/reusable-workflows.md` を設計正本、`docs/reusable-workflows/<用途名>.md` を個別仕様として扱う。

対象ファイルは次の対応を維持する。

- `.github/workflows/<用途名>-reusable.yml`: 呼び出される Reusable Workflow。
- `templates/.github/workflows/<用途名>.yml`: 配布先の呼び出し側の正本。
- `.github/workflows/<用途名>.yml`: このリポジトリ自身の生成済み呼び出し側。

## 手順

1. 横断設計と対象の個別仕様を読む。
2. 呼び出される側、配布テンプレート、個別仕様を同じ変更で整合させる。
3. 配布先の参照が `@main`、このリポジトリ自身の参照がローカルパスであることを確認する。
4. `scripts/sync-workflow-callers.sh --write` を実行する。
5. `scripts/check-workflow-templates.sh` と、変更した Workflow に必要な検証を実行する。対応する配布テンプレート、自己利用の呼び出し側、個別仕様が1つずつ存在することを確認する。

## 制約

- `templates/` を配布テンプレートの正本として扱い、`.github/workflows/<用途名>.yml` を直接編集しない。
- 呼び出される側は `<用途名>-reusable.yml`、呼び出し側は `<用途名>.yml` とする。
- 変更対象に対応する個別仕様がない場合は、Workflow と同時に追加する。

# Reusable Workflow 設計

この文書は、`hasegawa496/.github` が提供する Reusable Workflow の設計正本です。個別の入出力・権限・実行条件は各 Workflow の文書を参照します。

## 目的

- 個人管理のリポジトリ群で共通 Workflow を一元管理する。
- 利用側は常に検証済みの `main` を参照し、タグ更新作業を発生させない。
- 呼び出される側と配布先の入口を、ファイル名だけで区別できるようにする。

## ファイル命名

| 種別 | パス | 役割 |
| --- | --- | --- |
| Reusable Workflow | `.github/workflows/<用途名>-reusable.yml` | `on: workflow_call` を定義し、他リポジトリから呼び出される。 |
| 配布テンプレート | `templates/.github/workflows/<用途名>.yml` | 配布先へコピーする呼び出し側の正本。 |
| このリポジトリ用の呼び出し側 | `.github/workflows/<用途名>.yml` | 配布テンプレートから生成する。このリポジトリ自身ではローカル参照を使う。 |
| 個別仕様 | `docs/reusable-workflows/<用途名>.md` | 目的、実行条件、入力、権限、失敗時の挙動を定義する。 |

`<用途名>` は利用者が識別する機能名を kebab-case で表す。`-wc` のような略語は使わない。

各 Reusable Workflow には、同じ `<用途名>` の配布テンプレート、自己利用の呼び出し側、個別仕様を1つずつ置く。`scripts/check-workflow-templates.sh` がこの対応と参照先を検証する。

## 参照方法

- 配布先は `uses: hasegawa496/.github/.github/workflows/<用途名>-reusable.yml@main` を使う。
- このリポジトリ自身の呼び出し側は `uses: ./.github/workflows/<用途名>-reusable.yml` を使う。
- `v1` や `v1.0.0` のタグは Reusable Workflow の新規配布に使わない。個人管理であり、共有 Workflow の変更はテスト後に `main` へマージする運用を採用する。
- 既存のタグは、全配布先の参照が `@main` へ移行するまで削除・付け替えしない。移行後に参照が残っていないことを確認して削除する。

## 変更手順

1. `reusable-workflow-maintenance` Skill を適用し、関連する個別仕様を確認する。
2. Reusable Workflow と配布テンプレートを変更する。
3. `scripts/sync-workflow-callers.sh --write` でこのリポジトリ用の呼び出し側を同期する。
4. `scripts/check-workflow-templates.sh` と対象 Workflow に対応する検証を実行する。
5. `repo-ops` の `apply` で配布する。既存の `CI` は保持し、存在しない場合だけダミー `CI` を配置する。

## 提供する Workflow

- [Label Sync](reusable-workflows/label-sync.md)
- [ShellCheck](reusable-workflows/shellcheck.md)
- [Triage](reusable-workflows/triage.md)
- [Dependabot Auto-merge](reusable-workflows/dependabot-automerge.md)

設計判断の経緯は [ADR 0001](adr/0001-reusable-workflow-reference-and-naming.md) と [ADR 0002](adr/0002-template-distribution-and-ci-name.md) を参照します。

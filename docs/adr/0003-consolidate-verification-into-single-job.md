# ADR 0003: 検証系ワークフローを単一ジョブへ統合する

## ステータス

提案。

## 背景

GitHub Actions の課金は**ジョブ単位で 1 分未満を切り上げる**（[Actions runner pricing](https://docs.github.com/en/billing/reference/actions-runner-pricing)）。ワークフロー単位でも実行時間比例でもない。

`hasegawa496/repo-ops` で 2026-07 の全 2,932 run のジョブを取得して実測した結果、private 16 リポジトリの課金 2,721 分に対し実処理は 935 分で、**1,786 分（66%）が切り上げによる上乗せ**だった。根拠は `hasegawa496/repo-ops` の `docs/github-actions-cost-analysis-2026-07.md` に置く。

ADR 0001 と ADR 0002 で採用した「機能ごとに Reusable Workflow を分け、`templates/` から配布する」構成は、そのまま**ジョブ本数**に直結している。Reusable Workflow は `jobs.<job_id>.uses` で呼ぶため、呼び出しごとに独立したジョブになり、切り上げが 1 回ずつ発生する。同じ検証を 2 ワークフローに分けると、実処理が合計 27 秒でも 2 分課金される。

PR への push 1 回あたりの現状のジョブ数は次のとおりである。

| リポジトリ | 現状のジョブ構成（PR 時） | ジョブ数 |
| --- | --- | --- |
| visual-caret-move | ダミー CI + Test（lint / test） + ShellCheck | 4 |
| dilemma-procyon | ダミー CI + PR タイトル検証 + PR ビルド検証 + ShellCheck | 3〜4 |
| secure-sync | ダミー CI + Rust CI + ShellCheck | 3 |
| air-innovate-site | CI（quality / bun-compat） + ShellCheck | 3 |
| ai-tools-knowledge / bright-moon-shingetsu / bright-moon-site / headless_cms / misa-player / dotclaude / repo-ops | CI + ShellCheck | 2 |
| ai-chat-platform / ai-quota-hud / dev-env-setup / my-life / win-dev-bootstrap | ダミー CI + ShellCheck | 2 |

さらに 2 点、実測で判明した無駄がある。

- **`.sh` を 1 つも持たないリポジトリでも ShellCheck が走っている。** ai-chat-platform、ai-quota-hud、bright-moon-shingetsu、bright-moon-site、misa-player、my-life、win-dev-bootstrap の 7 リポジトリは `.sh` が 0 件で、`find` して 0 件で即終了するだけのジョブに月 153 分を払っている
- **`.sh` を持つリポジトリでも、変更されるのは稀である。** 2026-07 に作成された PR 496 件のうち `.sh` を含むものは 60 件（12%）だけだった

## 決定

### 1. ShellCheck を Reusable Workflow から composite action へ移す

`.github/actions/shellcheck/action.yml` を新設し、`.github/workflows/shellcheck-reusable.yml` と配布テンプレート `templates/.github/workflows/shellcheck.yml` を廃止する。

Reusable Workflow（`jobs.<job_id>.uses`）は必ず独立したジョブになるが、composite action（`steps.uses`）は呼び出し元ジョブの中で動くため、ジョブ本数を増やさない。1 つのジョブに `uses` は 1 つしか書けず、`steps` と併用もできないため、複数の Reusable Workflow を 1 ジョブにまとめることは構造上できない。

`shellcheck` は `ubuntu-latest`（0.9.0）、`ubuntu-26.04`（0.11.0）、`ubuntu-slim`（0.9.0）のいずれにも同梱されているため、composite action ではインストール処理を持たない。現行 Reusable の `sudo apt-get install shellcheck` は到達しない死んだコードであり、`ubuntu-slim` の非特権コンテナでは失敗する。

### 2. 各リポジトリの検証を `name: CI` の単一ワークフロー・単一ジョブへ集約する

`Rust CI`、`Test`、`PR ビルド検証`、`PR タイトル検証` のように別ファイルへ分かれている検証は、`ci.yml` の同一ジョブへステップとして統合する。ADR 0002 の「既存検証を段階的に `CI` へ統合する」を、ジョブ単位まで踏み込んで確定させる。

並列実行による短縮より、切り上げ回数の削減を優先する。実測ではどのリポジトリも CI の実処理が 2 分未満であり、直列化による待ち時間の増加は許容できる。

### 3. CI を持たないリポジトリへ配布する `ci.yml` を実検証にする

現在の `run: true` のダミーを、checkout と ShellCheck composite action の呼び出しに置き換える。`.sh` が無いリポジトリでは composite action が数秒で終了するため、実質的にこれまでのダミーと同じ役割（Dependabot Auto-merge の `workflow_run` を発火させる）を果たす。

ダミー専用のワークフローを別に持たないことで、「`CI` が実検証を兼ねる」という状態に全リポジトリを揃える。

### 4. `push: main` を CI から外す

Free プランの private リポジトリでは branch protection と ruleset が使えず（ADR 0001 関連）、`main` の検証結果をマージ可否の gate に使っていない。実運用でも `main` の実行結果は確認していない。

2026-07 の実測では `main` への 524 コミットのうち 518 件が PR 経由であり、非 PR の 6 件も 4 件が `Initial commit`、1 件が初期セットアップだった。実質的な直接 push は 1 件である。直接 push の防止は `pre-push` フックへ移す（`hasegawa496/repo-ops` の Issue #74）。

除外するのは次の 2 つとする。

- release-please 系（secure-sync、visual-caret-move、dilemma-procyon）。`push: main` がリリース PR 生成の起点そのものである
- `E2E NextCloud`（secure-sync）。トリガーの要否は別途 `hasegawa496/secure-sync` の Issue #211 で判断する

### 5. `runs-on` は検証内容で選ぶ

| 検証内容 | ランナー |
| --- | --- |
| ShellCheck だけ、または `gh` / `jq` 程度 | `ubuntu-slim`（$0.002/分） |
| ビルド・テストを伴う | `ubuntu-latest`（$0.006/分） |

判断基準は `docs/github-workflow-operations.md` の「ランナーの選び方」に従う。

### 6. ガバナンスは `repos` CLI の check で担保する

`ci.yml` は実検証を含むためリポジトリ固有になり、`templates/` から配布できるのは CI を持たないリポジトリの分だけである。統合状態の維持は配布ではなく検査で担保する。

`hasegawa496/repo-ops` に `repos ci check` を追加し、次を検証する。違反は報告のみとし、自動修正はしない。

- `name: CI` の workflow が 1 つだけ存在する
- `CI` のジョブが 1 本である
- `CI` の `on:` に `push: main` が含まれない（release 系リポジトリの除外は台帳で管理する）
- `.sh` を持つリポジトリは、`CI` のジョブに ShellCheck composite action のステップを含む
- `shellcheck.yml` が残っていない

### 7. 命名と対応関係

Reusable Workflow の命名規約（ADR 0001）に、composite action の規約を追加する。

| 種別 | パス | 役割 |
| --- | --- | --- |
| composite action | `actions/<用途名>/action.yml` | 呼び出し元ジョブの中でステップとして動く |
| 個別仕様 | `docs/actions/<用途名>.md` | 目的、入力、前提を定義する |

`scripts/check-workflow-templates.sh` は、`actions/<用途名>/action.yml` に対応する `docs/actions/<用途名>.md` の存在も検証する。

## 理由

課金の単位がジョブであり、実処理の 66% が切り上げで嵩上げされている以上、削減できるのはジョブ本数だけである。ジョブを速くする施策は効果を持たない。

composite action は、共通化を維持したままジョブ本数を増やさない唯一の手段である。ShellCheck を各リポジトリへコピーすれば同じ効果は得られるが、修正が全リポジトリへ届かなくなり ADR 0001 で解決した問題が再発する。

path フィルタで `shellcheck.yml` の発火を絞る案も検討した。実測では PR の 88% が `.sh` を変更しないため月 323 分の削減が見込めるが、composite action 化（月 367 分）に対して 44 分下回るうえ、`shellcheck.yml` を独立ワークフローとして残す構成が固定される。両者は排他であり、効果が大きく将来の追加検証にも効く composite action 化を採る。

## 結果

PR への push 1 回あたりのジョブ数が全リポジトリで 1 になる。`hasegawa496/repo-ops` の実測を基準にすると、2026-07 の 2,721 分は次のように推移する見込みである。

| 段階 | 課金 |
| --- | --- |
| 現状 | 2,721 分 |
| 検証系を 1 ジョブへ統合 | 1,869 分 |
| `push: main` を削除 | 1,485 分 |
| Label Sync の起動抑制（対応済み） | 1,255 分 |

無料枠 2,000 分に対して余裕ができ、`ubuntu-slim` への移行分がさらに超過時の単価を下げる。

失うものは次のとおりである。

- **ジョブ単位の切り分けが落ちる。** ShellCheck の失敗とテストの失敗が同じジョブの中に並ぶ。ステップ名で判別する
- **並列実行が無くなる。** 実処理が 2 分未満のため実害は小さいが、将来重い検証を足す場合は分割の是非を再検討する
- **`ci.yml` がリポジトリ固有になる。** 配布では維持できないため、`repos ci check` による検査が前提になる

## 移行

一度に全リポジトリへ適用しない。`repos apply` による配布は 16 リポジトリ分の PR と CI（約 64 分）を伴うため、テンプレート変更をまとめて 1 回で行う。

1. `.github` に composite action と `docs/actions/shellcheck.md` を追加する（このリポジトリ内で完結、public のため無料）
2. `templates/.github/workflows/ci.yml` を実検証版へ差し替え、`shellcheck.yml` を配布物から削除する
3. `hasegawa496/repo-ops` に `repos ci check` を追加する
4. 利用頻度の高いリポジトリから、`ci.yml` への統合を個別 PR で行う
5. 残りのリポジトリは翌月の `repos apply` でまとめて配布・移行する

`shellcheck-reusable.yml` は、全リポジトリの移行が完了し参照が無くなったことを確認してから削除する。ADR 0001 のタグ削除と同じ手順を踏む。

## 検討した代替案

- **`shellcheck.yml` に path フィルタを追加する。** 変更量は最小だが効果が composite action 化を下回り、独立ワークフロー構成が固定されるため採用しない
- **ShellCheck を各リポジトリへ直接コピーする。** ジョブ本数は同じく 1 になるが、修正が全リポジトリへ届かず ADR 0001 の問題が再発するため採用しない
- **重い検証だけ別ジョブに残し、軽い検証を `ubuntu-slim` の別ジョブにまとめる。** ジョブを分けた時点で最低 1 分の切り上げが増えるため、同一ジョブへの統合より常に高くなる。採用しない
- **`ci.yml` を完全に配布可能な形にし、リポジトリ固有の検証を `scripts/ci.sh` へ寄せる。** 配布で維持できる利点はあるが、mise / bun / cargo / uv のセットアップとキャッシュが action に依存しており、シェルスクリプトへ移すとキャッシュを失う。採用しない

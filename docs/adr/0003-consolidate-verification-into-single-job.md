# ADR 0003: CI で動く Reusable Workflow を廃止し検証を単一ジョブへ統合する

## ステータス

採用（2026-07-29）。実装は別 Issue で行う。

## 背景

GitHub Actions の課金は**ジョブ単位で 1 分未満を切り上げる**（[Actions runner pricing](https://docs.github.com/en/billing/reference/actions-runner-pricing)）。ワークフロー単位でも実行時間比例でもない。

`hasegawa496/repo-ops` で 2026-07 の全 2,932 run のジョブを取得して実測した結果、private 16 リポジトリの課金 2,721 分に対し実処理は 935 分で、**1,786 分（66%）が切り上げによる上乗せ**だった。根拠は `hasegawa496/repo-ops` の `docs/github-actions-cost-analysis-2026-07.md` に置く。

したがってジョブを速くしても効果はほとんど無く、**PR への push 1 回あたりのジョブ本数を減らすことだけが有効**である。目標は全リポジトリで 1 本にすることとする。

その前提として外せないのが、**Reusable Workflow は構造上ジョブを共有できない**という制約である。

- Reusable Workflow は `jobs.<job_id>.uses` で呼ぶ。呼び出しごとに独立したジョブになる
- 1 つのジョブに `uses` は 1 つしか書けず、`steps` との併用もできない
- したがって複数の Reusable Workflow を 1 ジョブへまとめることはできない

現在 CI の一部として動いている Reusable Workflow は ShellCheck だけである。これが残る限り、どのリポジトリも最低 2 ジョブになる。ADR 0001 と ADR 0002 で採用した「機能ごとに Reusable Workflow を分けて配布する」構成が、そのままジョブ本数に直結している。

PR への push 1 回あたりの現状は次のとおりである。

| リポジトリ | 現状のジョブ構成（PR 時） | ジョブ数 |
| --- | --- | --- |
| visual-caret-move | ダミー CI + Test（lint / test） + ShellCheck | 4 |
| dilemma-procyon | ダミー CI + PR タイトル検証 + PR ビルド検証 + ShellCheck | 3〜4 |
| secure-sync | ダミー CI + Rust CI + ShellCheck | 3 |
| air-innovate-site | CI（quality / bun-compat） + ShellCheck | 3 |
| ai-tools-knowledge / bright-moon-shingetsu / bright-moon-site / headless_cms / misa-player / dotclaude / repo-ops | CI + ShellCheck | 2 |
| ai-chat-platform / ai-quota-hud / dev-env-setup / my-life / win-dev-bootstrap | ダミー CI + ShellCheck | 2 |

## 決定

### 1. ShellCheck の Reusable Workflow を廃止し composite action へ置き換える（前提）

`actions/shellcheck/action.yml` を新設し、`.github/workflows/shellcheck-reusable.yml` と配布テンプレート `templates/.github/workflows/shellcheck.yml` を廃止する。

composite action は `steps.uses` で使うため呼び出し元ジョブの中で動き、ジョブ本数を増やさない。1 つのジョブに何個でも並べられる。これが 1 ジョブ化の前提であり、他のすべての決定はここから派生する。

`shellcheck` は `ubuntu-latest`（0.9.0）、`ubuntu-26.04`（0.11.0）、`ubuntu-slim`（0.9.0）のいずれにも同梱されているため、composite action ではインストール処理を持たない。現行 Reusable の `sudo apt-get install shellcheck` は到達しない死んだコードであり、`ubuntu-slim` の非特権コンテナでは失敗する。

### 2. Reusable Workflow は「ジョブを共有できないもの」に限る

今後の追加時に同じ問題を繰り返さないため、使い分けの基準を定める。

| 条件 | 手段 |
| --- | --- |
| CI と同じイベント（`pull_request`）で動き、CI のジョブに同居できる | **composite action** |
| CI と別のイベントで動き、ジョブを共有できない | Reusable Workflow |

この基準により、Triage（`issues`）、Label Sync（`workflow_dispatch`）、Dependabot Auto-merge（`workflow_run`）は Reusable Workflow のまま維持する。これらは CI のジョブに同居できないため、統合しても本数は減らない。

Dependabot Auto-merge が `pull_request` ではなく `workflow_run` で CI の完了を受け取るのは、次の 2 点による。

- **待機の課金を避けられる。** CI の完了後に起動するため、チェックの完結を待つポーリングがほとんど発生しない。`pull_request` で同じことをすると CI と同時に起動し、完了までランナーを保持する待機時間がそのまま課金される
- **ワークフロー定義が常に default branch のものになる。** `pull_request` では PR head の定義で動くため、PR 側からマージ条件を書き換えられる

### 3. 各リポジトリの検証を `name: CI` の単一ワークフロー・単一ジョブへ集約する

`Rust CI`、`Test`、`PR ビルド検証`、`PR タイトル検証` のように別ファイルへ分かれている検証は、`ci.yml` の同一ジョブへステップとして統合する。ADR 0002 の「既存検証を段階的に `CI` へ統合する」を、ジョブ単位まで踏み込んで確定させる。

並列実行による短縮より、切り上げ回数の削減を優先する。実測ではどのリポジトリも CI の実処理が 2 分未満であり、直列化による待ち時間の増加は許容できる。

### 4. 配布する `ci.yml` を標準 CI にする

`run: true` のダミーを、checkout と ShellCheck composite action の呼び出しに置き換える。あわせて「ダミー CI」という位置づけをやめ、**標準 CI** とする。

切り上げ課金のため、`run: true`（数秒）でも ShellCheck composite action（数秒〜十数秒）でも課金は 1 分で変わらない。同じ課金であれば、`.sh` を後から追加したリポジトリで自動的に検証が効くほうがよい。Dependabot Auto-merge の `workflow_run` を発火させる役割はそのまま維持する。

### 5. CI を `push: main` で発火させない

CI は `pull_request` だけで発火させる。PR でグリーンだったコミットを squash merge した直後に同じ内容を再検証しており、private リポジトリでは branch protection を使わないため（[ADR-001](https://github.com/hasegawa496/repo-ops/blob/main/docs/decisions/adr-001-branch-protection-standardization.md)）、main の検証結果を gate にしている箇所は無い。

除外は release-please 系のワークフローとする。これらは main への push を起点に動くことが役割そのものである。

### 6. composite action の命名と対応関係を定める

ADR 0001 の Reusable Workflow の規約に、composite action の規約を追加する。

| 種別 | パス | 役割 |
| --- | --- | --- |
| composite action | `actions/<用途名>/action.yml` | 呼び出し元ジョブの中でステップとして動く |
| 個別仕様 | `docs/actions/<用途名>.md` | 目的、入力、前提を定義する |

`scripts/check-workflow-templates.sh` は、`actions/<用途名>/action.yml` に対応する `docs/actions/<用途名>.md` の存在も検証する。

### 7. 配布は既存リポジトリの統合状態を維持しない

`ci.yml` は実検証を含むためリポジトリ固有になる。`repos apply` / `init` / `create` は共通の配布判定を通り、`name: CI` を持つ workflow が既にあるリポジトリへは `templates/.github/workflows/ci.yml` を配布しない。既存リポジトリはすべて `CI` を持つため、事実上、標準 CI が配布されるのは新規リポジトリだけになる。

配布側に「テンプレートから消えたファイルを配布先からも消す」削除の仕組みは設けない。既存リポジトリの `shellcheck.yml` の削除と CI の統合は一度きりの移行作業であり、恒久的な機構を要さない。取りこぼしは決定 8 の検査が検出する。

### 8. 統合状態は検査で担保する

`hasegawa496/repo-ops` に `repos check` を追加し、次を検証する。違反は報告のみとし、自動修正はしない。違反は Issue として起票し、Issue 内で CI 統合 Skill を指定する。

1. `pull_request` で発火する workflow が 1 ファイルだけである
2. その workflow のジョブが 1 本である
3. その workflow の `name` が `CI` である
4. `.sh` を持つリポジトリは、CI のジョブに ShellCheck composite action のステップを含む
5. `shellcheck.yml` が残っていない
6. CI が `push: main` で発火しない（release-please 系は除外）

`repos check` は CI だけでなく、既存の `labels check` / `settings check` / `agents-review check` もまとめて実行する入口とする。巡回を 1 コマンドで済ませ、違反をまとめて起票できるようにするためである。

## 理由

課金の単位がジョブであり、実処理の 66% が切り上げで嵩上げされている以上、削減できるのはジョブ本数だけである。そして Reusable Workflow が CI の一部として残る限り、ジョブ本数は 1 にできない。決定 1 は目標達成の必要条件である。

composite action は、共通化を維持したままジョブ本数を増やさない唯一の手段である。ShellCheck を各リポジトリへコピーしても本数は 1 になるが、修正が全リポジトリへ届かなくなり ADR 0001 で解決した問題が再発する。

決定 2 は、同じ判断を将来くり返さないための基準である。「共通化したいから Reusable Workflow」ではなく「ジョブを共有できるかどうか」で選ぶ。

決定 7 と決定 8 は対になっている。統合後の `ci.yml` はリポジトリ固有になるため、配布で追随させることができない。配布に削除や更新の機構を足しても、リポジトリ固有の内容を配布で維持できない事実は変わらない。維持する手段を配布から検査へ移し、検出した違反を Skill による修正へつなぐ。

## 結果

PR への push 1 回あたりのジョブ数が全リポジトリで 1 になる。`hasegawa496/repo-ops` の実測を基準にすると、統合で 2,721 分が 1,869 分、決定 5 を加えて 1,485 分になる見込みである。

失うものは次のとおりである。

- **ジョブ単位の切り分けが落ちる。** ShellCheck の失敗とテストの失敗が同じジョブの中に並ぶ。ステップ名で判別する
- **並列実行が無くなる。** 実処理が 2 分未満のため実害は小さいが、将来重い検証を足す場合は分割の是非を再検討する
- **`ci.yml` の配布による追随が無くなる。** 既存リポジトリの統合状態は `repos check` と CI 統合 Skill で維持する
- **main への merge 後の検証が無くなる。** PR で検証済みの内容だけが main に入る前提に依存する

## 非対象

- **`runs-on` の選択。** 単価の問題である。基準は `docs/github-workflow-operations.md` の「ランナーの選び方」で確定済み
- **`.sh` を持たないリポジトリでの ShellCheck の要否。** 決定 4 により composite action が数秒で終了し、ジョブ本数にも課金にも影響しない

## 移行

1. `.github` に composite action と `docs/actions/shellcheck.md` を追加し、`scripts/check-workflow-templates.sh` を拡張する（このリポジトリ内で完結し、public のため無料）
2. `templates/.github/workflows/ci.yml` を標準 CI へ更新し、`docs/reusable-workflows/ci.md` を「標準」の位置づけへ書き換える
3. `hasegawa496/repo-ops` に `repos check` を追加する
4. CI 統合 Skill を `hasegawa496/dotclaude` に作成する
5. 検査の違反を Issue として起票し、Skill で各リポジトリの CI を目標形へ修正する。`shellcheck.yml` の削除と `push: main` の除去も同じ修正に含める
6. 全リポジトリの移行完了と参照が無いことを確認してから、`shellcheck-reusable.yml` と `templates/.github/workflows/shellcheck.yml` を削除する

最後の削除は ADR 0001 のタグ削除と同じ手順を踏む。移行途中は composite action と Reusable Workflow が併存するが、`shellcheck-reusable.yml` は変更せず残すため、未移行リポジトリの動作には影響しない。

## 検討した代替案

- **`shellcheck.yml` に path フィルタを追加する。** ジョブ本数は 2 のままで、発火回数を減らす案である。実測では PR の 88% が `.sh` を変更しないため月 323 分の削減が見込めるが、composite action 化（月 367 分）を下回るうえ、1 ジョブ化の目標には到達しない。両者は排他であり採用しない
- **ShellCheck を各リポジトリへ直接コピーする。** 本数は 1 になるが、修正が全リポジトリへ届かず ADR 0001 の問題が再発するため採用しない
- **軽い検証だけ別ジョブに残し `ubuntu-slim` を使う。** ジョブを分けた時点で最低 1 分の切り上げが増えるため、同一ジョブへの統合より常に高くなる。採用しない
- **`ci.yml` を完全に配布可能な形にし、リポジトリ固有の検証を `scripts/ci.sh` へ寄せる。** 配布で維持できる利点はあるが、mise / bun / cargo / uv のセットアップとキャッシュが action に依存しており、シェルスクリプトへ移すとキャッシュを失う。採用しない
- **配布に削除の仕組みを設ける。** `templates/` から消えたファイルを配布先からも消す案である。`shellcheck.yml` の撤去は一度きりの移行作業であり、恒久的な機構に見合わない。加えて統合後の `ci.yml` はリポジトリ固有になるため、削除機構があっても配布で統合状態を維持できるようにはならない。採用しない（決定 7・8）
- **Dependabot Auto-merge を `pull_request` トリガーへ移す。** ジョブレベルの `if:` で Dependabot 以外をスキップでき、実検証を持たないリポジトリでは `CI` 自体が不要になる。ただし実検証を持つリポジトリでは Auto-merge が CI と同時に起動し、完了までランナーを保持する待機時間が課金される。2026-07 実測では Auto-merge の課金は 25 run・28 分であり、これが各 1 分程度増える一方、削減できるのは実検証を持たない 4 リポジトリの `CI` にとどまる（決定 5 適用後で月 50 分未満）。効果が相殺されるうえ、決定 2 に挙げたワークフロー定義の出所も失うため採用しない

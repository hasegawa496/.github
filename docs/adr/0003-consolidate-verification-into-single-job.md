# ADR 0003: CI で動く Reusable Workflow を廃止し検証を単一ジョブへ統合する

## ステータス

検討中。決定 1・2（下記）は方向性として固いが、配布方法とダミー CI の扱いに未解決の論点が残る。「未解決の検討事項」節を参照。

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

`.github/actions/shellcheck/action.yml` を新設し、`.github/workflows/shellcheck-reusable.yml` と配布テンプレート `templates/.github/workflows/shellcheck.yml` を廃止する。

composite action は `steps.uses` で使うため呼び出し元ジョブの中で動き、ジョブ本数を増やさない。1 つのジョブに何個でも並べられる。これが 1 ジョブ化の前提であり、他のすべての決定はここから派生する。

`shellcheck` は `ubuntu-latest`（0.9.0）、`ubuntu-26.04`（0.11.0）、`ubuntu-slim`（0.9.0）のいずれにも同梱されているため、composite action ではインストール処理を持たない。現行 Reusable の `sudo apt-get install shellcheck` は到達しない死んだコードであり、`ubuntu-slim` の非特権コンテナでは失敗する。

### 2. Reusable Workflow は「ジョブを共有できないもの」に限る

今後の追加時に同じ問題を繰り返さないため、使い分けの基準を定める。

| 条件 | 手段 |
| --- | --- |
| CI と同じイベント（`pull_request`）で動き、CI のジョブに同居できる | **composite action** |
| CI と別のイベントで動き、ジョブを共有できない | Reusable Workflow |

この基準により、Triage（`issues`）、Label Sync（`workflow_dispatch`）、Dependabot Auto-merge（`workflow_run`）は Reusable Workflow のまま維持する。これらは CI のジョブに同居できないため、統合しても本数は減らない。

### 3. 各リポジトリの検証を `name: CI` の単一ワークフロー・単一ジョブへ集約する

`Rust CI`、`Test`、`PR ビルド検証`、`PR タイトル検証` のように別ファイルへ分かれている検証は、`ci.yml` の同一ジョブへステップとして統合する。ADR 0002 の「既存検証を段階的に `CI` へ統合する」を、ジョブ単位まで踏み込んで確定させる。

並列実行による短縮より、切り上げ回数の削減を優先する。実測ではどのリポジトリも CI の実処理が 2 分未満であり、直列化による待ち時間の増加は許容できる。

### 4. 配布する `ci.yml` のダミーを実検証にする（検討中）

現在の `run: true` を、checkout と ShellCheck composite action の呼び出しに置き換える案。`.sh` が無いリポジトリでは composite action が数秒で終了するため、これまでのダミーと同じ役割（Dependabot Auto-merge の `workflow_run` を発火させる）を果たせる見込みである。

ただしこれは「ダミー CI」という現在の位置づけ自体を変えることになる（「未解決の検討事項」B 参照）。また、この変更を全リポジトリへ行き渡らせるには配布側の削除の仕組みが要る（同 A 参照）。この 2 点が解決してから確定する。

### 5. composite action の命名と対応関係を定める

ADR 0001 の Reusable Workflow の規約に、composite action の規約を追加する。

| 種別 | パス | 役割 |
| --- | --- | --- |
| composite action | `actions/<用途名>/action.yml` | 呼び出し元ジョブの中でステップとして動く |
| 個別仕様 | `docs/actions/<用途名>.md` | 目的、入力、前提を定義する |

`scripts/check-workflow-templates.sh` は、`actions/<用途名>/action.yml` に対応する `docs/actions/<用途名>.md` の存在も検証する。

### 6. 統合状態は配布ではなく検査で担保する

`ci.yml` は実検証を含むためリポジトリ固有になり、`templates/` から配布できるのは CI を持たないリポジトリの分だけである。

`hasegawa496/repo-ops` に `repos ci check` を追加し、次を検証する。違反は報告のみとし、自動修正はしない。

- `name: CI` の workflow が 1 つだけ存在する
- `CI` のジョブが 1 本である
- `.sh` を持つリポジトリは、`CI` のジョブに ShellCheck composite action のステップを含む
- `shellcheck.yml` が残っていない

## 理由

課金の単位がジョブであり、実処理の 66% が切り上げで嵩上げされている以上、削減できるのはジョブ本数だけである。そして Reusable Workflow が CI の一部として残る限り、ジョブ本数は 1 にできない。決定 1 は目標達成の必要条件である。

composite action は、共通化を維持したままジョブ本数を増やさない唯一の手段である。ShellCheck を各リポジトリへコピーしても本数は 1 になるが、修正が全リポジトリへ届かなくなり ADR 0001 で解決した問題が再発する。

決定 2 は、同じ判断を将来くり返さないための基準である。「共通化したいから Reusable Workflow」ではなく「ジョブを共有できるかどうか」で選ぶ。

## 結果

PR への push 1 回あたりのジョブ数が全リポジトリで 1 になる。`hasegawa496/repo-ops` の実測を基準にすると、統合だけで 2,721 分が 1,869 分になる見込みである。

失うものは次のとおりである。

- **ジョブ単位の切り分けが落ちる。** ShellCheck の失敗とテストの失敗が同じジョブの中に並ぶ。ステップ名で判別する
- **並列実行が無くなる。** 実処理が 2 分未満のため実害は小さいが、将来重い検証を足す場合は分割の是非を再検討する
- **`ci.yml` がリポジトリ固有になる。** 配布では維持できないため、`repos ci check` による検査が前提になる

## 非対象

本 ADR はジョブ本数だけを対象とする。次はコスト対策ではあるがジョブ本数とは独立であり、別途決める。

- **`push: main` トリガーの削除。** 発火回数の問題であり、ジョブ本数の問題ではない
- **`runs-on` の選択。** 単価の問題である。基準は `docs/github-workflow-operations.md` の「ランナーの選び方」で確定済み
- **`.sh` を持たないリポジトリでの ShellCheck の要否。** 決定 4 により composite action が数秒で終了するため、ジョブ本数には影響しない

## 移行（暫定案、未解決の検討事項の結論待ち）

一度に全リポジトリへ適用しない見込み。`repos apply` による配布は 16 リポジトリ分の PR と CI（約 64 分）を伴うため、テンプレート変更をまとめて 1 回で行う想定である。

1. `.github` に composite action と `docs/actions/shellcheck.md` を追加し、`scripts/check-workflow-templates.sh` を拡張する（このリポジトリ内で完結、public のため無料）
2. 配布先の `shellcheck.yml` を消す仕組みを用意する（未解決の検討事項 A）
3. `templates/.github/workflows/ci.yml` の扱いを、未解決の検討事項 B・C の結論に基づいて決める
4. `hasegawa496/repo-ops` に `repos ci check` を追加する
5. 利用頻度の高いリポジトリから、`ci.yml` への統合を個別 PR で行う
6. 残りのリポジトリは翌月の `repos apply` でまとめて配布・移行する
7. 全リポジトリの移行完了と参照が無いことを確認してから `shellcheck-reusable.yml` を削除する

最後の削除は ADR 0001 のタグ削除と同じ手順を踏む。移行途中は composite action と Reusable Workflow が併存するが、`shellcheck-reusable.yml` は変更せず残すため、未移行リポジトリの動作には影響しない。

## 未解決の検討事項

以下は、この ADR の議論の中で見えているが、まだ結論を出していない。次にこの ADR を扱うときはここから続きを検討する。

### A. 配布は「削除」を扱えない

`copy_shared_templates`（`hasegawa496/repo-ops` の `src/repository_ops_cli/cli.py`）は `templates/` を走査してコピーするだけで、**削除を扱わない**。`templates/` から `shellcheck.yml` を消しても、既に配布済みの各リポジトリの `.github/workflows/shellcheck.yml` は残り続ける。

残ったままだと ShellCheck の Reusable Workflow 呼び出しが動き続け、1 ジョブ化が成立しない。1 ジョブ化には配布側に「テンプレートから消えたファイルを配布先からも消す」削除の仕組みが必須だが、その設計はまだ無い。

一度配布すると後から消すのが難しくなる懸念があるため、配布メカニズムを変える前に、この削除の仕組みを先に用意できるかを詰める必要がある。

### B. ダミー CI は「標準 CI」と呼ぶべきかもしれない

ダミー CI（`run: true`）の唯一の役割は、Dependabot Auto-merge が待つ workflow 名 `CI` を発火させることであり、中身は重要でない。決定 4 で ShellCheck composite action の呼び出しに置き換える案を挙げたが、そうなると「ダミー」ではなく実体のある標準 CI になる。

この位置づけの変更を、早い段階で Issue化すべきという指摘がある。`ci.yml` を持たないリポジトリでも「何もしない」のではなく「最低限 ShellCheck だけは検証する」という要件がもともとあったはずで、ダミー CI という命名・位置づけ自体を見直す余地がある。

### C. Dependabot Auto-merge が `workflow_run` を使う理由の裏取りが未了

auto-merge が `pull_request` ではなく `workflow_run` 経由で CI 完了を監視しているのは、Dependabot が作った PR では `GITHUB_TOKEN` が読み取り専用になるためと推測しているが、未確認である。

この前提が正しければダミー CI は構造上必要で、`.sh` も実 CI も無いリポジトリ（ai-chat-platform、ai-quota-hud、my-life、win-dev-bootstrap）は PR ごとに最低 1 分を払い続ける。

もし読み取り専用の制約が無ければ、auto-merge を `pull_request` トリガーに寄せられる可能性がある。その場合 Dependabot 以外のアクターはジョブレベルの `if:` でスキップ（＝非課金）でき、ダミー CI 自体が不要になり、上記 4 リポジトリの月あたりの課金が追加で減る。

### D. 配布可否の判断基準が未定

「実 CI を持つリポジトリへ composite action 呼び出しの 1 行をいつ・どう入れるか」の判断基準が無い。前回の分析では対象は 5 リポジトリ（ai-tools-knowledge、air-innovate-site、dotclaude、headless_cms、repo-ops）で、手動追加で足りるとしたが、リポジトリ数が増えた場合にどう判断するか（自動検出するか、`repos ci check` の失敗を起票のトリガーにするか）は決めていない。

## 検討した代替案

- **`shellcheck.yml` に path フィルタを追加する。** ジョブ本数は 2 のままで、発火回数を減らす案である。実測では PR の 88% が `.sh` を変更しないため月 323 分の削減が見込めるが、composite action 化（月 367 分）を下回るうえ、1 ジョブ化の目標には到達しない。両者は排他であり採用しない
- **ShellCheck を各リポジトリへ直接コピーする。** 本数は 1 になるが、修正が全リポジトリへ届かず ADR 0001 の問題が再発するため採用しない
- **軽い検証だけ別ジョブに残し `ubuntu-slim` を使う。** ジョブを分けた時点で最低 1 分の切り上げが増えるため、同一ジョブへの統合より常に高くなる。採用しない
- **`ci.yml` を完全に配布可能な形にし、リポジトリ固有の検証を `scripts/ci.sh` へ寄せる。** 配布で維持できる利点はあるが、mise / bun / cargo / uv のセットアップとキャッシュが action に依存しており、シェルスクリプトへ移すとキャッシュを失う。採用しない

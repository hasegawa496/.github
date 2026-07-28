# Issue Forms と Triage workflow の仕様

この文書は、`.github/ISSUE_TEMPLATE/*.yml`（Issue Forms）と `triage-reusable.yml` /
`triage.yml`（Triage workflow）の役割分担、および何を指定すると何が起きるかを
明文化した仕様書です。**この文書を仕様の正本（SSOT）** として扱います。

## 全体像

Issue の起票経路は大きく2つあります。

1. GitHub の Web UI から Issue Forms を使って起票する
2. `gh issue create` などの CLI / Skill（例: dotclaude `issue-create` Skill）で
   headless に起票する

Issue Forms の一部機能（labels / assignees / projects の自動付与）は
**Web UI 経由（Issue Forms を実際に描画して送信した場合）にのみ** 有効です。
CLI で `--body` を直接指定して起票する場合は Issue Forms を経由しないため、
これらの自動付与は発生しません。Triage workflow は、この経路差を埋めるために
「Issue 本文のテキストを読んで Project フィールドを更新する」役割を担います。

## Issue Forms（`.github/ISSUE_TEMPLATE/*.yml`）の役割

- 優先度 / Size の入力 UI（dropdown）を提供する
- `labels:` でラベル（例: `bug`）を初期付与する
- `assignees:` で担当者（`hasegawa496`）を初期付与する
- `projects:` で Project（`hasegawa496/12`）への自動追加を行う
  - **Web UI 経由の起票でのみ動作する。** CLI で `--body` を直接渡す起票では
    動作しない
- 送信されたフォームは Markdown に変換され、各項目が `### <label>` の見出しに
  なる（例: `### 優先度` の次の行に選択値が入る）

対象ファイル: `bug.yml` / `feature.yml` / `improvement.yml` / `task.yml` /
`documentation.yml`。5 種類とも `優先度` / `Size` の見出し名・選択肢は統一されている。

## Triage workflow（`triage.yml` → `triage-reusable.yml`）の役割

- トリガー: `issues: [opened, edited, reopened]`（起票経路に依存せず、Web UI /
  CLI いずれの Issue にも反応する）
- 処理:
  1. Issue 本文から `### 優先度` / `### Size` 見出し直下の最初の非空行を抽出する
  2. `優先度` は `P0`〜`P3` で始まる値（Issue Form のフル表記 `P0: 緊急` や
     短縮表記 `P0` のいずれでも可）を、Project の実際の選択肢名である
     `P0`〜`P3` に正規化する。`未定` はそのまま扱う（Project 側に対応する
     選択肢が無いため、後述のフォールバックコメントになる）。Issue Form からは
     `未定` を削除済みだが、削除前に起票された既存 Issue の本文には残るため、
     workflow 側の扱いは変更していない
  3. `Size` は大文字に正規化する（`m` → `M`）
  4. Project（`project_number` input、既定 12）に Issue を追加する
     - 既に Project に追加済みの item があればそれを再利用し、二重追加はしない
  5. Project の `Priority` / `Size` フィールド（Single select）に、正規化できた値**だけ**を
     独立して設定する。優先度/Size は互いに独立に扱い、片方しか取得できない場合
     （見出しが無い・値が空・選択肢に一致しない・フィールド名が不一致など）でも、
     もう片方が取得できていればそちらだけは設定する
     - Project 12 の実際のフィールド名は `Priority`（`優先度` ではない。英語の
       既定フィールド名のまま運用している）。選択肢名: `P0`〜`P3`（`未定` に対応する
       選択肢は無いことを確認済み。#27）、Size = `XS`/`S`/`M`/`L`/`XL`
     - Issue Form の優先度 dropdown は `P0: 緊急`〜`P3: 低` の4択で、既定値は
       `P2: 中`（index 2）。`未定` は #27 で既定から外したうえで選択肢としては
       残していたが、明示的に選ぶとフォールバックコメントが付くだけで
       Project フィールドは空のままになるため、#55 で選択肢からも削除した。
       優先度が定まっていない状態は Project フィールドを空にすることで表す
     - Issue Form の dropdown 表示テキスト（`P0: 緊急` 等）はあくまで Issue 本文
       上の表記であり、Project 側の選択肢名とは異なる。混同しないこと
- 失敗時の挙動: **ハード失敗せず、Issue にフォールバックコメントを付けて
  `exit 0` で正常終了する。** Project への追加（4.）は優先度/Size の取得成否に
  関係なく独立して実行する。優先度/Size のフィールド更新（5.）は互いに独立で、
  一方が設定できない事情があってももう一方は設定を試みる。
  想定される失敗パターンと対応するコメント:
  - `PROJECT_TOKEN` シークレット未設定 → 「トークンが未設定です」
  - Project 取得失敗（owner/number 不一致） → 「Project の取得に失敗しました」
  - Project 追加の API 呼び出し失敗（権限不足など） → 「Project に追加できませんでした」
  - 優先度/Size の一方または両方が未取得・選択肢不一致・フィールド名不一致・
    API 呼び出し失敗 → 「Project への追加は完了していますが、一部フィールドは
    自動設定できませんでした」に、設定できなかったフィールドごとの理由を列挙する
    （設定できたフィールドがあれば、そちらは通常どおり設定済みでコメントは付かない）

### ランナー

`ubuntu-slim` を使う。`gh` と `jq` しか使わず、実処理は数秒で終わるためである。
private リポジトリで無料枠を超過した場合の単価が `ubuntu-latest` の $0.006/分 に対し
$0.002/分 になる。詳細は [ランナーの選び方](../github-workflow-operations.md#ランナーの選び方) を参照する。

### 必要な secret

- `PROJECT_TOKEN`: Projects v2 への書き込み権限を持つトークン（PAT など）。
  リポジトリ単位の Secret として設定する。未設定でもワークフロー自体は失敗せず、
  その旨のコメントが Issue に付く。
  - **スコープ**: Projects (v2) の GraphQL API は fine-grained PAT の対象外のため、
    classic PAT で `project` スコープのみを選択して発行する。`repo` など他の
    スコープは付けない。呼び出し先（`triage-reusable.yml`）は `@main` 参照であり、
    `hasegawa496/.github` の main に不具合が混入した場合に備え、このトークンで
    コード読み取り・push・他の secret へのアクセスができないようにする。

## CLI / Skill 起票時に指定すること

CLI（`gh issue create` や dotclaude `issue-create` Skill）で起票する場合、
Issue Forms の自動付与（labels / assignees / projects）は発生しない。
このうち labels / assignees は呼び出し側で明示的に設定する必要があるが、
projects（Project への追加）は Triage workflow が担うため、呼び出し側で
補う必要はない。

- `labels`: type ラベルを起票時に指定する
- `assignees`: 起票時に指定する（未指定なら repo owner を既定にする運用）
- Project への追加: **CLI / Skill 側では行わない。** Project への追加は
  Triage workflow のみが担う責務であり、CLI / Skill 側は `gh project item-add`
  の実行や `project` OAuth scope の確認を行う必要はない
- 本文: `### 優先度` と `### Size` の見出しを、Issue Forms と同じ表記
  （`P0: 緊急`〜`P3: 低` / `XS`〜`XL`、または `P0`〜`P3` の短縮形）で
  含める。見出し名・選択値の表記が変わると Triage workflow が値を抽出できず、
  フォールバックコメントが付くだけで Project フィールドは更新されない

Triage workflow は、この本文フォーマットが守られている前提で
**Project への追加と優先度 / Size フィールドの更新の両方** を担当する。
Web UI 経由の起票など Issue Forms によって既に Project に追加済みの場合は、
既存の item を再利用し二重追加はしない（「Triage workflow の役割」節を参照）。

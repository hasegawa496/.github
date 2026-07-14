# Issue Forms と Triage workflow の仕様

この文書は、`.github/ISSUE_TEMPLATE/*.yml`（Issue Forms）と `triage-wc.yml` /
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

## Triage workflow（`triage.yml` → `triage-wc.yml`）の役割

- トリガー: `issues: [opened, edited, reopened]`（起票経路に依存せず、Web UI /
  CLI いずれの Issue にも反応する）
- 処理:
  1. Issue 本文から `### 優先度` / `### Size` 見出し直下の最初の非空行を抽出する
  2. `優先度` は `P0`〜`P3` で始まる値（Issue Form のフル表記 `P0: 緊急` や
     短縮表記 `P0` のいずれでも可）を、Project の実際の選択肢名である
     `P0`〜`P3` に正規化する。`未定` はそのまま扱う
  3. `Size` は大文字に正規化する（`m` → `M`）
  4. Project（`project_number` input、既定 12）に Issue を追加する
     - 既に Project に追加済みの item があればそれを再利用し、二重追加はしない
  5. Project の `優先度` / `Size` フィールド（Single select）に正規化した値を設定する
     - Project 12 の実際の選択肢名: 優先度 = `P0`〜`P3`（`未定` を含む可能性あり、
       要確認）、Size = `XS`/`S`/`M`/`L`/`XL`
     - Issue Form の dropdown 表示テキスト（`P0: 緊急` 等）はあくまで Issue 本文
       上の表記であり、Project 側の選択肢名とは異なる。混同しないこと
- 失敗時の挙動: **ハード失敗せず、Issue にフォールバックコメントを付けて
  `exit 0` で正常終了する。** 想定される失敗パターンと対応するコメント:
  - 見出しが本文に無い / 値が空 → 「優先度/Size を取得できませんでした」
  - `PROJECT_TOKEN` シークレット未設定 → 「トークンが未設定です」
  - Project 取得失敗（owner/number 不一致） → 「Project の取得に失敗しました」
  - Project にフィールドが無い（名前不一致） → 「必要なフィールドが見つかりません」
  - Project 追加 / フィールド更新の API 呼び出し失敗（権限不足など） → 個別のコメント

### 必要な secret

- `PROJECT_TOKEN`: Projects v2 への書き込み権限を持つトークン（PAT など）。
  リポジトリ単位の Secret として設定する。未設定でもワークフロー自体は失敗せず、
  その旨のコメントが Issue に付く。

## CLI / Skill 起票時に指定すること

CLI（`gh issue create` や dotclaude `issue-create` Skill）で起票する場合、
Issue Forms の自動付与（labels / assignees / projects）は発生しないため、
呼び出し側で明示的に設定する必要がある。

- `labels`: type ラベルを起票時に指定する
- `assignees`: 起票時に指定する（未指定なら repo owner を既定にする運用）
- Project への追加: 起票時に `gh project item-add` 等で明示的に行う
  （Triage workflow は「既に追加済みか」を確認してから追加するため、
  CLI 側で先に追加していても二重追加にはならない）
- 本文: `### 優先度` と `### Size` の見出しを、Issue Forms と同じ表記
  （`未定` / `P0: 緊急`〜`P3: 低` / `XS`〜`XL`、または `P0`〜`P3` の短縮形）で
  含める。見出し名・選択値の表記が変わると Triage workflow が値を抽出できず、
  フォールバックコメントが付くだけで Project フィールドは更新されない

Triage workflow は、この本文フォーマットが守られている前提で
**優先度 / Size フィールドの更新のみ** を担当する。Project への追加そのものは
CLI 側（Skill）と Triage workflow の双方が行える設計だが、実運用では
CLI 側で明示的に追加し、Triage workflow は未追加時のフォールバックとして
扱う。

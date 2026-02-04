#!/usr/bin/env bash
set -euo pipefail

script_dir="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$script_dir/lib/common.sh"

usage() {
  cat >&2 <<'USAGE'
使い方: scripts/setup-label-sync.sh

ラベル同期 workflow を導入し、可能ならそのまま起動します。

注意:
  - 対象リポジトリのルートで実行してください。
  - 前提: git, gh（GitHub CLI）, `gh auth login` 済み
USAGE
}

case "${1:-}" in
  "" ) ;;
  -h|--help) usage; exit 0 ;;
  *) die "不明な引数です: $1（--help を参照）" ;;
esac

cd_repo_root
ensure_gh_auth

repo_full="$(get_repo_full)"

default_branch="$(gh repo view --json defaultBranchRef -q '.defaultBranchRef.name' 2>/dev/null || true)"
default_branch="${default_branch:-main}"

# スクリプトが投入する workflow の期待値（既に同じものがあれば「起動だけ」で済ませる）。
expected_workflow="$(mktemp -t sync-labels.XXXXXX)"
cleanup() { rm -f "$expected_workflow"; }
trap cleanup EXIT

cat >"$expected_workflow" <<'YAML'
# ラベル同期（Reusable Workflow呼び出し）
#
# 呼び出し先:
#   - hasegawa496/.github/.github/workflows/sync-labels.yml（Reusable Workflow）
#   - hasegawa496/.github/.github/labels.yml（ラベル定義）

name: Sync Labels

on:
  workflow_dispatch:  # 手動実行

permissions:
  contents: read
  issues: write

jobs:
  sync:
    uses: hasegawa496/.github/.github/workflows/sync-labels.yml@main
    secrets: inherit
    with:
      # 定義外ラベルは削除し、定義されているものだけに揃える
      delete_other_labels: true
YAML

# Actions が無効なら、可能なら API で有効化し、無理なら案内して中断する。
ensure_actions_enabled "$repo_full"

# 既に workflow が入っているなら、安全のため上書きはせず「起動だけ」する。
workflow_path=".github/workflows/sync-labels.yml"
if [[ -f "$workflow_path" ]]; then
  if ! command -v cmp >/dev/null 2>&1; then
    die "$workflow_path は既に存在します（cmp コマンドが無いため内容比較できません）。安全のため上書きしないので、内容確認の上で手動実行してください。"
  fi

  if ! cmp -s "$workflow_path" "$expected_workflow"; then
    die "既に存在します: $workflow_path（内容が想定と異なるため、安全のため上書きしません。内容を確認して手動で調整してください）"
  fi

  echo "既に存在します: $workflow_path（同一内容のため、上書きせず workflow を起動します）" >&2

  # workflow は登録直後に認識されるまで少し時間がかかることがある。
  for attempt in 1 2 3 4 5 6 7 8 9 10; do
    if gh workflow view sync-labels.yml >/dev/null 2>&1; then
      break
    fi
    echo "workflow の認識待ち... ($attempt/10)" >&2
    sleep 2
  done

  if ! gh workflow view sync-labels.yml >/dev/null 2>&1; then
    echo "GitHub が 'sync-labels.yml' を workflow としてまだ認識していません。" >&2
    echo "数分待ってから Actions 画面で 'Sync Labels' を手動実行してください。" >&2
    exit 1
  fi

  if ! err="$(gh workflow run sync-labels.yml --ref "$default_branch" 2>&1)"; then
    echo "$err" >&2
    echo "workflow の起動に失敗しました。Actions 画面から 'Sync Labels' を手動実行してください。" >&2
    exit 1
  fi

  echo "起動しました: Sync Labels（ref: $default_branch）"
  exit 0
fi

# ここから先は workflow 未導入の場合のみ（ブランチ作成/コミット/push を行う）。
if [[ -n "$(git status --porcelain=v1)" ]]; then
  die "作業ツリーがクリーンではありません。変更を commit / stash してから再実行してください。"
fi

if ! git remote get-url origin >/dev/null 2>&1; then
  die "remote 'origin' が設定されていません。設定（例: `git remote add origin ...`）して再実行してください。"
fi

# 事故防止: 必ずデフォルトブランチを最新化してから、そこを起点に専用ブランチを切る。
if ! err="$(git fetch --quiet origin "$default_branch" 2>&1)"; then
  echo "$err" >&2
  die "origin/$default_branch の fetch に失敗しました。ネットワーク/remote 設定を確認してください。"
fi

base_ref="origin/$default_branch"
if ! git show-ref --verify --quiet "refs/remotes/$base_ref"; then
  die "参照が見つかりません: $base_ref"
fi

ts="$(date -u +%Y%m%d-%H%M%S)"
branch="chore/add-sync-labels-$ts"

if git show-ref --verify --quiet "refs/heads/$branch"; then
  die "ローカルに同名ブランチが存在します: $branch（時間をおいて再実行してください）"
fi

if ! err="$(git checkout -q -b "$branch" "$base_ref" 2>&1)"; then
  echo "$err" >&2
  die "ブランチの作成に失敗しました。"
fi

mkdir -p "$(dirname "$workflow_path")"
cp "$expected_workflow" "$workflow_path"

git add "$workflow_path"
if ! err="$(git commit -q -m "chore: ラベル同期 workflow を追加" 2>&1)"; then
  echo "$err" >&2
  die "コミットに失敗しました。"
fi

if ! err="$(git push --quiet -u origin "$branch" 2>&1)"; then
  echo "$err" >&2
  die "push に失敗しました。リモート/権限/ブランチ保護などを確認してください。"
fi

gh pr create \
  --title "chore: ラベル同期 workflow を追加" \
  --body "hasegawa496/.github の Reusable Workflow を呼び出して、ラベルを同期できるようにします。" \
  --base "$default_branch" \
  --head "$branch" >/dev/null 2>&1 || true

pr_number="$(gh pr list --head "$branch" --json number -q '.[0].number' 2>/dev/null || true)"
pr_url="$(gh pr view "$branch" --json url -q '.url' 2>/dev/null || true)"

if [[ -z "$pr_number" ]]; then
  echo "PR を作成できませんでした（既に存在するか、権限不足の可能性があります）。" >&2
  echo "ブランチは push 済みです: $branch" >&2
  exit 1
fi

echo "PR: #$pr_number ($branch -> $default_branch)"
if [[ -n "$pr_url" ]]; then
  echo "PR URL: $pr_url"
fi

# ここから先は「できたらやる」。失敗しても原因を表示して案内する。
echo "PR をマージします..." >&2
if ! err="$(gh pr merge "$pr_number" --squash --delete-branch 2>&1)"; then
  echo "$err" >&2
  echo "PR を自動でマージできませんでした。PR を手動でマージした後、Actions から 'Sync Labels' を実行してください。" >&2
  exit 1
fi

echo "マージ完了。workflow を起動します..." >&2

# workflow はマージ直後に登録されるまで少し時間がかかることがある。
for attempt in 1 2 3 4 5 6 7 8 9 10; do
  if gh workflow view sync-labels.yml >/dev/null 2>&1; then
    break
  fi
  echo "workflow の認識待ち... ($attempt/10)" >&2
  sleep 2
done

if ! gh workflow view sync-labels.yml >/dev/null 2>&1; then
  echo "GitHub が 'sync-labels.yml' を workflow としてまだ認識していません。" >&2
  echo "数分待ってから Actions 画面で 'Sync Labels' を手動実行してください。" >&2
  exit 1
fi

if ! err="$(gh workflow run sync-labels.yml --ref "$default_branch" 2>&1)"; then
  echo "$err" >&2
  echo "workflow の起動に失敗しました。Actions 画面から 'Sync Labels' を手動実行してください。" >&2
  exit 1
fi

echo "起動しました: Sync Labels（ref: $default_branch）"

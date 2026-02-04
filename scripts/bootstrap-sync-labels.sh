#!/usr/bin/env bash
set -euo pipefail

die() {
  echo "$*" >&2
  exit 1
}

if ! command -v git >/dev/null 2>&1; then
  die "git が見つかりません。"
fi

inside_work_tree="$(git rev-parse --is-inside-work-tree 2>/dev/null || echo "false")"
is_bare_repo="$(git rev-parse --is-bare-repository 2>/dev/null || echo "true")"

if [[ "$is_bare_repo" == "true" || "$inside_work_tree" != "true" ]]; then
  die "このスクリプトは「作業ツリーがある」git リポジトリで実行してください（bare リポジトリや .git ディレクトリ内では実行できません）。"
fi

if ! command -v gh >/dev/null 2>&1; then
  die "gh (GitHub CLI) が見つかりません。インストール後、`gh auth login` を実行してください。"
fi

if ! gh auth status >/dev/null 2>&1; then
  die "gh の認証ができていません。`gh auth login` を実行してください。"
fi

if ! git remote get-url origin >/dev/null 2>&1; then
  die "remote 'origin' が設定されていません。設定（例: `git remote add origin ...`）して再実行してください。"
fi

if [[ -n "$(git status --porcelain=v1)" ]]; then
  die "作業ツリーがクリーンではありません。変更を commit / stash してから再実行してください。"
fi

repo_full="$(gh repo view --json nameWithOwner -q '.nameWithOwner' 2>/dev/null || true)"
if [[ -z "$repo_full" ]]; then
  die "gh から GitHub リポジトリ情報を取得できませんでした。GitHub リポジトリを clone したディレクトリで実行していますか？"
fi

default_branch="$(gh repo view --json defaultBranchRef -q '.defaultBranchRef.name' 2>/dev/null || true)"
default_branch="${default_branch:-main}"

# Actions が無効なら、可能なら API で有効化し、無理なら案内して中断する。
actions_enabled="$(gh api "repos/$repo_full/actions/permissions" -q '.enabled' 2>/dev/null || true)"
if [[ "$actions_enabled" != "true" && "$actions_enabled" != "false" ]]; then
  die "$repo_full の Actions 設定を取得できませんでした。admin 権限が必要、または Organization のポリシーで Actions が無効化されている可能性があります。"
fi

if [[ "$actions_enabled" == "false" ]]; then
  echo "$repo_full は GitHub Actions が無効です。API 経由で有効化を試みます..." >&2
  if ! err="$(gh api -X PUT "repos/$repo_full/actions/permissions" -f enabled=true 2>&1)"; then
    echo "$err" >&2
    die "Actions を有効化できませんでした。リポジトリ設定で Actions を有効化（admin 権限が必要）してから再実行してください。"
  fi
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

workflow_path=".github/workflows/sync-labels.yml"
if [[ -f "$workflow_path" ]]; then
  die "既に存在します: $workflow_path（安全のため上書きしません。内容を確認して手動で調整してください）"
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
cat >"$workflow_path" <<'YAML'
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
YAML

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

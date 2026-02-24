#!/usr/bin/env bash
set -euo pipefail

script_dir="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$script_dir/lib/common.sh"

assert_no_args "$@"
cd_repo_root
ensure_gh_auth

repo_full="$(get_repo_full)"

default_branch="$(gh repo view --json defaultBranchRef -q '.defaultBranchRef.name' 2>/dev/null || true)"
default_branch="${default_branch:-main}"

# このスクリプト自身（my-life）のテンプレートを正本として利用する。
template_workflow="$script_dir/../workflow-templates/triage.yml"
if [[ ! -f "$template_workflow" ]]; then
  die "テンプレートが見つかりません: $template_workflow"
fi

expected_workflow="$(mktemp -t triage.XXXXXX)"
cleanup() { rm -f "$expected_workflow"; }
trap cleanup EXIT

cp "$template_workflow" "$expected_workflow"

ensure_actions_enabled "$repo_full"

workflow_path=".github/workflows/triage.yml"
needs_apply_template="true"

if [[ -f "$workflow_path" ]]; then
  if ! command -v cmp >/dev/null 2>&1; then
    echo "既に存在します: $workflow_path（cmp が無いため、テンプレートで更新して導入を続行します）。" >&2
  elif cmp -s "$workflow_path" "$expected_workflow"; then
    needs_apply_template="false"
    echo "既に存在します: $workflow_path（同一内容のため、更新不要です）" >&2
  fi
fi

if [[ "$needs_apply_template" == "false" ]]; then
  exit 0
fi

ensure_clean_worktree
ensure_origin_exists

base_ref="$(ensure_remote_base_ref "$default_branch")"

ts="$(date -u +%Y%m%d-%H%M%S)"
branch="chore/update-triage-$ts"

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
if ! err="$(git commit -q -m "chore: Triage workflow を導入/更新" 2>&1)"; then
  echo "$err" >&2
  die "コミットに失敗しました。"
fi

if ! err="$(git push --quiet -u origin "$branch" 2>&1)"; then
  echo "$err" >&2
  die "push に失敗しました。リモート/権限/ブランチ保護などを確認してください。"
fi

if ! pr_number="$(create_or_get_pr \
  "$default_branch" \
  "$branch" \
  "chore: Triage workflow を導入/更新" \
  $'Issue 作成/編集時に Projects v2 へ追加し、Issue フォーム（優先度/Size）の値を Project フィールドへ反映します。\n\n前提:\n- Secrets: PROJECT_TOKEN\n- Project フィールド: 優先度（Single select）, Size（Single select: XS/S/M/L/XL）')"; then
  exit 1
fi

echo "PR をマージします..." >&2
if ! merge_pr_or_fail \
  "$pr_number" \
  "$branch" \
  "PR を自動でマージできませんでした。PR を手動でマージしてください。"; then
  exit 1
fi

echo "マージ完了。workflow の認識待ち..." >&2
for attempt in 1 2 3 4 5 6 7 8 9 10; do
  if gh workflow view triage.yml >/dev/null 2>&1; then
    break
  fi
  echo "workflow の認識待ち... ($attempt/10)" >&2
  sleep 2
done

if ! gh workflow view triage.yml >/dev/null 2>&1; then
  echo "GitHub が 'triage.yml' を workflow としてまだ認識していません。" >&2
  echo "数分待ってから、Issue を作成/編集してトリアージが走るか確認してください。" >&2
  exit 1
fi

echo "導入完了: Triage" >&2
echo "次に行うこと（対象リポジトリ側）:" >&2
echo "  1) Secrets に PROJECT_TOKEN を設定（Projects v2 へ書き込み可能な権限）" >&2
echo "  2) Projects v2 側にフィールド（優先度/Size）を作成" >&2
echo "  3) Issue を作成/編集して、Project フィールドが更新されるか確認" >&2

#!/usr/bin/env bash
# 配布先リポジトリに Dependabot 自動マージ workflow を導入/更新する。
# workflow-templates/dependabot-automerge.yml をコピーし、その配布先の CI workflow 名
# （on.workflow_run.workflows）を CI_WORKFLOW_NAME 環境変数で差し替えてから導入する。
# CI workflow を持たない配布先には導入しても発火しないため、呼び出し側で導入要否を判断すること。
set -euo pipefail

# shellcheck disable=SC1007
script_dir="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "$script_dir/lib/common.sh"

assert_no_args "$@"
cd_repo_root
ensure_gh_auth

repo_full="$(get_repo_full)"
ci_workflow_name="${CI_WORKFLOW_NAME:-CI}"

default_branch="$(gh repo view --json defaultBranchRef -q '.defaultBranchRef.name' 2>/dev/null || true)"
default_branch="${default_branch:-main}"

template_workflow="$script_dir/../workflow-templates/dependabot-automerge.yml"
if [[ ! -f "$template_workflow" ]]; then
  die "テンプレートが見つかりません: $template_workflow"
fi

expected_workflow="$(mktemp -t dependabot-automerge.XXXXXX)"
cleanup() { rm -f "$expected_workflow"; }
trap cleanup EXIT

cp "$template_workflow" "$expected_workflow"
sed -i -e "s#workflows: \\[\"CI\"\\]#workflows: [\"${ci_workflow_name}\"]#" "$expected_workflow"

ensure_actions_enabled "$repo_full"

workflow_path=".github/workflows/dependabot-automerge.yml"
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
branch="chore/update-dependabot-automerge-$ts"

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
if ! err="$(git commit -q -m "chore: Dependabot 自動マージ workflow を導入/更新" 2>&1)"; then
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
  "chore: Dependabot 自動マージ workflow を導入/更新" \
  "hasegawa496/.github の Reusable Workflow を呼び出して、CI（\`${ci_workflow_name}\`）成功時に dependabot PR を自動マージできるようにします。")"; then
  exit 1
fi

echo "PR をマージします..." >&2
if ! merge_pr_or_fail \
  "$pr_number" \
  "$branch" \
  "PR を自動でマージできませんでした。PR を手動でマージしてください。"; then
  exit 1
fi

echo "導入完了: Dependabot 自動マージ" >&2

if ! git show-ref --verify --quiet "refs/heads/$default_branch"; then
  git fetch --quiet origin "$default_branch" >/dev/null 2>&1 || true
  git checkout -q -B "$default_branch" "origin/$default_branch"
else
  git checkout -q "$default_branch"
  git pull --ff-only --quiet origin "$default_branch" >/dev/null 2>&1 || true
fi

if git show-ref --verify --quiet "refs/heads/$branch"; then
  git branch -D "$branch" >/dev/null 2>&1 || true
fi

git push --quiet origin --delete "$branch" >/dev/null 2>&1 || true

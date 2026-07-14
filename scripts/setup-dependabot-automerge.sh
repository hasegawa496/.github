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

workflow_path=".github/workflows/dependabot-automerge.yml"

if ! install_or_skip_caller_workflow \
  "$repo_full" \
  "$expected_workflow" \
  "$workflow_path" \
  "$default_branch" \
  "chore/update-dependabot-automerge" \
  "chore: Dependabot 自動マージ workflow を導入/更新" \
  "chore: Dependabot 自動マージ workflow を導入/更新" \
  "hasegawa496/.github の Reusable Workflow を呼び出して、CI（\`${ci_workflow_name}\`）成功時に dependabot PR を自動マージできるようにします。"; then
  exit 1
fi

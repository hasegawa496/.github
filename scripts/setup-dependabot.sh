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

template_file="$script_dir/../.github/dependabot.yml"
if [[ ! -f "$template_file" ]]; then
  die "テンプレートが見つかりません: $template_file"
fi

expected_file="$(mktemp -t dependabot.XXXXXX)"
cleanup() { rm -f "$expected_file"; }
trap cleanup EXIT

cp "$template_file" "$expected_file"

config_path=".github/dependabot.yml"
needs_apply_template="true"

if [[ -f "$config_path" ]]; then
  if ! command -v cmp >/dev/null 2>&1; then
    echo "既に存在します: $config_path（cmp が無いため、テンプレートで更新して導入を続行します）。" >&2
  elif cmp -s "$config_path" "$expected_file"; then
    needs_apply_template="false"
    echo "既に存在します: $config_path（同一内容のため、更新不要です）" >&2
  fi
fi

if [[ "$needs_apply_template" == "false" ]]; then
  exit 0
fi

ensure_clean_worktree
ensure_origin_exists

base_ref="$(ensure_remote_base_ref "$default_branch")"

ts="$(date -u +%Y%m%d-%H%M%S)"
branch="chore/update-dependabot-$ts"

if git show-ref --verify --quiet "refs/heads/$branch"; then
  die "ローカルに同名ブランチが存在します: $branch（時間をおいて再実行してください）"
fi

if ! err="$(git checkout -q -b "$branch" "$base_ref" 2>&1)"; then
  echo "$err" >&2
  die "ブランチの作成に失敗しました。"
fi

mkdir -p "$(dirname "$config_path")"
cp "$expected_file" "$config_path"

git add "$config_path"
if ! err="$(git commit -q -m "chore: Dependabot 設定を導入/更新" 2>&1)"; then
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
  "chore: Dependabot 設定を導入/更新" \
  "hasegawa496/.github の標準 Dependabot 設定を導入/更新します。")"; then
  exit 1
fi

echo "PR をマージします..." >&2
if ! merge_pr_or_fail \
  "$pr_number" \
  "$branch" \
  "PR を自動でマージできませんでした。PR を手動でマージしてください。"; then
  exit 1
fi

echo "導入完了: Dependabot" >&2

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

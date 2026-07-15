#!/usr/bin/env bash

die() {
  echo "$*" >&2
  exit 1
}

require_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    die "$cmd が見つかりません。"
  fi
}

cd_repo_root() {
  require_cmd git

  local inside_work_tree
  local is_bare_repo
  local repo_root

  inside_work_tree="$(git rev-parse --is-inside-work-tree 2>/dev/null || echo "false")"
  is_bare_repo="$(git rev-parse --is-bare-repository 2>/dev/null || echo "true")"

  if [[ "$is_bare_repo" == "true" || "$inside_work_tree" != "true" ]]; then
    die "このスクリプトは「作業ツリーがある」git リポジトリで実行してください（bare リポジトリや .git ディレクトリ内では実行できません）。"
  fi

  repo_root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
  if [[ -z "$repo_root" ]]; then
    die "git リポジトリのルートを取得できませんでした。"
  fi

  cd "$repo_root" || exit 1
}

ensure_gh_auth() {
  require_cmd gh

  if ! gh auth status >/dev/null 2>&1; then
    die "gh の認証ができていません。'gh auth login' を実行してください。"
  fi
}

SELF_MANAGED_CALLER_REPO="hasegawa496/.github"

# hasegawa496/.github 自身の呼び出し側 workflow（label-sync.yml 等）は、
# 配布用テンプレート（cross-repo参照）ではなく scripts/sync-workflow-callers.sh が
# ローカル参照版を自己管理している。caller workflow を配布する setup-*.sh は、
# 対象がこの repo 自身のときだけこの関数で早期スキップする。
is_self_managed_caller_repo() {
  [[ "$1" == "$SELF_MANAGED_CALLER_REPO" ]]
}

get_repo_full() {
  local repo_full
  repo_full="$(gh repo view --json nameWithOwner -q '.nameWithOwner' 2>/dev/null || true)"
  if [[ -z "$repo_full" ]]; then
    die "gh から GitHub リポジトリ情報を取得できませんでした。GitHub リポジトリを clone したディレクトリで実行していますか？"
  fi
  printf '%s' "$repo_full"
}

ensure_actions_enabled() {
  local repo_full="$1"
  local actions_enabled
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
}

assert_no_args() {
  [[ $# -eq 0 ]] || die "このスクリプトは引数を受け取りません。"
}

ensure_clean_worktree() {
  if [[ -n "$(git status --porcelain=v1)" ]]; then
    die "作業ツリーがクリーンではありません。変更を commit / stash してから再実行してください。"
  fi
}

ensure_origin_exists() {
  if ! git remote get-url origin >/dev/null 2>&1; then
    die "remote 'origin' が設定されていません。設定（例: \`git remote add origin ...\`）して再実行してください。"
  fi
}

ensure_remote_base_ref() {
  local default_branch="$1"
  local base_ref="origin/$default_branch"

  if ! err="$(git fetch --quiet origin "$default_branch" 2>&1)"; then
    echo "$err" >&2
    die "origin/$default_branch の fetch に失敗しました。ネットワーク/remote 設定を確認してください。"
  fi

  if ! git show-ref --verify --quiet "refs/remotes/$base_ref"; then
    die "参照が見つかりません: $base_ref"
  fi

  printf '%s' "$base_ref"
}

show_remote_branch_cleanup_hint() {
  local branch="$1"
  echo "リモートブランチが残っている場合の削除例:" >&2
  echo "  gh pr list --head \"$branch\"" >&2
  echo "  gh pr close --delete-branch \"$branch\"  # PRが残っていれば" >&2
  echo "  git push origin --delete \"$branch\"     # 直接消す（権限があれば）" >&2
}

ensure_git_author_for_actions() {
  # GitHub Actions 実行時向け: author 未設定なら補完
  git config user.name >/dev/null || git config user.name "github-actions[bot]"
  git config user.email >/dev/null || git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
}

create_or_get_pr() {
  local base_branch="$1"
  local head_branch="$2"
  local title="$3"
  local body="$4"

  gh pr create \
    --title "$title" \
    --body "$body" \
    --base "$base_branch" \
    --head "$head_branch" >/dev/null 2>&1 || true

  local pr_number pr_url
  pr_number="$(gh pr list --head "$head_branch" --json number -q '.[0].number' 2>/dev/null || true)"
  pr_url="$(gh pr view "$head_branch" --json url -q '.url' 2>/dev/null || true)"

  if [[ -z "$pr_number" ]]; then
    echo "PR を作成できませんでした（既に存在するか、権限不足の可能性があります）。" >&2
    echo "ブランチは push 済みです: $head_branch" >&2
    return 1
  fi

  echo "PR: #$pr_number ($head_branch -> $base_branch)" >&2
  if [[ -n "$pr_url" ]]; then
    echo "PR URL: $pr_url" >&2
  fi

  printf '%s' "$pr_number"
}

merge_pr_or_fail() {
  local pr_number="$1"
  local branch="$2"
  local fail_message="$3"
  local err

  if err="$(gh pr merge "$pr_number" --squash --delete-branch 2>&1)"; then
    return 0
  fi

  echo "$err" >&2
  echo "$fail_message" >&2
  show_remote_branch_cleanup_hint "$branch"
  return 1
}

# 配布用 caller workflow（label-sync.yml など）の導入をまとめて行う共通処理。
# 導入要否の判定（自己管理repo/既に同一内容）から、ブランチ作成・PR作成・自動マージまでを担う。
# 戻り値 0 は「呼び出し元は後続処理（workflow起動など）を続けてよい」ことを意味し、
# 自己管理repoでのスキップ・既に同一内容でのスキップ・導入成功のいずれでも 0 を返す。
# 1 は導入自体に失敗しており、後続処理を続けるべきではないことを意味する。
# 個々の setup-*.sh がここで is_self_managed_caller_repo の分岐を持たないようにすることで、
# 「自己管理repoでも本来必要な後続処理まで一緒にスキップしてしまう」抜け漏れを構造的に防ぐ。
install_or_skip_caller_workflow() {
  local repo_full="$1"
  local expected_content_path="$2"
  local workflow_path="$3"
  local default_branch="$4"
  local branch_prefix="$5"
  local commit_message="$6"
  local pr_title="$7"
  local pr_body="$8"

  if is_self_managed_caller_repo "$repo_full"; then
    echo "${repo_full} は呼び出し側 workflow を scripts/sync-workflow-callers.sh で自己管理するため、テンプレート導入はスキップします。" >&2
    return 0
  fi

  ensure_actions_enabled "$repo_full"

  local needs_apply_template="true"
  if [[ -f "$workflow_path" ]]; then
    if ! command -v cmp >/dev/null 2>&1; then
      echo "既に存在します: $workflow_path（cmp が無いため、テンプレートで更新して導入を続行します）。" >&2
    elif cmp -s "$workflow_path" "$expected_content_path"; then
      echo "既に存在します: $workflow_path（同一内容のため、更新不要です）" >&2
      needs_apply_template="false"
    fi
  fi

  if [[ "$needs_apply_template" == "false" ]]; then
    return 0
  fi

  ensure_clean_worktree
  ensure_origin_exists

  local base_ref
  base_ref="$(ensure_remote_base_ref "$default_branch")"

  local ts branch err
  ts="$(date -u +%Y%m%d-%H%M%S)"
  branch="${branch_prefix}-${ts}"

  if git show-ref --verify --quiet "refs/heads/$branch"; then
    die "ローカルに同名ブランチが存在します: $branch（時間をおいて再実行してください）"
  fi

  if ! err="$(git checkout -q -b "$branch" "$base_ref" 2>&1)"; then
    echo "$err" >&2
    die "ブランチの作成に失敗しました。"
  fi

  mkdir -p "$(dirname "$workflow_path")"
  cp "$expected_content_path" "$workflow_path"

  git add "$workflow_path"
  if ! err="$(git commit -q -m "$commit_message" 2>&1)"; then
    echo "$err" >&2
    die "コミットに失敗しました。"
  fi

  if ! err="$(git push --quiet -u origin "$branch" 2>&1)"; then
    echo "$err" >&2
    die "push に失敗しました。リモート/権限/ブランチ保護などを確認してください。"
  fi

  local pr_number
  if ! pr_number="$(create_or_get_pr "$default_branch" "$branch" "$pr_title" "$pr_body")"; then
    return 1
  fi

  echo "PR をマージします..." >&2
  if ! merge_pr_or_fail "$pr_number" "$branch" "PR を自動でマージできませんでした。PR を手動でマージしてください。"; then
    return 1
  fi

  echo "導入完了: $workflow_path" >&2

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
}

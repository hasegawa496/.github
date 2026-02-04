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

  cd "$repo_root"
}

ensure_gh_auth() {
  require_cmd gh

  if ! gh auth status >/dev/null 2>&1; then
    die "gh の認証ができていません。`gh auth login` を実行してください。"
  fi
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


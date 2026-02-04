#!/usr/bin/env bash
set -euo pipefail

die() {
  echo "$*" >&2
  exit 1
}

usage() {
  cat >&2 <<'USAGE'
Usage: scripts/bootstrap.sh [--skip-labels] [--skip-settings]

Runs shared bootstrap steps for this repository:
  - Enables "Automatically delete head branches" (delete_branch_on_merge)
  - Installs or runs label sync workflow (via ../.github/scripts/bootstrap-sync-labels.sh)
USAGE
}

skip_labels="false"
skip_settings="false"

for arg in "${@:-}"; do
  case "$arg" in
    -h|--help) usage; exit 0 ;;
    --skip-labels) skip_labels="true" ;;
    --skip-settings) skip_settings="true" ;;
    *) die "Unknown argument: $arg (use --help)" ;;
  esac
done

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

repo_full="$(gh repo view --json nameWithOwner -q '.nameWithOwner' 2>/dev/null || true)"
if [[ -z "$repo_full" ]]; then
  die "gh から GitHub リポジトリ情報を取得できませんでした。GitHub リポジトリを clone したディレクトリで実行していますか？"
fi

ensure_actions_enabled() {
  actions_enabled="$(gh api "repos/$repo_full/actions/permissions" -q '.enabled' 2>/dev/null || true)"
  if [[ "$actions_enabled" != "true" && "$actions_enabled" != "false" ]]; then
    die "$repo_full の Actions 設定を取得できませんでした。admin 権限が必要、または Organization のポリシーで Actions が無効化されている可能性があります。"
  fi

  if [[ "$actions_enabled" == "false" ]]; then
    echo "$repo_full: GitHub Actions が無効です。API 経由で有効化を試みます..." >&2
    if ! err="$(gh api -X PUT "repos/$repo_full/actions/permissions" -f enabled=true 2>&1)"; then
      echo "$err" >&2
      die "Actions を有効化できませんでした。リポジトリ設定で Actions を有効化（admin 権限が必要）してから再実行してください。"
    fi
  fi
}

if [[ "$skip_settings" != "true" ]]; then
  # マージ後のブランチ自動削除を有効化（リポジトリ設定）
  delete_on_merge="$(gh api "repos/$repo_full" -q '.delete_branch_on_merge' 2>/dev/null || true)"
  if [[ "$delete_on_merge" != "true" ]]; then
    echo "$repo_full: delete_branch_on_merge を有効化します..." >&2
    if ! out="$(gh api -X PATCH "repos/$repo_full" -f delete_branch_on_merge=true 2>&1)"; then
      echo "$out" >&2
      die "設定変更に失敗しました。gh のトークンに Administration 権限が必要な可能性があります。"
    fi
  fi
fi

if [[ "$skip_labels" != "true" ]]; then
  ensure_actions_enabled
  # 既に workflow があるなら起動だけ。無ければ共通スクリプトで導入する。
  if [[ -f ".github/workflows/sync-labels.yml" ]]; then
    default_branch="$(gh repo view --json defaultBranchRef -q '.defaultBranchRef.name' 2>/dev/null || true)"
    default_branch="${default_branch:-main}"
    echo "$repo_full: Sync Labels workflow を起動します (ref: $default_branch)..." >&2
    gh workflow run sync-labels.yml --ref "$default_branch" >/dev/null
  else
    shared_script="../.github/scripts/bootstrap-sync-labels.sh"
    if [[ ! -f "$shared_script" ]]; then
      die "共有スクリプトが見つかりません: $shared_script"
    fi
    "$shared_script"
  fi
fi

echo "OK: bootstrap 完了 ($repo_full)"

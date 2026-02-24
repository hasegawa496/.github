#!/usr/bin/env bash
set -euo pipefail

script_dir="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$script_dir/lib/common.sh"

assert_no_args "$@"

cd_repo_root
ensure_gh_auth

repo_full="$(get_repo_full)"

delete_on_merge="$(gh api "repos/$repo_full" -q '.delete_branch_on_merge' 2>/dev/null || true)"
if [[ "$delete_on_merge" != "true" ]]; then
  echo "$repo_full: delete_branch_on_merge を有効化します..." >&2
  if ! out="$(gh api -X PATCH "repos/$repo_full" -f delete_branch_on_merge=true 2>&1)"; then
    echo "$out" >&2
    die "設定変更に失敗しました。gh のトークンに Administration 権限が必要な可能性があります。"
  fi
fi

echo "OK: 設定の初期化が完了しました ($repo_full)"

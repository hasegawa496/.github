#!/usr/bin/env bash
set -euo pipefail

# shellcheck disable=SC1007
script_dir="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "$script_dir/lib/common.sh"

assert_no_args "$@"

"$script_dir/setup-repo-settings.sh"
"$script_dir/setup-dependabot.sh"
"$script_dir/setup-label-sync.sh"

# git hooks を有効化する（コミット前に shellcheck を自動実行）
git config core.hooksPath .githooks
echo "git hooks 有効化: .githooks/"

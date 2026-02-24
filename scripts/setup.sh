#!/usr/bin/env bash
set -euo pipefail

script_dir="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$script_dir/lib/common.sh"

assert_no_args "$@"

"$script_dir/setup-repo-settings.sh"
"$script_dir/setup-label-sync.sh"

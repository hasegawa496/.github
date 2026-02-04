#!/usr/bin/env bash
set -euo pipefail

# Deprecated: use scripts/bootstrap-sync-labels.sh
script_dir="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
exec "$script_dir/bootstrap-sync-labels.sh" "$@"

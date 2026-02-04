#!/usr/bin/env bash
set -euo pipefail

script_dir="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$script_dir/lib/common.sh"

usage() {
  cat >&2 <<'USAGE'
使い方: scripts/setup.sh

標準構成の初期設定をまとめて実行します（迷ったらこれ）:
  1) リポジトリ設定の初期化（scripts/setup-repo-settings.sh）
  2) ラベル同期 workflow の導入/起動（scripts/setup-label-sync.sh）

注意:
  - 対象リポジトリのルートで実行してください。
  - 前提: git, gh（GitHub CLI）, `gh auth login` 済み
USAGE
}

case "${1:-}" in
  "" ) ;;
  -h|--help) usage; exit 0 ;;
  *) die "不明な引数です: $1（--help を参照）" ;;
esac

"$script_dir/setup-repo-settings.sh"
"$script_dir/setup-label-sync.sh"

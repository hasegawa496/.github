#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
使い方:
  scripts/sync-workflow-callers.sh --write
  scripts/sync-workflow-callers.sh --check

目的:
  workflow-templates/ を配布テンプレ（ソース）として、.github/workflows/ にある
  「このリポジトリ自身の呼び出し側 workflow（CI/手動実行）」を同期します。

EOF
}

mode="${1:-}"
case "$mode" in
  --write|--check) ;;
  *) usage; exit 2 ;;
esac

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

die() {
  echo "エラー: $*" >&2
  exit 1
}

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

render() {
  local src="$1"
  local dst="$2"
  local local_uses="$3"
  local name_override="${4:-}"

  [[ -f "$src" ]] || die "見つかりません: $src"

  local out="$tmp_dir/$(basename "$dst")"
  cp "$src" "$out"

  # Reusable Workflow の参照をローカル参照に差し替える（配布先では使えないため）
  # 例:
  #   uses: hasegawa496/.github/.github/workflows/shellcheck-wc.yml@main
  #   uses: ./.github/workflows/shellcheck-wc.yml
  sed -i \
    -e "s#uses: \\s*hasegawa496/.github/\\.github/workflows/[^[:space:]]\\+@main#uses: ${local_uses}#g" \
    "$out"

  if [[ -n "${name_override:-}" ]]; then
    sed -i -e "s#^name: .*#name: ${name_override}#g" "$out"
  fi

  # 生成物であることを明示（先頭に短い注記を挿入）
  # 既にコメントがある場合でも、先頭に1行だけ追加する。
  if ! head -n 1 "$out" | rg -n "GENERATED" >/dev/null 2>&1; then
    { echo "# GENERATED: scripts/sync-workflow-callers.sh により生成"; cat "$out"; } >"$out.new"
    mv "$out.new" "$out"
  fi

  if [[ "$mode" == "--check" ]]; then
    if ! cmp -s "$out" "$dst"; then
      echo "差分あり: $dst（テンプレと不一致）" >&2
      return 1
    fi
    return 0
  fi

  mkdir -p "$(dirname "$dst")"
  mv "$out" "$dst"
}

# workflow-templates を配布テンプレ（ソース）として扱う
# - caller workflow を同名テンプレートから同期する
render "workflow-templates/shellcheck.yml" ".github/workflows/shellcheck.yml" "./.github/workflows/shellcheck-wc.yml"
render "workflow-templates/label-sync.yml" ".github/workflows/label-sync.yml" "./.github/workflows/label-sync-wc.yml"
render "workflow-templates/triage.yml" ".github/workflows/triage.yml" "./.github/workflows/triage-wc.yml"

echo "OK: 呼び出し側 workflow を同期しました（$mode）"

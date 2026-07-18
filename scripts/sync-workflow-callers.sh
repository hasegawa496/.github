#!/usr/bin/env bash
# templates/ を正本として、このリポジトリ自身で使うローカル参照版を生成する。
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
使い方:
  scripts/sync-workflow-callers.sh --write
  scripts/sync-workflow-callers.sh --check

目的:
  templates/ 配下の配布対象を、このリポジトリ自身向けに同期します。
  Reusable Workflow の参照だけは外部参照ではなくローカル参照へ変換します。
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
  local out="$tmp_dir/${dst//\//_}"

  cp "$src" "$out"
  sed -i \
    -e 's#uses:[[:space:]]*hasegawa496/\.github/\.github/workflows/\([^[:space:]@]\+\)@[^[:space:]]\+#uses: ./.github/workflows/\1#g' \
    "$out"

  if [[ "$src" == "templates/.github/workflows/shellcheck.yml" ]]; then
    sed -i -e 's/^name: ShellCheck$/name: CI/' "$out"
  fi

  if [[ "$src" == "templates/.github/workflows/"* ]] && ! head -n 1 "$out" | rg -q 'GENERATED'; then
    { echo "# GENERATED: scripts/sync-workflow-callers.sh により生成"; cat "$out"; } >"$out.new"
    mv "$out.new" "$out"
  fi

  if [[ "$mode" == "--check" ]]; then
    if ! cmp -s "$out" "$dst"; then
      echo "差分あり: $dst（templates/ と不一致）" >&2
      return 1
    fi
    return 0
  fi

  mkdir -p "$(dirname "$dst")"
  mv "$out" "$dst"
}

has_ci_workflow() {
  local workflow
  shopt -s nullglob
  for workflow in .github/workflows/*.yml .github/workflows/*.yaml; do
    if rg -q '^name:[[:space:]]*CI[[:space:]]*$' "$workflow"; then
      return 0
    fi
  done
  return 1
}

while IFS= read -r -d '' src; do
  dst="${src#templates/}"
  if [[ "$src" == "templates/.github/workflows/ci.yml" ]] && has_ci_workflow; then
    continue
  fi
  render "$src" "$dst"
done < <(find templates -type f -print0 | sort -z)

echo "OK: templates/ から自己利用設定を同期しました（$mode）"

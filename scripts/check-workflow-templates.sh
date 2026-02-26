#!/usr/bin/env bash
set -euo pipefail

die() {
  echo "エラー: $*" >&2
  exit 1
}

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

shopt -s nullglob
templates=(workflow-templates/*.yml)
(( ${#templates[@]} > 0 )) || die "workflow-templates/*.yml が見つかりません"

errors=0

for file in "${templates[@]}"; do
  # 1) template からローカル参照（./.github/workflows/...）が出てこないこと
  if rg -n "uses:\\s*\\./\\.github/workflows/" "$file" >/dev/null; then
    echo "NG: $file: template なのにローカル参照（./.github/workflows/...）があります" >&2
    errors=$((errors + 1))
  fi

  # 2) この repo の reusable workflow を参照する場合は @v1.0.0 を付けること
  #   （配布先がコピーして使う想定のため、ref を明示しないと動かない）
  if rg -n "uses:\\s*hasegawa496/.github/\\.github/workflows/[^\\s@]+\\.yml(\\s|$)" "$file" >/dev/null; then
    echo "NG: $file: uses に @<ref> がありません（例: @v1.0.0）" >&2
    errors=$((errors + 1))
  fi
done

if [[ -x scripts/sync-workflow-callers.sh ]]; then
  scripts/sync-workflow-callers.sh --check >/dev/null || {
    echo "NG: .github/workflows の呼び出し側 workflow がテンプレとズレています。scripts/sync-workflow-callers.sh を実行してください。" >&2
    exit 1
  }
fi

if (( errors > 0 )); then
  die "workflow-templates の検証に失敗しました（${errors}件）"
fi

echo "OK: workflow-templates の簡易検証に合格しました"

#!/usr/bin/env bash
# Reusable Workflow と templates/ の対応、自己利用の生成結果を検証する。
set -euo pipefail

die() {
  echo "エラー: $*" >&2
  exit 1
}

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

[[ -d templates/.github ]] || die "templates/.github が見つかりません"

shopt -s nullglob
reusable_workflows=(.github/workflows/*-reusable.yml)
(( ${#reusable_workflows[@]} > 0 )) || die ".github/workflows/*-reusable.yml が見つかりません"

errors=0
while IFS= read -r -d '' file; do
  if rg -n 'uses:[[:space:]]*\./\.github/workflows/' "$file" >/dev/null; then
    echo "NG: $file: 配布テンプレートにローカル参照があります" >&2
    errors=$((errors + 1))
  fi
  if rg -n 'uses:[[:space:]]*hasegawa496/\.github/\.github/workflows/[^[:space:]@]+\.yml([[:space:]]|$)' "$file" >/dev/null; then
    echo "NG: $file: Reusable Workflow の ref がありません" >&2
    errors=$((errors + 1))
  fi
  if rg -n -P 'uses:[[:space:]]*hasegawa496/\.github/\.github/workflows/[^[:space:]@]+\.yml@(?!main(?:[[:space:]]|$))' "$file" >/dev/null; then
    echo "NG: $file: Reusable Workflow の参照は @main にしてください" >&2
    errors=$((errors + 1))
  fi
done < <(find templates -type f -name '*.yml' -print0)

for reusable_workflow in "${reusable_workflows[@]}"; do
  workflow_name="$(basename "${reusable_workflow%-reusable.yml}")"
  template="templates/.github/workflows/${workflow_name}.yml"
  caller=".github/workflows/${workflow_name}.yml"
  documentation="docs/reusable-workflows/${workflow_name}.md"

  for required_file in "$template" "$caller" "$documentation"; do
    if [[ ! -f "$required_file" ]]; then
      echo "NG: $reusable_workflow: 対応するファイルがありません: $required_file" >&2
      errors=$((errors + 1))
    fi
  done

  if [[ -f "$template" ]] && ! rg -q "uses:[[:space:]]*hasegawa496/\\.github/\\.github/workflows/${workflow_name}-reusable\\.yml@main" "$template"; then
    echo "NG: $template: $reusable_workflow を @main で参照してください" >&2
    errors=$((errors + 1))
  fi
done

scripts/sync-workflow-callers.sh --check >/dev/null || {
  echo "NG: .github の自己利用設定が templates/ とズレています。scripts/sync-workflow-callers.sh --write を実行してください。" >&2
  exit 1
}

if (( errors > 0 )); then
  die "templates/ の検証に失敗しました（${errors}件）"
fi

echo "OK: templates/ と Reusable Workflow の検証に合格しました"

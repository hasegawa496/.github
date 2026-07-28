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

# 廃止予定の Reusable Workflow。composite action へ置き換え済みで
# 配布テンプレート・自己利用の呼び出し側は失うが、既存リポジトリが
# @main で参照し続けるため本体（*-reusable.yml）と個別仕様は残す
# （ADR 0003 移行手順6）。
deprecated_reusable_workflows=(
  shellcheck
)

is_deprecated_reusable_workflow() {
  local name="$1" deprecated
  for deprecated in "${deprecated_reusable_workflows[@]}"; do
    [[ "$deprecated" == "$name" ]] && return 0
  done
  return 1
}

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

  if is_deprecated_reusable_workflow "$workflow_name"; then
    required_files=("$documentation")
  else
    required_files=("$template" "$caller" "$documentation")
  fi

  for required_file in "${required_files[@]}"; do
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

actions=(actions/*/action.yml)
for action in "${actions[@]}"; do
  action_name="$(basename "$(dirname "$action")")"
  documentation="docs/actions/${action_name}.md"
  if [[ ! -f "$documentation" ]]; then
    echo "NG: $action: 対応するファイルがありません: $documentation" >&2
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

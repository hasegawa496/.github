#!/usr/bin/env bash
set -euo pipefail

# shellcheck disable=SC1007
script_dir="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "$script_dir/lib/common.sh"

watch_latest_run() {
  local run_id=""

  # `gh workflow run` は run id を返さないため、直近の run を取得して追跡する。
  for attempt in 1 2 3 4 5; do
    run_id="$(gh run list --workflow label-sync.yml --limit 1 --json databaseId -q '.[0].databaseId' 2>/dev/null || true)"
    if [[ -n "$run_id" ]]; then
      break
    fi
    echo "実行状況の取得待ち... ($attempt/5)" >&2
    sleep 2
  done

  if [[ -z "$run_id" ]]; then
    echo "実行状況を取得できませんでした。Actions 画面で 'Label Sync' の実行状況を確認してください。" >&2
    return 0
  fi

  if gh run watch "$run_id" --exit-status; then
    echo "workflow が完了しました（成功）。" >&2
    return 0
  fi

  echo "workflow が失敗しました。Actions のログを確認してください。" >&2
  return 1
}

run_label_sync_workflow() {
  local default_branch="$1"

  # workflow は登録直後に認識されるまで少し時間がかかることがある。
  for attempt in 1 2 3 4 5 6 7 8 9 10; do
    if gh workflow view label-sync.yml >/dev/null 2>&1; then
      break
    fi
    echo "workflow の認識待ち... ($attempt/10)" >&2
    sleep 2
  done

  if ! gh workflow view label-sync.yml >/dev/null 2>&1; then
    echo "GitHub が 'label-sync.yml' を workflow としてまだ認識していません。" >&2
    echo "数分待ってから Actions 画面で 'Label Sync' を手動実行してください。" >&2
    return 1
  fi

  if ! err="$(gh workflow run label-sync.yml --ref "$default_branch" 2>&1)"; then
    echo "$err" >&2
    if printf '%s' "$err" | grep -q "Workflow does not have 'workflow_dispatch' trigger"; then
      echo "label-sync.yml に workflow_dispatch が無いため起動できません。" >&2
      echo "（このリポジトリに入っているのは workflow_call 用の Reusable Workflow の可能性があります）" >&2
    fi
    echo "workflow の起動に失敗しました。Actions 画面から 'Label Sync' を手動実行してください。" >&2
    return 1
  fi

  watch_latest_run || true
  echo "起動しました: Label Sync（ref: $default_branch）"
}

assert_no_args "$@"
cd_repo_root
ensure_gh_auth

repo_full="$(get_repo_full)"

default_branch="$(gh repo view --json defaultBranchRef -q '.defaultBranchRef.name' 2>/dev/null || true)"
default_branch="${default_branch:-main}"

# このスクリプト自身（my-life）のテンプレートを正本として利用する。
# 想定実行: my-life を clone した状態で、対象リポジトリ上から相対/絶対パスで本スクリプトを呼ぶ。
template_workflow="$script_dir/../workflow-templates/label-sync.yml"
if [[ ! -f "$template_workflow" ]]; then
  die "テンプレートが見つかりません: $template_workflow"
fi

expected_workflow="$(mktemp -t label-sync.XXXXXX)"
cleanup() { rm -f "$expected_workflow"; }
trap cleanup EXIT

cp "$template_workflow" "$expected_workflow"

workflow_path=".github/workflows/label-sync.yml"

if ! install_or_skip_caller_workflow \
  "$repo_full" \
  "$expected_workflow" \
  "$workflow_path" \
  "$default_branch" \
  "chore/update-label-sync" \
  "chore: Label Sync workflow を導入/更新" \
  "chore: Label Sync workflow を導入/更新" \
  "hasegawa496/.github の Reusable Workflow を呼び出して、ラベルを同期できるようにします。"; then
  exit 1
fi

run_label_sync_workflow "$default_branch"

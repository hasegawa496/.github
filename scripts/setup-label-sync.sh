#!/usr/bin/env bash
set -euo pipefail

script_dir="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
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

# 期待値（既に同じものがあれば「起動だけ」で済ませる）。
expected_workflow="$(mktemp -t label-sync.XXXXXX)"
cleanup() { rm -f "$expected_workflow"; }
trap cleanup EXIT

cp "$template_workflow" "$expected_workflow"

# Actions が無効なら、可能なら API で有効化し、無理なら案内して中断する。
ensure_actions_enabled "$repo_full"

workflow_path=".github/workflows/label-sync.yml"
needs_apply_template="true"

if [[ -f "$workflow_path" ]]; then
  if ! command -v cmp >/dev/null 2>&1; then
    echo "既に存在します: $workflow_path（cmp が無いため、テンプレートで更新して導入を続行します）。" >&2
  else
    if cmp -s "$workflow_path" "$expected_workflow"; then
      needs_apply_template="false"
      echo "既に存在します: $workflow_path（同一内容のため、起動のみ実施します）" >&2
    fi
  fi
fi

if [[ "$needs_apply_template" == "false" ]]; then
  run_label_sync_workflow "$default_branch"
  exit 0
fi

# ここから先は workflow の導入/更新が必要な場合（ブランチ作成/コミット/push を行う）。
ensure_clean_worktree
ensure_origin_exists

# 事故防止: 必ずデフォルトブランチを最新化してから、そこを起点に専用ブランチを切る。
base_ref="$(ensure_remote_base_ref "$default_branch")"

ts="$(date -u +%Y%m%d-%H%M%S)"
branch="chore/update-label-sync-$ts"

if git show-ref --verify --quiet "refs/heads/$branch"; then
  die "ローカルに同名ブランチが存在します: $branch（時間をおいて再実行してください）"
fi

if ! err="$(git checkout -q -b "$branch" "$base_ref" 2>&1)"; then
  echo "$err" >&2
  die "ブランチの作成に失敗しました。"
fi

mkdir -p "$(dirname "$workflow_path")"
cp "$expected_workflow" "$workflow_path"

git add "$workflow_path"
if ! err="$(git commit -q -m "chore: Label Sync workflow を導入/更新" 2>&1)"; then
  echo "$err" >&2
  die "コミットに失敗しました。"
fi

if ! err="$(git push --quiet -u origin "$branch" 2>&1)"; then
  echo "$err" >&2
  die "push に失敗しました。リモート/権限/ブランチ保護などを確認してください。"
fi

if ! pr_number="$(create_or_get_pr \
  "$default_branch" \
  "$branch" \
  "chore: Label Sync workflow を導入/更新" \
  "hasegawa496/.github の Reusable Workflow を呼び出して、ラベルを同期できるようにします。")"; then
  exit 1
fi

# ここから先は「できたらやる」。失敗しても原因を表示して案内する。
echo "PR をマージします..." >&2
if ! merge_pr_or_fail \
  "$pr_number" \
  "$branch" \
  "PR を自動でマージできませんでした。PR を手動でマージした後、Actions から 'Label Sync' を実行してください。"; then
  exit 1
fi

echo "マージ完了。workflow を起動します..." >&2

if ! run_label_sync_workflow "$default_branch"; then
  exit 1
fi

echo "後片付けをします（ローカルブランチの削除など）..." >&2

# ローカルブランチは GitHub の設定（delete_branch_on_merge）では消えないため、
# ここで明示的に消します。作業ブランチ上にいる場合はデフォルトブランチへ戻します。
if ! git show-ref --verify --quiet "refs/heads/$default_branch"; then
  git fetch --quiet origin "$default_branch" >/dev/null 2>&1 || true
  git checkout -q -B "$default_branch" "origin/$default_branch"
else
  git checkout -q "$default_branch"
fi

if git show-ref --verify --quiet "refs/heads/$branch"; then
  git branch -D "$branch" >/dev/null 2>&1 || true
fi

# リモートブランチ削除は gh 側で試みていますが、残っている場合に備えて念のため実施します。
git push --quiet origin --delete "$branch" >/dev/null 2>&1 || true

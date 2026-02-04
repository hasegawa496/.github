#!/usr/bin/env bash
set -euo pipefail

script_dir="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$script_dir/lib/common.sh"

usage() {
  cat >&2 <<'USAGE'
使い方: scripts/setup-label-sync.sh

ラベル同期 workflow を導入し、可能ならそのまま起動します。

オプション:
  --no-wait  workflow の完了を待たずに終了します（デフォルトは待つ）
  --strict   既存の workflow が想定と違う場合は中断します（デフォルトは警告して実行）

注意:
  - 対象リポジトリのルートで実行してください。
  - 前提: git, gh（GitHub CLI）, `gh auth login` 済み
USAGE
}

wait_for_completion="true"
strict_mode="false"
for arg in "$@"; do
  case "$arg" in
    -h|--help) usage; exit 0 ;;
    --no-wait) wait_for_completion="false" ;;
    --strict) strict_mode="true" ;;
    *) die "不明な引数です: $arg（--help を参照）" ;;
  esac
done

watch_latest_run() {
  local run_id=""

  # `gh workflow run` は run id を返さないため、直近の run を取得して追跡する。
  for attempt in 1 2 3 4 5; do
    run_id="$(gh run list --workflow sync-labels-manual.yml --limit 1 --json databaseId -q '.[0].databaseId' 2>/dev/null || true)"
    if [[ -n "$run_id" ]]; then
      break
    fi
    echo "実行状況の取得待ち... ($attempt/5)" >&2
    sleep 2
  done

  if [[ -z "$run_id" ]]; then
    echo "実行状況を取得できませんでした。Actions 画面で 'Sync Labels (Manual)' の実行状況を確認してください。" >&2
    return 0
  fi

  if gh run watch "$run_id" --exit-status; then
    echo "workflow が完了しました（成功）。" >&2
    return 0
  fi

  echo "workflow が失敗しました。Actions のログを確認してください。" >&2
  return 1
}

cleanup_remote_branch_hint() {
  local branch="$1"
  echo "リモートブランチが残っている場合の削除例:" >&2
  echo "  gh pr list --head \"$branch\"" >&2
  echo "  gh pr close --delete-branch \"$branch\"  # PRが残っていれば" >&2
  echo "  git push origin --delete \"$branch\"     # 直接消す（権限があれば）" >&2
}

cd_repo_root
ensure_gh_auth

repo_full="$(get_repo_full)"

default_branch="$(gh repo view --json defaultBranchRef -q '.defaultBranchRef.name' 2>/dev/null || true)"
default_branch="${default_branch:-main}"

# スクリプトが投入する workflow の期待値（既に同じものがあれば「起動だけ」で済ませる）。
expected_workflow="$(mktemp -t sync-labels.XXXXXX)"
cleanup() { rm -f "$expected_workflow"; }
trap cleanup EXIT

cat >"$expected_workflow" <<'YAML'
# ラベル同期（Reusable Workflow呼び出し）
#
# 呼び出し先:
#   - hasegawa496/.github/.github/workflows/sync-labels.yml（Reusable Workflow）
#   - hasegawa496/.github/.github/labels.yml（ラベル定義）

name: Sync Labels

on:
  workflow_dispatch:  # 手動実行

permissions:
  contents: read
  issues: write

jobs:
  sync:
    uses: hasegawa496/.github/.github/workflows/sync-labels.yml@main
    secrets: inherit
YAML

# Actions が無効なら、可能なら API で有効化し、無理なら案内して中断する。
ensure_actions_enabled "$repo_full"

# 既に workflow が入っているなら、安全のため上書きはせず「起動だけ」する。
workflow_path=".github/workflows/sync-labels-manual.yml"
if [[ -f "$workflow_path" ]]; then
  if ! command -v cmp >/dev/null 2>&1; then
    if [[ "$strict_mode" == "true" ]]; then
      die "$workflow_path は既に存在します（cmp コマンドが無いため内容比較できません）。--strict のため中断します。"
    fi
    echo "既に存在します: $workflow_path（cmp が無いため内容比較できません）。上書きせず、workflow を起動します。" >&2
  else
    if ! cmp -s "$workflow_path" "$expected_workflow"; then
      if [[ "$strict_mode" == "true" ]]; then
        die "既に存在します: $workflow_path（内容が想定と異なるため、--strict のため中断します）"
      fi

      if ! grep -q "workflow_dispatch" -- "$workflow_path"; then
        die "既に存在します: $workflow_path（内容が想定と異なり、workflow_dispatch もありません）。この workflow は手動実行できません。テンプレート（workflow-templates/sync-labels-manual.yml）を .github/workflows/sync-labels-manual.yml として導入し直してください。"
      fi

      echo "既に存在します: $workflow_path（内容が想定と異なります）。上書きせず、workflow を起動します。" >&2
      echo "※ 定義や呼び出し先が更新されている可能性があるため、必要に応じて $workflow_path の内容を確認してください。" >&2
    else
      echo "既に存在します: $workflow_path（同一内容のため、上書きせず workflow を起動します）" >&2
    fi
  fi

  # workflow は登録直後に認識されるまで少し時間がかかることがある。
  for attempt in 1 2 3 4 5 6 7 8 9 10; do
    if gh workflow view sync-labels-manual.yml >/dev/null 2>&1; then
      break
    fi
    echo "workflow の認識待ち... ($attempt/10)" >&2
    sleep 2
  done

  if ! gh workflow view sync-labels-manual.yml >/dev/null 2>&1; then
    echo "GitHub が 'sync-labels-manual.yml' を workflow としてまだ認識していません。" >&2
    echo "数分待ってから Actions 画面で 'Sync Labels (Manual)' を手動実行してください。" >&2
    exit 1
  fi

  if ! err="$(gh workflow run sync-labels-manual.yml --ref "$default_branch" 2>&1)"; then
    echo "$err" >&2
    if printf '%s' "$err" | grep -q "Workflow does not have 'workflow_dispatch' trigger"; then
      echo "sync-labels-manual.yml に workflow_dispatch が無いため起動できません。" >&2
      echo "（このリポジトリに入っているのは workflow_call 用の Reusable Workflow の可能性があります）" >&2
    fi
    echo "workflow の起動に失敗しました。Actions 画面から 'Sync Labels (Manual)' を手動実行してください。" >&2
    exit 1
  fi

  if [[ "$wait_for_completion" == "true" ]]; then
    watch_latest_run || true
  fi

  echo "起動しました: Sync Labels (Manual)（ref: $default_branch）"
  exit 0
fi

# ここから先は workflow 未導入の場合のみ（ブランチ作成/コミット/push を行う）。
if [[ -n "$(git status --porcelain=v1)" ]]; then
  die "作業ツリーがクリーンではありません。変更を commit / stash してから再実行してください。"
fi

if ! git remote get-url origin >/dev/null 2>&1; then
  die "remote 'origin' が設定されていません。設定（例: `git remote add origin ...`）して再実行してください。"
fi

# 事故防止: 必ずデフォルトブランチを最新化してから、そこを起点に専用ブランチを切る。
if ! err="$(git fetch --quiet origin "$default_branch" 2>&1)"; then
  echo "$err" >&2
  die "origin/$default_branch の fetch に失敗しました。ネットワーク/remote 設定を確認してください。"
fi

base_ref="origin/$default_branch"
if ! git show-ref --verify --quiet "refs/remotes/$base_ref"; then
  die "参照が見つかりません: $base_ref"
fi

ts="$(date -u +%Y%m%d-%H%M%S)"
branch="chore/add-sync-labels-$ts"

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
if ! err="$(git commit -q -m "chore: ラベル同期 workflow を追加" 2>&1)"; then
  echo "$err" >&2
  die "コミットに失敗しました。"
fi

if ! err="$(git push --quiet -u origin "$branch" 2>&1)"; then
  echo "$err" >&2
  die "push に失敗しました。リモート/権限/ブランチ保護などを確認してください。"
fi

gh pr create \
  --title "chore: ラベル同期 workflow を追加" \
  --body "hasegawa496/.github の Reusable Workflow を呼び出して、ラベルを同期できるようにします。" \
  --base "$default_branch" \
  --head "$branch" >/dev/null 2>&1 || true

pr_number="$(gh pr list --head "$branch" --json number -q '.[0].number' 2>/dev/null || true)"
pr_url="$(gh pr view "$branch" --json url -q '.url' 2>/dev/null || true)"

if [[ -z "$pr_number" ]]; then
  echo "PR を作成できませんでした（既に存在するか、権限不足の可能性があります）。" >&2
  echo "ブランチは push 済みです: $branch" >&2
  exit 1
fi

echo "PR: #$pr_number ($branch -> $default_branch)"
if [[ -n "$pr_url" ]]; then
  echo "PR URL: $pr_url"
fi

# ここから先は「できたらやる」。失敗しても原因を表示して案内する。
echo "PR をマージします..." >&2
if ! err="$(gh pr merge "$pr_number" --squash --delete-branch 2>&1)"; then
  echo "$err" >&2
  echo "PR を自動でマージできませんでした。PR を手動でマージした後、Actions から 'Sync Labels (Manual)' を実行してください。" >&2
  cleanup_remote_branch_hint "$branch"
  exit 1
fi

echo "マージ完了。workflow を起動します..." >&2

# workflow はマージ直後に登録されるまで少し時間がかかることがある。
for attempt in 1 2 3 4 5 6 7 8 9 10; do
  if gh workflow view sync-labels-manual.yml >/dev/null 2>&1; then
    break
  fi
  echo "workflow の認識待ち... ($attempt/10)" >&2
  sleep 2
done

if ! gh workflow view sync-labels-manual.yml >/dev/null 2>&1; then
  echo "GitHub が 'sync-labels-manual.yml' を workflow としてまだ認識していません。" >&2
  echo "数分待ってから Actions 画面で 'Sync Labels (Manual)' を手動実行してください。" >&2
  exit 1
fi

if ! err="$(gh workflow run sync-labels-manual.yml --ref "$default_branch" 2>&1)"; then
  echo "$err" >&2
  echo "workflow の起動に失敗しました。Actions 画面から 'Sync Labels (Manual)' を手動実行してください。" >&2
  exit 1
fi

if [[ "$wait_for_completion" == "true" ]]; then
  watch_latest_run || true
fi

echo "起動しました: Sync Labels (Manual)（ref: $default_branch）"

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

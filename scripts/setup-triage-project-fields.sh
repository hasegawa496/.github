#!/usr/bin/env bash
set -euo pipefail

script_dir="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$script_dir/lib/common.sh"

usage() {
  cat >&2 <<'USAGE'
使い方: scripts/setup-triage-project-fields.sh

Issue 作成/編集時に Project（Projects v2）へ自動追加し、
Issue フォームの入力値（優先度/規模/Estimate）を Project フィールドへ反映する workflow を導入します。

オプション:
  --strict  既存の workflow が想定と違う場合は中断します（デフォルトは警告して継続）

注意:
  - 対象リポジトリのルートで実行してください。
  - 前提: git, gh（GitHub CLI）, `gh auth login` 済み
  - Secrets: PROJECT_TOKEN（Projects v2 へ書き込めるトークン）が必要です
USAGE
}

strict_mode="false"
for arg in "$@"; do
  case "$arg" in
    -h|--help) usage; exit 0 ;;
    --strict) strict_mode="true" ;;
    *) die "不明な引数です: $arg（--help を参照）" ;;
  esac
done

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

expected_workflow="$(mktemp -t triage-project-fields-issues.XXXXXX)"
cleanup() { rm -f "$expected_workflow"; }
trap cleanup EXIT

cat >"$expected_workflow" <<'YAML'
# Issue 作成/編集時に Project へ自動追加し、優先度/規模/Estimate を自動設定します
#
# 使い方:
#   1) このファイルを各リポジトリの `.github/workflows/triage-project-fields-issues.yml` へコピーして push
#   2) リポジトリの Secrets に以下を設定
#        - PROJECT_TOKEN: Projects v2 を更新できるトークン（PAT など）
#   3) Projects v2 側にフィールドを作成（名前を揃える）
#        - 優先度（Single select）
#        - 規模（Single select）
#        - Estimate（Number）

name: Issueトリアージ（Projectフィールド自動設定）

on:
  issues:
    types: [opened, edited, reopened]

permissions:
  contents: read
  issues: write

jobs:
  triage:
    uses: hasegawa496/.github/.github/workflows/triage-project-fields.yml@main
    with:
      project_number: 12
      # project_owner: hasegawa496
      # priority_field_name: 優先度
      # size_field_name: 規模
      # estimate_field_name: Estimate
    secrets:
      project_token: ${{ secrets.PROJECT_TOKEN }}
YAML

ensure_actions_enabled "$repo_full"

workflow_path=".github/workflows/triage-project-fields-issues.yml"
if [[ -f "$workflow_path" ]]; then
  if ! command -v cmp >/dev/null 2>&1; then
    if [[ "$strict_mode" == "true" ]]; then
      die "$workflow_path は既に存在します（cmp コマンドが無いため内容比較できません）。--strict のため中断します。"
    fi
    echo "既に存在します: $workflow_path（cmp が無いため内容比較できません）。上書きせず終了します。" >&2
    exit 0
  fi

  if ! cmp -s "$workflow_path" "$expected_workflow"; then
    if [[ "$strict_mode" == "true" ]]; then
      die "既に存在します: $workflow_path（内容が想定と異なるため、--strict のため中断します）"
    fi
    if ! grep -q "on:[[:space:]]*$" -- "$workflow_path" && ! grep -q "issues:" -- "$workflow_path"; then
      echo "既に存在します: $workflow_path（内容が想定と異なり、issues トリガが見当たりません）。" >&2
      echo "この workflow は Issue 作成時に自動実行されない可能性があります。内容を確認してください。" >&2
    else
      echo "既に存在します: $workflow_path（内容が想定と異なります）。上書きせず終了します。" >&2
      echo "※ 定義や呼び出し先が更新されている可能性があるため、必要に応じて内容を確認してください。" >&2
    fi
    exit 0
  fi

  echo "既に存在します: $workflow_path（同一内容のため、上書きせず終了します）" >&2
  exit 0
fi

if [[ -n "$(git status --porcelain=v1)" ]]; then
  die "作業ツリーがクリーンではありません。変更を commit / stash してから再実行してください。"
fi

if ! git remote get-url origin >/dev/null 2>&1; then
  die "remote 'origin' が設定されていません。設定（例: `git remote add origin ...`）して再実行してください。"
fi

if ! err="$(git fetch --quiet origin "$default_branch" 2>&1)"; then
  echo "$err" >&2
  die "origin/$default_branch の fetch に失敗しました。ネットワーク/remote 設定を確認してください。"
fi

base_ref="origin/$default_branch"
if ! git show-ref --verify --quiet "refs/remotes/$base_ref"; then
  die "参照が見つかりません: $base_ref"
fi

ts="$(date -u +%Y%m%d-%H%M%S)"
branch="chore/add-triage-project-fields-$ts"

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
if ! err="$(git commit -q -m "chore: Issue トリアージ workflow を追加" 2>&1)"; then
  echo "$err" >&2
  die "コミットに失敗しました。"
fi

if ! err="$(git push --quiet -u origin "$branch" 2>&1)"; then
  echo "$err" >&2
  die "push に失敗しました。リモート/権限/ブランチ保護などを確認してください。"
fi

gh pr create \
  --title "chore: Issue トリアージ workflow を追加" \
  --body "Issue 作成/編集時に Projects v2 へ追加し、Issue フォーム（優先度/規模/Estimate）の値を Project フィールドへ反映します。\n\n前提:\n- Secrets: PROJECT_TOKEN\n- Project フィールド: 優先度/規模（Single select）, Estimate（Number）" \
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

echo "PR をマージします..." >&2
if ! err="$(gh pr merge "$pr_number" --squash --delete-branch 2>&1)"; then
  echo "$err" >&2
  echo "PR を自動でマージできませんでした。PR を手動でマージしてください。" >&2
  cleanup_remote_branch_hint "$branch"
  exit 1
fi

echo "マージ完了。workflow の認識待ち..." >&2
for attempt in 1 2 3 4 5 6 7 8 9 10; do
  if gh workflow view triage-project-fields-issues.yml >/dev/null 2>&1; then
    break
  fi
  echo "workflow の認識待ち... ($attempt/10)" >&2
  sleep 2
done

if ! gh workflow view triage-project-fields-issues.yml >/dev/null 2>&1; then
  echo "GitHub が 'triage-project-fields-issues.yml' を workflow としてまだ認識していません。" >&2
  echo "数分待ってから、Issue を作成/編集してトリアージが走るか確認してください。" >&2
  exit 1
fi

echo "導入完了: Issue トリアージ（Projectフィールド自動設定）" >&2
echo "次に行うこと（対象リポジトリ側）:" >&2
echo "  1) Secrets に PROJECT_TOKEN を設定（Projects v2 へ書き込み可能な権限）" >&2
echo "  2) Projects v2 側にフィールド（優先度/規模/Estimate）を作成" >&2
echo "  3) Issue を作成/編集して、Project フィールドが更新されるか確認" >&2


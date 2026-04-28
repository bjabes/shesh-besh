#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

BASE_BRANCH="${BASE_BRANCH:-main}"
PR_TITLE="${PR_TITLE:-$(git log -1 --pretty=%s)}"
PR_BODY_PATH="${PR_BODY_PATH:-$ROOT_DIR/.context/pr-body.md}"
UPLOADED_PR_BODY_PATH="${UPLOADED_PR_BODY_PATH:-$ROOT_DIR/.context/pr-body-uploaded.md}"
SCREENSHOT_MANIFEST_PATH="${SCREENSHOT_MANIFEST_PATH:-$ROOT_DIR/.context/pr-screenshots.txt}"

usage() {
  cat <<'USAGE'
Usage: scripts/create-pr.sh [additional gh pr create flags]

Runs local PR prep, uploads captured screenshots to a secret gist when present,
embeds those images in the PR body, then creates the PR with gh.

Environment:
  BASE_BRANCH             PR base branch. Default: main
  PR_TITLE                PR title. Default: latest commit subject
  PR_BODY_PATH            Prep body path. Default: .context/pr-body.md
  UPLOADED_PR_BODY_PATH   Final body path. Default: .context/pr-body-uploaded.md
  SCREENSHOT_MANIFEST_PATH
                          Screenshot manifest. Default: .context/pr-screenshots.txt
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

./scripts/prepare-pr.sh
cp "$PR_BODY_PATH" "$UPLOADED_PR_BODY_PATH"

screenshots=()
if [[ -f "$SCREENSHOT_MANIFEST_PATH" ]]; then
  while IFS= read -r screenshot; do
    [[ -n "$screenshot" ]] && screenshots+=("$screenshot")
  done < "$SCREENSHOT_MANIFEST_PATH"
fi

if [[ "${#screenshots[@]}" -gt 0 ]]; then
  repo_name="$(gh repo view --json nameWithOwner -q .nameWithOwner)"
  branch_name="$(git branch --show-current)"
  gist_url="$(
    gh gist create "${screenshots[@]}" \
      --desc "PR screenshots for $repo_name $branch_name"
  )"
  gist_id="${gist_url##*/}"

  {
    echo
    echo "### Uploaded Screenshots"
    gh api "gists/$gist_id" \
      --jq '.files | to_entries[] | [.key, .value.raw_url] | @tsv' |
      while IFS=$'\t' read -r filename raw_url; do
        echo "![${filename}](${raw_url})"
      done
  } >> "$UPLOADED_PR_BODY_PATH"
fi

gh pr create \
  --base "$BASE_BRANCH" \
  --title "$PR_TITLE" \
  --body-file "$UPLOADED_PR_BODY_PATH" \
  "$@"

#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

BASE_REF="${BASE_REF:-origin/main}"
PR_BODY_PATH="${PR_BODY_PATH:-$ROOT_DIR/.context/pr-body.md}"
SCREENSHOT_DIR="${SCREENSHOT_DIR:-$ROOT_DIR/.context/pr-screenshots}"
manual_screenshot_backup=""

cleanup() {
  if [[ -n "$manual_screenshot_backup" && -d "$manual_screenshot_backup" ]]; then
    rm -rf "$manual_screenshot_backup"
  fi
}
trap cleanup EXIT

usage() {
  cat <<'USAGE'
Usage: scripts/prepare-pr.sh

Prepares local PR evidence against origin/main by:
  - inspecting changed files
  - capturing deterministic app screenshots for UI-affecting diffs
  - writing a PR body draft with a Screenshots section

Environment:
  BASE_REF       Diff base. Default: origin/main
  PR_BODY_PATH   Output PR body draft. Default: .context/pr-body.md
  SCREENSHOT_DIR Screenshot output directory. Default: .context/pr-screenshots
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if ! git rev-parse --verify "$BASE_REF" >/dev/null 2>&1; then
  echo "Base ref '$BASE_REF' was not found. Fetch origin or set BASE_REF." >&2
  exit 1
fi

changed_files=()
while IFS= read -r file; do
  [[ -n "$file" ]] && changed_files+=("$file")
done < <(
  {
    git diff --name-only "$BASE_REF"...HEAD
    git diff --name-only --cached
    git diff --name-only
    git ls-files --others --exclude-standard
  } | sort -u
)

ui_files=()
manual_review_files=()
screenshots=()

is_ui_file() {
  local file="$1"

  case "$file" in
    SheshBesh/*|SheshBesh.xcodeproj/*|SheshBeshUITests/*)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

is_deterministic_flow_file() {
  local file="$1"

  case "$file" in
    SheshBesh/Shared/BoardView.swift|\
    SheshBesh/Shared/CheckerLayout.swift|\
    SheshBesh/Shared/MatchViewModel.swift|\
    SheshBeshUITests/SheshBeshUITests.swift)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

collect_screenshots() {
  screenshots=()

  [[ -d "$SCREENSHOT_DIR" ]] || return 0

  while IFS= read -r screenshot; do
    [[ -n "$screenshot" ]] && screenshots+=("$screenshot")
  done < <(
    find "$SCREENSHOT_DIR" \
      -maxdepth 1 \
      -type f \
      \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' \) \
      -print | sort
  )
}

preserve_existing_screenshots() {
  [[ -d "$SCREENSHOT_DIR" ]] || return 0

  manual_screenshot_backup="$(mktemp -d "${TMPDIR:-/tmp}/pr-screenshots.XXXXXX")"
  while IFS= read -r screenshot; do
    cp "$screenshot" "$manual_screenshot_backup/$(basename "$screenshot")"
  done < <(
    find "$SCREENSHOT_DIR" \
      -maxdepth 1 \
      -type f \
      \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' \) \
      -print
  )
}

restore_preserved_screenshots() {
  [[ -n "$manual_screenshot_backup" && -d "$manual_screenshot_backup" ]] || return 0

  mkdir -p "$SCREENSHOT_DIR"
  while IFS= read -r screenshot; do
    cp -n "$screenshot" "$SCREENSHOT_DIR/$(basename "$screenshot")"
  done < <(
    find "$manual_screenshot_backup" \
      -maxdepth 1 \
      -type f \
      \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' \) \
      -print
  )
}

for file in "${changed_files[@]}"; do
  if is_ui_file "$file"; then
    ui_files+=("$file")

    if ! is_deterministic_flow_file "$file"; then
      manual_review_files+=("$file")
    fi
  fi
done

mkdir -p "$(dirname "$PR_BODY_PATH")"

screenshot_count=0
if [[ "${#ui_files[@]}" -gt 0 ]]; then
  preserve_existing_screenshots
  set +e
  SCREENSHOT_DIR="$SCREENSHOT_DIR" ./scripts/capture-pr-screenshots.sh
  capture_status=$?
  set -e
  restore_preserved_screenshots
  if [[ "$capture_status" -ne 0 ]]; then
    exit "$capture_status"
  fi

  collect_screenshots
  screenshot_count="${#screenshots[@]}"

  if [[ "$screenshot_count" -eq 0 ]]; then
    echo "No screenshots found in $SCREENSHOT_DIR after capture." >&2
    exit 1
  fi
fi

{
  echo "## Summary"
  echo "- "
  echo
  echo "## Tests"
  echo "- "
  echo
  echo "## Screenshots"

  if [[ "${#ui_files[@]}" -eq 0 ]]; then
    echo "Screenshots not applicable; this diff does not change app UI files."
  else
    rel_screenshot_dir="${SCREENSHOT_DIR#$ROOT_DIR/}"
    echo "Local screenshots available in \`$rel_screenshot_dir\`:"
    for screenshot in "${screenshots[@]}"; do
      rel_path="${screenshot#$ROOT_DIR/}"
      echo "- \`$rel_path\`"
    done
    echo
    echo "The PR screenshot workflow will upload the \`pr-screenshots\` artifact for reviewers."

    if [[ "${#manual_review_files[@]}" -gt 0 ]]; then
      echo
      echo "Manual screenshot review needed for changed files outside the deterministic board flow:"
      for file in "${manual_review_files[@]}"; do
        echo "- \`$file\`"
      done
      echo
      echo "Add targeted manual screenshots to \`$rel_screenshot_dir\`, then rerun \`./scripts/prepare-pr.sh\` so this PR body includes them."
    fi
  fi
} > "$PR_BODY_PATH"

echo "Changed files compared with $BASE_REF: ${#changed_files[@]}"
echo "UI-affecting files: ${#ui_files[@]}"
if [[ "${#ui_files[@]}" -gt 0 ]]; then
  echo "Screenshots captured: $screenshot_count"
fi
echo "PR body draft: ${PR_BODY_PATH#$ROOT_DIR/}"

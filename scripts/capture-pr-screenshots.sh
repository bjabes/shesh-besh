#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

IOS_TEST_DESTINATION="${IOS_TEST_DESTINATION:-platform=iOS Simulator,name=iPhone 17,OS=latest}"
SCREENSHOT_DIR="${SCREENSHOT_DIR:-$ROOT_DIR/.context/pr-screenshots}"
RESULT_BUNDLE_PATH="${RESULT_BUNDLE_PATH:-$ROOT_DIR/.context/pr-screenshots.xcresult}"
ATTACHMENTS_DIR="$SCREENSHOT_DIR/.xcresult-attachments"

rm -rf "$SCREENSHOT_DIR" "$RESULT_BUNDLE_PATH"
mkdir -p "$ATTACHMENTS_DIR"

xcodebuild \
  -project SheshBesh.xcodeproj \
  -scheme SheshBesh \
  -destination "$IOS_TEST_DESTINATION" \
  -only-testing:SheshBeshUITests/SheshBeshUITests/testPRScreenshots \
  -resultBundlePath "$RESULT_BUNDLE_PATH" \
  CODE_SIGNING_ALLOWED=NO \
  test

xcrun xcresulttool export attachments \
  --path "$RESULT_BUNDLE_PATH" \
  --output-path "$ATTACHMENTS_DIR"

screenshot_count=0
manifest_path="$ATTACHMENTS_DIR/manifest.json"
if command -v jq >/dev/null 2>&1 && [[ -f "$manifest_path" ]]; then
  while IFS=$'\t' read -r exported_name suggested_name; do
    source_path="$ATTACHMENTS_DIR/$exported_name"
    [[ -f "$source_path" ]] || continue

    extension="${suggested_name##*.}"
    filename="${suggested_name%.*}"
    filename="${filename%%_0_*}"
    cp "$source_path" "$SCREENSHOT_DIR/$filename.$extension"
    screenshot_count=$((screenshot_count + 1))
  done < <(
    jq -r '.[] | .attachments[] | [.exportedFileName, .suggestedHumanReadableName] | @tsv' \
      "$manifest_path"
  )
else
  while IFS= read -r -d '' attachment; do
    filename="$(basename "$attachment")"
    cp "$attachment" "$SCREENSHOT_DIR/$filename"
    screenshot_count=$((screenshot_count + 1))
  done < <(
    find "$ATTACHMENTS_DIR" \
    -maxdepth 2 \
    -type f \
    \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' \) \
    -print0
  )
fi

if [[ "$screenshot_count" -eq 0 ]]; then
  echo "No screenshots were exported from $RESULT_BUNDLE_PATH" >&2
  exit 1
fi

rm -rf "$ATTACHMENTS_DIR"

find "$SCREENSHOT_DIR" \
  -maxdepth 1 \
  -type f \
  \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' \) \
  -print

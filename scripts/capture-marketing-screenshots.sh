#!/usr/bin/env bash
set -euo pipefail

# Capture marketing-quality screenshots at App Store device sizes.
#
# Runs every method in SheshBeshUITests/PRScreenshotsTests against one or
# more iPhone simulators and exports the named attachments as PNGs into
# marketing/screenshots/<size>/. The PR pipeline lives in
# scripts/capture-pr-screenshots.sh and is intentionally separate so the
# diff visuals don't drift when this list grows.
#
# Override which devices to capture by setting MARKETING_SCREENSHOT_DEVICES
# to a comma-separated list of "<size-key>:<simulator-name>" entries, e.g.
#   MARKETING_SCREENSHOT_DEVICES="iphone-6.9:iPhone 17 Pro Max"
# Defaults capture both the App Store-required 6.9" size and a 6.3"
# reference size.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

OS_VERSION="${MARKETING_SCREENSHOT_OS:-latest}"
DEVICES_RAW="${MARKETING_SCREENSHOT_DEVICES:-iphone-6.9:iPhone 17 Pro Max,iphone-6.3:iPhone 17}"
OUTPUT_ROOT="${MARKETING_SCREENSHOT_DIR:-$ROOT_DIR/marketing/screenshots}"
RESULT_BUNDLE_ROOT="${MARKETING_RESULT_BUNDLE_DIR:-$ROOT_DIR/.context/marketing-screenshots-xcresult}"

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required for marketing screenshot renaming. Install with: brew install jq" >&2
  exit 1
fi

mkdir -p "$OUTPUT_ROOT"
rm -rf "$RESULT_BUNDLE_ROOT"
mkdir -p "$RESULT_BUNDLE_ROOT"

IFS=',' read -r -a device_entries <<<"$DEVICES_RAW"

for entry in "${device_entries[@]}"; do
  entry="${entry#"${entry%%[![:space:]]*}"}"
  entry="${entry%"${entry##*[![:space:]]}"}"
  [[ -z "$entry" ]] && continue

  size_key="${entry%%:*}"
  device_name="${entry#*:}"
  if [[ -z "$size_key" || -z "$device_name" || "$size_key" == "$device_name" ]]; then
    echo "Bad MARKETING_SCREENSHOT_DEVICES entry: '$entry' (expected 'size-key:Simulator Name')" >&2
    exit 1
  fi

  destination="platform=iOS Simulator,name=$device_name,OS=$OS_VERSION"
  size_dir="$OUTPUT_ROOT/$size_key"
  result_bundle="$RESULT_BUNDLE_ROOT/$size_key.xcresult"
  attachments_dir="$RESULT_BUNDLE_ROOT/$size_key-attachments"

  echo "==> Capturing $size_key on $device_name"
  rm -rf "$size_dir" "$result_bundle" "$attachments_dir"
  mkdir -p "$size_dir" "$attachments_dir"

  xcodebuild \
    -project SheshBesh.xcodeproj \
    -scheme SheshBesh \
    -destination "$destination" \
    -only-testing:SheshBeshUITests/PRScreenshotsTests \
    -resultBundlePath "$result_bundle" \
    CODE_SIGNING_ALLOWED=NO \
    test

  xcrun xcresulttool export attachments \
    --path "$result_bundle" \
    --output-path "$attachments_dir"

  manifest_path="$attachments_dir/manifest.json"
  if [[ ! -f "$manifest_path" ]]; then
    echo "No manifest at $manifest_path — xcresulttool exported nothing" >&2
    exit 1
  fi

  screenshot_count=0
  while IFS=$'\t' read -r exported_name suggested_name; do
    source_path="$attachments_dir/$exported_name"
    [[ -f "$source_path" ]] || continue

    extension="${suggested_name##*.}"
    filename="${suggested_name%.*}"
    filename="${filename%%_0_*}"
    cp "$source_path" "$size_dir/$filename.$extension"
    screenshot_count=$((screenshot_count + 1))
  done < <(
    jq -r '.[] | .attachments[] | [.exportedFileName, .suggestedHumanReadableName] | @tsv' \
      "$manifest_path"
  )

  if [[ "$screenshot_count" -eq 0 ]]; then
    echo "No screenshots exported for $size_key from $result_bundle" >&2
    exit 1
  fi

  rm -rf "$attachments_dir"
  echo "  wrote $screenshot_count screenshots to $size_dir"
done

rm -rf "$RESULT_BUNDLE_ROOT"

find "$OUTPUT_ROOT" \
  -type f \
  \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' \) \
  -print

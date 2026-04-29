#!/usr/bin/env bash
set -euo pipefail

# Build the App Store-ready marketing pack: 1024×1024 icon + screenshots.
#
# Outputs land under marketing/icon/ and marketing/screenshots/<size>/.
# Both subtrees are gitignored — run this script before any App Store
# Connect upload, not as a checked-in artifact.
#
# Icon step: copies SheshBesh/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png
# into marketing/icon/icon-1024.png with alpha stripped (App Store rejects
# alpha channels).
#
# Screenshot step: runs every method in SheshBeshUITests/PRScreenshotsTests
# against one or more iPhone simulators and exports the named attachments
# as PNGs. The PR pipeline lives in scripts/capture-pr-screenshots.sh and
# is intentionally separate so the diff visuals don't drift when this list
# grows.
#
# Override which devices to capture by setting MARKETING_SCREENSHOT_DEVICES
# to a comma-separated list of "<size-key>:<simulator-name>" entries, e.g.
#   MARKETING_SCREENSHOT_DEVICES="iphone-6.9:iPhone 17 Pro Max"
# Defaults capture the three App Store-relevant sizes: 6.9" (current Pro
# Max class), 6.5" (legacy Plus / Pro Max class), and 6.3" (standard).

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

OS_VERSION="${MARKETING_SCREENSHOT_OS:-latest}"
DEVICES_RAW="${MARKETING_SCREENSHOT_DEVICES:-iphone-6.9:iPhone 17 Pro Max,iphone-6.5:iPhone 11 Pro Max,iphone-6.3:iPhone 17}"
OUTPUT_ROOT="${MARKETING_SCREENSHOT_DIR:-$ROOT_DIR/marketing/screenshots}"
RESULT_BUNDLE_ROOT="${MARKETING_RESULT_BUNDLE_DIR:-$ROOT_DIR/.context/marketing-screenshots-xcresult}"
ICON_SOURCE="$ROOT_DIR/SheshBesh/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png"
ICON_DEST_DIR="$ROOT_DIR/marketing/icon"
ICON_DEST="$ICON_DEST_DIR/icon-1024.png"

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required for marketing screenshot renaming. Install with: brew install jq" >&2
  exit 1
fi

echo "==> Building App Store icon"
if [[ ! -f "$ICON_SOURCE" ]]; then
  echo "Missing icon source at $ICON_SOURCE" >&2
  exit 1
fi
mkdir -p "$ICON_DEST_DIR"
source_alpha="$(sips -g hasAlpha "$ICON_SOURCE" | awk '/hasAlpha/ {print $2}')"
if [[ "$source_alpha" == "yes" ]]; then
  sips -s format png -s hasAlpha no "$ICON_SOURCE" --out "$ICON_DEST" >/dev/null
else
  cp "$ICON_SOURCE" "$ICON_DEST"
fi
dest_alpha="$(sips -g hasAlpha "$ICON_DEST" | awk '/hasAlpha/ {print $2}')"
if [[ "$dest_alpha" != "no" ]]; then
  echo "Icon at $ICON_DEST has alpha (got: $dest_alpha) — App Store rejects alpha" >&2
  exit 1
fi
echo "  wrote $ICON_DEST"

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

printf '%s\n' "$ICON_DEST"
find "$OUTPUT_ROOT" \
  -type f \
  \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' \) \
  -print

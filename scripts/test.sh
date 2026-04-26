#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

run_step() {
  local title="$1"
  shift

  echo "::group::${title}"
  if "$@"; then
    echo "::endgroup::"
  else
    local status=$?
    echo "::endgroup::"
    return "$status"
  fi
}

run_step "Swift package build" \
  swift build

run_step "Swift package tests" \
  swift test

run_step "Xcode project build" \
  xcodebuild \
    -project SheshBesh.xcodeproj \
    -scheme SheshBesh \
    -destination "generic/platform=iOS Simulator" \
    CODE_SIGNING_ALLOWED=NO \
    build

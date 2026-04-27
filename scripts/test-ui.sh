#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

IOS_TEST_DESTINATION="${IOS_TEST_DESTINATION:-platform=iOS Simulator,name=iPhone 17,OS=latest}"

xcodebuild \
  -project SheshBesh.xcodeproj \
  -scheme SheshBesh \
  -destination "$IOS_TEST_DESTINATION" \
  CODE_SIGNING_ALLOWED=NO \
  test

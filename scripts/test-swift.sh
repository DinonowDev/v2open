#!/usr/bin/env bash
# Compile and run macOS unit tests that do not need the full app bundle.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=macos-env.sh
source "$ROOT/macos-env.sh"

OUT="$(mktemp -d "${TMPDIR:-/tmp}/v2open-swift-tests.XXXXXX")"
trap 'rm -rf "$OUT"' EXIT

swiftc -parse-as-library -g -Onone -target "$SWIFT_TARGET" \
  -o "$OUT/v2open-swift-tests" \
  "$ROOT/macos-app/Tests/SwiftTests.swift" \
  "$ROOT/macos-app/Sources/Shared/ViewFormatting.swift" \
  "$ROOT/macos-app/Sources/Core/LocaleStore.swift" \
  "$ROOT/macos-app/Sources/Core/Localization.swift" \
  "$ROOT/macos-app/Sources/Tools/TunnelAppList.swift" \
  -framework Foundation -framework AppKit -framework SwiftUI

"$OUT/v2open-swift-tests"
echo "test-swift: ok"

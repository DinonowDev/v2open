#!/usr/bin/env bash
# Full contributor gate: docs, Swift tests (macOS), Rust tests.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
"$ROOT/scripts/check-docs.sh"
if [[ "$(uname -s)" == "Darwin" ]]; then
  "$ROOT/scripts/test-swift.sh"
else
  echo "test: skip Swift tests on $(uname -s)"
fi
(
  cd "$ROOT/native"
  cargo test -p v2core
)
echo "test: ok"

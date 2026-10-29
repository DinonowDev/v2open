#!/usr/bin/env bash
# Contributor gate: locales and version copies must be consistent.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
"$ROOT/scripts/check-locales.sh"
"$ROOT/scripts/check-version.sh"
echo "check-docs: ok"

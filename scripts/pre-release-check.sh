#!/usr/bin/env bash
# Gate before tagging: version copies, changelog section, tests.
# Usage: ./scripts/pre-release-check.sh [MAJOR.MINOR.PATCH]
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VER="${1:-$(sed -n '1p' "$ROOT/VERSION" | tr -d '[:space:]')}"

if [[ ! "$VER" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "pre-release-check: invalid version '$VER'" >&2
  exit 1
fi

echo "pre-release-check: version $VER"

"$ROOT/scripts/check-docs.sh"

if ! "$ROOT/scripts/changelog-section.sh" "$VER" | grep -q "^\## \[$VER\]"; then
  echo "pre-release-check: CHANGELOG.md has no ## [$VER] section" >&2
  exit 1
fi
echo "pre-release-check: CHANGELOG ## [$VER] ok"

TAG="v$VER"
if git rev-parse "$TAG" >/dev/null 2>&1; then
  echo "pre-release-check: git tag $TAG already exists locally" >&2
  exit 1
fi

if [[ -n "$(git status --porcelain)" ]]; then
  echo "pre-release-check: working tree is not clean (commit or stash first)" >&2
  git status -sb
  exit 1
fi

cd "$ROOT/native"
cargo test -p v2core -- --skip ping_sets_positive_ms_for_real_host
cd "$ROOT"
./scripts/test-swift.sh

echo "pre-release-check: ready to tag and push:"
echo "  git tag -a \"$TAG\" -m \"V2Open $VER\""
echo "  git push origin \"$TAG\""

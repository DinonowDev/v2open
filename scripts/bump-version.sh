#!/usr/bin/env bash
# Set marketing version and build in every location listed in docs/versioning.md.
# Usage: ./scripts/bump-version.sh 1.2.0 [--build N]
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

if [[ $# -lt 1 ]]; then
  echo "usage: $0 MAJOR.MINOR.PATCH [--build N]" >&2
  exit 1
fi

VERSION="$1"
shift
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "bump-version: '$VERSION' is not MAJOR.MINOR.PATCH" >&2
  exit 1
fi

BUILD=""
if [[ "${1:-}" == "--build" ]]; then
  BUILD="${2:-}"
  if [[ ! "$BUILD" =~ ^[0-9]+$ ]]; then
    echo "bump-version: --build needs an integer" >&2
    exit 1
  fi
fi

if [[ -z "$BUILD" ]]; then
  CURRENT="$(sed -n '2p' "$ROOT/VERSION" 2>/dev/null | tr -d '[:space:]' || true)"
  if [[ "$CURRENT" =~ ^[0-9]+$ ]]; then
    BUILD="$((CURRENT + 1))"
  else
    BUILD="1"
  fi
fi

printf '%s\n%s\n' "$VERSION" "$BUILD" > "$ROOT/VERSION"

plist_set() {
  /usr/libexec/PlistBuddy -c "Set :$2 $3" "$1"
}

plist_set "$ROOT/macos-app/Info.plist" CFBundleShortVersionString "$VERSION"
plist_set "$ROOT/macos-app/Info.plist" CFBundleVersion "$BUILD"
plist_set "$ROOT/macos-app/PacketTunnel/Info.plist" CFBundleShortVersionString "$VERSION"
plist_set "$ROOT/macos-app/PacketTunnel/Info.plist" CFBundleVersion "$BUILD"

python3 - "$ROOT/native/core/Cargo.toml" "$VERSION" <<'PY'
from pathlib import Path
import re, sys
path = Path(sys.argv[1])
version = sys.argv[2]
text = path.read_text(encoding="utf-8")
new, n = re.subn(r'(?m)^version\s*=\s*"[^"]+"', f'version = "{version}"', text, count=1)
if n != 1:
    raise SystemExit("bump-version: could not patch Cargo.toml version")
path.write_text(new, encoding="utf-8")
PY

python3 - "$ROOT/native/core/src/app.rs" "$VERSION" <<'PY'
from pathlib import Path
import re, sys
path = Path(sys.argv[1])
version = sys.argv[2]
text = path.read_text(encoding="utf-8")
new, n = re.subn(r'"app_version":\s*"[^"]+"', f'"app_version": "{version}"', text, count=1)
if n != 1:
    raise SystemExit("bump-version: could not patch app.rs app_version")
path.write_text(new, encoding="utf-8")
PY

python3 - "$ROOT/macos-app/Sources/Settings/AboutView.swift" "$VERSION" <<'PY'
from pathlib import Path
import re, sys
path = Path(sys.argv[1])
version = sys.argv[2]
text = path.read_text(encoding="utf-8")
new, n = re.subn(r'(\?\?\s*")\d+\.\d+\.\d+(")', rf'\g<1>{version}\2', text, count=1)
if n != 1:
    raise SystemExit("bump-version: could not patch AboutView fallback")
path.write_text(new, encoding="utf-8")
PY

echo "bump-version: set $VERSION (build $BUILD)"
"$ROOT/scripts/check-version.sh"

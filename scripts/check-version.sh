#!/usr/bin/env bash
# Every version copy must match VERSION (marketing + build).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VER_FILE="$ROOT/VERSION"

if [[ ! -f "$VER_FILE" ]]; then
  echo "check-version: missing VERSION" >&2
  exit 1
fi

VERSION="$(sed -n '1p' "$VER_FILE" | tr -d '[:space:]')"
BUILD="$(sed -n '2p' "$VER_FILE" | tr -d '[:space:]')"

if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "check-version: VERSION line 1 must be MAJOR.MINOR.PATCH, got '$VERSION'" >&2
  exit 1
fi
if [[ ! "$BUILD" =~ ^[0-9]+$ ]]; then
  echo "check-version: VERSION line 2 must be an integer build, got '$BUILD'" >&2
  exit 1
fi

fail=0
check() {
  local label="$1"
  local got="$2"
  local want="$3"
  if [[ "$got" != "$want" ]]; then
    echo "check-version: $label is '$got' (want '$want')" >&2
    fail=1
  else
    echo "check-version: $label = $got"
  fi
}

plist_get() {
  python3 - "$1" "$2" <<'PY'
import plistlib, sys
with open(sys.argv[1], "rb") as f:
    data = plistlib.load(f)
print(data.get(sys.argv[2], ""))
PY
}

check "macos-app/Info.plist CFBundleShortVersionString" \
  "$(plist_get "$ROOT/macos-app/Info.plist" CFBundleShortVersionString)" "$VERSION"
check "macos-app/Info.plist CFBundleVersion" \
  "$(plist_get "$ROOT/macos-app/Info.plist" CFBundleVersion)" "$BUILD"
check "PacketTunnel Info.plist CFBundleShortVersionString" \
  "$(plist_get "$ROOT/macos-app/PacketTunnel/Info.plist" CFBundleShortVersionString)" "$VERSION"
check "PacketTunnel Info.plist CFBundleVersion" \
  "$(plist_get "$ROOT/macos-app/PacketTunnel/Info.plist" CFBundleVersion)" "$BUILD"

CRATE="$(python3 - "$ROOT/native/core/Cargo.toml" <<'PY'
import re, sys
text = open(sys.argv[1], encoding="utf-8").read()
m = re.search(r'(?m)^version\s*=\s*"([^"]+)"', text)
print(m.group(1) if m else "")
PY
)"
check "native/core/Cargo.toml version" "$CRATE" "$VERSION"

APP_RS="$(python3 - "$ROOT/native/core/src/app.rs" "$VERSION" <<'PY'
import re, sys
text = open(sys.argv[1], encoding="utf-8").read()
m = re.search(r'"app_version":\s*"([^"]+)"', text)
print(m.group(1) if m else "")
PY
)"
check "app.rs app_version" "$APP_RS" "$VERSION"

ABOUT="$(python3 - "$ROOT/macos-app/Sources/Settings/AboutView.swift" <<'PY'
import re, sys
text = open(sys.argv[1], encoding="utf-8").read()
m = re.search(r'\?\?\s*"(?:\d+\.\d+\.\d+)"', text)
# last fallback string in AboutView
matches = re.findall(r'\?\?\s*"(\d+\.\d+\.\d+)"', text)
print(matches[0] if matches else "")
PY
)"
check "AboutView.swift fallback" "$ABOUT" "$VERSION"

README_EN="$(python3 - "$ROOT/README.md" "$VERSION" "$BUILD" <<'PY'
import re, sys
text = open(sys.argv[1], encoding="utf-8").read()
ver, build = sys.argv[2], sys.argv[3]
m = re.search(r'\*\*Current version\*\*\s*\|\s*`(\d+\.\d+\.\d+)`\s*\(build `(\d+)`\)', text)
if not m:
    print("")
else:
    print(f"{m.group(1)}|{m.group(2)}")
PY
)"
README_FA="$(python3 - "$ROOT/README.fa.md" "$VERSION" "$BUILD" <<'PY'
import re, sys
text = open(sys.argv[1], encoding="utf-8").read()
m = re.search(r'\*\*نسخه فعلی\*\*\s*\|\s*`(\d+\.\d+\.\d+)`\s*\(بیلد `(\d+)`\)', text)
if not m:
    print("")
else:
    print(f"{m.group(1)}|{m.group(2)}")
PY
)"
if [[ -n "$README_EN" ]]; then
  got_ver="${README_EN%%|*}"
  got_build="${README_EN#*|}"
  check "README.md Current version" "$got_ver" "$VERSION"
  check "README.md build" "$got_build" "$BUILD"
else
  echo "check-version: README.md Current version row not found" >&2
  fail=1
fi
if [[ -n "$README_FA" ]]; then
  got_ver="${README_FA%%|*}"
  got_build="${README_FA#*|}"
  check "README.fa.md نسخه فعلی" "$got_ver" "$VERSION"
  check "README.fa.md build" "$got_build" "$BUILD"
else
  echo "check-version: README.fa.md نسخه فعلی row not found" >&2
  fail=1
fi

if [[ "$fail" -ne 0 ]]; then
  echo "check-version: failed. Run ./scripts/bump-version.sh $VERSION --build $BUILD" >&2
  exit 1
fi
echo "check-version: $VERSION ($BUILD) ok"

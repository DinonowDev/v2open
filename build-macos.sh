#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=macos-env.sh
source "$ROOT/macos-env.sh"
export V2OPEN_SIGN_STYLE="${V2OPEN_SIGN_STYLE:-distribution}"
export CARGO_TARGET_DIR="$ROOT/native/target"

if [[ "${V2OPEN_NOTARIZE:-}" == "1" ]]; then
  id="$(v2open_sign_identity || true)"
  if ! v2open_sign_is_distribution "$id"; then
    echo "build-macos: notarization needs a Developer ID Application identity (V2OPEN_SIGN_IDENTITY)" >&2
    exit 1
  fi
  if [[ -z "${V2OPEN_PROFILE_APP:-}" || ! -f "$V2OPEN_PROFILE_APP" || -z "${V2OPEN_PROFILE_TUNNEL:-}" || ! -f "$V2OPEN_PROFILE_TUNNEL" ]]; then
    echo "build-macos: notarization needs V2OPEN_PROFILE_APP and V2OPEN_PROFILE_TUNNEL" >&2
    exit 1
  fi
fi

if [[ "$V2OPEN_TARGET_ARCH" == "x86_64" ]] && ! v2open_engine_matches_arch "$V2OPEN_BINARIES_DIR/sing-box"; then
  "$ROOT/scripts/fetch-macos-engines.sh" x86_64 "$V2OPEN_BINARIES_DIR"
fi

cd "$ROOT/native"
HOST_RUST="$(rustc -vV | awk '/^host:/{print $2}')"
CARGO_ARGS=(build --release -p v2core)
if [[ "$V2OPEN_RUST_TARGET" != "$HOST_RUST" ]]; then
  rustup target add "$V2OPEN_RUST_TARGET"
  CARGO_ARGS+=(--target "$V2OPEN_RUST_TARGET")
  LIB="$ROOT/native/target/$V2OPEN_RUST_TARGET/release"
else
  LIB="$ROOT/native/target/release"
fi
cargo "${CARGO_ARGS[@]}"

APP="$ROOT/V2Open.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/Fonts" "$APP/Contents/Resources/rulesets" "$APP/Contents/Resources/Locales"
cp "$ROOT/macos-app/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/assets/fonts/"*.ttf "$APP/Contents/Resources/Fonts/"
mkdir -p "$APP/Contents/Resources/speedometer"
cp "$ROOT/macos-app/Resources/speedometer/"* "$APP/Contents/Resources/speedometer/"
if [[ -d "$ROOT/macos-app/Resources/Locales" ]]; then
  cp "$ROOT/macos-app/Resources/Locales/"*.json "$APP/Contents/Resources/Locales/" 2>/dev/null || true
fi
mkdir -p "$APP/Contents/Resources/AppIcons"
if [[ -d "$ROOT/macos-app/Resources/AppIcons" ]]; then
  cp "$ROOT/macos-app/Resources/AppIcons/"*.png "$APP/Contents/Resources/AppIcons/" 2>/dev/null || true
fi
if [[ -f "$ROOT/macos-app/Resources/AppIcon.icns" ]]; then
  cp "$ROOT/macos-app/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
fi

for tool in sing-box xray; do
  if ! v2open_engine_matches_arch "$V2OPEN_BINARIES_DIR/$tool"; then
    echo "build-macos: $V2OPEN_BINARIES_DIR/$tool is missing or not $V2OPEN_TARGET_ARCH" >&2
    exit 1
  fi
done
for tool in sing-box masterdns dnstt-client pingtunnel xray; do
  src="$V2OPEN_BINARIES_DIR/$tool"
  if [[ ! -f "$src" ]]; then
    echo "build-macos: optional engine not bundled: $tool" >&2
    continue
  fi
  if ! v2open_engine_matches_arch "$src"; then
    echo "build-macos: $src is not $V2OPEN_TARGET_ARCH" >&2
    exit 1
  fi
  cp "$src" "$APP/Contents/MacOS/$tool"
  chmod +x "$APP/Contents/MacOS/$tool"
  v2open_codesign_helper "$APP/Contents/MacOS/$tool"
done
naive_src="$V2OPEN_BINARIES_DIR/sing-box.official"
if [[ -f "$naive_src" ]] && v2open_engine_matches_arch "$naive_src"; then
  cp "$naive_src" "$APP/Contents/MacOS/sing-box-naive"
  chmod +x "$APP/Contents/MacOS/sing-box-naive"
  v2open_codesign_helper "$APP/Contents/MacOS/sing-box-naive"
else
  echo "build-macos: optional engine not bundled: sing-box-naive (NaiveProxy)" >&2
fi
for dat in geoip.dat geosite.dat; do
  cp "$ROOT/binaries/macos/$dat" "$APP/Contents/Resources/$dat"
done

v2open_compile_packet_tunnel "$APP" "local.v2open.desktop.PacketTunnel" "-O"
SWIFT_SOURCES=()
while IFS= read -r swift_file; do
  SWIFT_SOURCES+=("$swift_file")
done <<EOF
$(find "$ROOT/macos-app/Sources" -name '*.swift' | sort)
EOF
swiftc -parse-as-library -O -target "$SWIFT_TARGET" -o "$APP/Contents/MacOS/V2Open" \
  "${SWIFT_SOURCES[@]}" \
  -L "$LIB" -lv2core \
  "${V2OPEN_SWIFT_FRAMEWORKS[@]}"
if [[ -n "${V2OPEN_PROFILE_APP:-}" && -f "$V2OPEN_PROFILE_APP" ]]; then
  cp "$V2OPEN_PROFILE_APP" "$APP/Contents/embedded.provisionprofile"
fi
v2open_codesign "$APP/Contents/MacOS/V2Open"
v2open_codesign "$APP" "$ROOT/macos-app/V2Open.entitlements"
id="$(v2open_sign_identity || true)"
if v2open_sign_is_distribution "$id"; then
  codesign --verify --deep --strict --verbose=2 "$APP"
fi
if [[ "${V2OPEN_NOTARIZE:-}" == "1" ]]; then
  "$ROOT/scripts/notarize-macos.sh" "$APP"
fi
echo "built $APP ($V2OPEN_TARGET_ARCH)"

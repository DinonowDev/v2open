#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=macos-env.sh
source "$ROOT/macos-env.sh"
export CARGO_TARGET_DIR="$ROOT/native/target"
cd "$ROOT/native"
cargo build --release -p v2core
LIB="$ROOT/native/target/release"
APP="$ROOT/V2Open.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/Fonts" "$APP/Contents/Resources/rulesets"
cp "$ROOT/macos-app/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/assets/fonts/"*.ttf "$APP/Contents/Resources/Fonts/"
mkdir -p "$APP/Contents/Resources/speedometer"
cp "$ROOT/macos-app/Resources/speedometer/"* "$APP/Contents/Resources/speedometer/"
for tool in sing-box masterdns dnstt-client pingtunnel xray; do
  cp "$ROOT/binaries/macos/$tool" "$APP/Contents/MacOS/$tool"
  chmod +x "$APP/Contents/MacOS/$tool"
  codesign --force --sign - "$APP/Contents/MacOS/$tool"
done
for dat in geoip.dat geosite.dat; do
  cp "$ROOT/binaries/macos/$dat" "$APP/Contents/Resources/$dat"
done
APPEX="$APP/Contents/PlugIns/PacketTunnel.appex/Contents"
mkdir -p "$APPEX/MacOS"
swiftc -parse-as-library -O -target "$SWIFT_TARGET" -o "$APPEX/MacOS/PacketTunnel" \
  "$ROOT/macos-app/PacketTunnel/PacketTunnelProvider.swift" "$ROOT/macos-app/PacketTunnel/PacketBridge.swift" \
  -framework Foundation -framework NetworkExtension -framework Network
cp "$ROOT/macos-app/PacketTunnel/Info.plist" "$APPEX/Info.plist"
# Ad-hoc signing cannot carry the Network Extension entitlement, so the
# extension is signed plainly. A Developer ID signature should use
# macos-app/PacketTunnel/PacketTunnel.entitlements instead.
codesign --force --sign - "$APP/Contents/PlugIns/PacketTunnel.appex"
SWIFT_SOURCES=()
while IFS= read -r swift_file; do
  SWIFT_SOURCES+=("$swift_file")
done <<EOF
$(find "$ROOT/macos-app/Sources" -name '*.swift' | sort)
EOF
swiftc -parse-as-library -O -target "$SWIFT_TARGET" -o "$APP/Contents/MacOS/V2Open" \
  "${SWIFT_SOURCES[@]}" \
  -L "$LIB" -lv2core \
  -framework SwiftUI -framework AppKit -framework AVFoundation -framework Vision -framework CoreText \
  -framework Security -framework CoreFoundation -framework SystemConfiguration -framework NetworkExtension -framework CloudKit -framework WebKit \
  -lc++ -liconv
# Same constraint as the extension: V2Open.entitlements is for a real
# developer signature. Ad-hoc signing keeps the app launchable and the
# connection falls back to the administrator tunnel.
codesign --force --sign - "$APP"
echo "built $APP"

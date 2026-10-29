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
for tool in sing-box masterdns dnstt-client pingtunnel xray; do
  cp "$ROOT/binaries/macos/$tool" "$APP/Contents/MacOS/$tool"
  chmod +x "$APP/Contents/MacOS/$tool"
  codesign --force --sign - "$APP/Contents/MacOS/$tool"
done
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
  -framework SwiftUI -framework AppKit -framework AVFoundation -framework Vision -framework CoreText \
  -framework Security -framework CoreFoundation -framework SystemConfiguration -framework NetworkExtension -framework CloudKit -framework WebKit \
  -framework CoreWLAN -framework CoreLocation -framework CoreImage \
  -framework PhotosUI -framework Photos -framework CreateML -framework TabularData -framework CoreML -framework NaturalLanguage \
  -lc++ -liconv
v2open_codesign "$APP/Contents/MacOS/V2Open"
v2open_codesign "$APP" "$ROOT/macos-app/V2Open.entitlements"
echo "built $APP"

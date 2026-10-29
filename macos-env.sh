# Shared macOS build flags (source from dev-macos.sh / build-macos.sh).
# Default minimum macOS for Swift/Rust (not the SDK version). Using the SDK as
# the deployment target (e.g. 26.5) makes Launch Services refuse `open` on hosts
# below that point release (kLSIncompatibleSystemVersionErr / -10825).
export MACOSX_DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET:-14.0}"
_host_os="$(sw_vers -productVersion 2>/dev/null || true)"
if [[ -n "$_host_os" ]] && [[ "$(printf '%s\n' "$_host_os" "$MACOSX_DEPLOYMENT_TARGET" | sort -V | tail -1)" == "$MACOSX_DEPLOYMENT_TARGET" ]] && [[ "$MACOSX_DEPLOYMENT_TARGET" != "$_host_os" ]]; then
  echo "macos-env: MACOSX_DEPLOYMENT_TARGET=$MACOSX_DEPLOYMENT_TARGET > macOS $_host_os; using $_host_os" >&2
  export MACOSX_DEPLOYMENT_TARGET="$_host_os"
fi
unset _host_os
ARCH="$(uname -m)"
case "$ARCH" in
  aarch64) ARCH=arm64 ;;
esac
export SWIFT_TARGET="${ARCH}-apple-macos${MACOSX_DEPLOYMENT_TARGET}"

v2open_codesign_id() {
  security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/Apple Development|Developer ID Application|Mac Developer/{print $2; exit}'
}

v2open_codesign() {
  local target="$1"
  local ents="${2:-}"
  local id
  id="$(v2open_codesign_id || true)"
  if [[ -n "${id:-}" && -n "$ents" && -f "$ents" ]]; then
    if codesign --force --sign "$id" --entitlements "$ents" "$target"; then
      return 0
    fi
  fi
  codesign --force --sign - "$target"
}

v2open_compile_packet_tunnel() {
  local app="$1"
  local bundle_id="$2"
  local opt="${3:--g -Onone}"
  local appex="$app/Contents/PlugIns/PacketTunnel.appex"
  mkdir -p "$appex/Contents/MacOS"
  # shellcheck disable=SC2086
  swiftc -parse-as-library $opt -target "$SWIFT_TARGET" -o "$appex/Contents/MacOS/PacketTunnel" \
    "$ROOT/macos-app/PacketTunnel/PacketTunnelProvider.swift" "$ROOT/macos-app/PacketTunnel/PacketBridge.swift" \
    -framework Foundation -framework NetworkExtension -framework Network
  cp "$ROOT/macos-app/PacketTunnel/Info.plist" "$appex/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $bundle_id" "$appex/Contents/Info.plist" >/dev/null
  v2open_codesign "$appex" "$ROOT/macos-app/PacketTunnel/PacketTunnel.entitlements"
}

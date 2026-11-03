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

_host_arch="$(uname -m)"
case "$_host_arch" in
  aarch64) _host_arch=arm64 ;;
esac
_target_arch="${V2OPEN_ARCH:-$_host_arch}"
case "$_target_arch" in
  aarch64) _target_arch=arm64 ;;
  arm64|x86_64) ;;
  *)
    echo "macos-env: unsupported V2OPEN_ARCH=$_target_arch" >&2
    exit 1
    ;;
esac
export V2OPEN_HOST_ARCH="$_host_arch"
export V2OPEN_TARGET_ARCH="$_target_arch"
export SWIFT_TARGET="${_target_arch}-apple-macos${MACOSX_DEPLOYMENT_TARGET}"
case "$_target_arch" in
  arm64) export V2OPEN_RUST_TARGET="aarch64-apple-darwin" ;;
  x86_64) export V2OPEN_RUST_TARGET="x86_64-apple-darwin" ;;
esac
unset _host_arch _target_arch

if [[ -z "${ROOT:-}" ]]; then
  echo "macos-env: ROOT is not set" >&2
  exit 1
fi
if [[ -z "${V2OPEN_BINARIES_DIR:-}" ]]; then
  if [[ "$V2OPEN_TARGET_ARCH" == "x86_64" ]]; then
    export V2OPEN_BINARIES_DIR="$ROOT/binaries/macos-x86_64"
  else
    export V2OPEN_BINARIES_DIR="$ROOT/binaries/macos"
  fi
fi

v2open_sign_identity() {
  if [[ "${V2OPEN_ADHOC:-}" == "1" ]]; then
    return 0
  fi
  if [[ -n "${V2OPEN_SIGN_IDENTITY:-}" ]]; then
    printf '%s\n' "$V2OPEN_SIGN_IDENTITY"
    return 0
  fi
  local ids prefer id
  ids="$(security find-identity -v -p codesigning 2>/dev/null || true)"
  prefer="Developer ID Application"
  if [[ "${V2OPEN_SIGN_STYLE:-}" == "development" ]]; then
    prefer="Apple Development"
  fi
  id="$(printf '%s\n' "$ids" | awk -F'"' -v p="$prefer" 'index($2, p){print $2; exit}')"
  if [[ -z "$id" ]]; then
    id="$(printf '%s\n' "$ids" | awk -F'"' '/Developer ID Application|Apple Development|Mac Developer/{print $2; exit}')"
  fi
  printf '%s\n' "$id"
}

v2open_sign_is_distribution() {
  [[ "${1:-}" == *"Developer ID Application"* ]]
}

v2open_codesign() {
  local target="$1"
  local ents="${2:-}"
  local id
  id="$(v2open_sign_identity || true)"
  local -a args=(--force)
  if [[ -n "$id" ]]; then
    args+=(--sign "$id")
    if v2open_sign_is_distribution "$id"; then
      args+=(--options runtime --timestamp)
    fi
  else
    args+=(--sign -)
  fi
  if [[ -n "$ents" && -f "$ents" ]]; then
    args+=(--entitlements "$ents")
  fi
  codesign "${args[@]}" "$target"
}

v2open_codesign_helper() {
  local target="$1"
  local id
  id="$(v2open_sign_identity || true)"
  if v2open_sign_is_distribution "$id"; then
    v2open_codesign "$target" "$ROOT/macos-app/Helper.entitlements"
  else
    codesign --force --sign - "$target"
  fi
}

v2open_engine_matches_arch() {
  local path="$1"
  local info
  info="$(file "$path" 2>/dev/null || true)"
  case "$V2OPEN_TARGET_ARCH" in
    arm64) [[ "$info" == *"arm64"* || "$info" == *"universal"* ]] ;;
    x86_64) [[ "$info" == *"x86_64"* || "$info" == *"universal"* ]] ;;
    *) return 1 ;;
  esac
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
  if [[ -n "${V2OPEN_PROFILE_TUNNEL:-}" && -f "$V2OPEN_PROFILE_TUNNEL" ]]; then
    cp "$V2OPEN_PROFILE_TUNNEL" "$appex/Contents/embedded.provisionprofile"
  fi
  v2open_codesign "$appex/Contents/MacOS/PacketTunnel"
  v2open_codesign "$appex" "$ROOT/macos-app/PacketTunnel/PacketTunnel.entitlements"
}

# Swift frameworks linked into the app executable. Keep dev-macos.sh and build-macos.sh in sync.
V2OPEN_SWIFT_FRAMEWORKS=(
  -framework SwiftUI -framework AppKit -framework AVFoundation -framework Vision -framework CoreText
  -framework Security -framework CoreFoundation -framework SystemConfiguration -framework NetworkExtension
  -framework CloudKit -framework WebKit -framework CoreWLAN -framework CoreLocation -framework CoreImage
  -framework PhotosUI -framework Photos -framework CreateML -framework TabularData -framework CoreML
  -framework NaturalLanguage -framework UserNotifications -framework CryptoKit
  -lc++ -liconv
)

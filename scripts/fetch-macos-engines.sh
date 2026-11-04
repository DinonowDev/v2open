#!/usr/bin/env bash
# Download official engine binaries for a macOS architecture.
# Apple Silicon release builds keep the extended sing-box already in binaries/macos/.
# Intel builds have no committed engines; this script fills binaries/macos-x86_64/.
#
# Usage: ./scripts/fetch-macos-engines.sh [arm64|x86_64] [dest]
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ARCH="${1:-x86_64}"
DEST="${2:-$ROOT/binaries/macos-$ARCH}"
SING_BOX_VERSION="${SING_BOX_VERSION:-1.14.4}"
XRAY_VERSION="${XRAY_VERSION:-26.10.21}"
PINGTUNNEL_VERSION="${PINGTUNNEL_VERSION:-3.1}"
MASTERDNS_REPO="${MASTERDNS_REPO:-https://github.com/masterking32/MasterDnsVPN.git}"
MASTERDNS_REF="${MASTERDNS_REF:-v2026.10.26.100415-5f83ee9}"
MASTERDNS_VERSION="${MASTERDNS_VERSION:-v2026.10.26.100415-5f83ee9}"

case "$ARCH" in
  arm64)
    SING_ASSET="sing-box-${SING_BOX_VERSION}-darwin-arm64.tar.gz"
    XRAY_ASSET="Xray-macos-arm64-v8a.zip"
    PING_ASSET="pingtunnel_darwin_arm64.zip"
    GOARCH=arm64
    ;;
  x86_64)
    SING_ASSET="sing-box-${SING_BOX_VERSION}-darwin-amd64.tar.gz"
    XRAY_ASSET="Xray-macos-64.zip"
    PING_ASSET="pingtunnel_darwin_amd64.zip"
    GOARCH=amd64
    ;;
  *)
    echo "fetch-macos-engines: arch must be arm64 or x86_64" >&2
    exit 1
    ;;
esac

mkdir -p "$DEST"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

download() {
  local url="$1" out="$2"
  curl -fL --retry 3 --retry-delay 2 -o "$out" "$url"
}

extract_named() {
  local archive="$1" name="$2" dest="$3"
  local work found
  work="$(mktemp -d)"
  case "$archive" in
    *.zip) ditto -x -k "$archive" "$work" ;;
    *.tar.gz|*.tgz) tar -xzf "$archive" -C "$work" ;;
    *)
      echo "fetch-macos-engines: unknown archive $archive" >&2
      exit 1
      ;;
  esac
  found="$(find "$work" -type f -name "$name" | head -n 1)"
  if [[ -z "$found" ]]; then
    echo "fetch-macos-engines: $name not found in $archive" >&2
    find "$work" -type f | head -n 20 >&2
    exit 1
  fi
  cp "$found" "$dest/$name"
  chmod +x "$dest/$name"
  xattr -cr "$dest/$name" 2>/dev/null || true
  rm -rf "$work"
}

need() {
  local path="$1"
  if [[ "${V2OPEN_FETCH_FORCE:-}" == "1" || ! -f "$path" ]]; then
    return 0
  fi
  local info
  info="$(file "$path")"
  case "$ARCH" in
    arm64) [[ "$info" == *"arm64"* || "$info" == *"universal"* ]] || return 0 ;;
    x86_64) [[ "$info" == *"x86_64"* || "$info" == *"universal"* ]] || return 0 ;;
  esac
  return 1
}

if need "$DEST/sing-box"; then
  echo "fetch-macos-engines: sing-box $SING_BOX_VERSION ($ARCH)"
  download "https://github.com/SagerNet/sing-box/releases/download/v${SING_BOX_VERSION}/${SING_ASSET}" "$TMP/sing-box.tgz"
  extract_named "$TMP/sing-box.tgz" sing-box "$DEST"
fi
if [[ -f "$DEST/sing-box" && ! -f "$DEST/sing-box.official" ]]; then
  cp "$DEST/sing-box" "$DEST/sing-box.official"
  chmod +x "$DEST/sing-box.official"
fi

if need "$DEST/xray"; then
  echo "fetch-macos-engines: xray $XRAY_VERSION ($ARCH)"
  download "https://github.com/XTLS/Xray-core/releases/download/v${XRAY_VERSION}/${XRAY_ASSET}" "$TMP/xray.zip"
  extract_named "$TMP/xray.zip" xray "$DEST"
fi

if need "$DEST/pingtunnel"; then
  echo "fetch-macos-engines: pingtunnel $PINGTUNNEL_VERSION ($ARCH)"
  download "https://github.com/esrrhs/pingtunnel/releases/download/${PINGTUNNEL_VERSION}/${PING_ASSET}" "$TMP/pingtunnel.zip"
  extract_named "$TMP/pingtunnel.zip" pingtunnel "$DEST"
fi

if need "$DEST/dnstt-client"; then
  if command -v go >/dev/null 2>&1; then
    echo "fetch-macos-engines: dnstt-client via go ($GOARCH)"
    GOBIN="$DEST" GOOS=darwin GOARCH="$GOARCH" CGO_ENABLED=0 \
      go install www.bamsoftware.com/git/dnstt.git/dnstt-client@latest
    chmod +x "$DEST/dnstt-client" 2>/dev/null || true
  else
    echo "fetch-macos-engines: go is not installed; dnstt-client skipped" >&2
  fi
fi

if need "$DEST/masterdns"; then
  if command -v go >/dev/null 2>&1; then
    echo "fetch-macos-engines: masterdns $MASTERDNS_VERSION via go ($GOARCH)"
    work="$(mktemp -d)"
    if ! git clone --depth 1 --branch "$MASTERDNS_REF" "$MASTERDNS_REPO" "$work/src" 2>/dev/null; then
      git clone --depth 1 "$MASTERDNS_REPO" "$work/src"
      git -C "$work/src" checkout --detach "$MASTERDNS_REF"
    fi
    (
      cd "$work/src"
      GOOS=darwin GOARCH="$GOARCH" CGO_ENABLED=0 go build -trimpath \
        -ldflags="-s -w -X masterdnsvpn-go/internal/version.BuildVersion=${MASTERDNS_VERSION}" \
        -o "$DEST/masterdns" ./cmd/client
    )
    chmod +x "$DEST/masterdns"
    xattr -cr "$DEST/masterdns" 2>/dev/null || true
    rm -rf "$work"
  else
    echo "fetch-macos-engines: go is not installed; masterdns skipped (place one at $DEST/masterdns)" >&2
  fi
fi

for tool in sing-box xray; do
  info="$(file "$DEST/$tool")"
  echo "fetch-macos-engines: $tool $info"
  case "$ARCH" in
    arm64) [[ "$info" == *"arm64"* || "$info" == *"universal"* ]] ;;
    x86_64) [[ "$info" == *"x86_64"* || "$info" == *"universal"* ]] ;;
  esac
done
echo "fetch-macos-engines: ready in $DEST"

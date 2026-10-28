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

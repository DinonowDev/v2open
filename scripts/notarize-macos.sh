#!/usr/bin/env bash
# Notarize a Developer ID-signed V2Open.app and staple the ticket.
# Prefers an App Store Connect API key. Falls back to an Apple ID app-specific password.
#
#   APPLE_NOTARY_KEY_PATH or APPLE_NOTARY_KEY_BASE64
#   APPLE_NOTARY_KEY_ID
#   APPLE_NOTARY_ISSUER_ID
# or
#   APPLE_ID, APPLE_TEAM_ID, APPLE_APP_PASSWORD
set -euo pipefail
APP="${1:-}"
if [[ -z "$APP" || ! -d "$APP" ]]; then
  echo "usage: $0 V2Open.app" >&2
  exit 1
fi

KEY_PATH="${APPLE_NOTARY_KEY_PATH:-}"
CLEAN_KEY=""
if [[ -z "$KEY_PATH" && -n "${APPLE_NOTARY_KEY_BASE64:-}" ]]; then
  KEY_PATH="$(mktemp)"
  CLEAN_KEY="$KEY_PATH"
  printf '%s' "$APPLE_NOTARY_KEY_BASE64" | base64 --decode > "$KEY_PATH"
  chmod 600 "$KEY_PATH"
fi
trap '[[ -n "$CLEAN_KEY" ]] && rm -f "$CLEAN_KEY"' EXIT

ZIP="$(mktemp -t v2open-notarize).zip"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

submit() {
  if [[ -n "$KEY_PATH" && -n "${APPLE_NOTARY_KEY_ID:-}" && -n "${APPLE_NOTARY_ISSUER_ID:-}" ]]; then
    xcrun notarytool submit "$ZIP" \
      --key "$KEY_PATH" \
      --key-id "$APPLE_NOTARY_KEY_ID" \
      --issuer "$APPLE_NOTARY_ISSUER_ID" \
      --wait
    return 0
  fi
  if [[ -n "${APPLE_ID:-}" && -n "${APPLE_TEAM_ID:-}" && -n "${APPLE_APP_PASSWORD:-}" ]]; then
    xcrun notarytool submit "$ZIP" \
      --apple-id "$APPLE_ID" \
      --team-id "$APPLE_TEAM_ID" \
      --password "$APPLE_APP_PASSWORD" \
      --wait
    return 0
  fi
  echo "notarize-macos: set an App Store Connect API key or APPLE_ID / APPLE_TEAM_ID / APPLE_APP_PASSWORD" >&2
  exit 1
}

submit
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
spctl --assess --type execute -v "$APP"
rm -f "$ZIP"
echo "notarize-macos: stapled $APP"

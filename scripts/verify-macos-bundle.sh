#!/usr/bin/env bash
# Report codesign / notarization status for a V2Open.app bundle.
# Writes human-readable lines to stdout and, on GitHub Actions, sets GITHUB_OUTPUT.
set -euo pipefail

APP="${1:-}"
if [[ -z "$APP" || ! -d "$APP" ]]; then
  echo "usage: $0 V2Open.app" >&2
  exit 1
fi

AUTHORITY="$(codesign -dv --verbose=4 "$APP" 2>&1 | awk -F= '/Authority=/{print $2; exit}')"
TEAM="$(codesign -dv --verbose=4 "$APP" 2>&1 | awk -F= '/TeamIdentifier=/{print $2; exit}')"
SIGNED="$(codesign --verify --deep --strict "$APP" 2>&1 && echo ok || echo fail)"

STAPLER="n/a"
if xcrun stapler validate "$APP" >/dev/null 2>&1; then
  STAPLER="valid"
fi

SPCTL="rejected"
if spctl --assess --type execute "$APP" >/dev/null 2>&1; then
  SPCTL="accepted"
fi

KIND="adhoc"
if [[ "$AUTHORITY" == *"Developer ID Application"* && "$STAPLER" == "valid" && "$SPCTL" == "accepted" ]]; then
  KIND="notarized"
elif [[ "$AUTHORITY" == *"Developer ID Application"* ]]; then
  KIND="developer-id"
elif [[ "$AUTHORITY" == *"Apple Development"* || "$AUTHORITY" == *"Mac Developer"* ]]; then
  KIND="development"
fi

echo "V2OPEN_SIGNING=$KIND"
echo "AUTHORITY=${AUTHORITY:-unknown}"
echo "TEAM=${TEAM:-not set}"
echo "CODESIGN_VERIFY=$SIGNED"
echo "STAPLER=$STAPLER"
echo "SPCTL=$SPCTL"

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  {
    echo "signing_kind=$KIND"
    echo "signing_authority=${AUTHORITY:-unknown}"
    echo "signing_team=${TEAM:-not set}"
    echo "spctl=$SPCTL"
    echo "stapler=$STAPLER"
  } >> "$GITHUB_OUTPUT"
fi

if [[ "$KIND" == "notarized" ]]; then
  exit 0
fi
exit 0

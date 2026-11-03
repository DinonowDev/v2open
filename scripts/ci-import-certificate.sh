#!/usr/bin/env bash
# Import a Developer ID certificate and provisioning profiles on GitHub Actions.
# No-op when APPLE_CERTIFICATE_BASE64 is empty, so unsigned CI builds still run.
#
# Secrets:
#   APPLE_CERTIFICATE_BASE64, APPLE_CERTIFICATE_PASSWORD
#   APPLE_PROFILE_APP_BASE64, APPLE_PROFILE_TUNNEL_BASE64
#   APPLE_NOTARY_KEY_BASE64, APPLE_NOTARY_KEY_ID, APPLE_NOTARY_ISSUER_ID
# Optional notary fallback: APPLE_ID, APPLE_TEAM_ID, APPLE_APP_PASSWORD
set -euo pipefail

emit() {
  local line="$1"
  if [[ -n "${GITHUB_ENV:-}" ]]; then
    printf '%s\n' "$line" >> "$GITHUB_ENV"
  else
    printf '%s\n' "$line"
  fi
}

if [[ -z "${APPLE_CERTIFICATE_BASE64:-}" ]]; then
  echo "ci-import-certificate: no certificate secret; building ad-hoc"
  emit "V2OPEN_ADHOC=1"
  exit 0
fi

: "${APPLE_CERTIFICATE_PASSWORD:?APPLE_CERTIFICATE_PASSWORD is required}"
: "${APPLE_PROFILE_APP_BASE64:?APPLE_PROFILE_APP_BASE64 is required with APPLE_CERTIFICATE_BASE64}"
: "${APPLE_PROFILE_TUNNEL_BASE64:?APPLE_PROFILE_TUNNEL_BASE64 is required with APPLE_CERTIFICATE_BASE64}"
WORK="${RUNNER_TEMP:-$(mktemp -d)}"
mkdir -p "$WORK"
P12="$WORK/developer-id.p12"
KEYCHAIN="$WORK/v2open-signing.keychain-db"
KEYCHAIN_PASSWORD="${APPLE_KEYCHAIN_PASSWORD:-$(openssl rand -hex 16)}"

printf '%s' "$APPLE_CERTIFICATE_BASE64" | base64 --decode > "$P12"
security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
security set-keychain-settings -lut 21600 "$KEYCHAIN"
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
security import "$P12" -P "$APPLE_CERTIFICATE_PASSWORD" -A -t cert -f pkcs12 -k "$KEYCHAIN"
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
security list-keychains -d user -s "$KEYCHAIN" $(security list-keychains -d user | sed -e 's/"//g')

IDENTITY="$(security find-identity -v -p codesigning "$KEYCHAIN" | awk -F'"' '/Developer ID Application/{print $2; exit}')"
if [[ -z "$IDENTITY" ]]; then
  echo "ci-import-certificate: no Developer ID Application identity in the certificate" >&2
  exit 1
fi
emit "V2OPEN_SIGN_IDENTITY=$IDENTITY"
echo "ci-import-certificate: $IDENTITY"

decode_profile() {
  local b64="$1" name="$2"
  if [[ -z "$b64" ]]; then
    return 0
  fi
  local path="$WORK/$name.provisionprofile"
  printf '%s' "$b64" | base64 --decode > "$path"
  emit "V2OPEN_PROFILE_${name}=$path"
}

decode_profile "${APPLE_PROFILE_APP_BASE64:-}" "APP"
decode_profile "${APPLE_PROFILE_TUNNEL_BASE64:-}" "TUNNEL"

NOTARIZE=0
if [[ -n "${APPLE_NOTARY_KEY_ID:-}" && -n "${APPLE_NOTARY_ISSUER_ID:-}" && -n "${APPLE_NOTARY_KEY_BASE64:-}" ]]; then
  KEY="$WORK/AuthKey.p8"
  printf '%s' "$APPLE_NOTARY_KEY_BASE64" | base64 --decode > "$KEY"
  chmod 600 "$KEY"
  emit "APPLE_NOTARY_KEY_PATH=$KEY"
  emit "APPLE_NOTARY_KEY_ID=$APPLE_NOTARY_KEY_ID"
  emit "APPLE_NOTARY_ISSUER_ID=$APPLE_NOTARY_ISSUER_ID"
  emit "V2OPEN_NOTARIZE=1"
  NOTARIZE=1
elif [[ -n "${APPLE_ID:-}" && -n "${APPLE_TEAM_ID:-}" && -n "${APPLE_APP_PASSWORD:-}" ]]; then
  emit "APPLE_ID=$APPLE_ID"
  emit "APPLE_TEAM_ID=$APPLE_TEAM_ID"
  emit "APPLE_APP_PASSWORD=$APPLE_APP_PASSWORD"
  emit "V2OPEN_NOTARIZE=1"
  NOTARIZE=1
fi

if [[ "$NOTARIZE" == "1" ]]; then
  echo "ci-import-certificate: notarization enabled"
else
  echo "ci-import-certificate: certificate imported; notarization secrets are not set"
fi

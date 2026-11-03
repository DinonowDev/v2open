#!/usr/bin/env bash
# Print base64 payloads and gh secret set hints for GitHub Actions signing.
# Usage:
#   ./scripts/encode-apple-secrets.sh cert.p12 app.provisionprofile tunnel.provisionprofile [AuthKey.p8]
set -euo pipefail

P12="${1:-}"
APP_PROFILE="${2:-}"
TUNNEL_PROFILE="${3:-}"
NOTARY_KEY="${4:-}"

usage() {
  echo "usage: $0 certificate.p12 app.provisionprofile tunnel.provisionprofile [AuthKey.p8]" >&2
  exit 1
}

[[ -n "$P12" && -n "$APP_PROFILE" && -n "$TUNNEL_PROFILE" ]] || usage
for f in "$P12" "$APP_PROFILE" "$TUNNEL_PROFILE"; do
  if [[ ! -f "$f" ]]; then
    echo "encode-apple-secrets: not found: $f" >&2
    exit 1
  fi
done

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

b64_file() {
  local src="$1" dest="$2"
  base64 < "$src" | tr -d '\n' > "$dest"
  wc -c < "$dest" | tr -d ' '
}

echo "=== Base64 files (paste into GitHub Secrets or use gh secret set) ==="
echo

cert_bytes="$(b64_file "$P12" "$tmpdir/cert.b64")"
app_bytes="$(b64_file "$APP_PROFILE" "$tmpdir/app.b64")"
tunnel_bytes="$(b64_file "$TUNNEL_PROFILE" "$tmpdir/tunnel.b64")"

echo "APPLE_CERTIFICATE_BASE64  ($cert_bytes chars)  →  $tmpdir/cert.b64"
echo "APPLE_PROFILE_APP_BASE64  ($app_bytes chars)  →  $tmpdir/app.b64"
echo "APPLE_PROFILE_TUNNEL_BASE64 ($tunnel_bytes chars) → $tmpdir/tunnel.b64"

if [[ -n "$NOTARY_KEY" ]]; then
  [[ -f "$NOTARY_KEY" ]] || { echo "notary key not found: $NOTARY_KEY" >&2; exit 1; }
  key_bytes="$(b64_file "$NOTARY_KEY" "$tmpdir/notary.b64")"
  echo "APPLE_NOTARY_KEY_BASE64   ($key_bytes chars)  →  $tmpdir/notary.b64"
fi

echo
echo "=== Suggested gh commands (run from repo root, admin on DinonowDev/v2open) ==="
echo
echo "gh secret set APPLE_CERTIFICATE_BASE64 < \"$tmpdir/cert.b64\""
echo "gh secret set APPLE_CERTIFICATE_PASSWORD --body 'YOUR_P12_PASSWORD'"
echo "gh secret set APPLE_PROFILE_APP_BASE64 < \"$tmpdir/app.b64\""
echo "gh secret set APPLE_PROFILE_TUNNEL_BASE64 < \"$tmpdir/tunnel.b64\""
if [[ -n "$NOTARY_KEY" ]]; then
  echo "gh secret set APPLE_NOTARY_KEY_BASE64 < \"$tmpdir/notary.b64\""
  echo "gh secret set APPLE_NOTARY_KEY_ID --body 'YOUR_KEY_ID'"
  echo "gh secret set APPLE_NOTARY_ISSUER_ID --body 'YOUR_ISSUER_UUID'"
else
  echo "# Optional notary (or use APPLE_ID / APPLE_TEAM_ID / APPLE_APP_PASSWORD):"
  echo "# gh secret set APPLE_NOTARY_KEY_BASE64 < AuthKey_xxx.p8 (base64)"
fi
echo
echo "gh secret list"
echo
echo "See docs/apple-ci-secrets.md"

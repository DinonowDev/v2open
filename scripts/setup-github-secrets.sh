#!/usr/bin/env bash
# Upload Apple signing secrets to GitHub Actions (repo admin + gh auth required).
#
# Point env vars at local files, then run from repo root:
#
#   export V2OPEN_APPLE_CERT_P12="$HOME/certs/V2Open.p12"
#   export V2OPEN_APPLE_CERT_PASSWORD='…'
#   export V2OPEN_APPLE_PROFILE_APP="$HOME/certs/V2Open_App.provisionprofile"
#   export V2OPEN_APPLE_PROFILE_TUNNEL="$HOME/certs/V2Open_Tunnel.provisionprofile"
#   # Notary (pick one style):
#   export V2OPEN_APPLE_NOTARY_KEY="$HOME/certs/AuthKey_XXXX.p8"
#   export V2OPEN_APPLE_NOTARY_KEY_ID='XXXXXXXXXX'
#   export V2OPEN_APPLE_NOTARY_ISSUER_ID='xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx'
#   # Or Apple ID app-specific password:
#   # export V2OPEN_APPLE_ID='you@icloud.com'
#   # export V2OPEN_APPLE_TEAM_ID='XXXXXXXXXX'
#   # export V2OPEN_APPLE_APP_PASSWORD='xxxx-xxxx-xxxx-xxxx'
#
#   ./scripts/setup-github-secrets.sh
#
# To print base64 only (no gh): ./scripts/encode-apple-secrets.sh …
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPO="${GITHUB_REPOSITORY:-DinonowDev/v2open}"

need_file() {
  local label="$1" path="$2"
  if [[ -z "$path" || ! -f "$path" ]]; then
    echo "setup-github-secrets: missing $label (set env and ensure file exists)" >&2
    exit 1
  fi
}

need_file "V2OPEN_APPLE_CERT_P12" "${V2OPEN_APPLE_CERT_P12:-}"
need_file "V2OPEN_APPLE_PROFILE_APP" "${V2OPEN_APPLE_PROFILE_APP:-}"
need_file "V2OPEN_APPLE_PROFILE_TUNNEL" "${V2OPEN_APPLE_PROFILE_TUNNEL:-}"

if [[ -z "${V2OPEN_APPLE_CERT_PASSWORD:-}" ]]; then
  echo "setup-github-secrets: set V2OPEN_APPLE_CERT_PASSWORD" >&2
  exit 1
fi

if ! command -v gh >/dev/null 2>&1; then
  echo "setup-github-secrets: install GitHub CLI (gh) and run gh auth login" >&2
  exit 1
fi
if ! gh auth status >/dev/null 2>&1; then
  echo "setup-github-secrets: gh is not authenticated — run: gh auth login" >&2
  exit 1
fi

echo "setup-github-secrets: uploading secrets to $REPO"

gh secret set APPLE_CERTIFICATE_BASE64 --repo "$REPO" < <(base64 < "$V2OPEN_APPLE_CERT_P12" | tr -d '\n')
gh secret set APPLE_CERTIFICATE_PASSWORD --repo "$REPO" --body "$V2OPEN_APPLE_CERT_PASSWORD"
gh secret set APPLE_PROFILE_APP_BASE64 --repo "$REPO" < <(base64 < "$V2OPEN_APPLE_PROFILE_APP" | tr -d '\n')
gh secret set APPLE_PROFILE_TUNNEL_BASE64 --repo "$REPO" < <(base64 < "$V2OPEN_APPLE_PROFILE_TUNNEL" | tr -d '\n')

if [[ -n "${V2OPEN_APPLE_NOTARY_KEY:-}" ]]; then
  need_file "V2OPEN_APPLE_NOTARY_KEY" "$V2OPEN_APPLE_NOTARY_KEY"
  [[ -n "${V2OPEN_APPLE_NOTARY_KEY_ID:-}" ]] || { echo "setup-github-secrets: set V2OPEN_APPLE_NOTARY_KEY_ID" >&2; exit 1; }
  [[ -n "${V2OPEN_APPLE_NOTARY_ISSUER_ID:-}" ]] || { echo "setup-github-secrets: set V2OPEN_APPLE_NOTARY_ISSUER_ID" >&2; exit 1; }
  gh secret set APPLE_NOTARY_KEY_BASE64 --repo "$REPO" < <(base64 < "$V2OPEN_APPLE_NOTARY_KEY" | tr -d '\n')
  gh secret set APPLE_NOTARY_KEY_ID --repo "$REPO" --body "$V2OPEN_APPLE_NOTARY_KEY_ID"
  gh secret set APPLE_NOTARY_ISSUER_ID --repo "$REPO" --body "$V2OPEN_APPLE_NOTARY_ISSUER_ID"
fi

if [[ -n "${V2OPEN_APPLE_ID:-}" ]]; then
  [[ -n "${V2OPEN_APPLE_TEAM_ID:-}" && -n "${V2OPEN_APPLE_APP_PASSWORD:-}" ]] || {
    echo "setup-github-secrets: V2OPEN_APPLE_ID needs TEAM_ID and APP_PASSWORD" >&2
    exit 1
  }
  gh secret set APPLE_ID --repo "$REPO" --body "$V2OPEN_APPLE_ID"
  gh secret set APPLE_TEAM_ID --repo "$REPO" --body "$V2OPEN_APPLE_TEAM_ID"
  gh secret set APPLE_APP_PASSWORD --repo "$REPO" --body "$V2OPEN_APPLE_APP_PASSWORD"
fi

echo "setup-github-secrets: done. Verify with: gh secret list --repo $REPO"
echo "Next: ./scripts/pre-release-check.sh && git tag -a vX.Y.Z -m \"V2Open X.Y.Z\" && git push origin vX.Y.Z"

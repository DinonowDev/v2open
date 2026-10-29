#!/usr/bin/env bash
# Apply GitHub branch protection / ruleset for main. Requires gh admin auth.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if ! command -v gh >/dev/null 2>&1; then
  echo "protect-main: install GitHub CLI (brew install gh)" >&2
  exit 1
fi

if ! git remote get-url origin >/dev/null 2>&1; then
  echo "protect-main: no origin remote. Add git@github.com:DinonowDev/v2open.git and push main first." >&2
  echo "See docs/github.md" >&2
  exit 1
fi

if ! gh auth status >/dev/null 2>&1; then
  echo "protect-main: run gh auth login" >&2
  exit 1
fi

echo "protect-main: enabling classic branch protection on main…"
gh api "repos/{owner}/{repo}/branches/main/protection" \
  --method PUT \
  --input - <<'JSON'
{
  "required_status_checks": {
    "strict": true,
    "contexts": ["Docs and version", "Swift tests"]
  },
  "enforce_admins": false,
  "required_pull_request_reviews": {
    "dismiss_stale_reviews": true,
    "required_approving_review_count": 0
  },
  "restrictions": null,
  "allow_force_pushes": false,
  "allow_deletions": false,
  "required_linear_history": true
}
JSON

echo "protect-main: done. Confirm in GitHub Settings → Branches."
echo "If status check names differ, run the workflows once on main then re-run this script."

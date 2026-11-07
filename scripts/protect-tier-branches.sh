#!/usr/bin/env bash
# Branch protection for dev / stage / production (+ optional main legacy).
set -euo pipefail

if ! command -v gh >/dev/null 2>&1; then
  echo "protect-tier-branches: install gh" >&2
  exit 1
fi
if ! gh auth status >/dev/null 2>&1; then
  echo "protect-tier-branches: gh auth login" >&2
  exit 1
fi

apply_protection() {
  local branch="$1"
  echo "protect-tier-branches: $branch"
  gh api "repos/{owner}/{repo}/branches/${branch}/protection" \
    --method PUT \
    --input - <<JSON
{
  "required_status_checks": {
    "strict": true,
    "contexts": ["Docs and version", "macOS build and test", "Branch flow guard"]
  },
  "enforce_admins": true,
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
}

for b in dev stage production main; do
  if git ls-remote --heads origin "$b" | grep -q .; then
    apply_protection "$b" || echo "protect-tier-branches: warn: could not protect $b" >&2
  fi
done

echo "protect-tier-branches: done (verify required checks exist after one CI run)"

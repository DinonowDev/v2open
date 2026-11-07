#!/usr/bin/env bash
# One-time (or occasional) setup for GitHub PR labels used in the merge flow.
set -euo pipefail

if ! command -v gh >/dev/null 2>&1; then
  echo "sync-github-labels: gh CLI not found; install GitHub CLI or create labels manually." >&2
  exit 1
fi

create() {
  local name="$1"
  local color="$2"
  local description="$3"
  if gh label create "$name" --color "$color" --description "$description" --force 2>/dev/null; then
    echo "label: $name"
  else
    gh label edit "$name" --color "$color" --description "$description" 2>/dev/null || true
    echo "label: $name (updated)"
  fi
}

create "merged-to-dev" "2ea043" "Feature/fix branch integrated into dev"
create "on-stage" "1d76db" "Included in dev → stage promotion"
create "on-production" "6f42c1" "Included in stage → production release"
create "tier-sync" "fbca04" "Tier sync PR or tagged promotion"

echo "sync-github-labels: ok"

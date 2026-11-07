#!/usr/bin/env bash
# Create/update origin dev, stage, production pointers (one-time or refresh).
set -euo pipefail

if ! git remote get-url origin >/dev/null 2>&1; then
  echo "bootstrap-tier-branches: no origin" >&2
  exit 1
fi

git fetch origin

# integration
if git show-ref --verify --quiet refs/remotes/origin/dev; then
  echo "bootstrap-tier-branches: origin/dev exists"
else
  if git show-ref --verify --quiet refs/remotes/origin/main; then
    git push -u origin origin/main:refs/heads/dev
  else
    echo "bootstrap-tier-branches: need main or dev on origin" >&2
    exit 1
  fi
fi

# QA = latest dev
git push -u origin origin/dev:refs/heads/stage

# production = shipped line (main until first promote replaces it)
if git show-ref --verify --quiet refs/remotes/origin/production; then
  echo "bootstrap-tier-branches: origin/production exists (unchanged)"
else
  git push -u origin origin/main:refs/heads/production
fi

echo "bootstrap-tier-branches: ok (dev=$(git rev-parse --short origin/dev) stage=$(git rev-parse --short origin/stage) production=$(git rev-parse --short origin/production))"

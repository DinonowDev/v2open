#!/usr/bin/env bash
# Validate pull-request head/base pairs for production / stage / dev flow.
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: branch-flow-validate.sh <head-ref> <base-ref>

Exits 0 when the PR direction is allowed, 1 otherwise (message on stderr).

Rules:
  → dev:        feature/*, docs/*, refactor/*, test/*, chore/*
  → stage:      dev, fix/*, release/*, hotfix/*
  → production: stage, release/*, hotfix/*   (never dev or task branches)
EOF
}

head="${1:-}"
base="${2:-}"

if [[ -z "$head" || -z "$base" ]]; then
  usage >&2
  exit 1
fi

is_task() { [[ "$head" =~ ^(feature|docs|refactor|test|chore)/ ]]; }
is_fix() { [[ "$head" =~ ^fix/ ]]; }
is_release() { [[ "$head" =~ ^release/[0-9]+\.[0-9]+\.[0-9]+ ]]; }
is_hotfix() { [[ "$head" =~ ^hotfix/[0-9]+\.[0-9]+\.[0-9]+ ]]; }

fail() {
  echo "branch-flow: $1" >&2
  echo "  head=$head base=$base" >&2
  exit 1
}

# Pushing an integrated tier branch to itself (after local merge); prefer PR + CI.
if [[ "$head" == "$base" && "$base" =~ ^(dev|stage|production)$ ]]; then
  exit 0
fi

case "$base" in
  dev)
    if is_task; then exit 0; fi
    fail "only feature/*, docs/*, refactor/*, test/*, chore/* may target dev"
    ;;
  stage)
    if [[ "$head" == "dev" ]] || is_fix || is_release || is_hotfix; then exit 0; fi
    fail "stage accepts: dev (promote), fix/*, release/*, hotfix/*"
    ;;
  production)
    if [[ "$head" == "stage" ]] || is_release || is_hotfix; then exit 0; fi
    fail "production accepts only: stage (promote), release/*, hotfix/* — not dev or task branches"
    ;;
  main)
    fail "main is legacy; open PRs against dev, stage, or production per docs/git-flow.fa.md"
    ;;
  *)
    fail "unknown base branch; tier branches are dev, stage, production"
    ;;
esac

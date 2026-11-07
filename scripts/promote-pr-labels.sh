#!/usr/bin/env bash
# Mirror CI label promotion when tier merges happen locally (no GitHub PR).
set -euo pipefail

TIER="${1:-}"
TIP="${2:-HEAD}"
TIP="$(git rev-parse "$TIP")"

if [[ "$TIER" != "stage" && "$TIER" != "production" ]]; then
  echo "usage: promote-pr-labels.sh <stage|production> <tip-commit>" >&2
  exit 1
fi

if ! command -v gh >/dev/null 2>&1; then
  echo "promote-pr-labels: gh CLI required" >&2
  exit 1
fi

if [[ "$TIER" == "stage" ]]; then
  ADD="on-stage"
  REMOVE=(merged-to-dev)
else
  ADD="on-production"
  REMOVE=(merged-to-dev on-stage)
fi

count=0
while IFS= read -r row; do
  [[ -z "$row" ]] && continue
  num="${row%% *}"
  sha="${row#* }"
  if git merge-base --is-ancestor "$sha" "$TIP" 2>/dev/null; then
    for lab in "${REMOVE[@]}"; do
      gh pr edit "$num" --remove-label "$lab" 2>/dev/null || true
    done
    gh pr edit "$num" --add-label "$ADD" 2>/dev/null || true
    count=$((count + 1))
  fi
done < <(gh pr list --state merged --base dev --limit 500 --json number,mergeCommit \
  -q '.[] | select(.mergeCommit != null) | "\(.number) \(.mergeCommit.oid)"')

echo "promote-pr-labels: $count PR(s) -> $ADD @ $(git rev-parse --short "$TIP")"

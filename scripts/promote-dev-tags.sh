#!/usr/bin/env bash
# Move merged/dev/* tags (and on-stage/*) when tier tip advances (CI or local).
set -euo pipefail

TIER="${1:-}"
TIP="${2:-HEAD}"
PUSH="${PUSH_TAGS:-${PUSH:-0}}"

[[ "$TIER" == "stage" || "$TIER" == "production" ]] || {
  echo "usage: PUSH_TAGS=1 promote-dev-tags.sh <stage|production> <commit>" >&2
  exit 1
}

TIP="$(git rev-parse "$TIP")"

delete_remote_tag() {
  local tag="$1"
  if [[ "$PUSH" == "1" ]]; then
    git push origin ":refs/tags/${tag}" 2>/dev/null || true
  fi
}

push_tag() {
  local tag="$1"
  if [[ "$PUSH" == "1" ]]; then
    git push origin "refs/tags/${tag}"
    echo "promote-dev-tags: pushed $tag"
  fi
}

move_tag() {
  local from_tag="$1"
  local to_tag="$2"
  local sha
  sha="$(git rev-parse "$from_tag^{commit}")"
  if git rev-parse "$to_tag" >/dev/null 2>&1; then
    echo "promote-dev-tags: $to_tag exists; skip $from_tag" >&2
    return 0
  fi
  git tag -a "$to_tag" -m "Promoted from ${from_tag}" "$sha"
  git tag -d "$from_tag" 2>/dev/null || true
  delete_remote_tag "$from_tag"
  echo "promote-dev-tags: $from_tag -> $to_tag"
  push_tag "$to_tag"
}

if [[ "$TIER" == "stage" ]]; then
  while IFS= read -r tag; do
    [[ -z "$tag" ]] && continue
    if git merge-base --is-ancestor "$(git rev-parse "$tag^{commit}")" "$TIP" 2>/dev/null; then
      move_tag "$tag" "on-stage/${tag#merged/dev/}"
    fi
  done < <(git tag -l 'merged/dev/*')
elif [[ "$TIER" == "production" ]]; then
  while IFS= read -r tag; do
    [[ -z "$tag" ]] && continue
    if git merge-base --is-ancestor "$(git rev-parse "$tag^{commit}")" "$TIP" 2>/dev/null; then
      local_slug="${tag#on-stage/}"
      local_slug="${local_slug#merged/dev/}"
      move_tag "$tag" "on-production/${local_slug}"
    fi
  done < <(git tag -l 'on-stage/*' 'merged/dev/*' 2>/dev/null | sort -u)
fi

echo "promote-dev-tags: done ($TIER @ $(git rev-parse --short "$TIP"))"

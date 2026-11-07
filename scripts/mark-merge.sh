#!/usr/bin/env bash
# Annotated git tags for merge/sync events (dev / stage / production flow).
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  mark-merge.sh merged <tier> <source-branch> [commit] [--push]
  mark-merge.sh sync <to-tier> <from-tier> [commit] [--push]
  mark-merge.sh promote-labels <stage|production> <tip-commit> [--push]

Examples:
  mark-merge.sh merged dev feature/sub-refresh-on-launch --push
  mark-merge.sh sync stage dev --push
  mark-merge.sh sync production stage HEAD --push

Tags (promoted with sync):
  merged/dev/<slug> → on-stage/<slug> → on-production/<slug>
  sync/<to-tier>/from-<from>-<short-sha>

Re-tagging the same name updates the tag locally; use --force on push if you must move a tag.
EOF
}

slugify() {
  echo "$1" | tr '[:upper:]' '[:lower:]' | tr '/' '-' | tr -cd 'a-z0-9._-'
}

parse_args() {
  PUSH=0
  POSITIONAL=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --push) PUSH=1; shift ;;
      -h|--help) usage; exit 0 ;;
      *) POSITIONAL+=("$1"); shift ;;
    esac
  done
  if [[ ${#POSITIONAL[@]} -lt 1 ]]; then
    usage >&2
    exit 1
  fi
}

push_tag() {
  local tag="$1"
  if [[ "$PUSH" -eq 1 ]]; then
    git push origin "refs/tags/$tag"
    echo "mark-merge: pushed $tag"
  else
    echo "mark-merge: created $tag (pass --push to publish)"
  fi
}

cmd_merged() {
  local tier="$1"
  local branch="$2"
  local commit="${3:-HEAD}"
  local slug
  slug="$(slugify "$branch")"
  local tag="merged/${tier}/${slug}"
  if git rev-parse "$tag" >/dev/null 2>&1; then
    echo "mark-merge: tag $tag already exists ($(git rev-parse "$tag"^{commit} | cut -c1-7)); skipping" >&2
    return 0
  fi
  git tag -a "$tag" -m "Merged ${branch} into ${tier}" "$commit"
  echo "mark-merge: $tag -> $(git rev-parse --short "$commit")"
  push_tag "$tag"
}

cmd_sync() {
  local to_tier="$1"
  local from_tier="$2"
  local commit="${3:-HEAD}"
  local short
  short="$(git rev-parse --short "$commit")"
  local tag="sync/${to_tier}/from-${from_tier}-${short}"
  if git rev-parse "$tag" >/dev/null 2>&1; then
    echo "mark-merge: tag $tag already exists; skipping" >&2
  else
    git tag -a "$tag" -m "Synced ${from_tier} into ${to_tier} at ${short}" "$commit"
    echo "mark-merge: $tag -> $short"
    push_tag "$tag"
  fi
  if [[ "$to_tier" == "stage" || "$to_tier" == "production" ]]; then
    PUSH_TAGS="$PUSH" "$(cd "$(dirname "$0")" && pwd)/promote-dev-tags.sh" "$to_tier" "$commit"
  fi
}

cmd_promote_labels() {
  exec "$(cd "$(dirname "$0")" && pwd)/promote-pr-labels.sh" "$@"
}

main() {
  parse_args "$@"
  set -- "${POSITIONAL[@]}"
  local sub="${1:-}"
  case "$sub" in
    merged)
      [[ $# -ge 3 ]] || { usage >&2; exit 1; }
      cmd_merged "$2" "$3" "${4:-HEAD}"
      ;;
    sync)
      [[ $# -ge 3 ]] || { usage >&2; exit 1; }
      cmd_sync "$2" "$3" "${4:-HEAD}"
      ;;
    promote-labels)
      [[ $# -ge 3 ]] || { usage >&2; exit 1; }
      cmd_promote_labels "$2" "$3"
      ;;
    *)
      usage >&2
      exit 1
      ;;
  esac
}

main "$@"

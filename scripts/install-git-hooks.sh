#!/usr/bin/env bash
# Install repo git hooks (pre-push branch-flow validation).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$ROOT/.git/hooks/pre-push"

cat >"$HOOK" <<'HOOK'
#!/usr/bin/env bash
set -euo pipefail
ROOT="$(git rev-parse --show-toplevel)"
VALIDATE="$ROOT/scripts/branch-flow-validate.sh"
[[ -x "$VALIDATE" ]] || exit 0

while read -r _local_ref local_sha _remote_ref remote_ref; do
  [[ "$remote_ref" =~ refs/heads/(dev|stage|production)$ ]] || continue
  tier="${BASH_REMATCH[1]}"
  branch="$(git branch --show-current)"
  [[ -n "$branch" ]] || continue
  if ! "$VALIDATE" "$branch" "$tier"; then
    echo "pre-push: blocked — use PR flow (see docs/git-flow.fa.md)" >&2
    exit 1
  fi
done
HOOK

chmod +x "$HOOK" "$ROOT/scripts/branch-flow-validate.sh"
echo "install-git-hooks: pre-push installed"

#!/usr/bin/env bash
# Print one ## [x.y.z] section from CHANGELOG.md (stdout). Used by GitHub Release workflow.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${1:?usage: changelog-section.sh MAJOR.MINOR.PATCH}"
CHANGELOG="${2:-$ROOT/CHANGELOG.md}"

python3 - "$VERSION" "$CHANGELOG" <<'PY'
import re, sys

ver = sys.argv[1]
path = sys.argv[2]
text = open(path, encoding="utf-8").read()
pat = rf"(?ms)^## \[{re.escape(ver)}\][^\n]*\n(.*?)(?=^## \[|\Z)"
m = re.search(pat, text)
if m:
    print(m.group(0).rstrip())
else:
    print(f"V2Open {ver}\n\n(See CHANGELOG.md in the repository.)")
PY

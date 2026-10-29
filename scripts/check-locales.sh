#!/usr/bin/env bash
# Fail if any locale JSON is missing keys from en.json or has extra keys.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIR="$ROOT/macos-app/Resources/Locales"
EN="$DIR/en.json"

if [[ ! -f "$EN" ]]; then
  echo "check-locales: missing $EN" >&2
  exit 1
fi

python3 - "$DIR" "$EN" <<'PY'
import json, sys
from pathlib import Path

folder = Path(sys.argv[1])
en_path = Path(sys.argv[2])
en = json.loads(en_path.read_text(encoding="utf-8"))
if not isinstance(en, dict) or any(not isinstance(k, str) or not isinstance(v, str) for k, v in en.items()):
    sys.exit("check-locales: en.json must be a flat string-to-string object")
en_keys = set(en)

failed = 0
for path in sorted(folder.glob("*.json")):
    data = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(data, dict):
        print(f"check-locales: {path.name} is not an object")
        failed = 1
        continue
    keys = set(data)
    missing = sorted(en_keys - keys)
    extra = sorted(keys - en_keys)
    bad_types = [k for k, v in data.items() if not isinstance(v, str)]
    if missing or extra or bad_types:
        failed = 1
        print(f"check-locales: {path.name}")
        if missing:
            print(f"  missing ({len(missing)}): " + ", ".join(missing[:20]) + (" …" if len(missing) > 20 else ""))
        if extra:
            print(f"  extra ({len(extra)}): " + ", ".join(extra[:20]) + (" …" if len(extra) > 20 else ""))
        if bad_types:
            print(f"  non-string values: " + ", ".join(bad_types[:20]))
    else:
        print(f"check-locales: {path.name} ok ({len(keys)} keys)")

sys.exit(failed)
PY

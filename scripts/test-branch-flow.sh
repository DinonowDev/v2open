#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
V="$ROOT/scripts/branch-flow-validate.sh"
chmod +x "$V"

must() { "$V" "$1" "$2"; echo "  ok $1 -> $2"; }
must_fail() { if "$V" "$1" "$2"; then echo "  expected fail: $1 -> $2" >&2; exit 1; fi; echo "  ok blocked $1 -> $2"; }

must feature/foo dev
must docs/bar dev
must fix/bug stage
must dev stage
must stage production
must hotfix/1.3.6 production
must release/1.4.0 stage

must_fail feature/foo stage
must_fail feature/foo production
must_fail dev production
must_fail fix/foo dev
must_fail feature/foo main

echo "test-branch-flow: ok"

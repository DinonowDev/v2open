#!/bin/bash
# Rebuild and relaunch V2Open-Dev.app when Swift or v2core sources change.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
WATCH=(
  "$ROOT/macos-app/Sources"
  "$ROOT/macos-app/Resources/speedometer"
  "$ROOT/native/core/src"
)
DEBOUNCE="${DEV_WATCH_DEBOUNCE:-0.6}"
CORE_LOG="${V2OPEN_CORE_LOG:-$HOME/Library/Application Support/V2Open/core.log}"
RUNTIME_LOG="$ROOT/dev-logs/runtime.log"
LOG_TAIL_PIDS=()

start_log_tail() {
  local label="$1"
  local path="$2"
  mkdir -p "$(dirname "$path")" 2>/dev/null || true
  touch "$path" 2>/dev/null || true
  [[ -r "$path" ]] || return 0
  tail -n 0 -F "$path" 2>/dev/null | while IFS= read -r line; do
    clean=$(printf '%s' "$line" | sed $'s/\x1b\\[[0-9;]*[A-Za-z]//g')
    printf '[%s] %s\n' "$label" "$clean"
  done &
  LOG_TAIL_PIDS+=("$!")
}

stop_core_log_tail() {
  local pid
  for pid in "${LOG_TAIL_PIDS[@]+"${LOG_TAIL_PIDS[@]}"}"; do
    kill "$pid" 2>/dev/null || true
  done
  LOG_TAIL_PIDS=()
}

trap 'stop_core_log_tail' EXIT INT TERM

need_tool() {
  echo "Need $1 for live reload." >&2
  echo "  brew install $2" >&2
  exit 1
}

rebuild() {
  echo "—— $(date '+%H:%M:%S') rebuild ——"
  if ! "$ROOT/dev-macos.sh" relaunch; then
    echo "build failed; fix errors and save again" >&2
  fi
}

echo "V2Open macOS dev watch (Swift + v2core)"
echo "Paths: ${WATCH[*]}"
echo "Runtime log → terminal: $RUNTIME_LOG"
echo "Core log → terminal: $CORE_LOG"
echo "Press Ctrl+C to stop."
start_log_tail "app" "$RUNTIME_LOG"
start_log_tail "core" "$CORE_LOG"
rebuild

if command -v fswatch >/dev/null 2>&1; then
  fswatch -l "$DEBOUNCE" -o "${WATCH[@]}" | while read -r _; do rebuild; done
elif command -v watchexec >/dev/null 2>&1; then
  watchexec --debounce "${DEBOUNCE}s" --watch "$ROOT/macos-app/Sources" --watch "$ROOT/native/core/src" -- bash -c "\"$ROOT/dev-macos.sh\" relaunch"
else
  need_tool "fswatch or watchexec" "fswatch"
fi

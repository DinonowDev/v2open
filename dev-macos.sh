#!/bin/bash
# Debug build for local macOS development (symbols, no Swift -O).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=macos-env.sh
source "$ROOT/macos-env.sh"
export CARGO_TARGET_DIR="$ROOT/native/target"
APP="$ROOT/V2Open-Dev.app"
EXE="$APP/Contents/MacOS/V2Open"
LIB="$ROOT/native/target/debug"
CORE_LOG="${V2OPEN_CORE_LOG:-$HOME/Library/Application Support/V2Open/core.log}"
LOG_TAIL_PID=""
RUNTIME_TAIL_PID=""

RUNTIME_LOG="$ROOT/dev-logs/runtime.log"

ensure_core_log() {
  mkdir -p "$(dirname "$CORE_LOG")" 2>/dev/null || true
  touch "$CORE_LOG" 2>/dev/null || true
  mkdir -p "$(dirname "$RUNTIME_LOG")" 2>/dev/null || true
  touch "$RUNTIME_LOG" 2>/dev/null || true
}

start_core_log_tail() {
  ensure_core_log
  if [[ -n "$LOG_TAIL_PID" ]] && kill -0 "$LOG_TAIL_PID" 2>/dev/null; then
    return 0
  fi
  if [[ -r "$CORE_LOG" ]]; then
    tail -n 0 -F "$CORE_LOG" 2>/dev/null | while IFS= read -r line; do
      clean=$(printf '%s' "$line" | sed $'s/\x1b\\[[0-9;]*[A-Za-z]//g')
      printf '[core] %s\n' "$clean"
    done &
    LOG_TAIL_PID=$!
  fi
  if [[ -r "$RUNTIME_LOG" ]]; then
    tail -n 0 -F "$RUNTIME_LOG" 2>/dev/null | while IFS= read -r line; do
      clean=$(printf '%s' "$line" | sed $'s/\x1b\\[[0-9;]*[A-Za-z]//g')
      printf '[app] %s\n' "$clean"
    done &
    RUNTIME_TAIL_PID=$!
  fi
}

stop_core_log_tail() {
  if [[ -n "$LOG_TAIL_PID" ]]; then
    kill "$LOG_TAIL_PID" 2>/dev/null || true
    LOG_TAIL_PID=""
  fi
  if [[ -n "$RUNTIME_TAIL_PID" ]]; then
    kill "$RUNTIME_TAIL_PID" 2>/dev/null || true
    RUNTIME_TAIL_PID=""
  fi
}

stop_dev_app() {
  local pid
  pid=$(pgrep -f "$APP/Contents/MacOS/V2Open" 2>/dev/null || true)
  if [[ -z "$pid" ]]; then
    return 0
  fi
  kill "$pid" 2>/dev/null || true
  for _ in {1..30}; do
    pgrep -f "$APP/Contents/MacOS/V2Open" >/dev/null 2>&1 || return 0
    sleep 0.1
  done
  kill -9 "$pid" 2>/dev/null || true
}

core_source_stamp_line() {
  local path="$1"
  printf '%s %s' "$(stat -f%z "$path")" "$(shasum -a 256 "$path" | awk '{print $1}')"
}

stop_dev_tool() {
  local tool="$1"
  local pids
  pids=$(pgrep -f "$APP/Contents/MacOS/$tool" 2>/dev/null || true)
  [[ -z "$pids" ]] && return 0
  kill $pids 2>/dev/null || true
  for _ in {1..30}; do
    pgrep -f "$APP/Contents/MacOS/$tool" >/dev/null 2>&1 || return 0
    sleep 0.1
  done
  pids=$(pgrep -f "$APP/Contents/MacOS/$tool" 2>/dev/null || true)
  [[ -n "$pids" ]] && kill -9 $pids 2>/dev/null || true
}

scaffold_app() {
  rm -rf "$APP"
  mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/Fonts"
  cp "$ROOT/macos-app/Info.plist" "$APP/Contents/Info.plist"
  mark_dev_bundle
  cp "$ROOT/assets/fonts/"*.ttf "$APP/Contents/Resources/Fonts/"
  sync_speedometer
  sync_locales
  sync_app_icons
  sync_cores
}

sync_locales() {
  mkdir -p "$APP/Contents/Resources/Locales"
  if [[ -d "$ROOT/macos-app/Resources/Locales" ]]; then
    cp "$ROOT/macos-app/Resources/Locales/"*.json "$APP/Contents/Resources/Locales/" 2>/dev/null || true
  fi
}

sync_app_icons() {
  mkdir -p "$APP/Contents/Resources/AppIcons"
  if [[ -d "$ROOT/macos-app/Resources/AppIcons" ]]; then
    cp "$ROOT/macos-app/Resources/AppIcons/"*.png "$APP/Contents/Resources/AppIcons/" 2>/dev/null || true
  fi
}

sync_speedometer() {
  mkdir -p "$APP/Contents/Resources/speedometer"
  cp "$ROOT/macos-app/Resources/speedometer/"* "$APP/Contents/Resources/speedometer/"
}

sync_cores() {
  mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/.dev-core-stamps"
  for tool in sing-box masterdns dnstt-client pingtunnel xray; do
    local src="$ROOT/binaries/macos/$tool"
    local dst="$APP/Contents/MacOS/$tool"
    local stamp="$APP/Contents/Resources/.dev-core-stamps/$tool"
    [[ -f "$src" ]] || continue
    read -r size sum <<< "$(core_source_stamp_line "$src")"
    if [[ -f "$dst" && -f "$stamp" ]]; then
      read -r saved_size saved_sum < "$stamp" || true
      if [[ "$size" == "$saved_size" && "$sum" == "$saved_sum" ]]; then
        continue
      fi
    fi
    stop_dev_tool "$tool"
    cp "$src" "$dst"
    chmod +x "$dst"
    codesign --force --sign - "$dst"
    printf '%s %s\n' "$size" "$sum" > "$stamp"
  done
  rm -f "$APP/Contents/MacOS/geoip.dat" "$APP/Contents/MacOS/geosite.dat"
  mkdir -p "$APP/Contents/Resources"
  for dat in geoip.dat geosite.dat; do
    if [[ -f "$ROOT/binaries/macos/$dat" ]]; then
      cp "$ROOT/binaries/macos/$dat" "$APP/Contents/Resources/$dat"
    fi
  done
}

mark_dev_bundle() {
  /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier local.v2open.dev" "$APP/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c "Set :CFBundleName V2Open Dev" "$APP/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName V2Open Dev" "$APP/Contents/Info.plist"
}

build_dev_app() {
  cd "$ROOT/native"
  cargo build -p v2core
  if [[ ! -f "$APP/Contents/Info.plist" ]]; then
    scaffold_app
  fi
  mark_dev_bundle
  sync_cores
  sync_speedometer
  sync_locales
  sync_app_icons
  rm -f "$APP/Contents/MacOS/geoip.dat" "$APP/Contents/MacOS/geosite.dat"
  v2open_compile_packet_tunnel "$APP" "local.v2open.dev.PacketTunnel" "-g -Onone"
  SWIFT_SOURCES=()
  while IFS= read -r swift_file; do
    SWIFT_SOURCES+=("$swift_file")
  done <<EOF
$(find "$ROOT/macos-app/Sources" -name '*.swift' | sort)
EOF
  swiftc -parse-as-library -g -Onone -target "$SWIFT_TARGET" -o "$EXE" \
    "${SWIFT_SOURCES[@]}" \
    -L "$LIB" -lv2core \
    -framework SwiftUI -framework AppKit -framework AVFoundation -framework Vision -framework CoreText \
    -framework Security -framework CoreFoundation -framework SystemConfiguration -framework NetworkExtension -framework CloudKit -framework WebKit \
    -framework CoreWLAN -framework CoreLocation -framework CoreImage \
    -framework PhotosUI -framework Photos -framework CreateML -framework TabularData -framework CoreML -framework NaturalLanguage \
    -lc++ -liconv
  v2open_codesign "$EXE"
  v2open_codesign "$APP" "$ROOT/macos-app/V2Open.entitlements"
  echo "built $APP"
}

CMD="${1:-run}"
case "$CMD" in
  clean)
    stop_dev_app
    rm -rf "$APP"
    echo "removed $APP"
    ;;
  build)
    build_dev_app
    ;;
  run)
    build_dev_app
    open "$APP"
    ;;
  logs)
    ensure_core_log
    echo "Tailing $RUNTIME_LOG and $CORE_LOG (Ctrl+C to stop)"
    tail -F "$RUNTIME_LOG" "$CORE_LOG" | sed $'s/\x1b\\[[0-9;]*[A-Za-z]//g'
    ;;
  run-logs)
    build_dev_app
    stop_dev_app
    ensure_core_log
    start_core_log_tail
    export V2OPEN_DEV_LOG=1
    echo "V2Open dev — app + core log in this terminal (Ctrl+C to quit)"
    echo "  runtime log: $RUNTIME_LOG"
    echo "  core log: $CORE_LOG"
    trap 'stop_core_log_tail; stop_dev_app' EXIT INT TERM
    "$EXE" 2>&1 | while IFS= read -r line; do printf '[app] %s\n' "$line"; done
    ;;
  relaunch)
    stop_dev_app
    build_dev_app
    open "$APP"
    ;;
  console)
    build_dev_app
    stop_dev_app
    export V2OPEN_DEV_LOG=1
    exec "$EXE"
    ;;
  lldb)
    build_dev_app
    stop_dev_app
    exec lldb "$EXE"
    ;;
  *)
    echo "usage: $0 [run|run-logs|logs|build|relaunch|clean|console|lldb]" >&2
    exit 1
    ;;
esac

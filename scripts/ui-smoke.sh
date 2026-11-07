#!/usr/bin/env bash
# RPC smoke for About engine updates and Routing flows (no XCTest host).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
tests=(
  smoke_about_engines_routing_navigation
  route_sets_migrate_and_switch
  rename_route_set_rpc
  reorder_routes_persists_in_active_set
  backup_restore_keeps_route_sets
  clash_install_config_subscribes
  set_singbox_engine_rpc
  v2box_package_import_restores_route_sets
)
(
  cd "$ROOT/native"
  for t in "${tests[@]}"; do
    cargo test -p v2core "$t" --quiet
  done
)
echo "ui-smoke: ok"

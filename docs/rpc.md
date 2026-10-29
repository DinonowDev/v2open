# RPC reference

Swift calls Rust through `v2RPC(method:args:)` → `v2_call`. Arguments are a JSON object. Success:

```json
{ "ok": true, "data": { } }
```

Failure:

```json
{ "ok": false, "error": "human readable string" }
```

`data` for catalog-mutating methods is usually a full **state** snapshot (`settings`, `groups`, `routes`, `geo_assets`, `backups`, `runtime`). `Model.mergeState` / `refresh` apply it.

Do not rename or remove a method without a **MAJOR** version bump. Add new methods instead. Document every new method in this file in the same PR.

---

## Lifecycle and state

| Method | Args | Result |
| --- | --- | --- |
| `state` | `{}` | Full snapshot |
| `tick` | `{}` | Snapshot after traffic / due jobs |
| `set` | `{key, value}` | Writes `settings[key]`, saves library |
| `about` | `{}` | `app_version`, `sing_box`, `xray`, `engine`, `doq`, links |
| `reset` | `{}` | Settings → defaults, keep profiles |
| `erase` | `{}` | Wipe library |

`about.app_version` is compiled into `app.rs` and **must** match [`VERSION`](../VERSION).

---

## Catalog

| Method | Args | Result |
| --- | --- | --- |
| `import` | `{text, group_id?}` | Parse links / Clash / JSON into a group |
| `subscribe` | `{name, url}` | Fetch URL, import as a group |
| `save_profile` | `{profile}` | Create/update one profile object |
| `select` | `{id}` | `selected_id` |
| `delete` | `{id}` | Delete profile or group (id) |
| `clear_group` | `{id}` | Remove profiles, keep group |
| `update_group` | `{id, …}` | Rename / metadata |
| `set_group_url` | `{id, url}` | Subscription URL |
| `pin_group` | `{id, pinned}` | Pin |
| `lock_group` / `unlock_group` | `{id, password}` | Password gate |
| `profile_json` | `{id}` | Engine JSON for one profile |
| `xray_json` | `{id}` | Xray document for one profile |
| `export_group` | `{id}` | Share payload |
| `export_package` | `{…}` | Catalog package |
| `import_package` | `{text or path, password?}` | Inverse of export |
| `share_locked` | `{id?, password}` | Sealed `.v2box` (vault magic `V2OPEN1`) |
| `seal` / `unseal` | `{password, …}` | Vault helpers |

---

## Connect

| Method | Args | Result |
| --- | --- | --- |
| `prepare` | `{id, smart?, group_id?, keep_alive?}` | Writes `config.json`; returns `path`, `socks_port`, `mtu`, `dns`, `engine`, `launch_core`, tunnel flags |
| `connect` | `{id, smart?, group_id?}` | Spawns engine in-process (dev / fallback) |
| `mark_connected` | `{id}` | Runtime connected after Packet Tunnel starts |
| `disconnect` | `{}` | Stop engine, sidecars, clear phase |
| `ping` | `{id, throughput?}` | Latency (and optional throughput) on that profile |
| `pick_best` | `{}` | `{id}` of the lowest ping (respects settings) |
| `speed` | `{}` | Blocking speed probe |
| `speed_start` | `{}` | Start async probe (no Core lock for the whole run) |
| `speed_progress` | `{}` | Poll async probe |

Swift path: `prepare` → `TunnelManager.connect/reload` → `mark_connected`. If the extension is missing or start fails: `connect`.

---

## Routing and geo

| Method | Args |
| --- | --- |
| `preset` | `{name}` — `global` / `iran` / `russia` / `white` / `black` |
| `save_route` | `{route}` |
| `delete_route` | `{id}` |
| `toggle_route` | `{id}` |
| `reorder_routes` | `{ids}` |
| `import_routes` | `{text}` |
| `export_routes` | — returns `{text}` |
| `add_geo_asset` | `{url or name}` |
| `update_geo_asset` | `{id}` |
| `delete_geo_asset` | `{id}` |
| `update_all_geo_assets` | `{}` |
| `import_geo_asset_file` | `{path}` |

---

## DNS, MTU, Xray

| Method | Args |
| --- | --- |
| `import_hosts` | `{text}` |
| `save_dns_item` | `{item}` |
| `delete_dns_item` | `{id}` |
| `set_active_dns` | `{id, role}` role = remote / domestic |
| `optimize_mtu` | `{…}` uses `mtu_*` settings |
| `save_xray_advanced` | `{…}` policy fields |
| `save_xray_balancer` | `{balancer}` |
| `delete_xray_balancer` | `{id}` |

---

## Backup, logs, diagnostics

| Method | Args |
| --- | --- |
| `backup` | `{name?}` |
| `restore` | `{id}` |
| `delete_backup` | `{id}` |
| `rename_backup` | `{id, name}` |
| `export_backup` | `{id}` |
| `import_backup` | `{text, password?}` |
| `logs` | `{kind?}` access / dns / error |
| `clear_logs` | `{}` |
| `sidecar_logs` | `{}` |
| `diagnostics` | `{}` ifaces, tun, files, logging flag |
| `processes` | `{}` `{names}` for per-app picker |
| `clash_status` | `{}` |
| `clash_select` | `{tag, outbound}` |
| `clash_close` | `{}` |
| `clash_delay` | `{tag, url?}` |

---

## Implementing a new method

1. Add an arm in `Core::call` in `native/core/src/app.rs`.
2. Return `Ok(value)` or `Err(string)` — never panic across FFI.
3. Add a Swift call site through `Model.call` / `invoke`, not a second ABI.
4. Document the method in **this file**.
5. Add/adjust a Rust test if the method is pure (parse/build).
6. If the method is user-visible, add locales, [user-guide.md](user-guide.md), and a `CHANGELOG.md` line.
7. MINOR version bump when it ships (see [versioning.md](versioning.md)).

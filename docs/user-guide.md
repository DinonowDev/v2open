# User guide

V2Open is a local catalog + engine runner. It does not provide VPN servers.

Default language is Persian (`settings.language = fa`). Switch under **Settings → Language**.

---

## Tabs

| Tab | Screen id | Role |
| --- | --- | --- |
| Home | `home` | Connect / disconnect, timer, Smart Connect, selected profile, live speeds |
| Configs | `configs` | Groups and profiles: import, ping, sort, share, edit |
| Speed | `speedtest` | In-app latency / throughput test |
| Settings | `settings` | Appearance, connection, routing, DNS, backup, about |

Subpages are pushed on `Model.stack` (back button pops). A floating connect control can be pinned (`fab_fixed`, optionally `fab_home_only`).

---

## Home

- Connect uses the selected profile (`selected_id`). With **Auto connect to best** it calls `pick_best` first. With **Smart Connect** it can rotate using `smart_strategy` (`winner` or `urltest`).
- `legacy_slider` restores slide-to-connect instead of the power button.
- Stats: memory, upload/download rate and totals from `tick`.
- Stop on sleep is on by default. Persist-tunnel and reconnect-after-wake are off by default.

---

## Configs

Import menu:

| Action | RPC |
| --- | --- |
| Clipboard / paste | `import` with text |
| Subscription URL | `subscribe` |
| Manual editor | `save_profile` after editing `draft` |
| QR (camera or photo) | decoded text → `import` |
| File (JSON, links, Clash YAML, `.v2box`) | `import` / `import_package` / `import_backup` |

Groups can have a URL (`set_group_url`, `update_group`), pin (`pin_group`), lock (`lock_group` / `unlock_group`), export (`export_group`, `share_locked`).

Ping: per profile or **Ping all**. Optional throughput test (`throughput_test`) hits the configured hosts. Auto-ping every 60 seconds from `Model`.

Sort: `sort_by` = `default` / `name` / ping / newest / download / upload.

### Protocols (manual editor)

`ProtocolChipPicker` ids:

`vless`, `vmess`, `trojan`, `shadowsocks`, `shadowsocksr`, `hysteria2`, `hysteria`, `chain`, `wireguard`, `ssh`, `socks`, `http`, `dnstt`, `masterdns`, `ping`

Share-link schemes parsed in `parser.rs`: `vmess`, `vless`, `trojan`, `ss`, `hysteria2`/`hy2`, `hysteria`, `wireguard`/`wg`, `ssh`, `socks`/`socks5`, `http`/`https`, `dnstt`, `masterdns`, `ping`, `ssr`, `dnst`, `chain`, `v2box`/`v2open` (subscription URL).

Transport chips for proxy protocols include `tcp`, `ws`, `grpc`, `h2`, `httpupgrade`, `xhttp`, `quic`. TLS: `none`, `tls`, `reality`.

Clash YAML proxies are accepted through `parse_clash_yaml`.

If you add a protocol, update this section, URL schemes below, `Info.plist`, `parse_link`, the editor picker, tests, locales, and `CHANGELOG.md`.

---

## Settings

### General

| Setting key | Default | Meaning |
| --- | --- | --- |
| `language` | `fa` | UI locale code |
| `mode` | `tun` | `tun` = VPN, `proxy` = local SOCKS/HTTP |
| `loglevel` | `none` | `none` / `error` / `warning` / `info` / `debug` |
| `theme` | `dark` | `dark` / `light` / `system` |
| `glassy` | `false` | Extra translucency |
| `connect_button_size` | `medium` | `small` / `medium` / `large` |
| `app_icon` | `default` | Alternate icons from `Resources/AppIcons`; Dock uses `AppIcon.icns` |
| `legacy_slider` | `false` | Slide-to-connect |
| `fab_fixed` | `false` | Floating connect button |
| `fab_home_only` | `false` | FAB only on Home |
| `allow_insecure` | `false` | TLS skip verify |
| `prefer_ipv6` | `false` | Address family preference |
| `stop_on_sleep` | `true` | Disconnect on sleep |
| `persist_tunnel` | `false` | Reload Packet Tunnel instead of full stop |
| `reconnect_after_wake` | `false` | Connect after wake |
| `mux_enabled` | `false` | Mux |
| `mux_concurrency` | `8` | Mux streams |
| `hwid` | generated | Device id (copy only; `send_hwid` exists in defaults) |

### Configs behavior

| Key | Default | Meaning |
| --- | --- | --- |
| `sub_auto_update` | `false` | Refresh subscription groups |
| `sub_auto_interval_hours` | `24` | 6 / 12 / 24 / 48 / 72 |
| `throughput_test` | `false` | Extra ping metric |
| `auto_connect_best` | `false` | `pick_best` on connect |
| `smart_connect` | `false` | Observatory-style switching |
| `smart_strategy` | `winner` | `winner` / `urltest` |
| `smart_interval` | `1m` | Probe cadence |
| `smart_tolerance` | `50` | Switch hysteresis |
| `probe_url` | gstatic generate_204 | Health URL |

### Network subpages

From Settings:

- **Routing** — presets `global` / `iran` / `russia` / `white` / `black` (`preset` RPC), custom rules, geo assets, route editor. `routing_enabled`, `final` (`proxy`/`direct`), `bypass_lan`, `block_udp_443`, `apple_direct`, `domain_strategy`, `route_only`.
- **DNS** — `remote_dns`, `domestic_dns`, `query_strategy`, `dns_cache`, `dns_split` (`none` / `ir` / `cn` / …), FakeDNS, hosts file, DNS item catalog (`save_dns_item`, `set_active_dns`).
- **Inbounds / network** — SOCKS/HTTP ports, LAN sharing, Clash API port (`clash_port`, default 9097), MTU, include local/all/APNs/cellular, kill switch, fragment, sniffing.
- **Speed test settings** — `speed_mode` `http` / `tcp` / `icmp`, `speed_endpoint`, `speed_timeout`, `speed_concurrency`.
- **On demand** — `on_demand` plus rule text (`on_demand_text`) applied to the system VPN.
- **Clash API** — `clash_status`, `clash_select`, `clash_delay`, `clash_close`.
- **Per-app** — `per_app_mode` `off` / `include` / `exclude`. The UI lists apps installed on the Mac; the saved value is still process names in `per_app_text`.
- **Apply system proxy** — `apply_system_proxy` (default true) when in proxy mode.

### Advanced

Xray policy / balancers (`xray_advanced`, `save_xray_balancer`), xhttp optimization, memory limit (`memory_limit_mb`, default 30), geo source repos, logging toggle (`logging_enabled`).

### Data

- **Backup** — local snapshots (`backup` / `restore` / `export_backup` / `import_backup`), locked `.v2box` (`seal` / `unseal` / `share_locked`), optional iCloud (`icloud`).
- **Reset** — `reset` (settings → defaults, keep profiles).
- **Erase** — `erase` (wipe library).
- **Logs / Diagnostics / About** — core logs, interface dump, version plate, legal.

Routing preset files live in `assets/routing/*.json` and are compiled into `routing.rs` via `include_str!`.

---

## URL schemes and files

Registered in `macos-app/Info.plist`:

```
v2open, v2box, vless, vmess, trojan, ss, ssr, hy2, hysteria, hysteria2,
wireguard, ssh, socks, ping, dnstt, masterdns, chain
```

`v2open://…?text=` can carry a payload. File types: JSON, YAML, `.v2box` (locked catalog, UTI `local.v2open.v2box`). Locked files start with magic `V2OPEN1`.

Camera, photo library, and (for diagnostics BSSID) location usage strings are in Info.plist.

---

## Speed test

Home tab **Speed** runs `speed` / `speed_start` / `speed_progress`. HTTP mode measures the configured endpoint through the core; TCP/ICMP modes probe the remote host directly. Concurrent streams and timeout are in Speed test settings.

This is **not** a guarantee of line speed and does not send results to the developer.

---

## Tools

**Settings → More**: live paths to `config.json` and `core.log`, shortcuts into logs/diagnostics/apps, catalog lock/unlock helpers.

---

## Privacy in one page

- No account. No V2Open backend for configs.
- Library stays under `~/Library/Application Support/V2Open/` unless you export or enable iCloud.
- Speed tests and Smart Connect leave your Mac toward the hosts **you** configured (or public generate_204).
- Full text: in-app **About → Terms / Privacy**.

---

## When you change this guide

If you add a setting, protocol, tab, or scheme, update the tables above **in the same PR**, plus locales and `CHANGELOG.md`. See the [doc map](README.md).

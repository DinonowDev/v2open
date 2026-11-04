# Changelog

All notable changes to V2Open are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

How to edit this file: [docs/versioning.md](docs/versioning.md).

## [Unreleased]

### Added

### Changed

### Fixed

## [1.3.4] - 2026-11-05

Build `8`.

### Fixed

- Clash connections view: nested filter/sort types so release builds compile with Swift access control.

## [1.3.3] - 2026-11-05

Build `7`.

### Added

- Intel `masterdns` sidecar: built from [MasterDnsVPN](https://github.com/masterking32/MasterDnsVPN) during `fetch-macos-engines.sh` when Go is installed.
- [scripts/setup-github-secrets.sh](../scripts/setup-github-secrets.sh) uploads Apple signing secrets via `gh secret set` when local cert paths are in env vars.
- System notifications for unexpected disconnect, tunnel errors, and subscription refresh (Settings toggles). Update notifications reuse the same helper.
- About shows whether this copy is notarized, Developer ID–signed, or ad hoc (`SigningInfo`).
- [scripts/verify-macos-bundle.sh](../scripts/verify-macos-bundle.sh) prints codesign, stapler, and Gatekeeper status for a built `.app`.

### Changed

- README version table stays in sync with `VERSION` (`check-version.sh` / `bump-version.sh`).
- Release workflow skips the flaky remote TCP ping test (same as `pre-release-check.sh`).
- Clash / sing-box external controller view: search, filters, live speeds, and a short traffic chart.
- Clash API responses normalize connection metadata (host, process, network, rule fields) for the UI.
- CI build jobs run `verify-macos-bundle.sh` and attach a signing report to release notes when present.

## [1.3.2] - 2026-11-05

Build `6`.

### Fixed

- CI ping regression test no longer treats a fast datacenter link to `8.8.8.8` as a TUN-local path; TCP ping display uses microsecond timing with millisecond rounding.

## [1.3.1] - 2026-11-05

Build `5`.

### Removed

- The extra `id:` line when copying a share link or exporting group links, so pasted text stays a plain URI for other clients.

## [1.3.0] - 2026-11-05

Build `4`.

### Added

- NPV Tunnel configs import as ordinary profiles. `.npvt` and `.npvs` (NPVT1, open NPVO1, NPVS Gen-1, and Gen-2 including passphrase files) can be added from a file, Finder, the clipboard, or a QR code. A locked file asks for its passphrase. A file bound to another device is refused.
- Chain hop fields in the editor: TUIC heartbeat, 0-RTT, and disable SNI; Naive ShadowTLS SNI; SSH reserved and MTU; the full AmneziaWG key set; WARP ECH query server name.

### Changed

- The Home connection timer reads the engine `connected_at` time, so it keeps counting after the app becomes active again.
- Copying a share link appends a unique `id:` stamp so each copy can be told apart.

## [1.2.0] - 2026-11-03

Build `3`.

### Added

- Menu bar icon to connect, disconnect, and switch servers. Closing the window leaves the app running; Quit is in the menu. Optional Dock hiding.
- Update check against GitHub Releases, with a Home and About prompt, a system notification, and download-and-install that verifies the asset digest.
- Intel release zip (`macos-x86_64`) next to the Apple Silicon zip. Official sing-box, Xray, and pingtunnel are fetched at build time; dnstt-client is built when Go is available. MasterDNS is included only if an Intel `masterdns` binary is supplied.
- Release signing and notarization when Apple Developer ID, provisioning profiles, and notary credentials are configured. See [docs/signing.md](docs/signing.md) and [docs/apple-ci-secrets.md](docs/apple-ci-secrets.md).
- TUIC and AnyTLS: `tuic://` and `anytls://` links, Clash YAML, sing-box JSON, the manual editor, and sing-box outbounds. TUIC from Clash no longer fails with "unsupported protocol tuic".
- ShadowTLS v1–3 on Shadowsocks profiles (`plugin=shadow-tls;…`, Clash `plugin: shadow-tls`, editor). simple-obfs and v2ray-plugin options are passed to sing-box too.
- NaiveProxy: `naive+https://` / `naive+quic://` links and editor. Runs in the stock sing-box, now bundled as `sing-box-naive`, as a local SOCKS sidecar.
- ECH for TLS, Hysteria2, TUIC, AnyTLS and Naive: editor toggle, `ech=` link parameter, Clash `ech-opts`, sing-box `tls.ech`, and Xray `echConfigList`.
- AmneziaWG: `Jc`/`Jmin`/`Jmax`/`S1`–`S4`/`H1`–`H4`/`I1`–`I5` from WireGuard links, `.conf` text, AmneziaVPN `vpn://` exports, Clash `amnezia-wg-option`, and the editor.
- Built-in WARP: automatic Cloudflare account registration, optional WARP+ license, WARP-on-WARP, Hiddify-style `warp://` links, and a "WARP after config" chain that exits through WARP behind any other profile.
- Xray UDP noise editor (Settings → Xray advanced). Noise and TLS fragment are applied to Xray-run profiles through a `freedom` dialer outbound.

### Changed

- Profiles that Xray cannot carry exactly (AmneziaWG, Shadowsocks with a plugin or ShadowTLS, Hysteria v1, Hysteria2 with obfs or port hopping) now run on sing-box.
- Xray WireGuard outbounds now get `reserved`, MTU, keepalive, pre-shared key, allowed IPs, and both IPv4 and IPv6 addresses.
- The fragment setting now also applies to Xray-run TLS/REALITY profiles.
- WARP-after-config validates the selected profile at connect time; chain editor supports TUIC, AnyTLS, Naive, WireGuard, and WARP hops.
- Contributor docs: `development.md` (engines + protocol checklist), `rpc.md` (WARP/noise/fragment settings via `set`).
- README install steps for both `macos-arm64` and `macos-x86_64` zips; CI and Release workflows build both architectures.

### Fixed

## [1.1.0] - 2026-10-30

Build `2`.

### Added

- GitHub Actions: CI builds and tests on macOS (`cargo test`, Swift tests, `./build-macos.sh`); main-branch workflow artifacts; tag-triggered Releases with downloadable zip.
- App tunnel can pick installed Mac apps from a searchable list with their icons instead of typing process names.
- Project documentation, contributing rules, branching / PR guide, SemVer source file (`VERSION`), GitHub issue/PR templates, locale/version check scripts, MIT `LICENSE`, third-party `NOTICE`, Swift helper tests, and CI for docs + Swift tests.
- URL schemes for `v2open`, `v2box`, `vless`, `vmess`, `trojan`, `ss`, `ssr`, `hy2`, `hysteria`, `hysteria2`, `wireguard`, `ssh`, `socks`, `ping`, `dnstt`, `masterdns`, and `chain`.
- Alternate app icons shipped in the bundle.
- Locale JSON files for ten languages, loaded at runtime.
- Background scheduler (Launch Agent) for geo auto-update, on-demand, persist-tunnel, and subscription auto-update.
- Smart Connect, persist-tunnel, and reconnect-after-wake settings.
- DNS item list, DNS balancers, and Xray advanced / balancer UI.
- Light, dark, and system themes plus glassy chrome.
- Packet Tunnel Network Extension with reload support.

### Changed

- README: UI screenshots, project links (docs, contributing, issues, releases), donation addresses aligned with [DinonowDev/LazyDisk](https://github.com/DinonowDev/LazyDisk); download hero banner and install steps moved to the top.
- App icon replaced with a dimensional cyan tunnel mark, plus matching lime and violet alternates, shipped as the bundle `.icns`.
- `v2core` crate version aligned with the app marketing version (`1.1.0`).
- macOS app version string set to `1.1.0`.
- Dev and release build scripts copy locales, icons, speedometer assets, and engine binaries into the app bundle.

### Fixed

- CI: remote TCP ping self-test accepts fast WAN handshakes (>1 ms) on GitHub runners instead of requiring ≥5 ms.

## [1.0.0] - 2026-10

Build `1`.

### Added

- Initial macOS SwiftUI client, Rust `v2core`, bundled `sing-box` / Xray, routing presets, and local library.

[Unreleased]: https://github.com/DinonowDev/v2open/compare/v1.3.4...HEAD
[1.3.4]: https://github.com/DinonowDev/v2open/compare/v1.3.3...v1.3.4
[1.3.3]: https://github.com/DinonowDev/v2open/compare/v1.3.2...v1.3.3
[1.3.2]: https://github.com/DinonowDev/v2open/compare/v1.3.1...v1.3.2
[1.3.1]: https://github.com/DinonowDev/v2open/compare/v1.3.0...v1.3.1
[1.3.0]: https://github.com/DinonowDev/v2open/compare/v1.2.0...v1.3.0
[1.2.0]: https://github.com/DinonowDev/v2open/releases/tag/v1.2.0
[1.1.0]: https://github.com/DinonowDev/v2open/releases/tag/v1.1.0
[1.0.0]: https://github.com/DinonowDev/v2open/releases/tag/v1.0.0

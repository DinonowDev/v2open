# Changelog

All notable changes to V2Open are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

How to edit this file: [docs/versioning.md](docs/versioning.md).

## [Unreleased]

### Added

- App tunnel can pick installed Mac apps from a searchable list with their icons instead of typing process names.
- Project documentation, contributing rules, branching / PR guide, SemVer source file (`VERSION`), GitHub issue/PR templates, locale/version check scripts, MIT `LICENSE`, third-party `NOTICE`, Swift helper tests, and CI for docs + Swift tests.

### Changed

- App icon replaced with a dimensional cyan tunnel mark, plus matching lime and violet alternates, shipped as the bundle `.icns`.
- `v2core` crate version aligned with the app marketing version (`1.1.0`).

## [1.1.0] - 2026-10-29

Build `2`.

### Added

- URL schemes for `v2open`, `v2box`, `vless`, `vmess`, `trojan`, `ss`, `ssr`, `hy2`, `hysteria`, `hysteria2`, `wireguard`, `ssh`, `socks`, `ping`, `dnstt`, `masterdns`, and `chain`.
- Alternate app icons shipped in the bundle.
- Locale JSON files for ten languages, loaded at runtime.
- Background scheduler (Launch Agent) for geo auto-update, on-demand, persist-tunnel, and subscription auto-update.
- Smart Connect, persist-tunnel, and reconnect-after-wake settings.
- DNS item list, DNS balancers, and Xray advanced / balancer UI.
- Light, dark, and system themes plus glassy chrome.
- Packet Tunnel Network Extension with reload support.

### Changed

- macOS app version string set to `1.1.0`.
- Dev and release build scripts copy locales, icons, speedometer assets, and engine binaries into the app bundle.

## [1.0.0] - 2026-10

Build `1`.

### Added

- Initial macOS SwiftUI client, Rust `v2core`, bundled `sing-box` / Xray, routing presets, and local library.

[Unreleased]: https://github.com/DinonowDev/v2open/compare/v1.1.0...HEAD
[1.1.0]: https://github.com/DinonowDev/v2open/releases/tag/v1.1.0
[1.0.0]: https://github.com/DinonowDev/v2open/releases/tag/v1.0.0

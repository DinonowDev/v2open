# V2Open documentation

This folder is the product and contributor manual. **If you change the app, you change the matching page in the same pull request.** A PR that lands behavior without docs is incomplete.

Canonical process: [CONTRIBUTING.md](../CONTRIBUTING.md). Persian: [CONTRIBUTING.fa.md](../CONTRIBUTING.fa.md).

---

## Start here

| If you want to… | Read |
| --- | --- |
| Understand what the app is | [../README.md](../README.md) |
| Use the app (screens, settings, schemes) | [user-guide.md](user-guide.md) |
| Learn how the pieces fit | [architecture.md](architecture.md) |
| Build, run, debug | [development.md](development.md) |
| Call `v2core` from Swift | [rpc.md](rpc.md) |
| Add a translated string | [localization.md](localization.md) |
| Run or add tests | [testing.md](testing.md) |
| Bump the version | [versioning.md](versioning.md) |
| Name a branch or open a PR | [branching.md](branching.md) |
| Cut a GitHub release | [release.md](release.md) |
| Replace sing-box / Xray / sidecars | [binaries.md](binaries.md), [../NOTICE](../NOTICE) |
| Sign the Packet Tunnel | [signing.md](signing.md) |
| Protect `main` on GitHub | [github.md](github.md) |

---

## Doc map (code → document)

Use this table when you touch code. Update **every** matching row in the same PR.

| Code / area | Document |
| --- | --- |
| `macos-app/Sources/Home`, connect button, stats | [user-guide.md](user-guide.md) § Home |
| `macos-app/Sources/Configs`, editor, share, QR | [user-guide.md](user-guide.md) § Configs |
| `macos-app/Sources/Settings/*` | [user-guide.md](user-guide.md) § Settings |
| `macos-app/Sources/Tools`, per-app, speed test | [user-guide.md](user-guide.md) |
| `macos-app/Info.plist` URL schemes | [user-guide.md](user-guide.md) § URL schemes |
| `macos-app/Sources/Core/Model.swift` navigation / boot | [architecture.md](architecture.md) |
| `macos-app/Sources/Core/V2RPC.swift` | [rpc.md](rpc.md), [architecture.md](architecture.md) |
| `macos-app/Sources/Tunnel.swift`, `PacketTunnel/` | [architecture.md](architecture.md) § Tunnel |
| `macos-app/Sources/Cloud.swift` | [user-guide.md](user-guide.md) § Backup |
| `macos-app/Sources/App/BackgroundScheduler.swift` | [architecture.md](architecture.md) § Background |
| `macos-app/Resources/Locales/*.json` | [localization.md](localization.md) |
| `macos-app/Sources/Core/Localization.swift` fallbacks | [localization.md](localization.md) |
| `macos-app/Sources/Design/Theme.swift` | [user-guide.md](user-guide.md) § Appearance |
| `native/core/src/lib.rs` FFI | [rpc.md](rpc.md), [architecture.md](architecture.md) |
| `native/core/src/app.rs` `call()` methods | [rpc.md](rpc.md) |
| `native/core/src/app.rs` `defaults()` / settings keys | [user-guide.md](user-guide.md) |
| `native/core/src/migrate.rs` | [architecture.md](architecture.md) § Library format |
| `native/core/src/parser.rs` | [user-guide.md](user-guide.md) § Protocols |
| `native/core/src/builder.rs` | [architecture.md](architecture.md) § Engines |
| `native/core/src/routing.rs`, `assets/routing/` | [user-guide.md](user-guide.md) § Routing |
| `native/core/src/sidecar.rs`, `ssr.rs` | [architecture.md](architecture.md) § Sidecars |
| `native/core/src/vault.rs` | [user-guide.md](user-guide.md) § Locked catalog, [SECURITY.md](../SECURITY.md) |
| `native/core/src/xray.rs`, `xray_balancers.rs` | [user-guide.md](user-guide.md) § Xray |
| `native/core/src/dns_items.rs` | [user-guide.md](user-guide.md) § DNS |
| `native/core/src/diagnostics.rs` | [user-guide.md](user-guide.md) § Diagnostics |
| `native/core/tests/*` | [testing.md](testing.md) |
| `macos-app/Tests/*` | [testing.md](testing.md) |
| `dev-macos.sh`, `build-macos.sh`, `macos-env.sh` | [development.md](development.md) |
| `macos-app/*.entitlements`, Packet Tunnel ids | [signing.md](signing.md) |
| `binaries/macos/*` | [binaries.md](binaries.md), [../NOTICE](../NOTICE) |
| `VERSION`, plists, `Cargo.toml`, `app_version` | [versioning.md](versioning.md), [CHANGELOG.md](../CHANGELOG.md) |
| GitHub templates, branch names, CODEOWNERS | [branching.md](branching.md), [github.md](github.md), [CONTRIBUTING.md](../CONTRIBUTING.md) |

When you add a **new** area of code, add a row here in the same PR.

---

## Writing rules

- English is the canonical language of `docs/`. Keep [README.fa.md](../README.fa.md) and [CONTRIBUTING.fa.md](../CONTRIBUTING.fa.md) aligned when you change process.
- Write for a contributor who has never opened the repo. Name files, RPC methods, and setting keys exactly as they appear in code.
- Prefer short sections and tables over prose.
- Do not paste real configs, keys, or user data into docs.
- Do not document attack recipes. High-level threat notes belong in [SECURITY.md](../SECURITY.md).
- After editing, run `./scripts/check-docs.sh`.

---

## Checks

```bash
./scripts/check-locales.sh    # every locale has the same keys as en.json
./scripts/check-version.sh    # VERSION matches plist / crate / about
./scripts/check-docs.sh       # both of the above
./scripts/test-swift.sh       # macOS helper tests
./scripts/test.sh             # docs + Swift + cargo test
```

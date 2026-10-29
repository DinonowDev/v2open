# Testing

## Rust (`v2core`)

From `native/`:

```bash
cargo test -p v2core
```

| File | What it covers | Network |
| --- | --- | --- |
| `tests/config.rs` | Share links + per-app modes pass `sing-box check` | No (needs bundled `sing-box`) |
| `tests/clash.rs` | Clash YAML proxy parse | No |
| `tests/dns_balancers.rs` | DNS items and Xray balancer export | No |
| `tests/ping.rs` | ICMP/TCP ping to a real host | Yes (small) |
| `tests/live_connect.rs` | SOCKS/TUN download using **saved** library | Yes, `#[ignore]` |
| `tests/live_matrix.rs` | Site matrix (Telegram / YouTube / Instagram) | Yes, `#[ignore]` |

`config.rs` tests **return early** if `binaries/macos/sing-box` or `assets/rulesets` are missing. Keep those files in place for a meaningful run.

Ignored tests use `~/Library/Application Support/V2Open` and the currently selected profile. They can change system proxy and must tear the tunnel down in `Drop`. **Do not run them in CI. Do not commit `dev-logs/connection-matrix.txt`.**

```bash
# only if you intend to hit your own configs
cargo test -p v2core -- --ignored --nocapture
```

When you change `parser`, `builder`, `routing`, DNS items, or Xray export, add or extend a **non-ignored** test with `example.com` and the sample UUID already used in `config.rs`.

---

## Swift

There is no Xcode project and no `xcodebuild test`. Helper tests compile with `swiftc`:

```bash
./scripts/test-swift.sh
```

Sources: `macos-app/Tests/SwiftTests.swift` plus `ViewFormatting.swift`, `LocaleStore.swift`, `Localization.swift`, and `TunnelAppList.swift`. Do **not** put `@main` test files under `macos-app/Sources/` or the app will fail to link.

When you add a pure helper (formatting, parsing a version string, locale lookup), add a `check("name", …)` line in `SwiftTests.swift` in the same PR.

UI verification is still manual:

1. Build with `./dev-macos.sh run`.
2. Exercise the changed screen end to end (tap, type, save, navigate away and back).
3. Visit every tab that reads the same `settings` / `groups` / `runtime` keys.
4. Check empty, error, and RTL (`language = fa` or `ar`) if layout changed.
5. For Packet Tunnel work, test on a signed build ([signing.md](signing.md)); unsigned dev may take the child-process fallback.

Write the path you clicked in the PR template.

---

## Scripts

```bash
./scripts/check-docs.sh       # locales + version copies
./scripts/test-swift.sh       # macOS only
./scripts/test.sh             # docs + Swift + cargo test -p v2core
```

`./scripts/test.sh` is the bar before you request review. GitHub Actions (`.github/workflows/ci.yml`) run docs checks on Ubuntu and Swift tests on macOS.

---

## What “good” looks like

- Parser change: `cargo test -p v2core` plus a new sample link in `config.rs`
- Helper / formatting / locale lookup: a line in `macos-app/Tests/SwiftTests.swift`
- Setting change: defaults + migrate + locale keys + user guide table
- RPC change: documented in [rpc.md](rpc.md), error string stable
- Visual change: screenshot or short recording on the PR
- Engine binary swap: [binaries.md](binaries.md) + `VERSIONS` + [NOTICE](../NOTICE) if license/upstream changed

Do not add tests that require a paid VPN account or that print real share links.

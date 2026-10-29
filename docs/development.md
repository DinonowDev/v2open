# Development

## Prerequisites

- macOS 13+
- Xcode Command Line Tools (`swiftc`, `codesign`, `PlistBuddy`)
- Rust stable (`cargo`)
- Engine binaries already present under `binaries/macos/`
- Optional: `fswatch` for `./dev-watch-macos.sh` (`brew install fswatch`)

```bash
xcode-select -p
rustc --version
ls binaries/macos/sing-box binaries/macos/xray
```

There is no Xcode project. The app is compiled with `swiftc -parse-as-library` over every `macos-app/Sources/**/*.swift` file.

---

## Scripts

| Script | Purpose |
| --- | --- |
| `macos-env.sh` | Sourced by the others. Sets `MACOSX_DEPLOYMENT_TARGET`, `SWIFT_TARGET`, ad-hoc or identity codesign, Packet Tunnel compile helper. |
| `dev-macos.sh` | Debug `V2Open-Dev.app` (`-g -Onone`, debug `v2core`). |
| `dev-watch-macos.sh` | Rebuild + relaunch when Swift, speedometer assets, or `native/core/src` change. |
| `build-macos.sh` | Release `V2Open.app` (`-O`, `--release` crate). |

Do not copy compiler flags into a new script; extend `macos-env.sh`.

---

## Debug loop

```bash
./dev-macos.sh run          # build and `open` V2Open-Dev.app
./dev-macos.sh relaunch     # quit the running dev app, rebuild, open
./dev-macos.sh run-logs     # foreground process + tailed core/runtime logs
./dev-macos.sh logs         # tail only
./dev-macos.sh console      # exec the binary in this terminal (`V2OPEN_DEV_LOG=1`)
./dev-macos.sh lldb
./dev-macos.sh build        # compile without opening
./dev-macos.sh clean        # stop + delete V2Open-Dev.app
```

Live reload:

```bash
./dev-watch-macos.sh
# DEBOUNCE seconds: DEV_WATCH_DEBOUNCE=0.6
```

The watch script does **not** currently watch locale JSON, Info.plist, or Packet Tunnel sources. After editing those, run `./dev-macos.sh relaunch` yourself.

Dev bundle identity is rewritten with PlistBuddy to `local.v2open.dev` so it can sit next to a release install. Dev log is enabled when the bundle id is the dev id, the path contains `V2Open-Dev.app`, or `V2OPEN_DEV_LOG=1`.

---

## Release build

```bash
./build-macos.sh
# → ./V2Open.app
```

The script:

1. `cargo build --release -p v2core`
2. Copies fonts, locales, speedometer, app icons, `AppIcon.icns`, engines, `geoip.dat` / `geosite.dat`
3. Compiles `PacketTunnel.appex` (`-O`)
4. Compiles the SwiftUI app (`-O`) linking `libv2core`
5. Codesigns engines, the app binary, and the bundle (with `macos-app/V2Open.entitlements` when a development identity exists)

`V2Open.app` and `*.dSYM` are gitignored.

---

## Where files land

| Item | Location |
| --- | --- |
| User library | `~/Library/Application Support/V2Open/library.json` |
| Generated engine config | `~/Library/Application Support/V2Open/config.json` |
| Core log | `~/Library/Application Support/V2Open/core.log` |
| Rulesets (copied on first run) | `~/Library/Application Support/V2Open/rulesets/` |
| Dev UI log | `<repo>/dev-logs/runtime.log` |
| Launch Agent | `~/Library/LaunchAgents/app.v2open.scheduler.plist` |

To start from a clean library without deleting the repo: quit the app and move that Application Support folder aside.

---

## Adding Swift sources

Drop a `.swift` file anywhere under `macos-app/Sources/`. Both build scripts `find … -name '*.swift' | sort` — you do **not** register files in an Xcode project.

Keep types in the folder that owns the feature:

```
Sources/App/           entry, window, scheduler
Sources/Core/          Model, RPC, locales, toasts, log classifier
Sources/Home/          home + speed test
Sources/Configs/       catalog list, import sheets, share/QR
Sources/Settings/      all settings subpages
Sources/Editor/        manual profile editor
Sources/Tools/         extras, per-app
Sources/Navigation/    RootView, headers
Sources/Components/    buttons, fields, tab strip
Sources/Design/        tokens, frame, theme
PacketTunnel/          Network Extension (compiled separately)
```

---

## Adding Rust sources

Modules are declared in `native/core/src/lib.rs`. After adding a file, `mod` it there and export only what Swift or tests need.

```bash
cd native
cargo test -p v2core
cargo build -p v2core
```

`CARGO_TARGET_DIR` is forced to `native/target` by the shell scripts so debug and release do not fight a random env.

---

## Codesign and VPN

`macos-env.sh` picks the first `Apple Development` / `Developer ID Application` / `Mac Developer` identity. If none, it signs with `-` (ad-hoc).

Full system VPN requires a provisioning profile and the Network Extension entitlement on a real team. Unsigned `V2Open-Dev.app` still compiles `PacketTunnel.appex`, but if the OS refuses to start it, Swift falls back to `connect` (engine as a child process). That is expected during UI work.

Do not disable SIP or copy random provisioning profiles into the repo.

Full Packet Tunnel / notarization path: [signing.md](signing.md). Replacing engines: [binaries.md](binaries.md).

---

## Debugging checklist

1. Reproduce with `./dev-macos.sh run-logs`.
2. Read `[app]` vs `[core]` lines.
3. For engine JSON, inspect `~/Library/Application Support/V2Open/config.json` (do not commit it).
4. For RPC failures, `DevLog` prints `rpc: <method>: <error>` in the dev app.
5. Packet Tunnel issues: Console.app filtered by `PacketTunnel`, and `diagnostics` in the UI.

---

## What not to commit

Already gitignored: `V2Open.app`, `V2Open-Dev.app`, `*.dSYM`, `dev-logs/`, `data/*.json`, `.cursor/`.

Never add:

- Your real `library.json`
- New copies of `sing-box` / `xray` without a PR note (they are large)
- `.p12`, provisioning profiles, API tokens

---

## Contributor checks (required before a PR)

```bash
./scripts/test.sh                # locales, version copies, Swift helpers, cargo test
```

`./scripts/bump-version.sh x.y.z` is only for `release/*` and `hotfix/*` branches. Details: [versioning.md](versioning.md).

---

## After you change the toolchain

If you add a flag, a script, or a required brew formula, update **this file** and the Quick start in [README.md](../README.md) in the same PR.

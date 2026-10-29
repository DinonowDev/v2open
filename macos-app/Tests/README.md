# Swift tests

These tests compile with `swiftc` (there is no Xcode project). They cover pure helpers:

- `ViewFormatting.swift` (`jsonInt`, `formatBps`, …)
- `LocaleStore` fallbacks from `Localization.swift`

```bash
./scripts/test-swift.sh
```

They do **not** launch the GUI or the Packet Tunnel. UI flows stay a manual checklist on the pull request. Rust engine tests live in `native/core/tests/` — see [docs/testing.md](../../docs/testing.md).

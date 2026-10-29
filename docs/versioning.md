# Versioning

V2Open follows [Semantic Versioning](https://semver.org/) `MAJOR.MINOR.PATCH` plus a monotonic **build** number (`CFBundleVersion`).

Canonical file: [`VERSION`](../VERSION)

```
1.1.0
2
```

Line 1 is the marketing version (`CFBundleShortVersionString`). Line 2 is the build integer. Both are required.

---

## When to bump

| You changed | Bump |
| --- | --- |
| Crash, wrong ping, copy typo, locale fix, no API change | **PATCH**, **build + 1** |
| New setting, protocol, RPC method, tab, URL scheme, user-visible flow | **MINOR**, PATCH → `0`, **build + 1** |
| `library.json` field removed/renamed incompatibly, RPC method removed/renamed, URL scheme removed, vault magic changed | **MAJOR**, MINOR and PATCH → `0`, **build + 1** |
| Comments, docs-only, tests-only, private refactor | **no** bump |

Examples:

- Fix disconnect on sleep → `1.1.0` → `1.1.1`, build `2` → `3`
- Add a protocol → `1.1.1` → `1.2.0`, build `3` → `4`
- Rename `prepare` → `stage_tunnel` without a compatibility alias → `2.0.0`

Build **never** decreases. It increases on every shipped app bundle, including hotfixes.

Version-bearing commits live on `release/x.y.z` or `hotfix/x.y.z` (or inside a feature PR only when the maintainer already agreed that this PR **is** the release).

---

## Files that must stay equal

`./scripts/bump-version.sh` and `./scripts/check-version.sh` cover:

| File | Field |
| --- | --- |
| `VERSION` | line 1 version, line 2 build |
| `macos-app/Info.plist` | `CFBundleShortVersionString`, `CFBundleVersion` |
| `macos-app/PacketTunnel/Info.plist` | same |
| `native/core/Cargo.toml` | `package.version` (marketing version only) |
| `native/core/src/app.rs` | `"app_version": "x.y.z"` in `about_info` |
| `macos-app/Sources/Settings/AboutView.swift` | fallback `"1.1.0"` string |

`CHANGELOG.md` must have a `[x.y.z]` section **before** the tag is pushed (see [release.md](release.md)).

The About screen prefers `CFBundleShortVersionString` from the bundle; the Rust `about` payload and the Swift fallback are for diagnostics and older call sites. Leaving them stale is a bug.

`native/core` crate version tracks the **app** marketing version, not Cargo’s semver for a published crate (this library is not published to crates.io).

---

## Commands

```bash
# Set marketing version; increment build from VERSION
./scripts/bump-version.sh 1.2.0

# Set both
./scripts/bump-version.sh 1.2.0 --build 7

# Verify copies
./scripts/check-version.sh
```

Do not hand-edit one plist and forget the other. Do not put a date in `CFBundleVersion`.

---

## Changelog rules

File: [CHANGELOG.md](../CHANGELOG.md) ([Keep a Changelog](https://keepachangelog.com/)).

1. While work is on `main`, add bullets under `[Unreleased]`.
2. Group: `Added`, `Changed`, `Deprecated`, `Removed`, `Fixed`, `Security`. Omit empty groups.
3. Write user-facing sentences. Name the setting or protocol. No issue-number-only lines.
4. On release, rename `[Unreleased]` to `[x.y.z] - YYYY-MM-DD` and add a fresh empty `[Unreleased]`.
5. Keep compare links at the bottom in sync with tags `vX.Y.Z`.

A PR that is user-visible **without** a changelog bullet will be requested to add one before merge.

---

## Git tags

Tags are `v` + marketing version: `v1.1.0`. Annotated tags only. Never move a tag that was pushed. See [release.md](release.md).

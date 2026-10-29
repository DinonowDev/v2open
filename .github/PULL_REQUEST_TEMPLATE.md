## Summary

<!-- What changed and why. User-facing first. -->

## Type

- [ ] `feat` — new behavior
- [ ] `fix` — bug
- [ ] `docs` — documentation only
- [ ] `refactor` — no behavior change
- [ ] `test`
- [ ] `chore` / build
- [ ] `release` / `hotfix` — version bump

## Docs and version (required)

Use the [doc map](../docs/README.md). Uncheck only with a written reason.

- [ ] Matching pages under `docs/` updated (or N/A: ________)
- [ ] Locale keys added to **every** file in `macos-app/Resources/Locales/` (or N/A)
- [ ] `CHANGELOG.md` `[Unreleased]` updated (or N/A: docs/tests-only)
- [ ] `./scripts/test.sh` passes (`check-docs.sh` + Swift helpers + `cargo test`)
- [ ] Version **not** bumped (non-release) **or** `./scripts/bump-version.sh` + `check-version.sh` (release/hotfix)
- [ ] Engine swap: [docs/binaries.md](../docs/binaries.md) + `NOTICE` (or N/A)

## Test plan

- [ ] `./scripts/test.sh` (or `cargo test -p v2core` + `./scripts/test-swift.sh`)
- [ ] Manual: steps you clicked in the running app

<!-- UI: attach a screenshot or recording. Tunnel/VPN: say signed vs V2Open-Dev. -->

## Risk

<!-- Packet Tunnel, entitlements, library.json migration, URL schemes, vault. "None" is fine. -->

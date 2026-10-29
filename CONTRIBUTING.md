# Contributing to V2Open

Thank you for helping. This document is the contract for every contribution: code, docs, locales, binaries notes, and reviews.

Persian version: [CONTRIBUTING.fa.md](CONTRIBUTING.fa.md)

By opening a pull request you agree to the [Code of Conduct](CODE_OF_CONDUCT.md) and to keep documentation, changelog, and version numbers in sync with the change.

---

## Before you start

1. Read this file and [docs/README.md](docs/README.md).
2. Search existing issues and pull requests so you do not duplicate work.
3. For a large change (new protocol, new RPC surface, Network Extension behavior, settings schema), open an issue first and wait for agreement on the approach.
4. Never commit secrets, personal `library.json`, live configs, or engine crash dumps.

Development setup: [docs/development.md](docs/development.md).

---

## What we accept

| Kind | Typical branch | Docs you must touch |
| --- | --- | --- |
| Bug fix | `fix/short-slug` | `CHANGELOG.md` (if user-visible) + any stale guide |
| Feature | `feature/short-slug` | user guide / architecture / RPC + locales + changelog + version |
| Docs only | `docs/short-slug` | the docs themselves; no version bump |
| Refactor | `refactor/short-slug` | architecture if the map of the code changed |
| Tests | `test/short-slug` | [docs/testing.md](docs/testing.md) if you add a suite or flag |
| Chore / build | `chore/short-slug` | [docs/development.md](docs/development.md) if scripts or flags change |
| Release | `release/x.y.z` | `VERSION`, plist, crate, changelog, about string |

We do **not** accept:

- Drive-by reformatting of files you did not otherwise change
- New languages or frameworks (no Flutter/web/Linux/Windows ports in this tree)
- Unsigned third-party binaries without a written reason in the PR
- Changes that log or upload user configs
- PRs that change behavior without updating docs and locales

---

## Golden rules

### 1. Documentation is part of the patch

If a reviewer cannot understand the change from the docs + changelog, the PR is incomplete.

Use [docs/README.md](docs/README.md) (the **doc map**) to find which file to edit. Minimum:

- User-visible behavior → [docs/user-guide.md](docs/user-guide.md) and `CHANGELOG.md`
- New or changed RPC method → [docs/rpc.md](docs/rpc.md)
- New setting key → user guide **and** `defaults()` in `native/core/src/app.rs` **and** locales
- New UI string → **all** files in `macos-app/Resources/Locales/` (see [docs/localization.md](docs/localization.md))
- Build / run / debug → [docs/development.md](docs/development.md)
- Branch or review process → this file and [docs/branching.md](docs/branching.md)

Run `./scripts/check-docs.sh` before you push. It fails if locale keys drift or version files disagree.

### 2. Version every user-facing release

V2Open uses [Semantic Versioning](https://semver.org/) `MAJOR.MINOR.PATCH` plus a monotonic **build** integer.

| Change | Version |
| --- | --- |
| Bug fix, copy, crash, no API break | bump **PATCH**, bump **build** |
| New feature, new setting, new protocol, new RPC | bump **MINOR**, reset PATCH to `0`, bump **build** |
| Breaking library format, RPC rename/removal, URL scheme removal | bump **MAJOR**, reset MINOR and PATCH to `0`, bump **build** |
| Docs, comments, tests, internal-only refactor | **do not** bump version |

How to bump, which files to touch, and examples: [docs/versioning.md](docs/versioning.md).

```bash
./scripts/bump-version.sh 1.2.0        # sets marketing version, increments build
./scripts/bump-version.sh 1.2.0 --build 7
./scripts/check-version.sh             # all copies must match VERSION
```

Never leave `Info.plist`, Packet Tunnel plist, `native/core/Cargo.toml`, `app_version` in `app.rs`, or the About fallback disagreeing with [`VERSION`](VERSION).

### 3. Changelog is written for humans

Every user-facing PR adds an entry under `[Unreleased]` in [CHANGELOG.md](CHANGELOG.md) using [Keep a Changelog](https://keepachangelog.com/) sections: `Added`, `Changed`, `Fixed`, `Removed`, `Security`.

Do not write “misc fixes”. Write what a user or integrator will notice.

On release, move `[Unreleased]` into `[x.y.z] - YYYY-MM-DD` (see [docs/release.md](docs/release.md)).

---

## Branching

Canonical rules: [docs/branching.md](docs/branching.md). Summary:

```
main                 always releasable; protected
feature/<slug>       new work
fix/<slug>           bug
docs/<slug>          documentation
refactor/<slug>      no behavior change
test/<slug>          tests only
chore/<slug>         tooling, scripts, deps
release/x.y.z        version bump + changelog freeze
hotfix/x.y.z         production emergency from a tag
```

- Branch from the latest `main` (`git fetch origin && git checkout -b feature/foo origin/main`).
- One concern per branch. Do not mix a visual redesign with a parser fix.
- Rebase onto `main` before asking for review if your branch has drifted (`git rebase origin/main`). Do not rebase a branch others are using without asking.
- Never commit on `main` directly. Never force-push `main`. Never rewrite published tags.
- `release/*` and `hotfix/*` are the only branches that bump `VERSION`.

---

## Commits

Use [Conventional Commits](https://www.conventionalcommits.org/):

```
<type>(optional-scope): short summary in English

Optional body: why, not what. Wrap at 72 chars.
```

Types: `feat`, `fix`, `docs`, `refactor`, `test`, `chore`, `perf`, `revert`.

Scopes (optional): `core`, `ui`, `tunnel`, `parser`, `routing`, `dns`, `locales`, `build`, `docs`.

Examples:

```
feat(parser): import Hysteria2 hop ports from share links
fix(tunnel): reload PacketTunnel without dropping the session
docs(rpc): document mark_connected and prepare
chore(build): copy AppIcons into the dev bundle
```

- Imperative mood, present tense, no trailing period in the subject.
- Do not mention tooling brand names in commit messages.
- Do not mix `feat` and unrelated `refactor` in one commit if you can split them.
- Commit localizations with the UI change, not afterwards in a follow-up that can be forgotten.

---

## Pull requests

Open a PR against `main` as soon as the branch is reviewable. Draft PRs are welcome for early feedback.

### Title

Same shape as a Conventional Commit subject, for example `feat(ui): add compact connect button`.

### Body

Use the repository template. It asks for:

- What changed and why
- How you tested
- Doc / locale / changelog / version checklist
- Screenshots or screen recording for UI work
- Risk notes (tunnel, codesign, library migration)

### Size

Prefer PRs a reviewer can finish in one sitting. If a feature is large, split:

1. `refactor/…` with no behavior change
2. `feat/…` with the new path
3. `docs/…` only if docs truly cannot land with the feature (they usually can)

### Review

- You must not merge until checks pass: GitHub Action `Docs and version` (`.github/workflows/docs.yml` runs `./scripts/check-docs.sh`), `cargo test -p v2core` locally (non-ignored tests), and a manual run of the flow you touched.
- UI work is not done until you ran the app and clicked through the changed screens, including other tabs that share the same state.
- At least one approval is required when a second person is available. Maintainers may self-merge small docs/typo PRs.
- Address review comments with new commits or a rebase; do not force-push over review history unless the reviewer asked for a squash/rebase.
- Squash-merge is the default so `main` stays a clean history of features and fixes. The squash message must stay Conventional Commit shaped.

### After merge

Delete the remote branch. If the PR was a `feat` / `fix` that should ship, a maintainer cuts a `release/x.y.z` (or includes the bump in that same PR if it was already agreed).

---

## Tests

See [docs/testing.md](docs/testing.md).

```bash
cd native
cargo test -p v2core -- --skip live   # parser / builder / clash / dns
```

Live tests (`live_connect`, `live_matrix`) are `#[ignore]`. They use the **saved user library** and real network; do not run them in CI and do not commit their output.

Add a focused Rust test when you change `parser`, `builder`, `routing`, DNS items, or Xray export. There is no Swift test target yet; for UI, document the manual path in the PR.

---

## Locales

English JSON is the source of truth: `macos-app/Resources/Locales/en.json`.

Adding a string:

1. Add the key to **every** `macos-app/Resources/Locales/*.json`.
2. If the key is used at runtime before JSON loads, add it to the `enText` / `faText` fallbacks in `macos-app/Sources/Core/Localization.swift`.
3. Keep keys camelCase, matching existing names (`smartConnect`, not `smart_connect`).
4. Do not concatenate sentences in code; put the whole phrase in JSON so translators can reorder.

`./scripts/check-locales.sh` fails if any locale file is missing a key that `en.json` has, or has extra keys.

---

## Code style

### Swift

- SwiftUI views stay in the folder that owns the screen (`Home/`, `Configs/`, `Settings/`, …).
- Go through `Model` / `v2RPC` for engine work. Do not spawn `sing-box` from a view.
- Respect `PageLayout` and `C` theme tokens. Do not invent a second spacing scale.
- New user-facing text goes through `model.t("key")`, never a hardcoded English/Persian string (About/Legal bilingual blocks are the documented exception until they move to JSON).

### Rust

- `v2core` is macOS-only (`compile_error` on other OS).
- RPC methods return `Result<Value, String>` and stay backwards compatible unless you are doing a MAJOR bump.
- New settings go in `defaults()` and `migrate_settings()` so old `library.json` files keep working.
- Do not unwrap in `v2_call` paths; map errors to the JSON `{ok:false,error}` shape.

### Shell

- `set -euo pipefail`
- Shared flags live in `macos-env.sh`, not copied into a third script.

---

## Security and configs

- Do not paste real share links, UUIDs, or passwords into issues, PRs, or logs.
- Use `example.com` and the sample UUIDs already in tests.
- Report vulnerabilities privately: [SECURITY.md](SECURITY.md).
- Packet Tunnel and entitlements changes need an explicit risk note in the PR.

---

## Maintainer notes

- Default branch: `main`
- Tags: `vX.Y.Z` matching `VERSION` (see [docs/release.md](docs/release.md))
- Bundle IDs: `local.v2open.desktop` (release), `local.v2open.dev` (dev)
- Copyright holder: Amirhossein Rezaei

Questions that are not security issues belong in GitHub Issues.

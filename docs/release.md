# Release

Ship from `main` after a `release/x.y.z` or `hotfix/x.y.z` PR is merged.

---

## Checklist

1. `git status` clean on `main`, tests green: `cargo test -p v2core` and `./scripts/check-docs.sh`.
2. `[Unreleased]` in `CHANGELOG.md` lists everything that is going out.
3. Branch `release/x.y.z` (or hotfix).
4. Run `./scripts/bump-version.sh x.y.z` (build increments automatically).
5. Move changelog:
   - Rename `[Unreleased]` → `[x.y.z] - YYYY-MM-DD`
   - Insert a new empty `[Unreleased]` with the usual headings you actually use
   - Update the compare links at the bottom (`vPREV...vTHIS`, `vTHIS...HEAD`)
6. `./scripts/check-version.sh` must pass.
7. Open the PR. Title: `chore(release): x.y.z`.
8. After merge:

```bash
git checkout main
git pull --ff-only origin main
git tag -a "vX.Y.Z" -m "V2Open X.Y.Z"
git push origin "vX.Y.Z"
```

9. **GitHub Actions** runs [`.github/workflows/release.yml`](../.github/workflows/release.yml) on that tag: tests, `./build-macos.sh`, zip `V2Open-{version}-build{N}-macos-arm64.zip`, and a GitHub Release with the matching `[x.y.z]` section from `CHANGELOG.md`. No manual upload unless the workflow failed and you are recovering by hand.
10. Smoke-test About → version plate matches `x.y.z (build)`.

Optional: after every push to `main`, CI attaches an unsigned **`V2Open-macos-arm64`** artifact (14-day retention) on the latest workflow run — useful for testers before you tag.

---

## Optional signing on CI

Ad-hoc builds from CI are **unsigned** (same as local `./build-macos.sh` without a Developer ID). Users may need **Right-click → Open** the first time. Full **Network Extension / VPN** mode still needs a signed Packet Tunnel; see [signing.md](signing.md).

To sign and notarize release zips from Actions later, add repository secrets (same pattern as [DinonowDev/LazyDisk](https://github.com/DinonowDev/LazyDisk)):

| Secret | Purpose |
| --- | --- |
| `CODE_SIGN_IDENTITY` | e.g. `Developer ID Application: …` |
| `NOTARYTOOL_PROFILE` | Keychain profile name for `notarytool` |

Then extend `release.yml` to export those env vars before `./build-macos.sh` (and add notarization steps to `build-macos.sh` when you are ready).

---

## What not to do

- Tag a commit that does not contain the version bump
- Reuse a tag or move it with `--force` after it was pushed
- Ship a MINOR without user-guide / locale updates for the new UI
- Bump MAJOR without a migration note in the changelog and [architecture.md](architecture.md)

---

## Version locations recap

See [versioning.md](versioning.md). The bump script is the only supported way to edit them in bulk.

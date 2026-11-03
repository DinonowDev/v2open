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

9. **GitHub Actions** runs [`.github/workflows/release.yml`](../.github/workflows/release.yml) on that tag: tests, `./build-macos.sh` for **arm64** and **x86_64**, zips `V2Open-{version}-build{N}-macos-arm64.zip` and `V2Open-{version}-build{N}-macos-x86_64.zip`, and a GitHub Release with the matching `[x.y.z]` section from `CHANGELOG.md`. No manual upload unless the workflow failed and you are recovering by hand.
10. Smoke-test About → version plate matches `x.y.z (build)`.

After every push to `main`, CI uploads **`V2Open-macos-arm64`** and **`V2Open-macos-x86_64`** zip artifacts (14-day retention).

---

## Signing on CI

Without Apple secrets the zips are ad-hoc. Users may need **Right-click → Open** the first time. With the secrets in [signing.md](signing.md) and [apple-ci-secrets.md](apple-ci-secrets.md), the same workflow signs with Developer ID, notarizes, and staples before zipping. System VPN still needs those provisioning profiles; an ad-hoc Packet Tunnel is not a system VPN.

Before the first signed release, run [scripts/encode-apple-secrets.sh](../scripts/encode-apple-secrets.sh) and set repository secrets, then `./scripts/pre-release-check.sh` before tagging.

---

## What not to do

- Tag a commit that does not contain the version bump
- Reuse a tag or move it with `--force` after it was pushed
- Ship a MINOR without user-guide / locale updates for the new UI
- Bump MAJOR without a migration note in the changelog and [architecture.md](architecture.md)

---

## Version locations recap

See [versioning.md](versioning.md). The bump script is the only supported way to edit them in bulk.

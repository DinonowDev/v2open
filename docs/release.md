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
./build-macos.sh
git tag -a "vX.Y.Z" -m "V2Open X.Y.Z"
git push origin "vX.Y.Z"
```

9. Create the GitHub Release from that tag. Paste the changelog section. Attach `V2Open.app` only if you intend to distribute that artifact (zip it; do not commit the app to git).
10. Smoke-test About → version plate matches `x.y.z (build)`.

---

## What not to do

- Tag a commit that does not contain the version bump
- Reuse a tag or move it with `--force` after it was pushed
- Ship a MINOR without user-guide / locale updates for the new UI
- Bump MAJOR without a migration note in the changelog and [architecture.md](architecture.md)

---

## Version locations recap

See [versioning.md](versioning.md). The bump script is the only supported way to edit them in bulk.

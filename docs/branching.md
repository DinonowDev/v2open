# Branching and pull requests

This is the Git workflow for V2Open. Policy summary: [CONTRIBUTING.md](../CONTRIBUTING.md).

---

## Branch types

```
main
 ├─ feature/<slug>
 ├─ fix/<slug>
 ├─ docs/<slug>
 ├─ refactor/<slug>
 ├─ test/<slug>
 ├─ chore/<slug>
 ├─ release/x.y.z
 └─ hotfix/x.y.z
```

| Branch | Created from | Merges to | May bump `VERSION` |
| --- | --- | --- | --- |
| `main` | — | tags `vX.Y.Z` | no (only via release/hotfix PR) |
| `feature/<slug>` | `main` | `main` | no |
| `fix/<slug>` | `main` | `main` | no |
| `docs/<slug>` | `main` | `main` | no |
| `refactor/<slug>` | `main` | `main` | no |
| `test/<slug>` | `main` | `main` | no |
| `chore/<slug>` | `main` | `main` | no |
| `release/x.y.z` | `main` | `main` then tag | **yes** |
| `hotfix/x.y.z` | tag `vX.Y.Z` | `main` then tag | **yes** |

Slugs: lowercase, hyphens, short (`feature/hy2-hop-port`, `fix/sleep-disconnect`, `docs/rpc-prepare`). No personal names in the branch (`feature/ali-stuff`).

There is no long-lived `develop` branch. `main` is always supposed to be releasable.

---

## Daily flow

```bash
git fetch origin
git checkout main
git pull --ff-only origin main
git checkout -b feature/dns-item-search

# … commits …

git fetch origin
git rebase origin/main
./scripts/check-docs.sh
cd native && cargo test -p v2core
git push -u origin HEAD
```

Open a pull request against `main`. Fill `.github/PULL_REQUEST_TEMPLATE.md`.

---

## Pull request rules

1. **One concern.** A parser fix does not include a theme rewrite.
2. **Docs and locales travel with the code.** See the [doc map](README.md).
3. **Changelog.** User-visible work adds `[Unreleased]` bullets.
4. **Tests.** Parser/builder/routing get a Rust test. UI gets a written manual path.
5. **No secrets.** Redact configs.
6. **Title** is a Conventional Commit subject.
7. **Draft** is fine until you want review; mark Ready when checks and the template are done.
8. **Rebase** if `main` moved and the conflict is yours. Do not rebase after someone else pushed commits to your branch unless you coordinate.
9. **Force-push** only to your feature branch, never to `main`.
10. **Review.** Another person approves when available. Trivial docs/typos may be self-merged by a maintainer.
11. **Merge.** Default is **squash and merge** so `main` is one commit per PR. The squash message must remain `type(scope): summary`. Use merge commits only for release PRs that already have curated history (rare).
12. **Delete** the remote branch after merge.

### Reviewer checklist

- Does the PR update the doc map targets?
- Do locale keys still pass `./scripts/check-locales.sh`?
- If user-facing, is `CHANGELOG.md` updated?
- If this PR claims to be a release, does `./scripts/check-version.sh` pass?
- Any Packet Tunnel / entitlement / vault change called out?

---

## Release branches

When `main` has enough `[Unreleased]` work:

```bash
git checkout -b release/1.2.0 origin/main
./scripts/bump-version.sh 1.2.0
# move CHANGELOG [Unreleased] → [1.2.0] - date
git commit -am "chore(release): 1.2.0"
# PR → main, squash or merge as agreed
# then tag (see release.md)
```

Hotfix: branch from the **tag** that is in users’ hands, bump PATCH, PR to `main`, tag again.

```bash
git checkout -b hotfix/1.1.1 v1.1.0
./scripts/bump-version.sh 1.1.1
```

Do not mix extra features into a hotfix.

---

## Tags and GitHub

- Tag format: `v1.2.0` (annotated).
- GitHub Release notes are generated from the changelog section, not from a dump of commit subjects.
- Protect `main` on GitHub: require PR, require the template checklist, dismiss stale reviews on force-push if you enable that.

Issues:

- Bugs → `.github/ISSUE_TEMPLATE/bug_report.yml`
- Features → `feature_request.yml`
- Docs gaps → `docs.yml`

Link the PR with `Fixes #123` when it does.

---

## Permissions

Contributors: fork (or a branch on the origin if you have write access), PR, no push to `main`.

Maintainers: merge PRs, cut tags, run `./scripts/bump-version.sh` on release branches, publish GitHub Releases.

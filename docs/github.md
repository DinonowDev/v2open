# GitHub repository settings

File-based rules live in `.github/`. **Branch protection cannot be stored in git**; a maintainer must apply it once on the origin. This page is that checklist.

CODEOWNERS: [`.github/CODEOWNERS`](../.github/CODEOWNERS) (reviews request `@DinonowDev` when that account has write access).

---

## Required on `main`

In GitHub: **Settings → Rules → Rulesets** (or **Branches → Branch protection** on older UI). Create a ruleset for `main`:

| Setting | Value |
| --- | --- |
| Restrict deletions | On |
| Block force pushes | On |
| Require a pull request | On |
| Required approvals | 1 when a second collaborator exists; 0 is acceptable for a solo maintainer |
| Dismiss stale reviews on new commits | On if you have reviewers |
| Require conversation resolution | On |
| Required status checks | `Docs and version` (`check` job) and `Swift tests` (`swift` job) once those workflows have run once |
| Require linear history | Optional; squash-merge already keeps `main` linear |
| Do not allow bypassing | On for everyone except the repo owner if you need an emergency hatch |

Also:

- **Settings → General → Pull Requests**: enable squash merge; disable merge commits unless you have a reason.
- **Settings → General**: auto-delete head branches.
- **Settings → Code security**: enable private vulnerability reports (matches [SECURITY.md](../SECURITY.md)).

---

## Apply with `gh` (optional)

Requires `gh auth login` and admin on `DinonowDev/v2open`.

```bash
./scripts/protect-main.sh
```

The script targets `origin` of the current clone. If there is no remote yet, add one first:

```bash
git remote add origin git@github.com:DinonowDev/v2open.git
git push -u origin main
```

GitHub may reject a first push that contains `binaries/macos/sing-box` because of file size. See [binaries.md](binaries.md) (Git LFS).

---

## Why this is not automatic

A ruleset is server-side. Committing a YAML file does not protect `main`. Until this checklist is applied, contributors must still follow [docs/branching.md](branching.md) by convention.

# راهنمای ایجنت‌ها (Cursor و CI)

هر تسک کد در این ریپو **قبل از ویرایش** باید جریان Git زیر را دنبال کند.

## برنچ‌ها

- **اصلی:** `production` → `stage` → `dev` (کد تولید بالا، توسعه پایین).
- **کار:** از `dev` branch بساز: `feature/*`, `fix/*`, `docs/*`, `refactor/*`, `test/*`, `chore/*`, `release/x.y.z`, `hotfix/x.y.z`.

## ترتیب اجباری

1. `git fetch` → checkout/pull `dev` → `git checkout -b <type>/<slug>`
2. پیاده‌سازی، کامیت‌های Conventional Commits، `CHANGELOG`/`docs`/`locales` طبق CONTRIBUTING
3. `./scripts/check-docs.sh` (+ تست در صورت نیاز) → push → **PR به `dev`**
4. بعد از merge در `dev`: `./scripts/mark-merge.sh merged dev <branch> HEAD --push` (تگ `merged/dev/...`؛ لیبل PR با workflow)
5. پایان تسک / درخواست انتشار: **PR `dev`→`stage`** سپس **`stage`→`production`** + `./scripts/mark-merge.sh sync ... --push`
6. روی **`production`**: `./scripts/bump-version.sh`, `check-version.sh`, چنج‌لاگ، سپس تگ `vX.Y.Z` و `git push origin vX.Y.Z` برای ریلیز

روی `production` / `stage` / `dev` مستقیم کامیت نکن. force-push به `production` ممنوع.

## اسناد

- فارسی (کامل): [docs/git-flow.fa.md](docs/git-flow.fa.md)
- ورژن: [docs/versioning.md](docs/versioning.md)
- انتشار: [docs/release.md](docs/release.md)
- قوانین Cursor: `.cursor/rules/git-flow-branches.mdc`, `git-flow-task-execution.mdc`, `git-flow-release.mdc`

## وضعیت ریپو

اگر هنوز فقط `main` روی ریموت است، از `main` به‌عنوان پایهٔ موقت استفاده کن تا `dev`/`stage`/`production` bootstrap شوند (مراحل در `docs/git-flow.fa.md`).

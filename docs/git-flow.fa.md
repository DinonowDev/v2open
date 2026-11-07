# جریان Git: production / stage / dev

این سند استاندارد رسمی برای **انسان‌ها و ایجنت‌های Cursor** در V2Open است. قوانین دائمی در `.cursor/rules/git-flow-*.mdc` و خلاصه در `AGENTS.md` تکرار شده‌اند.

نسخه قبلی تک‌برنچ (`main`): [branching.md](branching.md) — تا وقتی CI فقط روی `main` trigger شود، PRها را می‌توان موقتاً به `main` نگه داشت؛ هدف نهایی جایگزینی پایهٔ ادغام با `dev` و انتشار از `production` است.

---

## برنچ‌های اصلی

```
production          ← کاربر نهایی، تگ و GitHub Release  (فقط از stage / release / hotfix)
    ↑
  stage             ← QA؛ dev + fix/* + release/* / hotfix/*
    ↑
   dev              ← feature/docs/chore/…
    ↑
 feature/* docs/* chore/* …          fix/* ──→ stage (مستقیم)
```

| برنچ | هدف | push مستقیم |
| --- | --- | --- |
| `production` | خط تولید، همیشه قابل انتشار | فقط via PR (maintainer) |
| `stage` | تست یکپارچه قبل از prod | فقط via PR |
| `dev` | ادغام روزانه | فقط via PR |

---

## راه‌اندازی اولیه (یک‌بار)

اگر فقط `main` دارید:

```bash
git fetch origin
git checkout main
git pull --ff-only origin main

# گزینه الف: main را production کنید
git branch -m main production
git push -u origin production
git push origin :main   # فقط بعد از به‌روز کردن branch protection و CI

# dev و stage از همان خط پایه
git branch dev production
git branch stage production
git push -u origin dev stage
```

یا گزینه ب: `main` را نگه دارید و `production` = `main` تا مهاجرت CI تمام شود.

CI: در `.github/workflows/ci.yml` شاخه‌های `dev`, `stage`, `production` را به `on.push.branches` اضافه کنید.

---

## انواع ساب‌برنچ (از `dev`)

همان قرارداد [branching.md](branching.md):

| نوع | مثال | PR به (base) |
| --- | --- | --- |
| `feature/*`, `docs/*`, `refactor/*`, `test/*`, `chore/*` | `feature/hy2-hop` | **`dev` فقط** |
| `fix/<slug>` | `fix/sleep-disconnect` | **`stage` فقط** |
| `release/x.y.z` | `release/1.4.0` | **`stage`** یا **`production`** |
| `hotfix/x.y.z` | `hotfix/1.3.6` | **`stage`** یا **`production`** |

**پروموت لایه‌ها (فقط این سرشاخه‌ها):**

| از → به | مجاز |
| --- | --- |
| `dev` → `stage` | PR با head=`dev` |
| `stage` → `production` | PR با head=`stage` (**نه** `dev` و نه ساب‌برنچ تسک) |
| `main` | فقط legacy؛ PR جدید به `main` **رد** می‌شود |

CI: [`.github/workflows/branch-flow-guard.yml`](../.github/workflows/branch-flow-guard.yml). لوکال: `./scripts/branch-flow-validate.sh` و `./scripts/install-git-hooks.sh`.

```bash
./scripts/bootstrap-tier-branches.sh    # ساخت stage/production روی origin
./scripts/protect-tier-branches.sh      # نیاز admin + یک بار CI برای نام checkها
```

---

## جریان روزانه (تسک جدید)

1. `git fetch` → `checkout dev` → `pull --ff-only`
2. `git checkout -b <type>/<slug>`
3. تغییر + کامیت‌های conv. + چنج‌لاگ/داک در صورت نیاز
4. `./scripts/check-docs.sh` (و تست‌های مرتبط)
5. `git push -u origin HEAD` → PR به **`dev`**
6. squash merge، حذف برنچ ریموت
7. **ردیابی:** بعد از merge (PR یا merge محلی):

```bash
./scripts/mark-merge.sh merged dev <type>/<slug> <merge-commit> --push
```

لیست تگ‌های مرج روی `dev`:

```bash
git tag -l 'merged/dev/*'
```

### لیبل‌های GitHub (PR)

یک‌بار: `./scripts/sync-github-labels.sh` (نیاز به `gh`).

| لیبل | معنی |
| --- | --- |
| `merged-to-dev` | PR تسک به `dev` merge شد |
| `on-stage` | همان PR بعد از رسیدن کدش به `stage` (لیبل قبلی حذف می‌شود) |
| `on-production` | همان PR بعد از رسیدن به `production` (`on-stage` / `merged-to-dev` حذف) |

PR پروموت لایه‌ها (`dev`→`stage` و …) لیبل `tier-sync` می‌گیرند.

بعد از merge محلی (بدون PR): `./scripts/mark-merge.sh sync … --push` (تگ‌ها) و `./scripts/promote-pr-labels.sh stage|production HEAD`.

### تگ پروموت بین لایه‌ها

```bash
git checkout stage && git pull --ff-only origin stage
./scripts/mark-merge.sh sync stage dev HEAD --push

# production بعد از merge و bump:
./scripts/mark-merge.sh sync production stage HEAD --push
```

روی `production` تگ **`vX.Y.Z`** همان مرجع انتشار رسمی است؛ `sync/production/...` تکمیلی است.

---

## پروموت بین لایه‌ها

### dev → stage

- وقتی مجموعه‌ای از PRها روی `dev` پایدار است (یا قبل از QA).
- PR از `dev` به `stage`؛ معمولاً **بدون** bump ورژن.
- در `stage` تست دستی / CI کامل.

### stage → production (+ ورژن اجباری)

1. برنچ `release/x.y.z` از `stage` (یا bump مستقیم در PR `stage` → `production` اگر تاریخچه تمیز است).
2. `./scripts/bump-version.sh x.y.z`
3. چنج‌لاگ: بستن `[Unreleased]` → `[x.y.z]`
4. `./scripts/check-version.sh`
5. PR به **`production`**، عنوان `chore(release): x.y.z`
6. بعد از merge:

```bash
git checkout production
git pull --ff-only origin production
git tag -a "vX.Y.Z" -m "V2Open X.Y.Z"
git push origin "vX.Y.Z"
```

7. GitHub Release از workflow روی تگ ساخته می‌شود ([release.md](release.md)).

**قانون:** هر مرج به `production` که برای کاربر قابل‌تحویل است باید ورژن همگام و (در انتشار رسمی) تگ `v*` داشته باشد.

---

## hotfix روی production

```bash
git fetch --tags
git checkout -b hotfix/1.3.6 v1.3.5
./scripts/bump-version.sh 1.3.6
# … fix …
# PR → production → tag v1.3.6
# سپس PRهای back-merge: hotfix → dev و hotfix → stage
```

در hotfix قابلیت جدید مخلوط نکنید.

---

## کامیت و PR

- عنوان PR = Conventional Commit.
- یک PR = یک موضوع.
- squash به `dev`؛ برای `release/x.y.z` می‌توان merge commit نگه داشت (نادر).
- جزئیات بیشتر: [CONTRIBUTING.fa.md](../CONTRIBUTING.fa.md).

---

## نقشه فایل‌ها

| موضوع | فایل |
| --- | --- |
| ورژن و فایل‌های همگام | [versioning.md](versioning.md) |
| چک‌لیست انتشار | [release.md](release.md) |
| قوانین ایجنت | `.cursor/rules/git-flow-*.mdc` |
| خلاصه برای ابزارها | `AGENTS.md` |

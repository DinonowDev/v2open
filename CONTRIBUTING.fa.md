# مشارکت در V2Open

قبل از هر پول‌ریکوئست این سند را بخوانید. نسخه انگلیسی (مرجع GitHub): [CONTRIBUTING.md](CONTRIBUTING.md)

با باز کردن PR با [منشور رفتار](CODE_OF_CONDUCT.md) موافقت می‌کنید و متعهد می‌شوید داکیومنت، چنج‌لاگ و شماره نسخه با تغییر همگام بماند.

---

## قبل از شروع

1. این فایل و [docs/README.md](docs/README.md) را بخوانید.
2. ایشو و PRهای موجود را جستجو کنید تا کار تکراری نکنید.
3. برای تغییر بزرگ (پروتکل جدید، سطح RPC، رفتار Network Extension، اسکیمای تنظیمات) اول ایشو باز کنید و روی روش به توافق برسید.
4. سکرت، `library.json` شخصی، کانفیگ زنده یا کرش‌دامپ هسته را کامیت نکنید.

راه‌اندازی محیط: [docs/development.md](docs/development.md).

---

## چه چیزی پذیرفته می‌شود

| نوع | برنچ | اسنادی که باید به‌روز شوند |
| --- | --- | --- |
| باگ | `fix/short-slug` | در صورت دیده شدن توسط کاربر: `CHANGELOG.md` |
| قابلیت | `feature/short-slug` | راهنما / معماری / RPC + ترجمه‌ها + چنج‌لاگ + نسخه |
| فقط داکیومنت | `docs/short-slug` | همان سندها؛ بدون بالا بردن نسخه |
| بازآرایی | `refactor/short-slug` | اگر نقشه کد عوض شد: معماری |
| تست | `test/short-slug` | اگر سوئیت یا فلگ جدید است: [docs/testing.md](docs/testing.md) |
| ابزار / بیلد | `chore/short-slug` | اگر اسکریپت عوض شد: [docs/development.md](docs/development.md) |
| انتشار | `release/x.y.z` | `VERSION`، plist، کریت، چنج‌لاگ |

پذیرفته **نمی‌شود**:

- فرمت‌کردن فایل‌هایی که موضوع PR نیستند
- پورت به فریمورک یا پلتفرم دیگر در همین درخت
- باینری شخص‌ثالث بدون توضیح در PR
- تغییری که کانفیگ کاربر را لاگ یا آپلود کند
- PR رفتاری بدون به‌روزرسانی داکیومنت و ترجمه

---

## قوانین اصلی

### ۱. داکیومنت بخشی از پچ است

اگر از روی داکیومنت و چنج‌لاگ نشود فهمید چه عوض شده، PR ناقص است.

نقشه سند: [docs/README.md](docs/README.md). حداقل‌ها:

- رفتار قابل‌دیدن برای کاربر → [docs/user-guide.md](docs/user-guide.md) و `CHANGELOG.md`
- متد RPC جدید یا عوض‌شده → [docs/rpc.md](docs/rpc.md)
- کلید تنظیمات جدید → راهنما **و** `defaults()` در `native/core/src/app.rs` **و** ترجمه‌ها
- رشته UI جدید → **همه** فایل‌های `macos-app/Resources/Locales/`
- بیلد / اجرا / دیباگ → [docs/development.md](docs/development.md)

قبل از پوش: `./scripts/check-docs.sh`

### ۲. نسخه برای هر انتشار کاربر-محور

SemVer: `MAJOR.MINOR.PATCH` به‌علاوه عدد **build** افزایشی.

| تغییر | نسخه |
| --- | --- |
| باگ، کپی، کرش، بدون شکست API | **PATCH** + **build** |
| قابلیت، تنظیمات، پروتکل یا RPC جدید | **MINOR**، PATCH صفر، **build** |
| شکست فرمت کتابخانه، حذف/تغییر نام RPC، حذف URL scheme | **MAJOR**، MINOR و PATCH صفر، **build** |
| داکیومنت، کامنت، تست، بازآرایی داخلی | نسخه را بالا **نبرید** |

جزئیات: [docs/versioning.md](docs/versioning.md)

```bash
./scripts/bump-version.sh 1.2.0
./scripts/check-version.sh
```

`Info.plist`، plist تونل، `Cargo.toml`، `app_version` در `app.rs` و فال‌بک About نباید با [`VERSION`](VERSION) فرق داشته باشند.

### ۳. چنج‌لاگ برای انسان نوشته می‌شود

هر PR کاربر-محور زیر `[Unreleased]` در [CHANGELOG.md](CHANGELOG.md) یک مورد اضافه می‌کند (`Added` / `Changed` / `Fixed` / `Removed` / `Security`).

«رفع مشکلات متفرقه» ننویسید. بنویسید کاربر چه می‌بیند.

---

## برنچینگ

قواعد کامل: [docs/branching.md](docs/branching.md)

```
main                 همیشه قابل انتشار
feature/<slug>       کار جدید
fix/<slug>           باگ
docs/<slug>          سند
refactor/<slug>      بدون تغییر رفتار
test/<slug>          فقط تست
chore/<slug>         ابزار
release/x.y.z        فریز نسخه و چنج‌لاگ
hotfix/x.y.z         اضطراری از روی تگ
```

- از آخرین `main` برنچ بگیرید.
- هر برنچ یک موضوع. بازطراحی UI را با فیکس پارسر قاطی نکنید.
- قبل از ریویو اگر از `main` عقب هستید rebase کنید.
- مستقیم روی `main` کامیت نکنید. به `main` فورس‌پوش نکنید. تگ منتشرشده را بازنویسی نکنید.
- فقط `release/*` و `hotfix/*` فایل `VERSION` را عوض می‌کنند.

---

## کامیت

[Conventional Commits](https://www.conventionalcommits.org/):

```
<type>(scope): خلاصه کوتاه انگلیسی

بدنه اختیاری: چرا، نه چه.
```

انواع: `feat`، `fix`، `docs`، `refactor`، `test`، `chore`، `perf`، `revert`.

موضوع به حالت امری، زمان حال، بدون نقطه پایان. نام ابزار تولیدکننده متن را در پیام کامیت نیاورید. ترجمه‌ها را با همان تغییر UI کامیت کنید، نه در PR جدا که فراموش شود.

---

## پول‌ریکوئست

PR را روی `main` باز کنید. Draft برای بازخورد زودهنگام مجاز است.

- عنوان مثل موضوع Conventional Commit باشد.
- قالب مخزن را پر کنید: چرا، تست، چک‌لیست داکیومنت/ترجمه/چنج‌لاگ/نسخه، اسکرین برای UI، ریسک تونل.
- PR را کوچک نگه دارید. قابلیت بزرگ را به بازآرایی + قابلیت + سند در صورت نیاز بشکنید.
- قبل از ادغام: اکشن GitHub با نام `Docs and version` (همان `./scripts/check-docs.sh`)، `cargo test -p v2core` (بدون تست‌های live)، و اجرای دستی فلوهایی که دست زدید.
- کار UI تمام نیست تا در اپ واقعی صفحه عوض‌شده و تب‌های وابسته را چک کنید.
- اگر ریویوکننده دیگری هست، حداقل یک تأیید لازم است.
- ادغام پیش‌فرض: squash-merge با پیام Conventional Commit.
- بعد از ادغام برنچ ریموت را حذف کنید.

---

## تست و ترجمه

```bash
cd native
cargo test -p v2core
```

تست‌های `live_*` با `#[ignore]` هستند، به کتابخانه واقعی کاربر وصل می‌شوند و برای CI نیستند.

منبع رشته‌ها: `macos-app/Resources/Locales/en.json`. کلید جدید باید در **همه** زبان‌ها اضافه شود. `./scripts/check-locales.sh` نبود کلید را رد می‌کند.

---

## امنیت

لینک اشتراک واقعی، UUID یا رمز را در ایشو و PR نگذارید. آسیب‌پذیری را خصوصی گزارش کنید: [SECURITY.md](SECURITY.md).

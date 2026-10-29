# V2Open

کلاینت محلی VPN / پروکسی برای macOS. کانفیگ‌ها، مسیرها، DNS و پشتیبان‌ها روی همین مک می‌مانند مگر خودتان خروجی بگیرید یا همگام‌سازی iCloud را روشن کنید.

V2Open سرویس VPN نمی‌فروشد و سرورهای کانفیگ شما را اداره نمی‌کند. اپ هسته‌های [sing-box](https://github.com/SagerNet/sing-box) یا [Xray](https://github.com/XTLS/Xray-core) را روی مک شما اجرا می‌کند.

| | |
| --- | --- |
| **نسخه فعلی** | `1.1.0` (بیلد `2`) — فایل [`VERSION`](VERSION) |
| **پلتفرم** | macOS ۱۳ به بالا |
| **منبع** | [github.com/DinonowDev/v2open](https://github.com/DinonowDev/v2open) |
| **توسعه‌دهنده** | امیرحسین رضایی |

سند انگلیسی پروژه: [README.md](README.md)

---

## قابلیت‌ها

- ورود لینک اشتراک (`vless`، `vmess`، `trojan`، `ss`، `ssr`، `hy2`، `hysteria`، `wireguard`، `ssh`، `socks`، `dnstt`، `masterdns`، `ping`، `chain` و …) از کلیپ‌بورد، QR، فایل یا URL scheme
- گروه اشتراک و به‌روزرسانی زمان‌بندی‌شده
- اتصال به‌صورت تونل VPN سیستمی یا پروکسی SOCKS/HTTP محلی
- روتینگ با پیش‌تنظیم (جهانی، ایران، روسیه، چین) یا ویرایشگر قانون
- پینگ، انتخاب بهترین سرور، Smart Connect و تست سرعت داخل اپ
- محدودیت per-app، kill switch، FakeDNS، mux، fragment، Clash API، بالانسر Xray
- پشتیبان محلی، بسته قفل‌شده `.v2box`، همگام‌سازی اختیاری iCloud
- ده زبان رابط از جمله فارسی

مسئولیت کانفیگ‌هایی که وارد می‌کنید و رعایت قوانین کشورتان با شماست.

---

## اجرای توسعه

```bash
./dev-macos.sh run          # بیلد دیباگ و باز کردن V2Open-Dev.app
./dev-watch-macos.sh        # ری‌بیلد با هر ذخیره
./build-macos.sh            # باندل انتشار: V2Open.app
```

داده زمان اجرا در `~/Library/Application Support/V2Open/` ذخیره می‌شود.

---

## مشارکت

قبل از پول‌ریکوئست [CONTRIBUTING.fa.md](CONTRIBUTING.fa.md) را بخوانید. خلاصه:

1. از `main` برنچ بزنید (`feature/`، `fix/`، `docs/` و …).
2. داکیومنت، ترجمه‌ها، تست و `CHANGELOG.md` را در همان PR به‌روز کنید.
3. اگر تغییر برای کاربر دیده می‌شود، نسخه را طبق SemVer بالا ببرید.
4. PR را روی `main` باز کنید و چک‌لیست قالب را پر کنید.

ایندکس کامل اسناد: [docs/README.md](docs/README.md)

---

## مجوز

کد منبع V2Open تحت **MIT** است: [LICENSE](LICENSE). هسته‌ها، فونت‌ها و فایل‌های geo مجوز خودشان را دارند: [NOTICE](NOTICE).

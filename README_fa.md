# Etonify

<div dir="rtl" align="center">

[English](README.md) / [Русский](README_ru.md) / [Українська](README_uk.md) / [简体中文](README_cn.md) / [فارسی](README_fa.md)

<img width="1672" height="941" alt="etonify" src="https://github.com/user-attachments/assets/c5a9780c-6b26-45e1-9458-42c23e204dde" />

[![Android](https://img.shields.io/badge/platform-Android-3DDC84?style=flat-square&logo=android)](#)
[![Flutter](https://img.shields.io/badge/built%20with-Flutter-02569B?style=flat-square&logo=flutter)](#)
[![License](https://img.shields.io/badge/license-GPL--3.0--or--later-blue?style=flat-square)](LICENSE)
[![Telegram](https://img.shields.io/badge/Telegram-@etonify-26A5E4?style=flat-square&logo=telegram)](https://t.me/etonify)

**یک کلاینت VPN متن‌باز با تمرکز روی Android و مبتنی بر هسته‌ی تغییر یافته‌ی sing-box.**

</div>

Etonify یک کلاینت VPN با تمرکز روی Android است؛ برای کاربرانی که به جای کلاینت‌های قدیمی یا بسته، به یک گزینه‌ی شفاف، قابل نگهداری و جامعه‌محور نیاز دارند. runtime اندروید، مدیریت subscription، رابط کاربری، تشخیص خطا و روند نگهداری حول Etonify و [**yamixdev/etonify-core**](https://github.com/yamixdev/etonify-core/tree/etonify-dev) توسعه می‌یابد؛ هسته‌ای بر پایه‌ی نسخه‌ی پایدار sing-box با تغییرات مورد نیاز کلاینت.

این برنامه سرور VPN ارائه نمی‌کند. Etonify یک کلاینت برای subscriptionها و configurationهایی است که مالک آن‌ها هستید یا اجازه‌ی استفاده از آن‌ها را دارید.

## وضعیت

Etonify در مرحله‌ی اولیه‌ی توسعه‌ی عمومی است. در حال حاضر Android تنها هدف production است. پوشه‌های سایر پلتفرم‌های Flutter ممکن است در مخزن وجود داشته باشند، اما فعلاً هدف انتشار نیستند.

## قابلیت‌ها

- حالت Android VPN TUN با هسته‌ی تغییر یافته‌ی sing-box.
- local mixed proxy inbound برای اپلیکیشن‌ها یا دستگاه‌هایی که HTTP/SOCKS را دستی تنظیم می‌کنند.
- import subscription از URL، QR code، فایل محلی، clipboard و deep link.
- پشتیبانی از deep linkهای `etonify://`، `happ://add`، `happ://crypt*` و `sing-box://import-remote-profile`.
- Happ link decryptor برای لینک‌های `crypt`، `crypt2`، `crypt3`، `crypt4` و `crypt5`.
- import subscriptionهای Happ با تأیید صریح HWID، اگر provider آن را لازم بداند.
- refresh و reparse subscription، نمایش usage/expire و برخورد امن با پاسخ‌های خراب refresh.
- لیست proxy با پرچم کشورها، latency، ترتیب اصلی subscription، sort بر اساس latency/name/country، URL-test و تغییر سریع سرور.
- Split tunneling با قوانین allow/disallow اپلیکیشن در Android VPN و fallback routing در sing-box.
- DNS preset و DNS resolver سفارشی، شامل UDP، TCP، DoT، DoH و DNS دستگاه.
- Smart Routing و فیلتر DNS محلی AdGuard که داخل برنامه ساخته می‌شود.
- داشبورد ترافیک با سرعت زنده، آمار session، profile فعال، proxy فعال و نمودار سبک.
- مرکز به‌روزرسانی GitHub Releases با انتخاب APK بر اساس معماری دستگاه و نمایش پیشرفت دانلود.
- runtime logs، diagnostics، hooks پاک‌سازی حافظه و redaction برای مقادیر حساس شناخته‌شده.
- لوکالایزیشن RU/EN در خود برنامه؛ ترجمه‌های بیشتر در برنامه‌ی آینده است.

## جامعه

- کانال Telegram: [@etonify](https://t.me/etonify)
- ارتباط مستقیم با توسعه‌دهندگان: [Etonify Direct](https://t.me/etonify?direct)
- MeowTeam: YamixDEV روی کلاینت Android، انتشارها و [etonify-core](https://github.com/yamixdev/etonify-core/tree/etonify-dev) کار می‌کند؛ [dudosxdev](https://github.com/dudosxdev) در بخش شبکه و پروتکل‌ها همکاری می‌کند.
- Issue و Pull Request پذیرفته می‌شود.
- گزارش امنیتی هم پذیرفته می‌شود. لطفاً قبل از بررسی تیم، جزئیات قابل سوءاستفاده را عمومی منتشر نکنید.

## توسعه

نیازمندی‌ها:

- Flutter 3.44.0 یا جدیدتر با Dart `>=3.11.4`.
- Android SDK 36.
- می‌توان از JDK 21 برای اجرای Gradle استفاده کرد، اما برای سازگاری با AGP فعلی، bytecode اندروید همچنان Java 17 است.

دستورهای رایج:

```powershell
flutter pub get
flutter gen-l10n
flutter analyze
flutter test
```

ساخت release APK محلی برای تست روی دستگاه:

```powershell
$env:MEOW_ALLOW_DEBUG_RELEASE_SIGNING='true'
flutter build apk --release
adb install -r build\app\outputs\flutter-apk\app-release.apk
```

برای انتشار عمومی، release keystore واقعی و فایل `android/key.properties` لازم است. این فایل عمداً توسط Git نادیده گرفته می‌شود.

## نکات

- تمرکز production روی Android است.
- تا زمانی که سازگاری API هسته‌ی sing-box جداگانه بررسی نشود، `libbox.aar` بدون تغییر می‌ماند.
- فایل‌های تولیدشده‌ی localization در `lib/l10n/generated` در source tree نگهداری می‌شوند، چون برنامه مستقیماً آن‌ها را import می‌کند.
- `third_party/flutter_circle_flags` به عنوان local path dependency در `pubspec.yaml` لازم است.
- توضیحات مربوط به componentهای شخص ثالث در [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) آمده است.
- buildهای رسمی release می‌توانند private Happ crypto compatibility assets را از GitHub Actions secrets بازیابی و داخل APK قرار دهند. این assets بخشی از source tree عمومی نیستند.

## مجوز

Etonify تحت [GNU General Public License v3.0 یا جدیدتر](LICENSE) منتشر می‌شود. توضیحات componentهای شخص ثالث و اقتباس‌شده در [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) آمده است.

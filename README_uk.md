# Etonify

<div align="center">

[English](README.md) / [Русский](README_ru.md) / [Українська](README_uk.md) / [简体中文](README_cn.md) / [فارسی](README_fa.md)

<img width="1672" height="941" alt="etonify" src="https://github.com/user-attachments/assets/c5a9780c-6b26-45e1-9458-42c23e204dde" />

[![Android](https://img.shields.io/badge/platform-Android-3DDC84?style=flat-square&logo=android)](#)
[![Flutter](https://img.shields.io/badge/built%20with-Flutter-02569B?style=flat-square&logo=flutter)](#)
[![License](https://img.shields.io/badge/license-Apache--2.0-blue?style=flat-square)](LICENSE)
[![Telegram](https://img.shields.io/badge/Telegram-@etonify-26A5E4?style=flat-square&logo=telegram)](https://t.me/etonify)

**Android-first VPN-клієнт з відкритим кодом на базі модифікованого sing-box.**

</div>

Etonify — Android-орієнтований VPN-клієнт для людей, яким потрібна прозора, підтримувана й відкрита альтернатива застарілим або закритим VPN-клієнтам. Проєкт починався в лінії ідей навколо Hiddify, але Android runtime, робота з підписками, інтерфейс, діагностика та супровід поступово перебудовуються навколо Etonify і модифікованого ядра **MeowSingBox**.

Застосунок не надає VPN-сервери. Це клієнт для підписок і конфігурацій, якими ви володієте або маєте право користуватися.

## Статус

Etonify перебуває на ранньому етапі публічної розробки. Наразі production-ціль — лише Android. Інші Flutter-платформи можуть залишатися в репозиторії, але вони поки не є релізними цілями.

## Можливості

- Android VPN TUN на базі модифікованого sing-box.
- Локальний mixed proxy inbound для застосунків або пристроїв, які використовують HTTP/SOCKS вручну.
- Імпорт підписок через URL, QR-код, локальний файл, буфер обміну та deep links.
- Deep link обробники для `etonify://`, `happ://add`, `happ://crypt*`, `sing-box://import-remote-profile`.
- Happ decryptor для посилань `crypt`, `crypt2`, `crypt3`, `crypt4` і `crypt5`.
- Імпорт Happ-підписок з явною згодою на надсилання HWID, якщо провайдер цього вимагає.
- Оновлення, перепарсинг, відображення трафіку/строку дії та безпечна обробка пошкоджених refresh-відповідей.
- Список проксі з прапорами країн, затримкою, вихідним порядком підписки, сортуванням за затримкою/іменем/країною, URL-test і швидким вибором сервера.
- Split tunneling через Android allow/disallow app rules і fallback-маршрутизацію sing-box.
- DNS-пресети та ручне введення DNS resolver, включно з UDP, TCP, DoT, DoH і DNS пристрою.
- Маршрути Росії та локальні правила в стилі AdGuard.
- Панель моніторингу трафіку зі швидкістю, статистикою сесії, активним профілем, активним проксі та легким графіком.
- Центр оновлень GitHub Releases з підбором APK під архітектуру пристрою та прогресом завантаження.
- Runtime-логи, діагностика, hooks для очищення пам'яті та маскування відомих чутливих значень.
- RU/EN локалізація застосунку; розширення перекладів планується.

## Спільнота

- Telegram-канал: [@etonify](https://t.me/etonify)
- Issues і pull requests вітаються.
- Повідомлення про вразливості вітаються. Будь ласка, не публікуйте експлуатаційні деталі відкрито до того, як команда матиме час розібратися.

## Розробка

Вимоги:

- Flutter 3.44.0 або новіший з Dart `>=3.11.4`.
- Android SDK 36.
- JDK 21 можна використовувати для запуску Gradle, але Android bytecode залишається Java 17 для сумісності з поточним AGP.

Основні команди:

```powershell
flutter pub get
flutter gen-l10n
flutter analyze
flutter test
```

Локальна release APK для тесту на пристрої:

```powershell
$env:MEOW_ALLOW_DEBUG_RELEASE_SIGNING='true'
flutter build apk --release
adb install -r build\app\outputs\flutter-apk\app-release.apk
```

Для публічного поширення потрібен справжній release keystore і `android/key.properties`. Цей файл навмисно ігнорується Git.

## Примітки

- Production-фокус — Android.
- `libbox.aar` залишається як є, доки сумісність sing-box API не перевіряється окремо.
- Згенеровані файли локалізації в `lib/l10n/generated` зберігаються в репозиторії, тому що застосунок імпортує їх напряму.
- `third_party/flutter_circle_flags` потрібен як local path dependency з `pubspec.yaml`.
- Нотатки щодо сторонніх компонентів і походження проєкту наведені в [NOTICE.md](NOTICE.md).
- Офіційні release-збірки можуть містити приватні Happ crypto compatibility assets, відновлені з GitHub Actions secrets. Ці assets не входять до публічного дерева вихідного коду.

## Ліцензія

Etonify поширюється за ліцензією [Apache License 2.0](LICENSE).

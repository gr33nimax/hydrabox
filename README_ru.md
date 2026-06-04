# Etonify

<div align="center">

[English](README.md) / [Русский](README_ru.md) / [Українська](README_uk.md) / [简体中文](README_cn.md) / [فارسی](README_fa.md)

<img width="1672" height="941" alt="etonify" src="https://github.com/user-attachments/assets/c5a9780c-6b26-45e1-9458-42c23e204dde" />

[![Android](https://img.shields.io/badge/platform-Android-3DDC84?style=flat-square&logo=android)](#)
[![Flutter](https://img.shields.io/badge/built%20with-Flutter-02569B?style=flat-square&logo=flutter)](#)
[![License](https://img.shields.io/badge/license-Apache--2.0-blue?style=flat-square)](LICENSE)
[![Telegram](https://img.shields.io/badge/Telegram-@etonify-26A5E4?style=flat-square&logo=telegram)](https://t.me/etonify)

**Android-first VPN-клиент с открытым исходным кодом на базе модифицированного sing-box.**

</div>

Etonify — Android-ориентированный VPN-клиент для людей, которым нужен прозрачный, поддерживаемый и открытый клиент вместо устаревших или закрытых решений. Проект начинался в ветке идей вокруг Hiddify, но Android runtime, работа с подписками, интерфейс, диагностика и сопровождение постепенно перестраиваются вокруг Etonify и модифицированного ядра **MeowSingBox**.

Приложение не предоставляет VPN-серверы. Это клиент для подписок и конфигураций, которыми вы владеете или которые имеете право использовать.

## Статус

Etonify находится в ранней публичной разработке. Сейчас production-цель только Android. Другие Flutter-платформы могут оставаться в репозитории, но они пока не являются релизными целями.

## Возможности

- Android VPN TUN на базе модифицированного sing-box.
- Локальный mixed proxy inbound для приложений или устройств, которые используют HTTP/SOCKS вручную.
- Импорт подписок по URL, QR-коду, локальному файлу, буферу обмена и deep links.
- Deep link обработчики для `etonify://`, `happ://add`, `happ://crypt*`, `sing-box://import-remote-profile`.
- Happ decryptor для ссылок `crypt`, `crypt2`, `crypt3`, `crypt4` и `crypt5`.
- Импорт Happ-подписок с явным согласием на отправку HWID, если провайдер этого требует.
- Обновление, перепарсинг, отображение трафика/срока действия и безопасная обработка битых refresh-ответов.
- Список прокси с флагами стран, задержкой, исходным порядком подписки, сортировкой по задержке/имени/стране, URL-test и быстрым выбором сервера.
- Split tunneling через Android allow/disallow app rules и fallback-маршрутизацию sing-box.
- DNS-пресеты и ручной ввод DNS resolver, включая UDP, TCP, DoT, DoH и DNS устройства.
- Маршруты России и локальные правила в стиле AdGuard.
- Панель мониторинга трафика со скоростью, статистикой сессии, активным профилем, активным прокси и лёгким графиком.
- Центр обновлений GitHub Releases с подбором APK под архитектуру устройства и прогрессом скачивания.
- Runtime-логи, диагностика, hooks для очистки памяти и маскирование известных чувствительных значений.
- RU/EN локализация приложения, расширение пользовательских переводов в планах.

## Сообщество

- Telegram-канал: [@etonify](https://t.me/etonify)
- Issues и pull requests приветствуются.
- Сообщения об уязвимостях приветствуются. Пожалуйста, не публикуйте эксплуатационные детали публично до того, как команда успеет разобраться.

## Разработка

Требования:

- Flutter 3.44.0 или новее с Dart `>=3.11.4`.
- Android SDK 36.
- JDK 21 можно использовать для запуска Gradle, при этом Android bytecode остаётся Java 17 для совместимости с текущим AGP.

Основные команды:

```powershell
flutter pub get
flutter gen-l10n
flutter analyze
flutter test
```

Локальная release APK для теста на устройстве:

```powershell
$env:MEOW_ALLOW_DEBUG_RELEASE_SIGNING='true'
flutter build apk --release
adb install -r build\app\outputs\flutter-apk\app-release.apk
```

Для публичной раздачи нужен настоящий release keystore и `android/key.properties`. Этот файл специально игнорируется Git.

## Заметки

- Production-фокус — Android.
- `libbox.aar` остаётся как есть, пока совместимость sing-box API не проверяется отдельно.
- Сгенерированные файлы локализации в `lib/l10n/generated` хранятся в исходниках, потому что приложение импортирует их напрямую.
- `third_party/flutter_circle_flags` нужен как local path dependency из `pubspec.yaml`.
- Заметки по сторонним компонентам и происхождению проекта указаны в [NOTICE.md](NOTICE.md).
- Официальные release-сборки могут включать приватные Happ crypto compatibility assets, восстановленные из GitHub Actions secrets. Эти assets не входят в публичное дерево исходников.

## Лицензия

Etonify распространяется под [Apache License 2.0](LICENSE).

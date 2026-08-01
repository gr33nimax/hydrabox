# HydraBox

<div align="center">

[English](README.md) / [Русский](README_ru.md) / [Українська](README_uk.md) / [简体中文](README_cn.md) / [فارسی](README_fa.md)

<img width="1672" height="941" alt="Интерфейс HydraBox, унаследованный от проекта Etonify" src="https://github.com/user-attachments/assets/c5a9780c-6b26-45e1-9458-42c23e204dde" />

[![Проверки клиента](https://github.com/gr33nimax/hydrabox/actions/workflows/ci.yml/badge.svg?branch=extended-core)](https://github.com/gr33nimax/hydrabox/actions/workflows/ci.yml)
[![Android](https://img.shields.io/badge/platform-Android-3DDC84?style=flat-square&logo=android)](#)
[![Flutter](https://img.shields.io/badge/built%20with-Flutter-02569B?style=flat-square&logo=flutter)](#)
[![License](https://img.shields.io/badge/license-GPL--3.0--or--later-blue?style=flat-square)](LICENSE)

**Subscription-first Android-клиент для self-hosted VPN-экосистемы Hydra.**

</div>

> [!IMPORTANT]
> HydraBox — независимый неофициальный проект на основе
> [Etonify](https://github.com/yamixdev/Etonify). Проект не заявляет авторство
> или права на исходную работу и не является официальным релизом Etonify или
> MeowTeam. Точные исходные ревизии и сохранённые идентификаторы перечислены в
> [UPSTREAM.md](UPSTREAM.md).

HydraBox — официальный клиент self-hosted экосистемы Hydra. Его основной
контракт — [HydraBox Subscription v1](docs/hydrabox-subscription-v1.md), которую
создаёт [HYDRA Ultimate](https://github.com/gr33nimax/HYDRA-ULTIMATE), а исполняет
[HydraCore](https://github.com/gr33nimax/hydracore). Полные нативные
JSON-конфигурации сохраняются без потерь, поэтому новые протоколы и поля ядра
не требуют одновременного изменения Flutter-схемы.

Ручной и legacy-импорт остаются для миграции и совместимости. Это не второе
направление продукта: экосистема Hydra строится вокруг одной зашифрованной
подписки от собственного сервера до клиента.

Приложение не предоставляет VPN-серверы. Это клиент для подписок и конфигураций, которыми вы владеете или которые имеете право использовать.

## Статус

HydraBox находится в публичной beta-стадии. Поддерживаемая production-цель —
Android. Другие Flutter-платформы могут оставаться в репозитории, но пока не
являются релизными целями.

## Экосистема Hydra

```text
HYDRA Ultimate  ->  зашифрованная подписка  ->  HydraBox  ->  HydraCore
self-hosted сервер                              клиент        ядро
```

- [HYDRA Ultimate](https://github.com/gr33nimax/HYDRA-ULTIMATE) разворачивает
  и управляет собственным сервером и формирует подписку.
- HydraBox импортирует, хранит, обновляет и активирует подписку.
- [HydraCore](https://github.com/gr33nimax/hydracore) проверяет и исполняет
  нативную сетевую конфигурацию.

Hydra не является VPN-провайдером: сервер и подписка принадлежат пользователю.

## Быстрый старт

1. Разверните HYDRA Ultimate на своём сервере.
2. Скопируйте зашифрованную ссылку подписки HydraBox или её QR-код.
3. Установите HydraBox из [GitHub Releases](https://github.com/gr33nimax/hydrabox/releases).
4. Импортируйте подписку в HydraBox и подключитесь.

Ключ расшифрования находится только во fragment URL и не отправляется серверу
подписки. Точная модель доверия описана в
[спецификации Subscription v1](docs/hydrabox-subscription-v1.md).

## Возможности

- Android VPN TUN на базе HydraCore.
- Версионированная подписка HydraBox v1: явные профили, единый нативный
  runtime-документ, сохранение полей будущих протоколов и JWE A256GCM.
- Локальный mixed proxy inbound для приложений или устройств, которые используют HTTP/SOCKS вручную.
- Импорт подписок по URL, QR-коду, локальному файлу, буферу обмена и deep links.
- Deep link обработчики для `hydrabox://`, совместимых старых схем
  `etonify://` и `meowvpn://`, а также `happ://add`, `happ://crypt*` и
  `sing-box://import-remote-profile`.
- Happ decryptor для ссылок `crypt`, `crypt2`, `crypt3`, `crypt4` и `crypt5`.
- Импорт Happ-подписок с явным согласием на отправку HWID, если провайдер этого требует.
- Обновление, перепарсинг, отображение трафика/срока действия и безопасная обработка битых refresh-ответов.
- Список прокси с флагами стран, задержкой, исходным порядком подписки, сортировкой по задержке/имени/стране, URL-test и быстрым выбором сервера.
- Split tunneling через Android allow/disallow app rules и fallback-маршрутизацию sing-box.
- DNS-пресеты и ручной ввод DNS resolver, включая UDP, TCP, DoT, DoH и DNS устройства.
- Умная маршрутизация и локально собранный DNS-фильтр AdGuard.
- Панель мониторинга трафика со скоростью, статистикой сессии, активным профилем, активным прокси и лёгким графиком.
- Опциональный центр обновлений GitHub Releases с подбором APK под архитектуру
  устройства и прогрессом скачивания; он отключён, пока распространитель не
  настроит источник релизов HydraBox.
- Runtime-логи, диагностика, hooks для очистки памяти и маскирование известных чувствительных значений.
- RU/EN локализация приложения, расширение пользовательских переводов в планах.

## Исходный проект и сообщество

- Исходный проект: [`yamixdev/Etonify`](https://github.com/yamixdev/Etonify).
- Канал и контакт разработчиков Etonify:
  [@etonify](https://t.me/etonify) и
  [Etonify Direct](https://t.me/etonify?direct).
- Атрибуция Etonify/MeowTeam: YamixDEV занимается исходным Android-клиентом,
  релизами и
  [etonify-core](https://github.com/yamixdev/etonify-core/tree/etonify-dev);
  [dudosxdev](https://github.com/dudosxdev) помогает с сетевой частью и
  протоколами.
- Issues и pull requests приветствуются.
- Сообщения об уязвимостях приветствуются. Пожалуйста, не публикуйте эксплуатационные детали публично до того, как команда успеет разобраться.

## Разработка

Требования:

- Flutter 3.44.0 или новее с Dart `>=3.11.4`.
- Android SDK 36.
- JDK 21 можно использовать для запуска Gradle, при этом Android bytecode остаётся Java 17 для совместимости с текущим AGP.

Основные команды:

```powershell
python -B scripts/fetch_libbox.py
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
- HydraCore пока сохраняет техническое имя артефакта `libbox.aar` и путь
  подмодуля `etonify-core`; точная версия и SHA-256 записаны в
  `android/app/libs`.
- Идентификаторы `com.etonify.meow_client`, `meow_client`, старые deep links и
  форматы резервных копий намеренно оставлены для совместимости Keystore,
  пользовательских данных и разрешённой миграции. Одного Android ID недостаточно,
  чтобы APK с другой подписью заменил Etonify. Подробнее: [UPSTREAM.md](UPSTREAM.md).
- Сгенерированные файлы локализации в `lib/l10n/generated` хранятся в исходниках, потому что приложение импортирует их напрямую.
- `third_party/flutter_circle_flags` нужен как local path dependency из `pubspec.yaml`.
- Заметки по сторонним компонентам указаны в [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
- В репозитории может находиться унаследованный зашифрованный архив совместимости
  Happ. Не восстанавливайте и не распространяйте его содержимое без проверки
  прав на распространение; см. [NOTICE.md](NOTICE.md).

## Лицензия

HydraBox и унаследованный код Etonify распространяются под
[GNU General Public License v3.0 или новее](LICENSE). Происхождение и
атрибуция описаны в [NOTICE.md](NOTICE.md), [UPSTREAM.md](UPSTREAM.md) и
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

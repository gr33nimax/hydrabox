# HydraBox

<div align="center">

[English](README.md) / [Русский](README_ru.md)

<img width="220" alt="Логотип HydraBox" src="assets/branding/hydrabox-logo.png" />

<img width="1672" height="941" alt="Интерфейс HydraBox" src="https://github.com/user-attachments/assets/c5a9780c-6b26-45e1-9458-42c23e204dde" />

[![Проверки клиента](https://github.com/gr33nimax/hydrabox/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/gr33nimax/hydrabox/actions/workflows/ci.yml)
[![Android](https://img.shields.io/badge/platform-Android-3DDC84?style=flat-square&logo=android)](#)
[![Flutter](https://img.shields.io/badge/built%20with-Flutter-02569B?style=flat-square&logo=flutter)](#)
[![License](https://img.shields.io/badge/license-GPL--3.0--or--later-blue?style=flat-square)](LICENSE)

**Subscription-first Android-клиент для self-hosted VPN-стека Hydra.**

</div>

HydraBox импортирует, обновляет, хранит и активирует единую зашифрованную
подписку с сервера пользователя. [HYDRA Ultimate](https://github.com/gr33nimax/HYDRA-ULTIMATE)
создаёт подписку, а [HydraCore](https://github.com/gr33nimax/hydracore)
проверяет и исполняет её нативную сетевую конфигурацию.

```text
HYDRA Ultimate  ->  зашифрованная подписка  ->  HydraBox  ->  HydraCore
self-hosted сервер                                клиент        runtime
```

Hydra не является VPN-провайдером. HydraBox не продаёт и не выдаёт серверы:
сервер и подписка принадлежат пользователю.

## Статус

HydraBox находится в публичной beta-стадии. Поддерживаемая production-цель —
Android. Каталоги других Flutter-платформ остаются в исходниках, но пока не
являются релизным обещанием.

## Возможности

- Android VPN TUN на базе HydraCore.
- HydraBox Subscription v1 с JWE A256GCM и сохранением нативного runtime-
  документа без потерь.
- Fail-closed проверка capabilities и remote-safety policy до активации.
- Импорт подписки по URL, QR-коду, файлу, буферу обмена и deep link.
- Локальный HTTP/SOCKS mixed proxy для ручных клиентов.
- Split tunnelling, DNS/маршрутизация, проверка задержки серверов, updater и
  диагностика с маскированием секретов.
- Ручной и legacy-импорт для миграции и совместимости; продуктовый контракт
  Hydra остаётся зашифрованной подпиской.

## Быстрый старт

1. Разверните HYDRA Ultimate на своём сервере.
2. Скопируйте URL или QR-код зашифрованной подписки HydraBox.
3. Установите HydraBox из [GitHub Releases](https://github.com/gr33nimax/hydrabox/releases).
4. Импортируйте подписку и подключитесь.

Ключ расшифрования находится только во fragment URL и не отправляется серверу
подписки. Точная схема, граница доверия, правила проверки и test vectors
описаны в [HydraBox Subscription v1](docs/hydrabox-subscription-v1.md).

## Модель безопасности

HydraBox считает любую удалённую подписку недоверенным вводом. Для активации
нужны аутентифицированное JWE-расшифрование, проверка схемы, точное совпадение с
policy manifest установленного HydraCore, удаление полей локальных полномочий,
замкнутый граф ссылок и нативная проверка конфига. Неизвестные будущие поля
можно сохранить, но нельзя исполнять только потому, что они присутствуют в JSON.

Уязвимости сообщаются по [SECURITY.md](SECURITY.md). Не прикладывайте к
публичным issues рабочие подписки, ключи, пароли, идентификаторы устройств и
приватные адреса серверов.

## Разработка

Авторитетная среда сборки и проверки — GitHub Actions. Она проверяет
закреплённый HydraCore и provenance, Flutter analyze/tests, Android
unit/lint/assembly gates и CodeQL. Изменения направляются в `main`; подробности
в [CONTRIBUTING.md](CONTRIBUTING.md) и
[GitHub Actions](docs/github-actions.md).

## Авторы, происхождение и лицензия

HydraBox сохраняет полную историю исходников, corresponding source, copyright
notices и лицензии проектов, из которых он развился. Точное происхождение и
сохранённые идентификаторы совместимости вынесены из продуктовой страницы в
[CREDITS.md](CREDITS.md), [NOTICE.md](NOTICE.md) и
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md). Лицензия проекта —
[GPL-3.0-or-later](LICENSE).

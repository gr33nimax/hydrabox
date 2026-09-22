# Tasks: связность VK parasite и UX-дефекты

**Status:** In progress
**Bugfix:** `bugfix.md`
**Date:** 2026-09-16

## Progress

| Task | Status | Evidence |
| --- | --- | --- |
| TSK-B01 — Уведомление исчезает навсегда | ✅ Код готов | компиляция — только в CI (verifyLibboxProvenance) |
| TSK-B02 — Растянутая иконка в шторке | ✅ Артворк исправлен | измерено: поля ~19% против 16.7%; XML 108dp |
| TSK-B03 — Полоса устаревания в списке серверов | ✅ Готово | `:ui:app` + `:ui:design` — BUILD SUCCESSFUL |
| TSK-B04 — ANR при обновлении подписки | ⛔ Снят владельцем | не нужен: 2026-09-17 |
| TSK-B05 — B1: отвал на VK parasite | ✅ Готово | 7/7 тестов супервизора PASS |
| TSK-B06 — B2: ping в белых списках | ✅ Разобран | ICMP-гипотеза опровергнута |

## Tasks

- [ ] **TSK-B01 — Вернуть уведомление после смахивания**
  - **Requirement:** B4
  - **Deliverables:** `setDeleteIntent` на action сервиса (`HydraVpnService.kt`); в `onStartCommand` повторный `startForeground()` при активном рантайме и включённой настройке; при пустом рантайме — `stopSelfResult`, а не вечное существование ради свайпа.
  - **Evidence:** Android 14 разрешает смахивать `setOngoing`; в коде не было ни `deleteIntent`, ни receiver; `statusNotificationEnabled` пишется только из настроек (`RuntimeControlActivity.kt:874-892`), читается сервисом как `liveTraffic` (`HydraVpnService.kt:875`).
  - **Acceptance:** после смахивания уведомление возвращается; `adb shell dumpsys notification --noredact` показывает `hydrabox-vpn` активным.
  - **Факт:** не проверено компиляцией локально — `:platform:android` требует гидрированный libbox AAR (`verifyLibboxProvenance`). Проверка — в CI по решению владельца.

- [ ] **TSK-B02 — Иконка в шторке**
  - **Requirement:** B5
  - **Deliverables:** перерисовать `hydrabox_launcher_foreground.png` и `hydrabox_launcher_monochrome.png` с полем ≥16.7% с каждой стороны; в `ic_launcher_foreground.xml` убрать item 50dp и `gravity="fill"` в пользу 108dp-слоя.
  - **Evidence:** измерено — логотип 529×526 при 640×640, отступы 6.1–11.7% против требуемых 16.7%; статусбар чист, потому что там small icon.
  - **Acceptance:** иконка в шторке без искажений на устройстве.

- [ ] **TSK-B03 — Полоса устаревания списка**
  - **Requirement:** B3
  - **Deliverables:** в `ServersScreen.kt:81-83` переформулировать как устаревание («Список от «X» не обновлялся»), добавить смахивание.
  - **Evidence:** `problemOf` (`AppStore.kt:695-740`) + `rememberFailure` (сброс только успехом, `:310,417,446`).
  - **Acceptance:** полоса отражает устаревание, убирается жестом, возвращается после успешного обновления.

- [x] **TSK-B04 — ANR при обновлении подписки (снят)**
  - **Requirement:** B1
  - **Result:** снят по решению владельца — не нужен. Исследование уже дало что могло: блокирующий вызов главного потока в пути обновления не найден, строка «не отвечает» принадлежит другому состоянию (`Trouble.SERVER_UNREACHABLE`), а не обновлению подписки. Различие системного ANR от busy-состояния требует устройства и остаётся непроверенным.

- [x] **TSK-B05 — Отвал на VK parasite**
  - **Requirement:** B1
  - **Deliverables:** в ядре `supervisor.go Client.healthSnapshot` отдавать `Recovering`, когда линии уже поднимались и потеряны, а отказ ретраябельный; `FAILED` — для терминальных и для отказа до первого поднятия линии.
  - **Evidence:** доказано кодом — `supervisor.go:196-206` (ветка `Recovering` была недостижима), `CoreObserver.kt:636`, `RuntimeReducer.kt:423-430`.
  - **Факт:** `go test -tags with_call_client ./transport/call/vk-parasite/ -run TestHealthSnapshot` — 7/7 PASS, включая новый `TestHealthSnapshotKeepsRecoveringAfterLanesWereUp` и оба намеренных теста на быстрый отказ при старте (их не менял).
  - **Граница:** причина установлена кодом; подтверждение, что именно это давало отвал на устройстве, требует журнала (`transport recovering` вместо `failed`).
  - **Уточнение к предложению агента:** его версия («только терминальные — Failed») ломала бы намеренный fail-fast на старте (`RuntimeReducer.kt:419-422`). Ключ — `sawPath`, а не только `Terminal`.

- [x] **TSK-B06 — B2: ping в белых списках**
  - **Requirement:** B2
  - **Evidence:** правило ICMP узкое (`TunnelConfig.kt:617-621`, адрес `172.19.0.2/32` при TUN `172.19.0.1/30`), публичный VK не матчится; «ping» продукта — STUN до TURN-edge (`TurnEdgeProbe.kt:10-18,115-165`); ICMP через `call` не поддержан (`hydracore/protocol/call/outbound.go:78`).
  - **Result:** правило-глушилку не трогаем. Причина «нет ping» — не наши правила.

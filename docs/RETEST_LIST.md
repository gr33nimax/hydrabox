# Сценарии к перепрогону

Проверки, признанные VACUOUS или частичными на момент прогона: код формально проходит,
но доказано отсутствие издателя, а не отсутствие дефекта. Каждая строка обязана быть
повторена после указанной задачи. Пункт закрывается только содержательным прогоном.

| Сценарий | Проверка | Почему VACUOUS сейчас | Перепрогон после |
|---|---|---|---|
| M06 / B3a | отзыв согласия VPN у работающего runtime вызывает `STOP stage=revoked` и не даёт автовосстановления | у adb нет триггера `VpnService.onRevoke()`; `appops ACTIVATE_VPN deny` проверяет только запрет до старта | ручной отзыв в системных настройках владельцем либо другой VPN-клиент |
| B5 | `START_STICKY` после смерти :core без UI даёт `CONNECT source=sticky`, attempt ≤2 | после смахивания карточки главный процесс остаётся жив из-за bind к `CoreRuntimeService`; recovery выигрывает гонку | устройство/окружение, где смахивание завершает главный процесс |
| M20 | старт и стоп из Quick Settings tile дают `CONNECT source=tile` | tile HydraBox не добавлен в Quick Settings; `click-tile` не вызвал события | добавить tile вручную на устройстве |

## Закрыто

- **M03** — «нет `runtime.stop.unconfirmed`»: закрыт по итогам `HB-RW-032-FIX-2` (DEVICE-2).
  Содержательный прогон: издатель теперь есть (`CoreRuntimeService.handleControllerEvent`
  обрабатывает `runtime.stop.unconfirmed`, `android/app/src/main/kotlin/io/hydrabox/client/runtime/CoreRuntimeService.kt:1838`).
  Во всех стоп-циклах сессии (A1, прогоны a1/a1b/a1c, ~40 остановок) — 0 вхождений строки.

- **M07** — Wi-Fi → cellular трижды: закрыт по итогам DEVICE-2.
  Новая базовая линия: 6 `NETWORK branch=changed` и 6 соответствующих `REBIND`; дополнительные callbacks были только `branch=noop`.

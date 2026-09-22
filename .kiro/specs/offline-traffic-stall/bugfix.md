# Bugfix: оффлайн-проба вешает трафик при живом VPN

**Date:** 2026-09-21
**Repo:** HydraBox2 (симптом) + возможно HydraCore (VK parasite / QUIC relay)
**Status:** spec, код не менялся — root cause не подтверждён устройством
**Phase:** Bugfix-spec (фаза 1 — ждёт одобрения)

## Важное уточнение владельца (2026-09-21)

Мёртвый по трафику туннель ловился **и на обычных конфигах**, не только на VK parasite —
пока приложение не остановишь руками. Это **смещает диагноз**: причина не может
быть только в VK-lane/TURN (этого нет на обычном vless/trojan). Значит корень — в
транспорт-независимом слое: путь rebind / генерация сети / underlying network /
монитор, общий для всех протоколов. VK-сценарий (H2) — частный усилитель, а не
вся картина.

## Current behavior

Пинг/проба достижимости или попытка подключения, случившаяся когда сети нет (оффлайн),
по какой-то причине способна повесить получение трафика: туннель остаётся в статусе
RUNNING (VPN жив, не отвалился), но данные через него не идут, пока не перезапустить
вручную.

Со слов владельца: «если произошёл пинг или подключение в оффлайне, то по какой-то
причине это вообще может повесить получение трафика». Симптом плавающий.

## Expected behavior

- WHEN проба/подключение запускается в оффлайне и сеть затем появляется THEN туннель
  SHALL продолжить (или восстановить) перенос трафика без ручного перезапуска.
- WHEN идёт оффлайн-замер и одновременно происходит реальная смена сети (handover) THEN
  ядро SHALL корректно ребиндиться на новую сеть, а не остаться на исчезнувшем интерфейсе.
- WHEN трафик перестал идти при живом VPN THEN причина SHALL попадать в журнал (какой
  путь встал: rebind, VK paths, TURN credentials).

## Unchanged behavior

- Изоляция оффлайн-прохода (`OfflineSweep`, ADR 0017, 0021) не меняется: провал одной цели
  не отменяет остальные.
- Порядок rebind (сначала generation в ядре, потом publish интерфейса) — намеренный,
  переписывать без причины нельзя.
- Отмена прохода при реальном handover (результаты с другой сети несравнимы) остаётся.
- Выбор маршрута, поведение остальных протоколов и настройки не меняются.

## Подозреваемые места (доказано кодом, до устройства)

### H1 — гонка `awaitingMeasurementBaseline` съедает реальный handover

- `HydraVpnService.kt:406-408`: `monitor.onChanged` при `awaitingMeasurementBaseline ==
  true` **не** зовёт `cancelSweep`, только `compareAndSet(true,false)`, и всё равно шлёт
  `NetworkChanged`.
- `measureNow` в оффлайне (`:444-445`) ставит `awaitingMeasurementBaseline =
  (currentNetwork == null)`. Замысел: первый network-callback после создания сервиса —
  это baseline, не handover.
- **Риск:** если во время оффлайн-замера приходит первый callback, он трактуется как
  baseline и «съедается», хотя это могло быть реальное появление сети, требующее полного
  rebind живого туннеля. Флаг один на сервис — если состояний больше одного, baseline и
  настоящий handover неразличимы.

### H2 — rebind при generation=0 сносит все VK lane (осн. гипотеза владельца)

- `HydraVpnService.kt:1191-1207` (комментарий в `rebind`): при generation `0` `QUICRelay.
  RebindNetwork` пропускает свою дедупликацию, рвёт все lane на каждом уведомлении, VK
  после нескольких handover перестаёт выдавать TURN credentials (`incomplete_credentials`),
  и parasite-outbound остаётся без путей — **«a tunnel that worked and then quietly stopped
  carrying traffic»**. Это дословно симптом.
- Оффлайн→онлайн переход — это как раз серия быстрых callback'ов
  (`onCapabilitiesChanged` + `onLinkPropertiesChanged` всегда парой, см.
  `DefaultNetworkMonitor.refresh` комментарий), то есть несколько rebind подряд.

### H3 — рассинхрон generation между монитором и ядром

- `DefaultNetworkMonitor.refresh` (`:170-190`) поднимает generation и зовёт `onChanged`,
  затем `NetworkChanged` идёт в reducer (`RuntimeReducer.kt:305-311`): RUNNING →
  `RebindNetwork`. Если `awaitingMeasurementBaseline` съел один переход (H1), reducer может
  не получить `NetworkChanged` для перехода, который ядро уже увидело — generation
  разъезжается.

## Что уже сделано рядом (не путать)

- `hb-ping-truth`: подвес lifecycle-потока на длинном оффлайн-проходе (минуты) — **закрыто**
  (`OfflineSweep.withinDeadline`, дедлайн замера). Это про «поток занят», не про «трафик
  встал при живом VPN». Другой дефект.
- `client-connectivity-ux-bugs` B1: отвал VK parasite в `FAILED`/`RECOVERING` — **закрыто**
  в супервизоре ядра. Пересекается по VK, но там туннель отваливается, а здесь остаётся
  RUNNING без трафика. Проверить, не тот же ли корень.

### H4 — транспорт-независимый залип underlying network / интерфейса (новая, основная)

- Баг на **обычных** конфигах исключает VK/TURN как единственный корень. Общий для
  всех протоколов путь: `rebind()` зовёт `setUnderlyingNetworks(network?)` и
  `monitor.publishCurrent()` (`HydraVpnService.kt:1195-1207`).
- **Риск:** если в момент rebind `monitor.currentNetwork == null` (оффлайн ещё не сменился
  на живую сеть, либо baseline-флаг съел переход), туннель может остаться привязан
  к исчезнувшему интерфейсу (`setUnderlyingNetworks(null)` или старый), а `publish` не
  отдаёт новый — ядро копает через мёртвый интерфейс. Это валит любой протокол,
  не только VK.
- Совпадает с комментарием `DefaultNetworkMonitor` (`:36-44`): *«tunnel that stops carrying
  traffic after a walk out of Wi-Fi range»* — это про все протоколы, не про VK.

## Root cause

Не установлен. После уточнения владельца (баг и на обычных конфигах) основная гипотеза
смещена на **H4** (транспорт-независимый залип underlying network/интерфейса при rebind),
усиленную H1 (baseline-флаг съедает переход). H2 (VK-lane) остаётся частным
усилителем для VK-конфигов. Требуется воспроизведение на устройстве с журналом:
последовательность `generation N`, вызовы `rebind`, значение `currentNetwork`/underlying в
момент остановки трафика — на обычном конфиге (vless/trojan), где VK не участвует.

## Fix plan (черновик, ждёт фазы Design)

1. **Диагностика первой (обязательно):** воспроизвести на устройстве на **обычном** конфиге
   (vless/trojan) — airplane mode ON → «Измерить»/подключение → airplane mode OFF, снять
   журнал `network`. Подтвердить H4/H1/H3, прежде чем трогать код.
2. **H4:** гарантировать, что rebind не привязывает туннель к мёртвому интерфейсу при
   `currentNetwork == null`; проверить порядок `setUnderlyingNetworks` / `publishCurrent` на
   обычном протоколе.
3. **H1:** различить «baseline после старта» и «реальный handover во время замера» — не
   одним булевым флагом, а сопоставлением generation, под которой стартовал замер.
4. **H2 (только если VK-конфиг):** rebind живого туннеля всегда с ненулевой generation.
5. **Регрессия:** тест на reducer/сервис — переход оффлайн→онлайн во время измерения
   даёт ровно один rebind с корректной generation и живым underlying network, а не
   съеденный переход или привязку к мёртвому интерфейсу.

## Acceptance

- Воспроизводимый сценарий с зафиксированной в журнале причиной остановки трафика.
- После фикса: airplane OFF→ON→OFF с пробой/подключением в оффлайне — трафик
  восстанавливается сам, без ручного рестарта, серия из N повторов без залипания.
- Регрессионный тест на гонку baseline/handover проходит.
- `OfflineSweep`-изоляция и порядок rebind не нарушены (существующие тесты зелёные).

## Evidence

- `D:/dev/HydraBox2/platform/android/.../HydraVpnService.kt:406-408` — onChanged и baseline.
- `…/HydraVpnService.kt:444-445,454-455` — установка/снятие `awaitingMeasurementBaseline`.
- `…/HydraVpnService.kt:1150-1207` — `PublishNetwork`/`RebindNetwork`/`rebind`, комментарий
  про generation=0 и «quietly stopped carrying traffic».
- `…/DefaultNetworkMonitor.kt:36-44,170-190` — «tunnel that stops carrying traffic after a
  walk out of Wi-Fi range», парность callback'ов, generation.
- `D:/dev/HydraBox2/core/runtime/.../RuntimeReducer.kt:305-311` — reducer NetworkChanged →
  RebindNetwork в RUNNING.

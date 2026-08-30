# Task ledger

Машиночитаемый журнал исполнения плана. Единственный источник ответа на вопрос
«выполнен ли предшественник». Строку добавляет сам агент — последним шагом задачи,
после коммита.

Формат: `<TASK ID> | <repo> | <commit> | <RESULT>`

`repo`: `hydrabox` = `D:\dev\HydraBox\hydrabox`, `hydracore` = `D:\dev\hydracore\hydracore`.
`RESULT`: `DONE` либо `BLOCKED(<что ждёт>)`.

| TASK ID | REPO | COMMIT | RESULT |
|---|---|---|---|
| HB-RW-001 | hydrabox | ce91815 | DONE |
| HB-RW-002 | hydrabox | f83ffeb | DONE |
| HB-RW-040 | hydrabox | 38d4f83 | DONE |
| HB-RW-041+042 | hydrabox | 2f49ba5 | DONE (карточки слиты решением тимлида, C17) |
| HB-RW-003 | hydrabox | 305c139 | DONE (+ 97caf72 фикс фейка config coordinator) |
| HB-RW-004 | hydrabox | 491eacf | DONE |
| HB-RW-006 | hydrabox | 3832fab | DONE |
| HC-RW-001 | hydracore | 2951d7d3 | DONE (ветка debug; дубль df03fa02 в submodule отброшен) |
| HC-RW-002 | hydracore | 6b0b122d | DONE |
| HC-RW-003 | hydracore | 34da49ed | DONE |
| HC-RW-004 | hydracore | be30c53c | DONE (включает HC-RW-006) |
| HC-RW-005 | hydracore | 2e868e16 | DONE |
| HB-BUNDLE-001 | hydrabox | 4c00f16 | DONE |
| HB-RW-023 | hydrabox | 2e2706f | DONE |
| HB-RW-019 | hydrabox | 267f320 | DONE |
| HB-RW-016 | hydrabox | df78787 | DONE (+ одна строка в MainActivity по решению тимлида) |
| HB-RW-012 | hydrabox | 7df8463 | DONE |
| HB-RW-005 | hydrabox | 83f9f95 | DONE (P1: network_wait входит в 45 s; E1=P2 diagnostic CommandClient non-blocking) |
| HB-RW-015 | hydrabox | 6b80169 | DONE |
| HB-RW-015-FIX | hydrabox | — | DONE |
| HB-RW-014 | hydrabox | d3339ae | DONE |
| HB-RW-013 | hydrabox | c3b3922 | DONE (_queuedRestartSuppressed оставлен — дефект плана, см. §8.3) |
| HB-RW-002-FIX | hydrabox | b663a02 | DONE |
| HB-RW-001-FIX | hydrabox | 7082e08 | DONE |
| HB-EXP-E2B | hydrabox | — | DONE (P2) |
| E2B-BUILD-FIX | hydrabox | c74030b | DONE (+9e2ac06, eeb9b3e, 9d624fe, 5c15625 — R8 для release-инструментации) |
| HB-RW-007 | hydrabox | 593df55 | DONE |
| HB-RW-008a | hydrabox | 44d68da | DONE |
| HB-RW-008b | hydrabox | 53e2773 | DONE |
| HB-RW-008 | hydrabox | 44d68da, 53e2773, a9c2e9a | DONE |
| HB-RW-034 | hydrabox | 8b1ce84 | DONE |
| HB-RW-009 | hydrabox | 9584767 | DONE |
| HB-RW-010 | hydrabox | 69cd538 | DONE |
| HC-RW-007 | hydracore | — | CANCELLED решением тимлида: ConnectClient поднимает QUICRelay и healthLoop и возвращается, дозвоны фоновые, поэтому в call.Connect нечего ограничивать; ветка P2 карточки HB-EXP-E2B унаследовала ложную посылку E2A о синхронном ожидании линий (сам E2A = P1). Ветка P2 HB-RW-009 реализуется без изменений ядра. STOP CONDITION HB-RW-009 про несмерженный HC-RW-007 снят. |
| HB-RW-035 | hydrabox | a30161b | DONE |
| HB-RW-011 | hydrabox | 2a7bfa3 | DONE |
| §2.4 AMEND | hydrabox | — | Решение тимлида: NETWORK_CHANGED НЕ инкрементирует commandGeneration. Причина: cg означает вытеснение намерения (после HB-RW-011 launch.generation == currentCommandGeneration отменяет старт), а смена сети намерения не вытесняет. Устаревание сетевых событий обслуживает networkGeneration со своим guard (QUICRelay.appliedNetworkGeneration отбрасывает ng <= applied). Строка §2.4 со списком инкремента cg — дефект плана. Действует для HB-RW-017, HB-RW-018 и далее. |
| HB-RW-017 | hydrabox | d43f505 | DONE |
| HB-RW-012-FIX | hydrabox | 0f1eaca | DONE |
| HB-RW-012B | hydrabox | bce1f89 | DONE |
| HB-RW-015-FIX-2 | hydrabox | e855a4e | DONE |
| HB-RW-018 | hydrabox | c3ad3f2 | DONE |
| HB-BUNDLE-002 | hydrabox | 70c6218 | DONE |
| HB-BUNDLE-003 | hydrabox | e140e21 | SATISFIED BY HB-BUNDLE-001: бандл debug.51 (gitlink d0de9624) уже содержит HC-RW-001..005 — 2951d7d3, 6b0b122d, 34da49ed, be30c53c, 2e868e16. Отдельный bump не нужен, дублирующий коммит не создаётся. Разблокирует HB-RW-020. |
| HB-RW-020 | hydrabox | 1831bed | DONE |
| HB-RW-021 | hydrabox | 95c71e9 | DONE |
| HB-RW-029 | hydrabox | — | BLOCKED(HB-RW-028) |
| HB-RW-032 | hydrabox | 8477d22 | DONE |
| HB-RW-007-FIX | hydrabox | 71137fe, cca5088 | DONE |
| HB-RW-017-FIX | hydrabox | bf5cc07 | DONE |
| HB-RW-032-FIX-2 | hydrabox | 63c8cfd, d521964 | BLOCKED(DEVICE-2: A1 10/10, M03, M05, B3b, R8/B4 и C1–C6 выполненные части зелёные; ожидаются внешние прогоны B3a/M06 (ручной `VpnService.onRevoke()`), B5 (устройство не завершает UI после swipe) и M20 (tile не добавлен в Quick Settings).) |
| HB-EXP-E5 | hydrabox | 8d35c65 | DONE (P1) |
| HB-EXP-E3 | hydrabox | 73c5032 | DONE (P1) |
| HB-EXP-E9 | hydrabox | a783f2c, 15ac1bc | DONE (P1) |
| FIRST-START-IFACE-FIX | hydrabox | 73e3ef0, f99a751 | DONE — 5/5 холодных старта до RUNNING; поправка к NEGATIVE ASSERTIONS HB-RW-017: прямой вызов updateDefaultInterface разрешён только в пути replay при регистрации listener'а, решение тимлида. |
| HB-EXP-E7 | hydrabox | 9bfc6e5 | DONE (P2) |

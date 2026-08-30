
# HydraBox Runtime — Implementation Contract

Второй проход над `docs/HYDRABOX_RUNTIME_REWORK_PLAN.md`. Тот документ — исходный
архитектурный аудит; он остаётся в силе как обоснование и **не переписывается**.
Этот документ — исполняемый контракт: решения приняты, задачи атомарны, каждая
задача самодостаточна для передачи coding agent.

| | |
|---|---|
| Составлен | 2026-08-26 |
| HydraBox baseline | ветка `fix/instrumentation-release-variant`, HEAD `6c4bf26045583bbc996b2f218c56f000a1bd49a4` |
| HydraCore baseline | ветка `debug`, HEAD `9eefdec8ab44abf4203f8e0efa17dbb697f1beac` |
| Источник обоснований | `docs/HYDRABOX_RUNTIME_REWORK_PLAN.md`, разделы A–W |
| Reference (design principles only) | NekoBoxForAndroid `5768494d8ae3c74a057bb6d46c0f8dc071b0d821` |
| HYDRA-ULTIMATE | вне scope; ни одна задача его не затрагивает |

Навигация: §0 контракт агента → §1 adversarial review → §2 финальные инварианты иконтракты → §3 эксперименты → §4 задачи → §5 DAG → §6 совместимость →§7 порядок исполнения → §8 журнал evidence.

**Состояние на 2026-08-26.** 49 задач, 13 экспериментов, 20 инвариантов.
Шесть экспериментов класса A (STATIC) выполнены при составлении документа, их
evidence записан в §8.1, выбранные ветки вписаны в задачи. Осталось семь блокеров,
все класса C — требуют Android-устройства. Первая задача к исполнению — `HB-RW-001`
(§7.2).

---

# §0. AGENT EXECUTION CONTRACT

Обязателен к прочтению перед любой задачей. Нарушение любого пункта — основание
отклонить PR целиком.

## 0.1 Дисциплина исполнения

1. **Одна TASK за один запуск.** Взял `HB-RW-014` — делаешь только `HB-RW-014`.
2. **Не начинать следующую задачу автоматически**, даже если она разблокирована.

   Завершил — отчитался — остановился.
3. **Никакого попутного cleanup и рефакторинга.** Увидел кривой код рядом — в отчёт,
   не в diff. Форматирование, переименования и «улучшения» вне списка
   `FILES / SYMBOLS` запрещены.
4. **STATUS BLOCKED — задача не выполняется и blocker не обходится.** Ответ:
   «задача заблокирована, требуется сначала выполнить `HB-EXP-<ID>`». Никаких
   «сделаю по варианту А, потом поправим».
5. **STOP CONDITIONS обязательны.** При срабатывании: остановиться, зафиксировать
   наблюдение, не импровизировать.
6. **Обнаружен несвязанный баг — в отчёт, не в код.**
7. **Знание об архитектуре может быть устаревшим; источник истины — исходный код на BASELINE-коммите.** Если документ противоречит коду — остановиться и сообщить
   о расхождении, не подгонять код под документ.

## 0.2 Тесты и инварианты

8. **Существующие тесты — спецификация.** Нельзя удалять тест, ставить skip/Ignore,

   ослаблять expect, менять expected value или fixture ради зелёного прогона.
   Единственное исключение: тест покрывает код, который задача **явно** удаляет —
   тогда тест удаляется в том же PR и это указано в `DELETE`.
9. **Сначала regression test, затем изменение поведения** — там, где это указано
   в `TESTS TO ADD FIRST`.
10. **Инварианты завершённых задач неприкосновенны** (список — §2.1). Если задача
    требует изменить уже установленный инвариант — это ошибка плана: остановиться
    и сообщить.
11. **Verify-скрипты в `scripts/` — исполняемый контракт, а не линтер.**
    `verify_client_boundaries.py`, `verify_libbox.py`, `verify_extended_core.py`,
    `verify_hydra_ultimate_contract.py` не обходятся и не правятся под diff.
12. **Generated-код не правится руками.** `lib/singbox/singbox_api.g.dart` и
    Kotlin-сторона Pigeon — только через
    `dart run pigeon --input pigeons/singbox_api.dart`.

## 0.3 Запреты по существу

13. **Никаких performance-оптимизаций.** Запрещено менять количество workers,

    keepalive, TURN UDP/TCP preference, battery / wake-lock / doze, memory limits,
    любые интервалы опроса и cadence, TTL кэшей, batching. Всё это `DEFERRED`
    до прохождения gate из `HYDRABOX_RUNTIME_REWORK_PLAN.md` §W.
14. **Никаких новых архитектурных механизмов** сверх перечисленных в
    `IMPLEMENTATION`. Ни `Manager`, ни `Coordinator`, ни `Supervisor`, ни
    `Orchestrator`.
15. **Версии контракта HydraCore не меняются**, кроме задач, где это явно разрешено
    в `BACKWARD COMPATIBILITY`. Запрещено менять `api_version`, `runtime.version`,
    `runtime.snapshot_schema_version`, `schema_version` в
    `HydraCoreTransportState`, `APIVersion`, `CoreID`.
16. **HYDRA-ULTIMATE не затрагивается.**
17. **Секреты не логируются**: ни credentials, ни token, ни cookie, ни join_link,
    ни captcha URL, ни IP, ни hostname. `HydraBoxLogSanitizer` — последний барьер,
    а не первый.

## 0.4 Валидация

Разрешённые команды (из `AGENTS.md`; локальные сборки APK/AAB не выполняются, ихделает CI):

```bash
flutter analyze
flutter test test/<path>
flutter test --reporter expanded
dart format .
dart run pigeon --input pigeons/singbox_api.dart
flutter gen-l10n
./gradlew :app:testDebugUnitTest :app:lintDebug
python3 -B -m unittest discover -s scripts/tests -p "test_*.py"
python3 -B scripts/verify_extended_core.py --source-only
python3 -B scripts/verify_client_boundaries.py
python3 -B scripts/verify_libbox.py
python3 -B scripts/verify_hydra_ultimate_contract.py
```
HydraCore (`D:\dev\hydracore\hydracore`):

```bash
go build ./...
go vet ./transport/call/... ./common/hydracore/...
go test ./transport/call/... ./common/hydracore/... ./dns/...
```
`./gradlew :app:connectedAndroidTest` — только на устройстве и только взадачах-экспериментах класса C.

## 0.5 Формат отчёта агента

```
TASK: <ID>
RESULT: DONE

| BLOCKED | STOPPED
INVARIANTS ESTABLISHED: R..
FILES CHANGED: <список>
TESTS ADDED: <список>
VALIDATION OUTPUT: <вывод команд из VALIDATION, кратко>
NEGATIVE ASSERTIONS CHECKED: <как именно проверены>
UNRELATED FINDINGS: <или "нет">
STOPPED BECAUSE: <если применимо>
```

---

# §1. ADVERSARIAL CONSISTENCY REVIEW

Атака на `HYDRABOX_RUNTIME_REWORK_PLAN.md`. Каждое противоречие — `C<n>`, с принятым
решением. Решения зафиксированы в §2 и разложены на задачи в §4.

## C1. Phase 3 сама себя блокирует: serializer занят START, STOP не может войти

**Противоречие.** §K.2 требует «исполнять команды до конца … без выхода на
`mainHandler`», §S Phase 3 требует перевести `awaitRunning` / `awaitTransportReady` /
`awaitRuntimeServicesReleased` «на ожидание на `commandExecutor`». Но
`CoreRuntimeService.commandExecutor` — `Executors.newSingleThreadExecutor`. Ожидание
READY на нём означает, что поставленный следом `STOP` не будет исполнен до конца
ожидания. Это ровно та патология, которую Phase 3 должна устранить: сегодня
`stopInternal` ждёт блокирующий `startOrReloadService` в `HydraBoxService.executor`,
а после Phase 3 `STOP` ждал бы READY в `CoreRuntimeService.commandExecutor`.
Блокировка была бы перенесена на уровень выше, а не убрана.

**Проверка предложенной модели против кода.** Модель из постановки подтверждается:- `submit()` уже отвечает синхронным `RECEIPT_ACCEPTED` и уходит на
  `commandExecutor.execute { execute(command) }` — приём и исполнение уже разделены;- все точки инвалидации существуют: каждый stage-колбэк начинается с
  `if (generation.get() != commandGeneration) return`;- `HydraBoxService` уже имеет `executor`, `retryExecutor`, `recoveryExecutor` —
  выделенный поток запуска не является новым механизмом;- `RemoteCallbackList` + `emit()` уже устроены как «издать событие», а не «вернуть
  результат вызова», поэтому внутренние события ложатся на существующий транспорт.

**РЕШЕНИЕ (принято).** Serializer сериализует **переходы состояний**, а не ожидания:

```
serializer = один FIFO, один поток, два вида входа:
    EXTERNAL COMMAND  (из binder submit)
    INTERNAL EVENT    (из LaunchTask / CloseTask / health / network / deadline timer)
и НИКОГДА не выполняет операцию длительностью более ~5 ms.

START:
    commandGeneration++ ; state := STARTING ; write desired ; emit
    launch := LaunchTask(commandGeneration) ; поток RuntimeLaunch.start()
    arm deadline timer -> INTERNAL EVENT DEADLINE(commandGeneration)
    RETURN в event loop

LaunchTask (поток RuntimeLaunch, вне serializer):
    стадии foreground / native_setup / network_wait / command_server /
           libbox_start / command_client
    между стадиями: if (cancelled) -> post CANCELLED(cg) ; return
    успех  -> post LAUNCHED(cg, runtimeGeneration)
    ошибка -> post LAUNCH_FAILED(cg, domain, code)

STOP (обрабатывается в любой момент):
    commandGeneration++ ; state := STOPPING ; emit
    launch?.cancel()          // неблокирующе: флаг + closeService из потока отмены
    CloseTask(commandGeneration) ; поток RuntimeClose.start()
    arm deadline timer
    RETURN в event loop

CloseTask -> post RELEASED(cg) либо RELEASE_FAILED(cg)
```
Все `await*`-циклы на `mainHandler` удаляются. Дедлайны — таймеры`ScheduledExecutorService`, публикующие `DEADLINE(commandGeneration)`; они не ждут.

**Полная инвентаризация длительных операций**, чтобы противоречие не вернулось:

| Операция | Сейчас выполняется на | Целевой владелец |
|---|---|---|
| `server.startOrReloadService(...)` (JNI) | `HydraBoxService.executor` | `LaunchTask`, поток `RuntimeLaunch` |
| `server.closeService()`, `server.close()` (join 1200 ms каждый) | одноразовые потоки `runCleanupStep`, join на `executor` | `CloseTask`, поток `RuntimeClose` |
| `SingboxController.disconnectClientBlocking(1200 ms)` | `HydraBoxService.executor` | `CloseTask` |
| `awaitUsableDefaultInterface(2500 ms)` плюс до 5 retry | `HydraBoxService.executor` | `LaunchTask`, стадия `network_wait` |
| `SingboxController.getRuntimeSnapshot` (RPC) | callback на `mainHandler` | `LaunchTask`, стадия `command_client` |
| `Libbox.hydraCoreTransportState()` каждые 250 ms | `mainHandler` | `ScheduledExecutorService`, событие `HEALTH` в serializer |
| `lookupOutboundExternalInfo` (`CountDownLatch`, до 10 s) | **binder-поток** `executeUtility` | асинхронный ответ через `ipcExecutor` (задача `HB-RW-034`) |

Инвариант **R3**.

## C2. `emit()` вызывается из двух потоков — `RemoteCallbackList` этого не выдерживает

**Новая находка, в аудите отсутствовала.** `CoreRuntimeService.emit()` делает`listeners.beginBroadcast()` и `finishBroadcast()` и вызывается:- из `commandExecutor` — `start()` → `updateState(PREPARING/STARTING)`;- из `mainHandler` — `updateState` внутри `awaitRunning`, `failStartAndRollback`,

  stop-колбэков, `refreshTransportHealth(emitIfChanged = true)` (poll 250 ms),
  `handleControllerEvent` (сток событий `SingboxController`, постящий в `mainHandler`).`RemoteCallbackList.beginBroadcast()` бросает `IllegalStateException`, если вызванповторно до `finishBroadcast()`. Два потока — реальная гонка. Дополнительно`eventBuilder()` инкрементирует `sequence` в одном потоке, а физическая отправкаможет произойти в другом порядке, поэтому `lastSequence` перестаёт быть монотоннымдля получателя и любая проверка пропусков даёт ложные срабатывания.

**Также трёхпоточная запись `state`:** `commandExecutor` (`start`), `mainHandler`
(`updateState` в stage-колбэках), `mainHandler` через `refreshFromController()` из
`handleControllerEvent`. `AtomicReference` защищает значение, но не логику:
`refreshFromController` перезаписывает `STARTING` на `RUNNING`, если
`SingboxController.running` уже true, минуя проверку readiness.

**РЕШЕНИЕ.** Все `emit`, все записи `state` / `mode` / generation и построение
`RuntimeEvent` выполняются **только на потоке serializer**. `registerListener`
(binder-поток) не вызывает `emit`, а публикует `INTERNAL EVENT REPLAY(listener)`;
единственный синхронный ответ binder-у — `getSnapshot()`, который читает под
`snapshotLock` и ничего не мутирует. Инварианты **R1**, **R3**, **R12**.

## C3. Несовместимые определения generation

**Противоречие.** §H.1 определяет `runtimeGeneration` как «+1 при каждом успешномсоздании нового native runtime», а таблица §I.2 в строке `STOPPED --START-->`предписывает `runtimeGeneration++` **до** запуска. §K.3 использует`runtimeGeneration++` как механизм вытеснения команды, что относится к команде.В коде уже сосуществуют две величины с почти одинаковыми именами:`CoreProcessIdentity.generation` (инкремент в `start`/`stop`/`reload`/`recover` —семантика команды) и `SingboxController.activeRuntimeGeneration` (инкремент в`markServiceStarted` — семантика живого runtime).

**РЕШЕНИЕ.** `runtimeGeneration` остаётся «живой runtime», то есть сегодняшний
`activeRuntimeGeneration`. Все места, где в аудите написано `runtimeGeneration++`
при приёме команды, читаются как `commandGeneration++`. Пять величин, пять
владельцев, пять условий инкремента — таблица §2.
4. Инвариант **R6**.

## C4. Phase 1 создаёт временное двоевластие в Dart

**Противоречие.** Phase 1 переводит Dart-предикаты на чтение `state`, но`app.dart:_syncRuntimeState()` (polling `status()` плюс `decideStatus` плюс`setState`) удаляется только в Phase 9/11. В интервале фазу UI пишут два пути —редьюсер событий и polling-редьюсер — по разным правилам (`decideStateEvent`против `decideStatus`).

**РЕШЕНИЕ.** Удаление polling переносится в Phase 2, в тот же PR, что и удаление
Dart-супервизора (`HB-RW-007`). После него единственный writer фазы — редьюсер
снимка. Инварианты **R2**, **R11**.

## C5. Phase 4 зависит от Phase 3, но prerequisite указан только Phase 1

**Противоречие.** Phase 4 предписывает: «`RuntimeSession.kt`: удалить`writeRuntimeIntent` … `shouldRestoreStickyStart` заменить на вызов`CoreRuntimeService`». Класс `RuntimeSession` появляется только в Phase 3.Итоговая таблица §3 аудита указывает prerequisite Phase 4 = «фаза 1».Missing prerequisite.

**РЕШЕНИЕ.** Phase 4 разделяется: `HB-RW-012` и `HB-RW-013` (файл desired state,
reconciliation, удаление service-state API) зависят только от Phase 1 и работают
с текущим именем `HydraBoxService`; sticky-restart через `CoreRuntimeService`
(`HB-RW-012B`) зависит от Phase 3. DAG §5 отражает это явно.

## C6. Два владельца `selectedOutbounds`

**Противоречие, отмеченное в аудите без задачи.**`CoreRuntimeService.selectOutbound` пишет `selectedOutbounds[groupId]` после успеха

RPC; `updateOutboundGroups` (событие ядра) делает `clear()` и перезаполняет изснимка ядра. Порядок между ними не определён: успешный `selectOutbound` может бытьперезаписан событием, сформированным до применения выбора.

**РЕШЕНИЕ.** Ядро authoritative. `selectOutbound` не пишет `selectedOutbounds`;
он пишет `pendingSelection[groupId] = outboundId` вместе с `commandGeneration`,
и снимок несёт оба поля. `pendingSelection` снимается, когда событие ядра
подтвердило выбор либо когда `commandGeneration` устарел.
Инварианты **R1**, **R13**. Задача `HB-RW-035`.

## C7. Скрытый бесконечный retry: авто-rebind `CoreRuntimeClient`

**Новая находка.** `CoreRuntimeClient.onBindingDied` делает `unbindService`,`disconnect(...)` и **безусловно

** `connect()`. Если `CoreRuntimeService.onCreate`падает (он ловит, логирует и перебрасывает исключение), связывание умирает снова,и снова вызывается `connect()`. Получается неограниченный цикл bind → crash → bind,без счётчика и без backoff. `CoreStartupFailureStore` при этом уже содержит стадиюпадения, то есть данные для остановки есть.

**РЕШЕНИЕ.** Ограниченный rebind: не более 3 попыток подряд без единого успешного
`onServiceConnected`; после исчерпания —
`CoreRuntimeException("runtime.ipc.unavailable")` с причиной из
`CoreStartupFailureStore` и никаких автопопыток до явной пользовательской команды.
Счётчик сбрасывается при успешном подключении. Инвариант **R9**. Задача `HB-RW-016`.

## C8. Скрытые retry-циклы без владельца домена

Инвентаризация всех автоматических повторов и их судьба:

| Механизм | Домен | Судьба |
|---|---|---|
| `QUICRelay.reconnectPath` backoff 0.5→5 s, **без ограничения числа попыток** | AUTH/TURN/DTLS/QUIC | остаётся единственным владельцем этих доменов, получает domain-guard: при `terminal` — выход |
| `TURNCredentialProvider` flood control плюс cache | CREDENTIALS | остаётся |
| `HydraBoxService` network-wait: 5 попыток по 1500 ms | NETWORK на старте | становится стадией `LaunchTask` и входит в общий `START_DEADLINE` |
| `HydraBoxService.requestRuntimeRecovery` (4 триггера) | NETWORK/PROCESS | удаляется (`HB-RW-025`, после `HB-EXP-E7`) |
| `HydraBoxVpnService.onTaskRemoved` → AlarmManager | PROCESS | остаётся, однократный |
| `START_STICKY` плюс `runtime-intent` без TTL | PROCESS | заменяется на `wantRunning` плюс `recoveryAttempt ≤ 2` |
| `CoreRuntimeService.recover()` (`REQUEST_RECOVERY`) | PROCESS | удаляется как команда |
| `CoreRuntimeClient.onBindingDied` → `connect()` | PROCESS | ограничивается (C7) |
| `CommandClientLifecycle` reconnect 250→5000 ms | наблюдение, не runtime | остаётся: это транспорт диагностики |
| Dart `_scheduleInvalidOutboundRetry` | CONFIG | остаётся только для invalid-outbound |
| Dart `safeCoreRestart` → `fullServiceRestart` | смешанный | удаляется (`HB-RW-036`) |
| Dart `_retryOnResume` | смешанный | удаляется (`HB-RW-013`) |
| Dart watchdog → `stop(start_timeout)` | смешанный | удаляется (`HB-RW-007`) |
| `HydraBoxQuickSettingsTileService.scheduleRefreshes` (3 таймера) | UI | удаляется (`HB-RW-015`) |

**РЕШЕНИЕ.** Таблица владельцев доменов §2.6 нормативна. Инварианты **R5**, **R9**.

## C9. Семантика desired state / FAILED / process death была неоднозначной

**Противоречие.** §J.2 определяет `wantRunning` как «желание пользователя»;
§M.3 говорит, что после timeout `wantRunning` **сохраняется**, если провал
retryable; §J.5 предписывает при `wantRunning == true` запускать runtime после
смерти процесса. Композиция трёх правил даёт ровно запрещённый сценарий: FAILED
(retryable) → `wantRunning` остался true → Android убивает `:core` → новый процесс
сам начинает retry, хотя UI сообщил «ждём пользователя».

Дополнительно §J.2 не ограничивает число автоматических восстановлений, а
`START_STICKY` перезапускает сервис после каждого падения: падение на стадии старта
даёт бесконечное воскрешение.

**РЕШЕНИЕ (§2.5).** `wantRunning` переопределяется как **разрешение на
автоматическое восстановление**, а не как «пользователь любит VPN»:

- `wantRunning = true` означает «runtime обязан быть живым, автоматическое
  восстановление разрешено».- Ставится в `true` только при приёме START, инициированного пользователем
  (кнопка UI, Quick Settings tile).- Ставится в `false` при пользовательском STOP, при `onRevoke`, при **любом** входе
  в FAILED (включая retryable), при исчерпании `recoveryAttempt`.- Отдельный флаг `autoRecoverAllowed` **не нужен и не вводится**: `wantRunning`
  и есть он по определению. Фиксируется инвариантом, чтобы позже никто не вернул
  второй флаг.- «Пользователь хочет включить снова» не является durable состоянием. UI показывает
  Retry, выводя это из `runtimeState == FAILED`; Retry — новая команда START.- `recoveryAttempt: int` в том же файле: +1 при каждом START от reconciliation
  (не от пользователя); сбрасывается в 0 при READY; при `recoveryAttempt >2` →
  `wantRunning := false` и `FAILED(runtime.recovery.exhausted)`. Это единственное
  новое поле, и оно необходимо: без него `START_STICKY` вместе с `wantRunning` дают
  неограниченный цикл воскрешения при падении на старте.Итог: FAILED → `wantRunning = false` → смерть процесса → reconciliation ничего неделает. Запрещённый сценарий невозможен. Инварианты **R7**, **R8**, **R9**.

## C10. Циклическая зависимость Phase 6 (Android) и Phase 7 (Hydra

Core)

**Противоречие.** Phase 6 требует `RebindNetwork(generation)` в HydraCore, Phase 7
требует удалить `rebindMu` / `rebindCancel` в том же `client.go` и переписать
`healthSnapshot` в `supervisor.go`; при этом Phase 6 в итоговой таблице идёт до
Phase 7. Обе Go-задачи трогают один файл и обе требуют новой сборки `libbox.aar`.
При независимом мерже — конфликт и два несовместимых артефакта.

**РЕШЕНИЕ.** HydraCore получает строгий линейный порядок задач:

```
HC-RW-001  safe error codes и stage events
HC-RW-002  health: один writer, per-generation registry, domain/terminal (аддитивно)
HC-RW-003  healthSnapshot: сброс lastFailure, отсутствие failure при activeLanes>0
HC-RW-004  RebindNetwork(gen), per-generation pathCtx, удаление мёртвых полей,
           плюс требования HC-RW-006 (код отмены CAPTCHA) — один PR
HC-RW-005  reconnectPath: выход при terminal вместо backoff
```
`rebindMu` и `rebindCancel` удаляются в `HC-RW-004`, а не в Phase 7. Android-задачи,
зависящие от Go, зависят от конкретного `HB-BUNDLE-*`, а не от «Phase N».

## C11. Bundle-артефакт — единственная точка синхронизации репозиториев

**Находка.** HydraCore попадает в приложение не исходниками, а как`android/app/libs/libbox.aar` плюс `libbox.sha256` и `libbox.provenance.json`,проверяемые `scripts/verify_libbox.py` и `scripts/verify_extended_core.py` противпина submodule (`hydracore/release/UPSTREAM_BASELINE`, `HYDRACORE_VERSION`).Ни одна фаза аудита не содержала шага «обновить submodule и артефакт», без которогоизменения HydraCore в приложении не наблюдаются вообще.

**РЕШЕНИЕ.** Введён отдельный тип задачи `HB-BUNDLE-<n>`: bump submodule pointer,
новый артефакт, provenance и sha, прохождение обоих verify-скриптов. После решения
C17 это **единственный** механизм доставки ядра, и он всегда совпадает с релизом APK.

## C17. Сменяемое ядро внутри приложения — избыточная подсистема (решение владельца)

**Вводные.** Владелец продукта зафиксировал: модель подмены ядра во время работы
приложения (`CoreBundleManager`, `CoreBundleUpdater`, `CoreCandidateProbeClient`,
процесс `:core_probe`, `CoreProbeService`, Core Manager UI и его Pigeon-API) была
debug-экспериментом и признана избыточной.

**Почему это относится к рефакторингу runtime, а не к продуктовому бэклогу.

**Подсистема добавляет в runtime-путь состояние и побочные эффекты:- `CoreRuntimeService.onCreate` при `HydraNativeLoader.loadedSource() == "active"`
  вызывает `CoreBundleManager(this).readState()` и `markHealthy(...)` — файловый
  ввод-вывод внутри инициализации владельца runtime;- `completeHealthyStart`, то есть точка достижения READY, снова вызывает
  `readState()` и `markHealthy(...)` — побочный эффект на успешном старте, не
  относящийся к runtime;- `HydraBoxApplication.onCreate` ветвится по трём процессам и в `:core` вызывает
  `noteCoreProcessStart()` и `configureNativeLoader()`;- третий процесс `:core_probe` существует только ради валидации кандидата;- `HydraNativeLoader` держит изменяемое глобальное состояние (`candidate`,
  `loadedSource`, `loaded`) и путь загрузки, зависящий от файла на диске;- `app.dart` вызывает `CoreManagerHostApi().rollback()`.То есть у стадии старта есть четвёртый владелец побочных эффектов, не упомянутыйни в одном контракте §2. Удаление подсистемы убирает его целиком.

**РЕШЕНИЕ (принято).** Подсистема удаляется тремя атомарными задачами
`HB-RW-040`, `HB-RW-041`, `HB-RW-042`, размещёнными сразу после observability и
**до** `HB-RW-003`. Ядро поставляется только внутри APK; пин — submodule плюс
артефакт; `HB-BUNDLE-*` сохраняется, но теперь всегда совпадает с релизом приложения.

Что **сохраняется** и почему:

| Компонент | Решение | Причина |
|---|---|---|
| `go.HydraNativeLoader` (класс) | сохранить, удалить только конфигурацию кандидата | Патченный статический инициализатор `go.Seq` в артефакте вызывает `HydraNativeLoader.loadLibrary`. Удаление класса потребовало бы менять сборку AAR: это вне scope и ломает `verify_libbox.py`. После задачи `loadedSource()` всегда возвращает `embedded`. |
| `CoreBundleSignatureVerifier` | сохранить на месте, не переименовывать | Используется `update/AppUpdateManifestVerifier` для проверки подписи обновлений APK. Это не про ядро. Перенос пакета и переименование запрещены правилом 3 контракта агента. |
| `CoreCapabilityContract` | сохранить | Валидирует капабилити встроенного ядра при построении контракта; ловит ошибки сборки. |
| `CoreStartupFailureStore` | сохранить | Единственный способ узнать стадию падения `:core`; используется `HB-RW-016`. |
| `scripts/verify_libbox.py` | не менять | Требование динамического загрузчика уже условное: `require_dynamic_loader` включается только если в provenance есть `hydracore-bundle-manifest-v1.json`. Когда HydraCore перестанет публиковать этот артефакт, проверка сама станет no-op. |

Что **обязательно меняется в исполняемом контракте** — единственное разрешённоеисключение из правила 11:- `scripts/verify_client_boundaries.py`: из `required_process_bindings` удаляются
  `android:name=".runtime.CoreProbeService"` и `android:process=":core_probe"`;
  из `verify_platform_bridge_boot_order` удаляется маркер
  `CoreManagerHostApi.setUp(binaryMessenger, handler)`. Эти строки пинуют
  существование удаляемой подсистемы, и их сохранение сделало бы удаление
  невозможным. Изменение разрешено **только** в задачах `HB-RW-041` и `HB-RW-042`
  соответственно и обосновывается отдельной строкой в commit message.

**Последствия для остального плана:**

1. `:core_probe` исчезает: процессов остаётся два — `default` и `:core`.
2. Конфигурация «старый HydraBox плюс новый HydraCore» перестаёт существовать в
   production. Совместимость нужна только для окна внутри истории репозитория:
   hydracore-задача смержена, а `HB-BUNDLE-*` ещё нет.
3. Инвариант **R14** сохраняется, но его обоснование меняется: не «на устройстве
   может оказаться новое ядро со старым приложением», а «`CoreCapabilityContract`
   и `verify_extended_core.py` пинуют версию 2, а повышение не даёт ничего, кроме
   риска». Аддитивность остаётся обязательной для безопасности окна из пункта 2.
4. Постоянный dual-read health в `HB-RW-020` понижается до переходного: обязателен
   до `HB-BUNDLE-003`, снимается позже отдельным решением. Отдельной задачи на его
   снятие план не содержит.5. §2.10: `CoreProbeService` не переименовывается, а удаляется.
6. Стадия READY теряет побочный эффект `markHealthy`, что упрощает `HB-RW-008`
   и `HB-RW-009`.

## C12. Версии контракта ядра запинены — повышать их не нужно

**Находка.** §M.1 предлагала перевести `HydraCoreTransportState` на`schema_version: 3`. Однако:- `TransportHealthBridge.parse` делает `require(root.getInt("schema_version") == 2)` —

  жёсткое равенство, не диапазон;- `CoreCapabilityContract.supportedProtocolIds` требует `api_version == 2`,
  `runtime.version == 2`, `runtime.snapshot_schema_version == 2`;- `scripts/verify_extended_core.py` проверяет маркеры `APIVersion = 2` и
  `CoreID: "io.hydrabox.hydracore"`.

**РЕШЕНИЕ (принято, отменяет §M.1).** Версии не повышаются. Все расширения
transport-контракта — аддитивные ключи внутри `schema_version: 2`:
`failure.domain`, `failure.terminal`, `runtime_generation`, `network_generation`,
`applicable`. Обоснование после C17: повышение потребовало бы синхронной правки трёх
запиненных мест и одного verify-скрипта, не давая ничего взамен; аддитивность
дополнительно делает безопасным окно «hydracore смержен, артефакт не обновлён».
Ограничение: новые ключи в `features` капабилити не должны совпадать с
`CoreCapabilityContract.legacyFeatureNames`, иначе `bundleApiMajor()` вернёт 1.
Инвариант **R14**.

## C13. Расхождение блокирующих экспериментов с итоговой таблицей

**Противоречие.** В приложении аудита указано: E1 блокирует Phase 2, E3 — Phase 8,E10 — generation-guard Phase 6, E11 — Phase 2, E12 — формулировку I.
4. Итоговаятаблица §3 аудита указывает для Phase 2 только «фаза 1», для Phase 8 — «фаза 7»,для Phase 6 — только E4, для Phase 10 — только E5; E9, E11, E12 не упомянуты вовсе.

**РЕШЕНИЕ.** Нормативная матрица «эксперимент → задачи» в §3.0 и поле `STATUS`
в каждой задаче. Ни одна задача не может иметь `READY`, пока её эксперимент не
выполнен и evidence не записан в §8. Таблица §7 сгенерирована из этой матрицы.

## C14. `interfaceIndex == -1` публикуется в ядро как «сети нет»

**Находка (в §L.2 отмечена, но не выделена в задачу).** В `notifyListenerInternal`,
если после 10 попыток по 100 ms `NetworkInterface.getByName` не дал индекс,
вызывается `notifyListeners(currentListeners, "", -1)`, что в Go означает
`notifyInterfaceUpdate(nil)` и далее `pauseManager.NetworkPause()`. Временная
невозможность прочитать индекс интерфейса приостанавливает весь runtime, хотя сеть
есть.

**РЕШЕНИЕ.** Самостоятельный дефект корректности, не требующий ни одного
эксперимента и ни одной другой фазы. Выделен в раннюю задачу `HB-RW-019` сразу после
observability: при живом кандидате с `index < 0` повторить слепок, `NONE` не
публиковать.

## C15. `PREPARING` лишнее, `RECOVERING` необходимое

**Проверка.** `RUNTIME_STATE_PREPARING` выставляется в `start()` на время записиконфига и не наблюдается извне осмысленно; `toLegacyRuntimeMap` трактует его так же,как `STARTING`. `RECOVERING` необходим: он единственный отличает автоматическоевосстановление от пользовательского старта, и от этого зависят `recoveryAttempt`и текст UI.

**РЕШЕНИЕ.** `PREPARING` удаляется из целевой машины состояний. Значение enum в
IPC-схеме сохраняется как deprecated, но `:core` его больше не выставляет.

## C16. Промежуточные окна с двумя источниками истины — исчерпывающий список

| Окно | Двоевластие | Допустимо | Закрывает |
|---|---|---|---|
| после `HB-RW-040`, до `HB-RW-042` | `CoreBundleManager` существует без вызывающих | два PR | `HB-RW-042` |
| после `HB-RW-003`, до `HB-RW-007` | фазу UI пишет редьюсер событий и polling `status()` | один PR, обязательно в том же спринте | `HB-RW-007` |
| после `HB-RW-008`, до `HB-RW-029` | `running` живёт в `SingboxController` и как производная в `CoreRuntimeService` | до Phase 11 | `HB-RW-029` |
| после `HB-RW-012`, до `HB-RW-033` | читается новый `runtime-desired.txt` и старый `singbox-runtime-intent.txt` | до Phase 11 | `HB-RW-033` |
| после `HC-RW-002`, до `HB-BUNDLE-003` | health несёт новые ключи, артефакт в приложении их ещё не содержит | до bundle bump | `HB-BUNDLE-003` |
| после `HB-RW-020` | Android читает health и без `domain`, и с `domain` | переходно, снимается отдельным решением | вне плана |
| после `HB-RW-017`, до `HB-RW-018` | `networkGeneration` инкрементируется старым правилом, но доставляется командой | один PR | `HB-RW-018` |

Остальные окна закрываются внутри одного PR и отмечены в `BACKWARD COMPATIBILITY`соответствующих задач.

---

# §2. FINAL TARGET CONTRACT

## 2.1 Инварианты (нормативно)Минимальный полный набор. Каждая задача в §4 указывает, какие из них устанавливает.Установленный инвариант не отменяется последующими задачами.

| ID | Инвариант |
|---|---|
| **R1** | `CoreRuntimeService` — единственный writer `runtimeState`, `mode`, `commandGeneration`, `runtimeGeneration`, `lastError`, `desiredRuntime`. Все записи выполняются на потоке serializer. |
| **R2** | UI никогда не выводит live runtime truth из persisted файлов и никогда не реконструирует её опросом. Единственный вход — `RuntimeSnapshot` и `RuntimeEvent`. |
| **R3** | Long-running native operation никогда не удерживает command serializer. Serializer не выполняет ни одной операции длительностью более примерно 5 ms и никогда не ждёт результата. |
| **R4** | Одно семантическое изменение сети создаёт ровно один `networkGeneration`, ровно один `updateDefaultInterface` и ровно один `RebindNetwork`. Семантически неизменный upstream не доходит до ядра. |
| **R5** | Один failure domain имеет ровно одного retry owner (§2.6). Никакие два компонента не повторяют один и тот же сбой. |
| **R6** | Пять величин версионирования имеют пять различных семантик и пять владельцев (§2.4). Ни одно имя не используется в двух смыслах. |
| **R7** | `wantRunning == true` означает «runtime обязан быть живым И автоматическое восстановление разрешено». Второго флага автовосстановления не существует. |
| **R8** | Любой вход в FAILED снимает `wantRunning`. После FAILED система не предпринимает ни одной автоматической попытки — ни таймером, ни после смерти процесса. |
| **R9** | Каждое автоматическое восстановление ограничено счётчиком и конечно. На стороне Android не существует ни одного неограниченного retry-цикла. |
| **R10** | `PROCESS RUNNING` и `TRANSPORT READY` — разные величины. Ни нотификация, ни UI не показывают Connected раньше `runtimeState == RUNNING`, а `RUNNING` требует выполнения порога readiness. |
| **R11** | Фаза UI имеет ровно одного writer — редьюсер снимка. Ни один Android- или Dart-таймер не пишет фазу. |
| **R12** | Все `RuntimeEvent` издаются с одного потока; `eventSequence` монотонна в порядке доставки. |
| **R13** | Выбранный outbound authoritative только у ядра. Команда выбора создаёт `pendingSelection`, а не истину. |
| **R14** | Версии контракта HydraCore (`api_version`, `runtime.version`, `runtime.snapshot_schema_version`, `schema_version` transport-состояния, `APIVersion`, `CoreID`) не меняются. Расширения только аддитивные. |
| **R15** | Probe не может изменить ни одно поле runtime-поддерева снимка и не может задержать `STOP`. |
| **R16** | UI lifecycle (foreground/background, экран, пересоздание Activity, потеря binder) не порождает ни одной runtime-мутирующей команды и не пересоздаёт транспорт наблюдения. |
| **R17** | Ни один DNS-запрос не переживает смену `networkGeneration`. DNS-сбой всегда виден как отдельный failure domain. |
| **R18** | Каждый сбой имеет `failureDomain` и код из закрытого словаря. Не существует пути, возвращающего сбой без домена. |
| **R19** | Каждая принятая мутирующая команда завершается ровно одним `CommandResult`: успех, отказ или `runtime.superseded`. Нет пути, оставляющего команду без результата. |
| **R20** | Persisted state описывает только желаемую конфигурацию. Ни один файл не утверждает, что что-то живо. |

## 2.2 Контракт 1 — Runtime state machine

Шесть состояний: `STOPPED`, `STARTING`, `RUNNING`, `RECOVERING`, `STOPPING`, `FAILED`.`PREPARING` не выставляется (C15). Владелец переходов — serializer`CoreRuntimeService`; вход — EXTERNAL COMMAND и INTERNAL EVENT.

| FROM | INPUT | GUARD | ACTION | TO |
|---|---|---|---|---|
| STOPPED, FAILED | `START(plan, origin)` | digest совпал, mode задан | `commandGeneration++`; записать конфиг; при `origin=user` → `wantRunning:=true`, `recoveryAttempt:=0`; при `origin=recovery` → `recoveryAttempt++`; создать `LaunchTask(cg)`; вооружить `DEADLINE(cg)` | STARTING, при `origin=recovery` — RECOVERING |
| STARTING, RECOVERING | `LAUNCHED(cg, rg)` | `cg` актуален | `runtimeGeneration := rg`; подписаться на health | без изменения |
| STARTING, RECOVERING | `HEALTH(rg)` | `rg` актуален, порог READY достигнут (§2.3) | `recoveryAttempt := 0`; `CommandResult(SUCCEEDED)` | RUNNING |
| STARTING, RECOVERING | `HEALTH(rg)` с `challenge` | есть `challengeId` | перевооружить таймер на `CHALLENGE_DEADLINE`; состояние не менять | без изменения |
| STARTING, RECOVERING | `LAUNCH_FAILED(cg, domain, code)` | `cg` актуален | `CloseTask(cg)`; `wantRunning := false` | FAILED после `RELEASED` |
| STARTING, RECOVERING | `DEADLINE(cg)` | `cg` актуален | `launch.cancel()`; `CloseTask(cg)`; код `runtime.start.deadline` либо `transport.recovery.timeout`; `wantRunning := false` | FAILED после `RELEASED` |
| STARTING, RECOVERING | `STOP(reason)` | — | `commandGeneration++`; `launch.cancel()`; `CloseTask(cg')`; активной START — `CommandResult(FAILED, runtime.cancelled)`; при `reason=user` → `wantRunning := false` | STOPPING |
| STARTING, RECOVERING | `START` с тем же `(configSha256, mode)` | — | no-op; результат первой команды выдаётся обеим | без изменения |
| STARTING, RECOVERING | `START` с другим планом | — | первой команде `CommandResult(FAILED, runtime.superseded)`; далее как STOPPED→START | STARTING |
| RUNNING | `STOP(reason)` | — | `commandGeneration++`; `CloseTask`; при `reason=user` → `wantRunning := false` | STOPPING |
| RUNNING | `HEALTH(rg)`, `activeLanes >0` | — | обновить снимок | RUNNING |
| RUNNING | `HEALTH(rg)`, `activeLanes == 0` дольше `LOST_GRACE` | `applicable` | вооружить `DEADLINE` = `RECOVERY_DEADLINE` | RECOVERING |
| RUNNING | `NETWORK_CHANGED(ng)` | `ng >appliedNg` | применить underlying, `updateDefaultInterface`, `RebindNetwork(ng)` | RUNNING |
| RUNNING | `CORE_DIED` | `wantRunning` | как `START(origin=recovery)` | RECOVERING |
| RUNNING | `RELOAD` | `configSha256` изменился | `SingboxController.reloadService`; таймер `RELOAD_DEADLINE` | RUNNING |
| RECOVERING | `DEADLINE(cg)` | `recoveryAttempt >2` | `wantRunning := false`; код `runtime.recovery.exhausted` | FAILED |
| STOPPING | `RELEASED(cg)` | `cg` актуален | сбросить `runtimeGeneration := 0`, health, `pendingSelection` | STOPPED |
| STOPPING | `RELEASE_FAILED(cg)` | `cg` актуален | код `runtime.stop.unconfirmed`; `wantRunning := false` | FAILED |
| STOPPING | `STOP` | — | присоединить к тому же результату | STOPPING |
| STOPPING | `START` | — | сохранить **одну** отложенную START; повторная заменяет её | STOPPING |
| STOPPED | переход из STOPPING при наличии отложенной START | есть отложенная START | применить её | STARTING |
| FAILED | `STOP` | — | гарантировать освобождение ресурсов | STOPPING |
| любое | процесс умер | — | состояния нет; новый процесс начинает со STOPPED и выполняет reconciliation (§2.7) | STOPPED |

Дедлайны фиксированы этим документом и не являются предметом оптимизации:`START_DEADLINE` = 45 s (включая стадию `network_wait`, см. `HB-EXP-E11`),`CHALLENGE_DEADLINE` = 120 s, `RECOVERY_DEADLINE` = 60 s, `CLOSE_DEADLINE` = 5 s,`RELOAD_DEADLINE` = 15 s, `LOST_GRACE` = 10 s.

## 2.3 Контракт 2 — Transport readiness

Публикует HydraCore, аддитивно внутри `schema_version: 2` (C12). Новые ключипомечены `+`:

```json
{ "schema_version": 2,
  "health": { "state": "starting

|waiting_user|healthy|degraded|recovering|failed",
              "active_lanes": 0, "total_lanes": 8, "demand": false,
              "last_progress_at": 0, "last_aggregate_progress_at": 0,
              "last_inbound_at": 0, "observed_at": 0,
              "applicable": true,                 // +
              "runtime_generation": 0,            // +
              "network_generation": 0,            // +
              "failure": { "stage": "", "kind": "", "code": "",
                           "retry_after_ms": 0, "challenge_id": "",
                           "domain": "AUTH",      // +
                           "terminal": false } }, // +
  "challenge": { "id": "", "kind": "", "url": "", "created_at": 0, "expires_at": 0 } }
```
Правила:

- **Единственный writer** `health` — `vk-parasite.Client.healthLoop`.
  `vk.solveVKCaptcha` публикует только `challenge`.- Значения `state` не переименовываются, иначе ломается старый читатель.- `applicable` приходит из ядра; Android до `HB-RW-020` продолжает вычислять его сам,
  после — предпочитает значение ядра и деградирует к локальному вычислению при его
  отсутствии.- `domain` из закрытого набора `DNS

| CREDENTIALS | AUTH | TURN | DTLS | QUIC |
  NETWORK | INTERNAL`; отсутствие ключа читается как `INTERNAL`.- `terminal = true` означает «повтор без действия пользователя или смены конфигурации
  бессмыслен».- `runtime_generation` и `network_generation` позволяют отбросить снимок, относящийся
  к другому runtime или к другой сети.

**Единственный порог готовности**, вычисляется только в `CoreRuntimeService`:

```
READY  <=>  applicable == false
        OR  ( state in {healthy, degraded} AND active_lanes >= 1 )
```
Порог `>= 1` сохраняет текущее поведение `TransportHealthBridge.isConnected` и не
является предметом оптимизации до gate.

Проекция в UI:

| runtimeState | health | UI |
|---|---|---|
| STOPPED | — | Disconnected |
| STARTING | `challenge == null` | Connecting |
| STARTING, RECOVERING | `challenge != null` | Needs User Action |
| RUNNING | `state == healthy` | Connected |
| RUNNING | `state == degraded` | Connected с индикатором «частично» |
| RECOVERING | `challenge == null` | Reconnecting |
| FAILED | `terminal == true` | Failed без Retry |
| FAILED | `terminal == false` | Failed с Retry |
| STOPPING | — | Disconnecting |

## 2.4 Контракт 4 — Generation semantics

| Величина | Owner | Increment condition | Lifetime | Persistence | Stale-event guard |
|---|---|---|---|---|---|
| `processEpoch` | `CoreProcessIdentity` в `:core` | один раз при создании процесса (UUID) | процесс `:core` | нет | UI, увидев новое значение в снимке, обнуляет все локальные кэши; ни одно решение не переносится через смену epoch |
| `commandGeneration` | serializer `CoreRuntimeService` | +1 при приёме **каждой** мутирующей команды: `START`, `STOP`, `RELOAD`, `SELECT_OUTBOUND`, `NETWORK_CHANGED`, `USER_AUTH_RESULT` | процесс `:core` | нет | все INTERNAL EVENT и все таймеры несут `cg`; при `cg != current` событие отбрасывается без побочных эффектов; `RuntimeCommand.expectedGeneration` сверяется с ним |
| `runtimeGeneration` | serializer, по событию `LAUNCHED` | +1 **только** когда native runtime стал живым: `CommandServer` создан и `startOrReloadService` вернулся успешно — там, где сегодня `markServiceStarted` | от `LAUNCHED` до `RELEASED`, иначе 0 | нет | health-снимки, group-события, probe-результаты и `RebindNetwork` несут `rg`; при несовпадении отбрасываются |
| `networkGeneration` | `HydraBoxDefaultNetworkMonitor` | +1 **только** при семантическом изменении `EffectiveUnderlyingNetwork`, то есть кортежа (`androidNetworkId`, `interfaceName`, `interfaceIndex`) | процесс `:core` | нет | `QUICRelay.appliedNetworkGeneration` отбрасывает `ng <= applied`; DNS-запросы отменяются при росте `ng` |
| `eventSequence` | `CoreRuntimeService.eventBuilder`, только на потоке serializer | +1 на каждый изданный `RuntimeEvent` | процесс `:core` | нет | UI фиксирует пропуск (`SNAPSHOT_GAP`) и запрашивает `getSnapshot()`; сама последовательность ничего не отменяет |

Запрещено: переиспользовать `runtimeGeneration` как признак вытеснения команды;инкрементировать `runtimeGeneration` при приёме START; инкрементировать`networkGeneration` при подключении нового listener, при reassert или при любомне-семантическом изменении.

## 2.5 Контракт 3 — Desired state

Файл `filesDir/runtime-desired.txt`, atomic write, единственный writer — serializer.

```
schema=1
wantRunning=true|false
mode=vpn|proxy
configSha256=<64 hex>
recoveryAttempt=<int 0..3>
updatedAtMillis=<epoch ms>
```
Нормативные определения:- `wantRunning` — **разрешение на автоматическое восстановление** и одновременно
  утверждение «runtime обязан быть живым». Не «пользователю нравится VPN».- `mode` — целевой режим последнего пользовательского START.- `configSha256` — digest плана, который пользователь просил запустить; сверяется
  с фактическим содержимым `singbox-config.json` при reconciliation.- `recoveryAttempt` — число подряд идущих **автоматических** попыток; сбрасывается
  в 0 при READY и при пользовательском START; предел 2.

| Событие | `wantRunning` | `recoveryAttempt` |
|---|---|---|
| START от пользователя (UI, tile) | `true` | `0` |
| START от reconciliation или `CORE_DIED` | без изменения, остаётся `true` | `+1` |
| достигнут READY | без изменения | `0` |
| STOP от пользователя | `false` | `0` |
| `onRevoke` | `false` | `0` |
| вход в FAILED по любой причине | **`false`** | без изменения |
| `recoveryAttempt >2` | `false` | без изменения |
| смерть процесса | не изменяется, файл durable | не изменяется |

Ответы на вопросы постановки:
1. **Что означает `wantRunning`** — разрешение на автовосстановление, см. выше.
2. **Сохраняется ли `wantRunning` после retryable FAILED** — **нет.** Любой FAILED
   его снимает. Retryable влияет только на то, показывает ли UI кнопку Retry.
3. **Должна ли смерть процесса после FAILED приводить к новой попытке** — **нет.**
   `wantRunning` уже `false`, reconciliation завершается на шаге 1.
4. **Чем «пользователь хочет VPN» отличается от «разрешено автовосстановление»** —
   в durable состоянии не отличается ничем, потому что durable хранит только второе.
   Первое — эфемерное состояние UI (`RuntimeIntentController`), не переживающее процесс.
5. **Нужен ли `autoRecoverAllowed`** — **нет.** Введение второго флага запрещено
   инвариантом **R7**.

## 2.6 Контракт 5 — Recovery ownership: ровно один владелец на домен

| Failure domain | RETRY OWNER | Кто НЕ имеет права retry |
|---|---|---|
| `DNS` | **HydraCore**: DNS-transport внутри `dns/router.go`. `DnsResolver.FLAG_EMPTY` перебирает серверы средствами Android — это часть одного запроса, а не retry | Android-слой, Dart, `vk-parasite`, `reconnectPath` |
| `CREDENTIALS` | **HydraCore**: `transport/call/vk/turn_credentials.go:TURNCredentialProvider` — cache и flood control | `reconnectPath`, Android, Dart |
| `AUTH` без CAPTCHA | **HydraCore**: `quic_relay.go:reconnectPath`, только при `terminal == false` | Android, Dart, `TURNCredentialProvider` |
| `AUTH` с CAPTCHA | **USER.** Автоматического повтора нет ни у кого; `captchaFlowGate` только сериализует | все компоненты |
| `TURN` | **HydraCore**: `reconnectPath`. Перебор адресов внутри `allocateTURN` — часть одной попытки | Android, Dart |
| `DTLS` | **HydraCore**: `reconnectPath` | Android, Dart |
| `QUIC` | **HydraCore**: `reconnectPath` | Android, Dart |
| `NETWORK` | **Android**: `HydraBoxDefaultNetworkMonitor` через команду `NETWORK_CHANGED`. Ядро не повторяет: per-generation контекст отменяет попытки старой сети | `reconnectPath` обязан выйти по отмене контекста; Dart |
| `PROCESS` | **Android**: `CoreRuntimeService.reconcile()` при `wantRunning == true`, предел `recoveryAttempt <= 2`; плюс однократный AlarmManager из `HydraBoxVpnService.onTaskRemoved` | Dart; `CoreRuntimeClient` (его rebind ограничен и не является runtime-recovery) |
| `CONFIG` | **NONE / USER.** Невалидный или устаревший план не повторяется автоматически никогда. Dart `_scheduleInvalidOutboundRetry` — не retry сбоя, а однократная пересборка плана без неработающего outbound | все остальные |

## 2.7 Контракт 6 — Process death model

```
1. desired := readDesiredRuntime()
   файла нет либо wantRunning == false:
        runtimeState := STOPPED ; emit snapshot ; КОНЕЦ
2. recoveryAttempt > 2:
        wantRunning := false
        runtimeState := FAILED(runtime.recovery.exhausted) ; emit ; КОНЕЦ
3. config := singbox-config.json
   не читается либо Libbox.checkConfig бросил:
        quarantine ; wantRunning := false
        runtimeState := FAILED(config.quarantined) ; emit ; КОНЕЦ
   sha256(config) != desired.configSha256:
        wantRunning := false
        runtimeState := FAILED(config.stale) ; emit ; КОНЕЦ
4. START(plan=config, mode=desired.mode, origin=recovery)
        recoveryAttempt++ ; runtimeState := RECOVERING
5. emit snapshot с НОВЫМ processEpoch
```
UI-сторона: получив снимок с `processEpoch`, отличным от запомненного, обязана
обнулить `RuntimeOperationCoordinator`, latency-кэши, `pendingVkCaptchaId` и
`pendingVkCaptchaUri`, `_runtimeStartupUrlTestGate`, и построить фазу заново из
снимка. Ни одно решение, принятое до смены epoch, не переносится.

## 2.8 Контракт 7 — CAPTCHA и user-action model

- Challenge публикует **только

** `vk.solveVKCaptcha` через `PublishRuntimeChallenge`.

  Health его не публикует; `healthSnapshot` выводит `waiting_user` из
  `CurrentRuntimeChallenge()`.- Наличие `challenge` **не** меняет `runtimeState`: оно перевооружает таймер на
  `CHALLENGE_DEADLINE` и меняет только проекцию UI.- Отмена возможна **только** пользователем через команду
  `CANCEL_RUNTIME_CHALLENGE`, которая теперь несёт `runtimeGeneration`; при
  несовпадении — `runtime.challenge.stale`.- После `ClearRuntimeChallenge` `Client.lastFailure` **обязан** быть сброшен, иначе
  снимки продолжают нести captcha-failure. Это и есть наблюдавшийся «auth_failed
  после закрытия капчи».- `terminal` для отменённой CAPTCHA равен `true`: автоматического повтора нет.- Поведение при смене сети во время CAPTCHA установлено `HB-EXP-E12` (§8.1):
  путь в стадии CAPTCHA ещё не находится в `r.paths`, поэтому `RebindNetwork` его не
  закрывает и CAPTCHA переживает смену сети. Целевое поведение: отмена
  `generationCtx` в `HC-RW-004` отменяет и dial, и challenge, а публикация
  `code=vk.captcha.cancelled` с `terminal=false` выполняется в том же PR.

## 2.9 Контракт 8 — DNS failure model

```
app query -> dns.Router (rules) -> upstream transport (DoH/DoT/UDP)
                                       └─ resolve server hostname
                                             -> bootstrap = dns-local
                                                 -> HydraBoxLocalResolver
                                                     -> physical network (bound, ng)
```

- `route.default_domain_resolver = 'dns-local'` остаётся: bootstrap не должен
  зависеть от публичной UDP/DoT-доступности.- Каждый платформенный запрос захватывает пару (`Network`, `networkGeneration`) и
  регистрирует `CancellationSignal` в реестре монитора; рост `ng` отменяет запрос
  немедленно (**R17**).- Ошибки DNS маркируются доменом `DNS` и кодом из группы `dns.*`; они никогда не
  сводятся к общему «connection failed».- Пока `runtimeState != RUNNING`, DNS-запросы не должны идти в `dns-remote`, у
  которого `detour = <selected proxy>`. Способ реализации определяется
  `HB-EXP-E5`; до его выполнения `HB-RW-028` остаётся `BLOCKED`.- Значение таймаута ожидания в `HydraBoxLocalResolver` (сейчас 15 s) **не меняется**:
  это оптимизация, `DEFERRED`.

## 2.10 Контракт 9 — Probe isolation model- Отдельный `probeExecutor` (второй single-thread) в `CoreRuntimeService`.

  `START_PROBE` и `CANCEL_PROBE` не попадают в serializer и не могут задержать `STOP`.- Probe пишет **только** `probeSessions`, `probeResults`, `probeLastError`. Никогда —
  `runtimeState`, `mode`, `lastError`, `selectedOutbounds`, `pendingSelection`,
  `desiredRuntime`, `runtimeGeneration`.- Матрица выбора режима, заменяет `selectProbeExecutionMode`:

| runtime | compiledConfig | режим |
|---|---|---|
| работает | есть | `MANAGED`, если outbound есть в активном плане; иначе `REJECT(probe.requires_stopped_runtime)` |
| работает | нет | `MANAGED` |
| остановлен | есть | `EPHEMERAL` |
| остановлен | нет | `REJECT(probe.ephemeral.missing_plan)` |

- Ephemeral probe отменяется при `STOP` и при переходе `STOPPED - >STARTING`.
  Managed probe отменяется при `NETWORK_CHANGED` и при смене `runtimeGeneration`.- `managedProbeAliases` очищается при завершении, при отмене и при смене
  `runtimeGeneration`.- `CoreProbeService` (валидация кандидата ядра) **удаляется вместе с процессом
  `:core_probe`** задачей `HB-RW-041`, поэтому имя больше ни с чем не конкурирует
  (решение C17). После этого в приложении остаётся два процесса: `default` и `:core`.

## 2.11 Контракт 10 — Notification и UI projection model- Статус-строка foreground-нотификации — **проекция `runtimeState`**, а не аргумент

  от того, кто запускает libbox: STARTING и RECOVERING → «Connecting»,
  RUNNING → «Connected», STOPPING → «Disconnecting», FAILED → «Failed».
  `showForeground("Connected")` из места, где libbox только что поднялся, запрещено
  (**R10**).- Presentation (заголовок, латентность, тексты, лейблы) остаётся владением UI и
  доставляется utility-вызовом; на статус она не влияет.- Cadence наблюдения (foreground/background/screen) влияет **только** на частоту
  выдачи событий из `SingboxController` и никогда не пересоздаёт `CommandClient`
  (**R16**).- Quick Settings tile читает снимок и подписывается на события на время
  `onStartListening`: ни файлов, ни таймеров.- Фаза UI вычисляется одной чистой функцией из снимка (**R11**).

---

# §3. BLOCKING EXPERIMENTS AS FIRST-CLASS TASKS

Классы:

- **A — STATIC.** Доказывается ревью исходного кода. Устройство не нужно.
- **B — AUTOMATED RUNTIME.** Доказывается тестом, который можно написать и
  запустить без устройства (JVM unit, Go test).
- **C — DEVICE RUNTIME.** Нужен подключённый Android-девайс
  (`./gradlew :app:connectedAndroidTest`) либо ручной прогон с `adb logcat`.Правило: **пока эксперимент не выполнен и его evidence не записан в этот файл,ни одна зависящая задача не может иметь статус READY.** Формулировок вида«агент решает» в плане нет: у каждого эксперимента ровно две ветки, и каждаяветка называет конкретную задачу.

## 3.0 Матрица «эксперимент → задачи» (нормативная)

| EXP | Класс | Статус | Ветка | Блокирует задачи |
|---|---|---|---|---|
| `HB-EXP-E1` | A | **RESOLVED** | P2 | `HB-RW-005` снято, `HB-RW-007` снято |
| `HB-EXP-E2A` | A | **RESOLVED** | P1 | `HB-RW-009` снято |
| `HB-EXP-E2B` | C | **RESOLVED** | P2 | `HB-RW-009`, `HB-RW-010` |
| `HB-EXP-E3` | C | **RESOLVED** | P1 (решение тимлида) | `HB-RW-022` |
| `HB-EXP-E4` | A | **RESOLVED** | P1 плюс находка | `HB-RW-018` снято |
| `HB-EXP-E5` | C | **RESOLVED** | P1 (решение тимлида) | `HB-RW-028` |
| `HB-EXP-E6` | A | **RESOLVED** | P2 | `HB-RW-020` снято |
| `HB-EXP-E7` | C | ожидается | — | `HB-RW-025` |
| `HB-EXP-E8` | C | ожидается | — | post-gate решение о heartbeat, задачи нет |
| `HB-EXP-E9` | C | ожидается | — | `HB-RW-026` |
| `HB-EXP-E10` | A | **RESOLVED** | P1 | `HC-RW-004` снято |
| `HB-EXP-E11` | C | ожидается | — | `HB-RW-005` |
| `HB-EXP-E12` | A | **RESOLVED** | P2 | `HC-RW-006` сливается с `HC-RW-004` |

Шесть экспериментов класса A выполнены при составлении этого документа; их evidenceзаписан в §8.
1. Осталось семь блокеров, все класса C, все требуют устройства.

---

## HB-EXP-E1 — Может ли `getRuntimeSnapshot` провалиться при здоровом ядре

**CLASS:** A (STATIC). **REPOSITORY:** hydrabox + hydracore (чтение).

**STATUS:** **RESOLVED 2026-08-26 — ветка P2.** Evidence: §8.1.

**QUESTION.** Существует ли путь, на котором
`CoreRuntimeService.verifyHealthAndCompleteStart` получает отказ от
`SingboxController.getRuntimeSnapshot` при полностью здоровом native runtime, и тем
самым вызывает `failStartAndRollback`, уничтожая работающий VPN?

**WHY BLOCKING.** Если такой путь есть, задача «единственный супервизор старта»
(`HB-RW-007`) уберёт Dart-страховку, и ложный провал станет наблюдаемым как
окончательный FAILED. Нужно знать, требуется ли устранить путь в той же пачке.

**INSTRUMENTATION.** Никакой. Только чтение:
`android/.../singbox/SingboxController.kt` (`connectClient`,
`withPersistentCommandClient`, `getRuntimeSnapshot`, `setRunning`,
`markServiceStarted`), `android/.../singbox/CommandClientLifecycle.kt`
(`beginConnect`, `onConnected`, `acceptsEvents`, `claimReconnect`),
`hydracore/experimental/libbox/command_client.go` (`Connect`, `dispatchCommands`).

**PROCEDURE.**1. Установить, синхронен ли `CommandClient.Connect()`: вызывает ли он
   `handler.Connected()` до возврата.
2. Установить порядок задач в `SingboxController.commandExecutor`: попадает ли
   `connectClient()` в очередь раньше `getRuntimeSnapshot()` при последовательности
   `markServiceStarted` → `awaitRunning` → `verifyHealthAndCompleteStart`.
3. Перечислить все ветки, на которых `beginConnect(shouldConnect=true)`
   возвращает `null` (то есть подключение не выполняется), и определить,
   достижима ли любая из них сразу после `markServiceStarted`.
4. Зафиксировать вывод одним абзацем в этом файле, в разделе
   «EVIDENCE LOG» (§8), с точными именами функций.

**PRELIMINARY STATIC FINDING (подлежит подтверждению агентом).**
`Connect()` синхронен: `dialWithRetry` → `handler.Connected()` → `dispatchCommands()`
→ return. Поэтому обычного race по асинхронности нет: `connectClient` завершает
подключение внутри своей задачи, а `getRuntimeSnapshot` — следующая задача того же
single-thread executor. Опасен только путь `beginConnect → null`: при
`reconnectPendingEpoch != null` или `state != DISCONNECTED` подключение молча не
происходит, и следующая задача бросает
`IllegalStateException("HydraCore command client is not connected")`.

**EXPECTED EVIDENCE.** Список путей `beginConnect → null` с указанием, достижим ли
каждый после `markServiceStarted`.

**PASS** (ни один путь недостижим): ветка **P1** — `HB-RW-007` выполняется какописано, без дополнительных изменений.

**FAIL** (хотя бы один достижим): ветка **P2** — в `HB-RW-005` дополнительно
требуется: стадия `command_client` в `LaunchTask` обязана **дождаться**
подтверждённого подключения (`acceptsEvents == true`) с собственным подшагом и
таймаутом внутри `START_DEADLINE`, а неудача подключения диагностики не должна
приводить к `failStartAndRollback` — только к событию
`START stage=command_client result=fail`, без разрушения runtime. Формулировка
ветки P2 добавляется в `HB-RW-005` как обязательный подпункт.

**CLEANUP.** Нет (инструментирование не добавлялось).

**BLOCKED TASK IDS.** `HB-RW-005`, `HB-RW-007`.

---

## HB-EXP-E2

A — Где именно блокируется старт**CLASS:** A (STATIC). **REPOSITORY:** hydracore (чтение).

**STATUS:** **RESOLVED 2026-08-26 — ветка P1.** Evidence: §8.1.

**QUESTION.** Какая именно операция внутри
`HydraBoxService.startOrReloadInternal → server.startOrReloadService(...)`
удерживает поток десятки секунд: `box.Start(StateStart)`, `openTun`,
`box.Start(StatePostStart)` или `call.Connect`?

**WHY BLOCKING.** `HB-RW-009` (отменяемый старт) проектируется по-разному в
зависимости от того, отменяема ли блокирующая операция по контексту.

**INSTRUMENTATION.** Нет. Чтение: `hydracore/box.go` (`Start`, стадии),
`experimental/libbox/command_server*.go` (`startOrReloadService` → `startService`),
`protocol/call/outbound.go` (`Start`, `startHandler`, `awaitBridge`),
`transport/call/config.go` (`Connect`),
`transport/call/vk-parasite/client.go` (`ConnectClient`), `quic_relay.go` (`Start`).

**PROCEDURE.**1. Проследить, в какой стадии `adapter.StartStage` вызывается
   `protocol/call.Outbound.Start` и является ли `startHandler` горутиной
   (то есть возвращает ли `Start` управление немедленно).
2. Установить, ждёт ли `box.Start` завершения `startHandler`.
3. Установить, ждёт ли `QUICRelay.Start()` установления путей (`ready` канал)
   или возвращает управление сразу.
4. Зафиксировать: возвращается ли `startOrReloadService` **до** появления
   первой QUIC-линии.

**PRELIMINARY STATIC FINDING.** `Outbound.Start` при `StartStatePostStart` делает
`go o.startHandler()` и возвращает; `ConnectClient` вызывает `relay.Start()`,
который запускает N горутин `initPath` и не ждёт их. Значит `startOrReloadService`
**не** блокируется на подъёме линий, и наблюдаемая длительная блокировка (если она
есть) относится к `openTun` или к более ранним стадиям `box.Start`, а не к
vk-parasite.

**EXPECTED EVIDENCE.** Цепочка вызовов с указанием, какая стадия синхронна, акакая асинхронна.

**PASS** (`startOrReloadService` возвращается быстро, до подъёма линий):
ветка **P1** — `HB-RW-009` реализует отмену как «выставить флаг +
`closeService()` из потока отмены», потому что окно блокировки короткое, а долгое
ожидание READY уже находится вне JNI-вызова.

**FAIL** (`startOrReloadService` синхронно ждёт линии или иным образом держит поток
минуты): ветка **P2** — `HB-RW-009` дополнительно требует `HB-EXP-E2B` для
подтверждения, что `closeService()` прерывает вызов; при отрицательном результате
`HB-RW-009` заменяется на `HC-RW-007` (дедлайн внутри `call.Connect` на стороне
ядра), а Android-часть ограничивается неблокирующим `cancel`-флагом.

**CLEANUP.** Нет.

**BLOCKED TASK IDS.** `HB-RW-009`.

---

## HB-EXP-E2

B — Прерывает ли `closeService()` висящий `startOrReloadService()`**CLASS:** C (DEVICE RUNTIME). **REPOSITORY:** hydrabox. **STATUS:** READY(зависит от `HB-EXP-E2A` только по смыслу, не по исполнению).

**QUESTION.** Если `HydraBoxService.startOrReloadInternal` находится внутри
блокирующего `server.startOrReloadService(...)`, прерывает ли вызов
`server.closeService()` из другого потока это ожидание, и за какое время?

**WHY BLOCKING.** `HB-RW-009` (отменяемый старт) построен на предположении, что
`closeService()` — точка прерывания. Если предположение ложно, отмена старта на
стороне Android невозможна, и требуется дедлайн внутри ядра (`HC-RW-007`).

**INSTRUMENTATION (временное).**1. Инструментальный тест
   `android/app/src/androidTest/kotlin/io/hydrabox/client/runtime/LaunchCancellationInstrumentedTest.kt`.
2. Профиль-фикстура с `type=call, mode=vk_parasite`, у которого `server` указывает
   на маршрутизируемый, но не отвечающий IP (например `203.0.113.1`), чтобы
   гарантировать длительную стадию соединения.
3. Временные `HydraBoxDiagnostics.event("EXP2B", ...)` вокруг
   `server.startOrReloadService` (before/after с `elapsed_ms`) и вокруг
   `server.closeService()` из потока отмены.

**ЧТО УЖЕ ИЗВЕСТНО СТАТИЧЕСКИ (из `HB-EXP-E2A`).**
`daemon/started_service.go:StartOrReloadService` держит `serviceAccess` только на
время создания инстанса и **освобождает его перед `instance.Start()`**;
`CloseService()` требует статус из множества `{STARTING, STARTED}` и берёт тот же
`serviceAccess`. Следовательно во время длинного `instance.Start()` статус равен
`STARTING`, лок свободен, и `CloseService()` **входит без ожидания** — вопрос лишь
в том, прерывает ли `instance.Close()` уже идущий `Start()`. Побочно это означает,
что `Start()` и `Close()` могут исполняться над одним инстансом **одновременно**;
эксперимент обязан проверить, безопасно ли это.

**PROCEDURE.**

1. Запустить runtime с фикстурой через `CoreRuntimeClient.start`.
2. Через 2000 ms из отдельного потока вызвать `server.closeService()`.
3. Замерить `elapsed_ms` между вызовом `closeService()` и возвратом
   `startOrReloadService`.
4. Зафиксировать, не возникает ли при этом падения, `panic` в logcat из Go-слоя,
   утечки TUN-дескриптора либо состояния, при котором `SingboxController.running`
   остаётся `true` после возврата.
5. Повторить 5 раз; зафиксировать минимум, медиану, максимум.
6. Записать результат в §8 EVIDENCE LOG.

**EXPECTED EVIDENCE.** Пять измерений задержки возврата после `closeService()`.

**PASS** (возврат в пределах 2000 ms в каждом из 5 прогонов **и** ни одного падения
либо зависшего состояния из шага 4): ветка **P1** — `HB-RW-009` реализует
`LaunchTask.cancel()` как «выставить `cancelled`, вызвать
`commandServer?.closeService()` из потока отмены, затем `join(CLOSE_DEADLINE)`».

**FAIL** (хотя бы один прогон не вернулся в пределах 2000 ms): ветка **P2** —
`HB-RW-009` сокращается до неблокирующего флага отмены и немедленного перехода в
STOPPING; фактическое освобождение ресурсов делает `CloseTask` с `CLOSE_DEADLINE`;
дополнительно создаётся `HC-RW-007` (дедлайн внутри `call.Connect` в HydraCore), и
`HB-RW-010` получает зависимость от `HB-BUNDLE` с этой задачей. При FAIL запрещено
оставлять `join` без дедлайна.

**CLEANUP.** Удалить временные `event("EXP2B", ...)`. Инструментальный тест
**остаётся** в репозитории как regression на отмену старта, но фикстура-профиль
переносится в `test`-ресурсы и не попадает в production-ассеты.

**BLOCKED TASK IDS.** `HB-RW-009`, `HB-RW-010`.

---

## HB-EXP-E3 — Переживает ли ephemeral probe остановку runtime

**CLASS:** C (DEVICE RUNTIME). **REPOSITORY:** hydrabox. **STATUS:** RESOLVED — P1 (решение тимлида; прямое наблюдение недостижимо).

**QUESTION.** Может ли ephemeral probe (`Libbox.newStandaloneURLTestSession` через
`SingboxController.preconnectUrlTest`) продолжать работу после того, как
`stopInternal` вызвал `HydraBoxDefaultNetworkMonitor.stop()` и закрыл
`CommandServer`, и обращается ли она при этом к остановленному монитору?

**WHY BLOCKING.** `HB-RW-022` определяет, какие именно точки отмены probe нужны.
Если probe после стопа обращается к монитору, требуется явная отмена в обработчике
`STOP`, а не только при смене сети.

**INSTRUMENTATION (временное).** `HydraBoxDiagnostics.event("EXP3", stage=...)` в
`SingboxController.preconnectUrlTest` (вход, `session.run` before / after, finally),
в `HydraBoxDefaultNetworkMonitor.stop()` и в
`HydraBoxDefaultNetworkMonitor.require()`.

**PROCEDURE.**1. Runtime остановлен. Запустить ephemeral probe с `timeoutMillis = 30000` и
   недостижимым `url`.
2. Через 500 ms отправить `START`, затем через 500 ms — `STOP`.
3. Собрать `adb logcat` и последовательность `EXP3`.
4. Проверить, появляются ли записи `EXP3` и `require()` **после**
   `monitor stop`.
5. Повторить 3 раза. Записать результат в §8.

**EXPECTED EVIDENCE.** Временная последовательность событий probe относительно`monitor stop` и закрытия `CommandServer`.

**PASS** (probe не обращается к монитору после `monitor stop`): ветка **P1** —`HB-RW-022` добавляет отмену ephemeral probe только при `STOP` и при`STOPPED - >STARTING`, без дополнительных барьеров.

**FAIL** (обращается): ветка **P2** — `HB-RW-022` дополнительно требует, чтобы
`CloseTask` **дожидался** завершения отмены ephemeral probe перед закрытием
`CommandServer`, с отдельным подшагом внутри `CLOSE_DEADLINE`, и чтобы
`HydraBoxDefaultNetworkMonitor.require()` при `started == false` возвращал ошибку
вместо ожидания.

**CLEANUP.** Удалить все `event("EXP3", ...)`.

**BLOCKED TASK IDS.** `HB-RW-022`.

---

## HB-EXP-E4 — Получает ли физический кандидат `isActive == true` при активном TUN**CLASS:** A (STATIC). **REPOSITORY:** hydrabox.

**STATUS:** **RESOLVED 2026-08-26 — ветка P1 плюс дополнительная находка.** Evidence: §8.1.

**QUESTION.** Может ли какой-либо кандидат в
`HydraBoxDefaultNetworkMonitor.resolveBestNetwork` иметь `isActive == true`, пока
TUN активен, и, следовательно, имеет ли слагаемое `+40` в `networkScore`
какой-либо эффект?

**WHY BLOCKING.** `HB-RW-018` упрощает выбор сети. Удаление слагаемого без
доказательства — нарушение правила «не удалять abstraction, пока не установлено,
какую проблему он решает».

**INSTRUMENTATION.** Нет. Чтение:
`HydraBoxDefaultNetworkMonitor.resolveBestNetwork`, `isBaseUsableNetwork`,
`networkScore`, `DefaultNetworkSelection.selectDefaultNetworkCandidate` и его тест.

**PROCEDURE.**1. Установить, что `candidates` строится из `connectivity.allNetworks` с фильтром
   `isBaseUsableNetwork`, который отбрасывает `TRANSPORT_VPN`.
2. Установить, что `active = connectivity.activeNetwork` и `isActive = (active == network)`.
3. Определить, при каких условиях `activeNetwork` **не** является VPN, пока TUN
   активен (в частности split-tunnel и `bypassLan`-конфигурации).
4. Проверить, зависит ли хоть один кейс `DefaultNetworkSelectionTest` от `isActive`
   отдельно от `isValidated`.
5. Записать вывод в §8.

**PRELIMINARY STATIC FINDING.** Пока TUN активен, `connectivity.activeNetwork`
возвращает сам VPN, а VPN отфильтрован `isBaseUsableNetwork`. Значит
`isActive == true` невозможно ни для одного кандидата в этот период, и `+40` влияет
только на окно между потерей TUN и его пересозданием.

**EXPECTED EVIDENCE.** Утверждение «`isActive` достижимо / недостижимо» с перечислениемусловий и со списком тестов, которые от него зависят.

**PASS** (недостижимо при активном TUN и ни один тест от него не зависит):
ветка **P1** — `HB-RW-018` удаляет слагаемое `isActive` из `networkScore`, оставля
я     поле `isActive` в
`DefaultNetworkCandidate` (оно  используется какfallback-признакв `selectDefaultNetworkCandidate`)
     .

**FAIL** (достижимо либо тест зависит): ветка **P2** — слагаемое `isActive`
**сохраняется без изменений**, и `HB-RW-018` ограничивается объединением двух
расчётов `resolveBestNetwork` в один. Никаких изменений в `networkScore`.

**CLEANUP.** Нет.

**BLOCKED TASK IDS.** `HB-RW-018`.

---

## HB-EXP-E5 — Попадают ли DNS-запросы в `dns-remote` до READY**CLASS:** C (DEVICE RUNTIME). **REPOSITORY:** hydrabox. **STATUS:** RESOLVED — P1 (решение тимлида).

**QUESTION.** При холодном старте профиля с `vk_parasite` попадают ли DNS-запросы в
транспорт `dns-remote` (у которого `detour = <selected proxy>`) до достижения
`runtimeState == RUNNING`, и приводит ли это к ошибкам вида `no active QUIC paths`
либо `connection timed out`?

**WHY BLOCKING.** `HB-RW-028` вводит правило «до READY не в `dns-remote`». Если
такие запросы не происходят, правило избыточно и вводить его запрещено.

**INSTRUMENTATION (временное).**1. `log.level = debug` в сгенерированном конфиге (через настройку уровня логов в UI,
   без правки `singbox_config_builder.dart`).2. `HydraBoxDiagnostics.event("EXP5", transport=<tag>, domain_hash=<sha8>)` в
   `HydraBoxLocalResolver.lookup` и `exchange`; **имя домена не логировать**, только
   первые 8 hex от sha256.

**PROCEDURE.**

1. Полная остановка приложения, очистка логов (`adb logcat -c`).
2. Холодный старт, подключение к профилю с `vk_parasite`.
3. Из логов ядра выбрать все строки `exchange` / `lookup` с указанием транспорта,
   попавшие в интервал между `CONNECT` и `READY`.
4. Посчитать, сколько из них разрешены через `dns-remote`, сколько через
   `dns-direct`, сколько через `dns-local`.
5. Повторить 5 раз на Wi-Fi и 5 раз на cellular. Записать результат в §8.

**EXPECTED EVIDENCE.** Таблица «транспорт → число запросов до READY» для 10 прогонов.

**PASS** (есть хотя бы один запрос в `dns-remote` до READY): ветка **P1** —
`HB-RW-028` реализуется: в `singbox_config_builder.dart` добавляется DNS-правило,
направляющее запросы в `dns-direct`, пока транспорт не готов. Конкретный механизм:
дополнительное правило в `dns.rules` со `action: route` на `dns-direct`, включаемое
флагом в конфиге, который `CoreRuntimeService` переключает через `RELOAD` при
достижении READY, — **только** если это не требует reload на каждом старте; если
требует, применяется вариант P1b: `dns-remote` получает
`domain_resolver: dns-local` и не используется как `final` до READY. Выбор между P1
и P1b определяется наличием в логах реального reload; агент `HB-RW-028` обязан
зафиксировать выбор в §8.

**FAIL** (ни одного запроса в `dns-remote` до READY во всех 10 прогонах):
ветка **P2** — `HB-RW-028` **отменяется** и удаляется из плана.
`singbox_config_builder.dart` не меняется. В §8 фиксируется, что наблюдавшийся
`lookup dns.cloudflare.com: connection timed out` относится к bootstrap-пути
`dns-local`, и его закрывает `HB-RW-027` (отмена по generation).

**CLEANUP.** Удалить `event("EXP5", ...)`, вернуть уровень логов.

**BLOCKED TASK IDS.** `HB-RW-028`.

---

## HB-EXP-E6 — Есть ли в libbox push-канал для transport health

**CLASS:** A (STATIC). **REPOSITORY:** hydracore.

**STATUS:** **RESOLVED 2026-08-26 — ветка P2.** Evidence: §8.1.

**QUESTION.** Существует ли в текущем `experimental/libbox` способ получать
`TransportHealthSnapshot` событием (подписка, callback, stream), или единственный
доступ — синхронный `HydraCoreTransportState()`?

**WHY BLOCKING.** `HB-RW-020` должен либо заменить `transportHealthPoll` подпиской,
либо оставить polling, ограничив его STARTING и RECOVERING. Это два разных diff-а.

**INSTRUMENTATION.** Нет. Чтение: `experimental/libbox/hydracore_capabilities.go`,
`command_server.go`, `command_client.go` (список `CommandLog`, `CommandStatus`,
`CommandRuntimeEvents`, `setRuntimeEventHandler`), `RuntimeEvents` и его schema.

**PROCEDURE.**1. Перечислить все команды, поддерживаемые `CommandClient`, и содержимое
   `RuntimeEvents`.
2. Установить, содержит ли `RuntimeEvents` transport-health или только
   groups и urlTestSessions.
3. Установить, можно ли добавить health в `RuntimeEvents` **аддитивно**, не меняя
   `runtime.snapshot_schema_version` (**R14**).
4. Записать вывод в §8.

**EXPECTED EVIDENCE.** Список полей `RuntimeEvents` и утверждение о наличии либоотсутствии health-канала, плюс оценка возможности аддитивного добавления.

**PASS** (push-канал есть либо может быть добавлен аддитивно): ветка **P1** —
создаётся `HC-RW-008` (публикация health в `RuntimeEvents` аддитивно), затем
`HB-RW-020` подписывается на него и **полностью удаляет** `transportHealthPoll`.

**FAIL** (канала нет и аддитивно добавить нельзя без смены версии схемы):
ветка **P2** — `HB-RW-020` сохраняет polling, но переводит его на
`ScheduledExecutorService`, публикующий INTERNAL EVENT `HEALTH`, и **вооружает его
только в STARTING и RECOVERING**, снимая в STOPPED, RUNNING и FAILED. Интервал
250 ms **не меняется** (это оптимизация).

**CLEANUP.** Нет.

**BLOCKED TASK IDS.** `HB-RW-020`.

---

## HB-EXP-E7 — Снимается ли пауза libbox без `server.wake()`**CLASS:** C (DEVICE RUNTIME). **REPOSITORY:** hydrabox. **STATUS:** READY.

**QUESTION.** После потери и возврата сети, а также после длительного пребывания в
фоне с погашенным экраном, восстанавливается ли трафик без вызова `server.wake()`
из `HydraBoxService.requestRuntimeRecovery`?

**WHY BLOCKING.** `HB-RW-025` удаляет `requestRuntimeRecovery` и все четыре его
триггера. Если `NetworkWake()` не вызывается сам, удаление приведёт к «немому» VPN
после выхода из doze.

**INSTRUMENTATION (временное).** Сборка-эксперимент, в которой
`HydraBoxService.requestRuntimeRecovery` заменён на запись
`event("EXP7", stage=suppressed, source=<source>)` без выполнения тела. Прочий код
не меняется. Ветка эксперимента **не мержится**.

**PROCEDURE.**

1. Три устройства: одно Android 8–12, одно 13–14, одно Xiaomi/HyperOS либо realme.
2. Сценарий M09: Wi-Fi → отключить обе сети на 60 s → включить cellular.
   Проверить восстановление трафика без вмешательства в течение 30 s.
3. Сценарий M04: Home, экран выключен, 10 минут. Затем проверить, что фоновое
   приложение получает данные **до** открытия HydraBox.
4. Сценарий: вход и выход из doze (`adb shell dumpsys deviceidle force-idle`,
   затем `unforce`), проверить трафик.
5. Каждый сценарий по 3 повтора на каждом устройстве. Записать результат в §8.

**EXPECTED EVIDENCE.** Матрица «устройство × сценарий → трафик восстановился да/нет»плюс наличие строк `NETWORK` в логе в момент восстановления.

**PASS** (трафик восстанавливается во всех прогонах на всех устройствах):
ветка **P1** — `HB-RW-025` выполняется полностью: удаляются broadcast receiver,
`requestRuntimeRecovery`, `RuntimeRecoveryGate`, `recoveryExecutor`,
`updateDeviceIdleMode`; `RuntimeRecoveryGateTest` удаляется как тест удалённого кода.

**FAIL** (хотя бы один прогон не восстановился): ветка **P2** —
`requestRuntimeRecovery` **сохраняется**, но сужается до одного триггера
`device_idle_exit` и до одного действия `server.wake()`; вызовы
`HydraBoxDefaultNetworkMonitor.start()` и `reassertDefaultInterface` из него
удаляются (их роль берёт `NETWORK_CHANGED`); `RuntimeRecoveryGate` и его тест
остаются. Триггеры `SCREEN_ON`, `USER_PRESENT`, `task_removed` удаляются в любом
случае, потому что для них ветка FAIL не даёт обоснования.

**CLEANUP.** Ветка эксперимента удаляется целиком, в main не попадает.

**BLOCKED TASK IDS.** `HB-RW-025`.

---

## HB-EXP-E8 — Сколько раз heartbeat находит то, чего не дал callback

**CLASS:** C (DEVICE RUNTIME, 24 часа). **REPOSITORY:** hydrabox. **STATUS:** READY.

**QUESTION.** За 24 часа реальной работы сколько раз каждая из четырёх ветвей
`HydraBoxDefaultNetworkMonitor.heartbeatTick` обнаружила расхождение, которому
**не** предшествовал Android-callback в течение предыдущих 30 s?

**WHY BLOCKING.** Никакую задачу не блокирует. Является предусловием для
post-gate-решения об удалении heartbeat. Пока evidence нет, heartbeat **остаётся**
и в `HB-RW-018` не удаляется.

**INSTRUMENTATION (постоянное, входит в `HB-RW-001`).**
`event("NETWORK", trigger=callback

|heartbeat|launch, branch=<divergence|lost_selectable|lost_active|stale_iface|noop>, ms_since_last_callback=<n>)`.
Это не временный инструмент: событие `NETWORK` предусмотрено §Q.2 аудита.

**PROCEDURE.**1. Три устройства, обычное пользование, 24 часа, VPN включён.
2. Экспортировать логи, посчитать по каждой ветке число событий
   `trigger=heartbeat` с `ms_since_last_callback >30000`.
3. Записать результат в §8 в виде таблицы «устройство × ветка → число».

**EXPECTED EVIDENCE.** Таблица частот по четырём ветвям на трёх устройствах.

**PASS** (сумма по всем устройствам равна нулю): ветка **P1** — после прохождения
gate создаётся отдельная задача на удаление heartbeat. До gate — не удалять.

**FAIL** (сумма больше нуля): ветка **P2** — heartbeat остаётся навсегда как
триггер слепка; в `HYDRABOX_RUNTIME_REWORK_PLAN.md` §W критерий G13 считается
выполненным для heartbeat с ссылкой на эту запись.

**CLEANUP.** Нет; инструментирование постоянное.

**BLOCKED TASK IDS.** нет.

---

## HB-EXP-E9 — Совпадают ли regex-срабатывания с `failureDomain=NETWORK`**CLASS:** C (DEVICE RUNTIME). **REPOSITORY:** hydrabox. **STATUS:

**BLOCKED(`HB-BUNDLE-002`) — требует ядра, публикующего `failure.domain`.

**QUESTION.** Совпадают ли ситуации, в которых срабатывает
`SingboxController.INTERFACE_DIAL_FAILURE_REGEX` (порог 4 за 8 s), с ситуациями,
в которых ядро сообщает `failure.domain == NETWORK`?

**WHY BLOCKING.** `HB-RW-026` удаляет лог-скрапинг. Удалять его можно только если
существует эквивалентный явный сигнал.

**INSTRUMENTATION (временное).** В `maybeReassertDefaultInterfaceFromCoreLog`
добавить `event("EXP9", reason=<reason>, failures=<n>)` **и отключить фактическое
действие** (`reassertDefaultInterface` не вызывать), оставив только запись.
Параллельно писать `event("EXP9", source=health, domain=<domain>)` при получении
health со `domain == NETWORK`.

**PROCEDURE.**1. 50 handover-ов Wi-Fi ↔ cellular на трёх устройствах, включая один
   Xiaomi/HyperOS либо realme.
2. Дополнительно 10 сценариев «Wi-Fi без интернета» (точка доступа без uplink).
3. Сопоставить по времени: для каждого regex-срабатывания найти health-событие с
   `domain == NETWORK` в окне ±5 s.
4. Записать в §8: число regex-срабатываний, число покрытых health-событием,
   число не покрытых.

**EXPECTED EVIDENCE.** Три числа плюс список непокрытых случаев с их `reason`.

**PASS** (все regex-срабатывания покрыты health-событием): ветка **P1** —
`HB-RW-026` удаляет `maybeReassertDefaultInterfaceFromCoreLog`,
`classifyCoreInterfaceFailure`, `recordInterfaceDialFailure`,
`clearInterfaceDialFailures`, `INTERFACE_DIAL_FAILURE_REGEX`,
`lastNoInterfaceReassertUptimeMs`, `interfaceDialFailureUptimes`.

**FAIL** (есть непокрытые): ветка **P2** — лог-скрапинг **сохраняется**, но его
действием становится не `reassertDefaultInterface`, а публикация INTERNAL EVENT
`NETWORK_RECHECK`, обрабатываемого монитором как ещё один триггер слепка (§2 L.2).
Regex остаётся, `HB-RW-026` переформулируется как «заменить действие», а не
«удалить».

**CLEANUP.** Удалить `event("EXP9", ...)`, вернуть фактическое действие на время до`HB-RW-026`.

**BLOCKED TASK IDS.** `HB-RW-026`.

---

## HB-EXP-E10 — Можно ли пробросить `networkGeneration` в `InterfaceUpdated`**CLASS:** A (STATIC). **REPOSITORY:** hydracore.

**STATUS:** **RESOLVED 2026-08-26 — ветка P1.** Evidence: §8.1.

**QUESTION.** `adapter.InterfaceUpdateListener.InterfaceUpdated()` не имеет
параметров, а `route.NetworkManager.ResetNetwork()` вызывает его без контекста.
Существует ли способ доставить `networkGeneration` до
`protocol/call.Outbound.InterfaceUpdated` → `bridge.RebindNetwork(gen)`, не меняя
сигнатуру интерфейса, унаследованного от upstream sing-box?

**WHY BLOCKING.** `HC-RW-004` вводит `RebindNetwork(gen)` и generation-guard.
Без источника generation внутри ядра guard бессмыслен.

**INSTRUMENTATION.** Нет. Чтение: `adapter/network.go`, `route/network.go`
(`ResetNetwork`, `notifyInterfaceUpdate`, `networkInterfaces`), все реализации
`InterfaceUpdated` в `protocol/*`, `common/hydracore/*`.

**PROCEDURE.**1. Установить, кто и когда вызывает `NetworkManager.ResetNetwork`.
2. Установить, доступен ли внутри `notifyInterfaceUpdate` идентификатор,
   монотонно растущий при каждом обновлении интерфейса (например счётчик
   обновлений либо `defaultInterface.Index` в паре с именем).
3. Проверить вариант A: Android пишет `networkGeneration` в
   `common/hydracore` (новая функция `SetNetworkGeneration(gen)`), а
   `call.Outbound.InterfaceUpdated` читает её оттуда. Оценить, не нарушает ли это
   **R14** (это не wire format, а внутренний process-global — не нарушает).
4. Проверить вариант B: расширение интерфейса в форке. Оценить объём: число
   реализаций `InterfaceUpdated`, которые придётся менять.
5. Записать вывод в §8 с числом затронутых файлов для каждого варианта.

**EXPECTED EVIDENCE.** Для варианта A — существует ли уже подходящее место в`common/hydracore`; для варианта B — точное число реализаций `InterfaceUpdated`.

**PASS** (вариант A применим): ветка **P1** — `HC-RW-004` реализует вариант A:
`common/hydracore` получает `SetNetworkGeneration(uint64)` /
`CurrentNetworkGeneration()`, Android вызывает первую через новый libbox-экспорт
**аддитивно**, `Outbound.InterfaceUpdated` читает вторую и передаёт в
`RebindNetwork(gen)`.

**FAIL** (вариант A неприменим): ветка **P2** — `HC-RW-004` реализует вариант B:
интерфейс расширяется методом `InterfaceUpdatedWithGeneration(uint64)` с
default-реализацией через type assertion, чтобы не менять существующие реализации;
`route.NetworkManager` вызывает расширенный метод при его наличии.

**Запрещено** использовать guard по времени вместо generation.

**CLEANUP.** Нет.

**BLOCKED TASK IDS.** `HC-RW-004`.

---

## HB-EXP-E11 — Фактическая длительность стадии `network_wait`**CLASS:** C (DEVICE RUNTIME). **REPOSITORY:** hydrabox.

**STATUS:** BLOCKED(`HB-RW-002`) — требует уже внедрённых событий `START stage=`.

**QUESTION.** Какова фактическая длительность стадии ожидания сетевого интерфейса
(`awaitUsableDefaultInterface` плюс до 5 retry по 1500 ms) при холодном старте на
Wi-Fi и на cellular?

**WHY BLOCKING.** `HB-RW-005` назначает единый `START_DEADLINE`. Если реальная
длительность `network_wait` близка к 10 s, дедлайн 45 s оставляет транспорту всего
35 s, и это надо знать заранее, а не обнаружить в поле.

**INSTRUMENTATION.** Постоянное, внедряется `HB-RW-002`:`event("START", stage=network_wait, result=ok|fail, elapsed_ms=<n>, attempt=<n>)`.

**PROCEDURE.**

1. 50 холодных подключений на Wi-Fi и 50 на cellular, на трёх устройствах.
2. Дополнительно 10 подключений сразу после включения самолётного режима и обратно.
3. Посчитать распределение `elapsed_ms`: медиана, P95, максимум, число случаев
   `attempt >0`.
4. Записать в §8.

**EXPECTED EVIDENCE.** Медиана, P95, максимум `elapsed_ms` и доля прогонов с retry.

**PASS** (P95 <= 3000 ms): ветка **P1** — `START_DEADLINE = 45 s` принимается какесть, стадия `network_wait` входит в него.

**FAIL** (P95 >3000 ms): ветка **P2** — `START_DEADLINE` остаётся 45 s, но стадия`network_wait` получает **собственный внутренний предел 8 s**, после которого`LaunchTask` публикует `LAUNCH_FAILED(domain=NETWORK, code=network.no_interface)`,не дожидаясь общего дедлайна. Число retry не увеличивается и не уменьшается(это оптимизация).

**CLEANUP.** Нет; инструментирование постоянное.

**BLOCKED TASK IDS.** `HB-RW-005`.

---

## HB-EXP-E12 — Что происходит с CAPTCHA при смене сети

**CLASS:** A (STATIC). **REPOSITORY:** hydracore.

**STATUS:** **RESOLVED 2026-08-26 — ветка P2.** Evidence: §8.1.

**QUESTION.** При `RebindNetwork` во время активной CAPTCHA отменяется ли
`challengeContext`, и получает ли UI осмысленное событие, или challenge исчезает
молча?

**WHY BLOCKING.** `HC-RW-006` (сообщать `vk.captcha.cancelled` при смене сети)
имеет смысл только если отмена действительно происходит.

**INSTRUMENTATION.** Нет. Чтение: `transport/call/vk/vk_auth.go`
(`solveVKCaptcha`, происхождение `ctx`), `turn_credentials.go` (`Fetch`),
`transport/call/vk-parasite/client.go` (`DialPath`, `dialTrackedPath`),
`quic_relay.go` (`initPath`, `addPath`, `watchPath`, `reconnectPath`,
`RebindNetwork`, `Close`).

**PROCEDURE.**1. Установить, из какого контекста происходит `ctx` в `solveVKCaptcha`
   (проследить `initPath` → `dialPath(pathCtx, ...)` → `Credentials(ctx, ...)`).
2. Установить, какие пути закрывает `RebindNetwork`: только элементы `r.paths` или
   также ещё не добавленные (то есть находящиеся в процессе dial).
3. Определить, попадает ли путь, находящийся в стадии CAPTCHA, в `r.paths`.
4. Записать вывод в §8.

**PRELIMINARY STATIC FINDING.** `initPath` добавляет путь в `r.paths` только
**после** успешного `dialPath`. CAPTCHA возникает внутри `dialPath`, до `addPath`.
Значит путь в стадии CAPTCHA **не находится** в `r.paths`, и `RebindNetwork`,
который итерируется по `r.paths`, его не закрывает и его контекст не отменяет.
Следствие: CAPTCHA **переживает** смену сети, а параллельно `reconnectPath` уже
дозванивается по новой сети. Это же означает, что `RebindNetwork` вообще не отменяет
ни один in-flight dial — что независимо подтверждает необходимость per-generation
`pathCtx` в `HC-RW-004`.

**EXPECTED EVIDENCE.** Утверждение о принадлежности dialing-пути к `r.paths` ио судьбе его контекста при `RebindNetwork`.

**PASS** (CAPTCHA отменяется при смене сети): ветка **P1** — `HC-RW-006`
реализуется: при отмене challenge по причине смены сети публикуется
`failure.domain=AUTH`, `code=vk.captcha.cancelled`, `terminal=false`.

**FAIL** (CAPTCHA переживает смену сети): ветка **P2** — `HC-RW-006`
переформулируется: `HC-RW-004` обязан отменять in-flight dial при смене generation,
и это автоматически отменяет challenge; `HC-RW-006` сводится к публикации
`code=vk.captcha.cancelled`, `terminal=false` в момент отмены контекста, и
объединяется с `HC-RW-004` в один PR.

**CLEANUP.** Нет.

**BLOCKED TASK IDS.** `HC-RW-006`.

---

# §4. ATOMIC AGENT TASKS

Формат каждой задачи фиксирован. Поля, отсутствующие по смыслу, помечены «—»,
а не опускаются.

Легенда `STATUS`: `READY` — можно брать; `BLOCKED(<ID>)` — сначала выполнить
указанный эксперимент или задачу.

Все `BASELINE` — HydraBox `6c4bf26` / HydraCore `9eefdec8`, если не указано иное;
задача, идущая после другой, берёт baseline с её merge-коммита.

                

---

## HB-RW-001 — Структурированные события `HB1` и словарь safe error codes

- **STATUS:** IN_PROGRESS
- **GOAL:** добавить в `HydraBoxDiagnostics` типизированный вывод событий формата
  `HB1` и закрытый словарь безопасных кодов ошибок, не меняя ни одного поведения.
- **INVARIANTS ESTABLISHED:** R18 (частично: появляется словарь), подготовка R12
- **REPOSITORY:** hydrabox
- **BASELINE:** `6c4bf26`
- **PRECONDITIONS:** нет
- **FILES / SYMBOLS:**
  - `android/app/src/main/kotlin/io/hydrabox/client/singbox/HydraBoxDiagnostics.kt` —
    добавить `fun event(name: String, vararg fields: Pair<String, Any?>)`
  - новый `android/app/src/main/kotlin/io/hydrabox/client/singbox/HydraBoxEventCodes.kt` —
    `object HydraBoxEventCodes` со списком кодов
  - новый `android/app/src/test/kotlin/io/hydrabox/client/singbox/HydraBoxEventFormatTest.kt`
- **CURRENT BEHAVIOR:** диагностика пишется свободным текстом через
  `HydraBoxDiagnostics.log(tag, message)`; коды ошибок разбросаны строковыми
  литералами по `CoreRuntimeService`.
- **TARGET BEHAVIOR:** существует `event()`, выдающий строку
  `HB1 <ts_ms ><EVENT >k=v k=v ...`; все значения — числа, enum-имена, boolean или
  hex-префиксы длиной не более 16 символов; существует `HydraBoxEventCodes` с полным
  словарём из `HYDRABOX_RUNTIME_REWORK_PLAN.md` §Q.4.
- **IMPLEMENTATION:**
  1. `event()` формирует строку и передаёт её в существующий `log("HB1", line)`,
     переиспользуя буферизацию и `HydraBoxLogSanitizer`.
  2. Значения проходят нормализацию: пробелы заменяются на `_`; значение длиннее
     64 символов обрезается; `null` даёт пропуск пары.
  3. `HydraBoxEventCodes` — `object` с `const val` для каждого кода и
     `val ALL: Set<String>`.
- **DELETE:** —
- **DO NOT CHANGE:** `log()`, `readTail`, размеры буферов, интервалы flush,
  `HydraBoxLogSanitizer`.
- **BACKWARD COMPATIBILITY:** формат существующих строк лога не меняется; экспорт
  логов продолжает работать.
- **TESTS TO ADD FIRST:** `HydraBoxEventFormatTest`:
  (а) значения не содержат пробелов; (б) `null` не попадает в вывод;
  (в) строка начинается с `HB1 `; (г) `HydraBoxEventCodes.ALL` содержит все
  константы объекта через reflection и не содержит дубликатов.
- **TESTS THAT MUST REMAIN UNCHANGED:** `HydraBoxLogSanitizerTest`.
- **VALIDATION:** `./gradlew :app:testDebugUnitTest :app:lintDebug`
- **MANUAL SCENARIO:** —
- **EXPECTED STRUCTURED LOG:** ни одного нового события в рантайме (только API).
- **NEGATIVE ASSERTIONS:** после задачи в логах не появляется ни одной новой строки
  при обычном запуске; поведение runtime не меняется.
- **ROLLBACK:** revert одного коммита; ничто от него не зависит на момент мержа.
- **DEFINITION OF DONE:** `HydraBoxEventFormatTest` зелёный;
  `./gradlew :app:testDebugUnitTest :app:lintDebug` зелёный; diff касается только
  трёх перечисленных файлов.
- **STOP CONDITIONS:** если `HydraBoxDiagnostics` окажется недоступен из процесса
  `:core` без инициализации `HydraBoxApplication.application` — остановиться и
  сообщить (это меняет план `HB-RW-002`).
- **COMMIT BOUNDARY:** один коммит, только эти три файла.
- **NEXT TASK:** `HB-RW-002`, `HC-RW-001` (независимо).

---

## HB-RW-002 — Разметка runtime-путей событиями `HB1`

- **STATUS:** READY
- **GOAL:** покрыть событиями `HB1` весь путь CONNECT → READY → STOP, смену сети и
  стадии старта, не меняя ни одного перехода состояний.
- **INVARIANTS ESTABLISHED:** подготовка R12, R18; даёт инструмент для `HB-EXP-E8`,
  `HB-EXP-E11`
- **REPOSITORY:** hydrabox
- **BASELINE:** merge `HB-RW-001`
- **PRECONDITIONS:** `HB-RW-001` смержен
- **FILES / SYMBOLS:**
  - `runtime/CoreRuntimeService.kt`: `start`, `stop`, `updateState`,
    `refreshTransportHealth`, `commandSucceeded`, `failRuntime`, `recover`
  - `runtime/CoreRuntimeService.kt`, объявление `private object CoreProcessIdentity`
    (строка рядом с началом файла): **разрешено и требуется** изменить видимость
    `private` → `internal`. Это единственное изменение видимости в задаче. Владелец,
    файл, поля и способ инициализации не меняются; ничего не переносится и не
    дублируется. Причина: `epoch` и `generation` нужны сайтам инструментирования в
    других файлах того же модуля, а сегодня объект file-private.
  - `singbox/HydraBoxService.kt`: `onStartCommand`, `startInternal`,
    `startOrReloadInternal` (все `native_start_marker` заменить на `event`),
    `stopInternal`, `requestRuntimeRecovery`
  - `singbox/HydraBoxDefaultNetworkMonitor.kt`: `notifyListenerInternal`,
    `heartbeatTick`, `updateNetwork`
  - `singbox/HydraBoxDefaultNetworkMonitor.kt`, четыре override-а внутри объекта
    `callback`: `onAvailable`, `onCapabilitiesChanged`, `onLinkPropertiesChanged`,
    `onLost` — **разрешено и требуется** добавить в них запись нового
    diagnostic-only поля (см. следующий пункт) и импорт `android.os.SystemClock`
  - `singbox/HydraBoxDefaultNetworkMonitor.kt`, объявления полей объекта:
    **разрешено и требуется** добавить одно новое приватное поле
    `private val lastAndroidCallbackElapsedMs = AtomicLong(NO_CALLBACK_YET)`
    и приватную константу `private const val NO_CALLBACK_YET = -1L`.
    Проверено на baseline `6c4bf26`: монотонного времени последнего Android-callback
    в мониторе нет вовсе — нет ни импорта `SystemClock`, ни эквивалентного поля;
    `System.currentTimeMillis()` встречается только в `awaitUsableDefaultInterface`
    (дедлайн-цикл) и в `currentInterfaceState().updatedAtMillis`, где это **время
    запроса**, а не время callback, к тому же wall-clock. Эквивалентного источника
    в других файлах модуля нет: `SingboxController.lastNoInterfaceReassertUptimeMs`
    относится к лог-скрапингу и использует `uptimeMillis`,
    `RuntimeRecoveryGate` получает время параметром.
  - `singbox/HydraBoxVpnService.kt`: `onRevoke`, `onTaskRemoved`  
- **Существующие read-only accessor-ы, используемые как есть, без изменений:**
    `SingboxController.activeRuntimeGeneration` (public, `private set`);
    `HydraBoxDefaultNetworkMonitor.currentInterfaceState(reason).generation`
    (public функция, public поле `InterfaceState.generation`);
    `HydraBoxDefaultNetworkMonitor.notificationGeneration` (только внутри самого
    монитора).
- **CURRENT BEHAVIOR:** стадии старта пишутся как
  `SingboxController.log("info", "native_start_marker phase=...")`, сетевые события —
  свободным текстом в `HydraBoxDiagnostics`.
  **Фактический baseline по доступности полей** (проверено на `6c4bf26`):
  `SingboxController.activeRuntimeGeneration` — public, доступен из всех четырёх
  файлов; `HydraBoxDefaultNetworkMonitor.currentInterfaceState(...).generation` —
  public, доступен; `CoreProcessIdentity` — `private object` в
  `CoreRuntimeService.kt`, из других файлов **недоступен**;
  `CoreRuntimeService.activeConfigSha256` — `private var` **экземпляра**, из других
  файлов недоступен и не имеет read-only accessor-а.
- **TARGET BEHAVIOR:** события `CONNECT`, `START`, `NETWORK`, `READY`, `REBIND`,
  `RECOVERY`, `STOP`, `EPOCH` публикуются согласно
  `HYDRABOX_RUNTIME_REWORK_PLAN.md` §Q.
2. Требование «каждое событие несёт все
  четыре поля» **скорректировано**: набор полей задаётся сайтом издания, потому что
  `prof` на baseline недоступен вне владельца и его получение потребовало бы либо
  plumbing, либо второго вычисления того же digest. Нормативная матрица:
  **Единое правило для `prof`, отменяющее любые иные формулировки в этой карточке.**
  Правило **файловое**, а не по имени события, потому что имена `STOP` и `RECOVERY`
  издаются из двух файлов, и правило по имени события противоречило бы физической
  доступности поля: >`prof` присутствует в **каждом** вызове `event(` внутри >`runtime/CoreRuntimeService.kt` и **ни в одном** вызове в трёх остальных файлах. >Значение — `shortHex(activeConfigSha256)`, то есть первые 8 hex, либо литерал >`none`, если digest ещё не присвоен (например в `EPOCH`, издаваемом из >`onCreate`, и в отказах валидации плана до присваивания).
  Отдельного случая для `EPOCH` больше нет: он несёт `prof=none`. Это устраняет весь
  класс расхождений «какое событие обязано нести `prof`».
  | Сайт (файл) | `ep` | `cg` | `rg` | `ng` | `prof` |
  |---|---|---|---|---|---|
  | `CoreRuntimeService.kt` — все события | обязателен | обязателен | обязателен | обязателен | **обязателен, значение может быть `none`** |
  | `HydraBoxService.kt` — все события | обязателен | обязателен | обязателен | обязателен | **не несёт** |
  | `HydraBoxDefaultNetworkMonitor.kt` — все события | обязателен | обязателен | обязателен | обязателен | **не несёт** |
  | `HydraBoxVpnService.kt` — все события | обязателен | обязателен | обязателен | обязателен | **не несёт** |
  Корреляция обеспечивается парой `ep` плюс `cg`: `cg` берётся из существующего
  счётчика `CoreProcessIdentity.generation`, который инкрементируется в
  `CoreRuntimeService.start/stop/reload/recover`, то есть однозначно привязывает
  стадии одной попытки к своей команде. Строки без `prof` относятся к той же попытке,
  что и строка `CONNECT` с тем же `ep` плюс `cg`.
  Стадия `START stage=network_wait` обязательно несёт `elapsed_ms` и `attempt`
  (нужно для `HB-EXP-E11`). Событие `NETWORK` обязательно несёт
  `trigger=callback

|heartbeat|launch`, `branch=...`, `ms_since_last_callback`
  (нужно для `HB-EXP-E8`). Значение `ms_since_last_callback` — монотонная разница в
  миллисекундах от последнего Android-callback, либо `-1`, если в этом процессе
  callback ещё не наблюдался. Источник времени на baseline отсутствует, поэтому
  задача вводит одно приватное diagnostic-only поле — см. `FILES / SYMBOLS` и
  пункт 5 в `IMPLEMENTATION`.
- **IMPLEMENTATION:**
  1. Изменить видимость `object CoreProcessIdentity` с `private` на `internal` в
     `runtime/CoreRuntimeService.kt`. Больше ничего в объекте не менять.
  2. Добавить вызовы `HydraBoxDiagnostics.event(...)` в перечисленных функциях;
     `native_start_marker`-строки заменить на `event("START", ...)`.
  3. Источник каждого поля на каждом сайте — строго следующий, новых владельцев
     состояния не вводится:   
  - `ep` — `CoreProcessIdentity.epoch.take(8)` (после смены видимости доступен
       из всех четырёх файлов модуля);   
  - `cg` — `CoreProcessIdentity.generation.get()`;   
  - `rg` — `SingboxController.activeRuntimeGeneration`;   
  - `ng` — внутри `HydraBoxDefaultNetworkMonitor` это `notificationGeneration.get()`;
       во всех остальных файлах — `HydraBoxDefaultNetworkMonitor.currentInterfaceState(reason).generation`;   
  - `prof` — **только** в `CoreRuntimeService`, во **всех** его вызовах `event(`,
       как `shortHex(activeConfigSha256)`.
  4. Ни один сайт вне `CoreRuntimeService` не вычисляет digest конфигурации
     самостоятельно и не читает `HydraBoxApplication.configFile` ради `prof`.
  4a. **Обязательные приватные хелперы форматирования** в `CoreRuntimeService.kt`.
     Аргументы `event(` должны быть простыми выражениями, поэтому форматирование
     выносится из вызова:   
  - `private fun shortHex(bytes: ByteArray): String` — первые 4 байта как 8 hex
       в нижнем регистре, либо `"none"` при пустом массиве;   
  - `private fun shortId(value: String): String` — первые 8 символов, либо
       `"none"` при пустой строке; используется для `ep`.
     В теле `event(` **запрещены** `joinToString`, `String.format`, `%02x` и любые
     иные строковые преобразования: они попадают под статическую проверку (б) и
     были причиной её падения в первой попытке. Правильно:
     `"prof" to shortHex(activeConfigSha256)`, `"ep" to shortId(processEpoch)`.
     В трёх остальных файлах `ep` формируется тем же способом через локальный
     приватный аналог `shortId`, без обращения к `CoreRuntimeService`.
  5. Добавить diagnostic-only источник для `ms_since_last_callback` в
     `HydraBoxDefaultNetworkMonitor`:   
  - объявить `private val lastAndroidCallbackElapsedMs = AtomicLong(NO_CALLBACK_YET)`
       и `private const val NO_CALLBACK_YET = -1L`;     
- **единственный writer** — четыре override-а объекта `callback`
       (`onAvailable`, `onCapabilitiesChanged`, `onLinkPropertiesChanged`, `onLost`).
       В каждом первой строкой тела выполнить
       `lastAndroidCallbackElapsedMs.set(SystemClock.elapsedRealtime())`, до любых
       других действий и до логирования. Больше нигде запись не выполняется;   
  - время монотонное: `SystemClock.elapsedRealtime()`, не `uptimeMillis` (оно
       останавливается в deep sleep) и не `System.currentTimeMillis()`;   
  - `ms_since_last_callback` вычисляется в момент издания события `NETWORK` как
       `SystemClock.elapsedRealtime() - lastAndroidCallbackElapsedMs.get()`;
       если значение поля равно `NO_CALLBACK_YET`, в событие пишется `-1`;   
  - при `trigger=callback` значение закономерно близко к нулю, потому что запись
       происходит на входе в тот же callback; величина осмысленна для
       `trigger=heartbeat` и `trigger=launch`, ради которых поле и вводится
       (`HB-EXP-E8`);   
  - поле не читается и не пишется нигде, кроме перечисленного, и не участвует ни
       в выборе сети, ни в `notificationGeneration`, ни в debounce, ни в rebind, ни в
       любом другом решении.
- **DELETE:** строки `SingboxController.log("info", "native_start_marker ...")`
  (заменяются на `event`), но **не** сам `SingboxController.log`.
- **DO NOT CHANGE:** любые условия, дедлайны, порядок вызовов, содержимое
  `RuntimeSnapshot`. Владение состоянием не меняется: `epoch`, `generation` и
  `activeConfigSha256` остаются в `CoreRuntimeService.kt`; ни новых полей, ни
  копий, ни accessor-ов на экземпляр `CoreRuntimeService` не добавляется.
  `activeConfigSha256` **остаётся `private`** — расширять его видимость запрещено.
  Новое поле `lastAndroidCallbackElapsedMs` — строго diagnostic-only: запрещено
  читать его в `updateNetwork`, `resolveBestNetwork`, `notifyListener`,
  `notifyListenerInternal`, `heartbeatTick`, `markInterfaceState`,
  `awaitUsableDefaultInterface`, `require`, `currentInterfaceState` и в любом другом
  месте, влияющем на поведение; оно не попадает ни в `InterfaceState`, ни в
  `NetworkSnapshot`, ни в `RuntimeSnapshot`. Значения `NETWORK_CHANGE_DEBOUNCE_MS` и
  интервал heartbeat не меняются.
- **BACKWARD COMPATIBILITY:** экспорт логов остаётся читаемым; удаление
  `native_start_marker` допустимо, потому что это диагностическая строка, не контракт.
- **TESTS TO ADD FIRST:** `HydraBoxEventCoverageTest` (JVM, статический): парсит
  исходники перечисленных файлов и проверяет, что
  (а) каждое из 8 имён событий встречается хотя бы один раз;
  (б) **сканируются только строковые литералы**, переданные в `event(` как ключи или
  значения; идентификаторы, имена функций и вызовы не сканируются. Запрещённые
  подстроки внутри таких литералов: `http`, `join_link`, `joinLink`, `token`,
  `password`, `secret`, `cookie`, `captcha_sid`, `success_token`. Бывшая проверка на
  подстроку `join` **отменена**: она ловила `joinToString` — стандартный способ
  форматирования hex — и делала карточку неисполнимой. Форматирование теперь вынесено
  в хелперы (пункт 4a `IMPLEMENTATION`), поэтому дополнительно проверяется, что в
  тексте вызовов `event(` не встречаются `joinToString`, `String.format` и `%02x`;
  (в) **соответствие файловой матрице**: в `CoreRuntimeService.kt` **каждый** вызов
  `event(` содержит ключ `prof`; в `HydraBoxService.kt`,
  `HydraBoxDefaultNetworkMonitor.kt` и `HydraBoxVpnService.kt` ключ `prof` не
  встречается **ни в одном** вызове `event(`. Проверка ведётся по файлу, а не по
  имени события, потому что `STOP` и `RECOVERY` издаются из двух файлов;
  (г) `activeConfigSha256` не упоминается ни в одном файле, кроме
  `CoreRuntimeService.kt`;
  (д) `lastAndroidCallbackElapsedMs` упоминается только в
  `HydraBoxDefaultNetworkMonitor.kt`, причём `.set(` — ровно четыре раза, и все четыре
  внутри объекта `callback`.
  Плюс `NetworkCallbackTimestampTest` (JVM, на чистой функции): вынести расчёт в
  `internal fun msSinceLastCallback(nowMs: Long, lastMs: Long): Long` в том же файле и
  проверить: `lastMs == -1L` даёт `-1`; `nowMs - lastMs` при нормальных значениях;
  отрицательная разница (регресс часов невозможен для `elapsedRealtime`, но проверяем
  контракт) приводится к `0`.
- **TESTS THAT MUST REMAIN UNCHANGED:** все существующие.
- **VALIDATION:** `./gradlew :app:testDebugUnitTest :app:lintDebug`
- **MANUAL SCENARIO:** M01 (connect → ready на Wi-Fi), M07 (Wi-Fi → cellular ×3):
  экспортировать логи и убедиться, что восстанавливается последовательность из
  `EXPECTED STRUCTURED LOG` этой карточки. Она является уточнением §Q.3 аудита:
  §Q.3 приведён до проверки baseline и показывает `prof` на всех строках.
- **EXPECTED STRUCTURED LOG:**  

```
  HB1 <ts> EPOCH   ep=a1b2c3d4 cg=0 rg=0 ng=0 prof=none native_source=<active|embedded> api=2.1
  HB1 <ts> CONNECT ep=a1b2c3d4 cg=7 rg=0 ng=12 prof=9f8e7d6c mode=vpn source=ui
  HB1 <ts> START   ep=a1b2c3d4 cg=7 rg=0 ng=12 stage=foreground result=ok
  HB1 <ts> START   ep=a1b2c3d4 cg=7 rg=0 ng=12 stage=network_wait result=ok elapsed_ms=<n> attempt=0
  HB1 <ts> NETWORK ep=a1b2c3d4 cg=7 rg=0 ng=12 trigger=launch branch=noop iface_idx=<n> ms_since_last_callback=<n>
  HB1 <ts> START   ep=a1b2c3d4 cg=7 rg=0 ng=12 stage=libbox_start result=ok elapsed_ms=<n>
  HB1 <ts> READY   ep=a1b2c3d4 cg=7 rg=3 ng=12 prof=9f8e7d6c active_lanes=<n> target_lanes=<n> elapsed_ms_from_connect=<n>
  HB1 <ts> STOP    ep=a1b2c3d4 cg=8 rg=3 ng=12 prof=9f8e7d6c reason=user stage=requested
  HB1 <ts> STOP    ep=a1b2c3d4 cg=8 rg=3 ng=12 stage=released elapsed_ms=<n>
```
  Значение `native_source` до `HB-RW-040` зависит от установленного бандла, после —
  всегда `embedded`. Пример соответствует файловому правилу для `prof`: он есть на
  всех строках из `CoreRuntimeService` (`EPOCH` — со значением `none`, потому что
  digest ещё не присвоен; `CONNECT`, `READY`, `STOP stage=requested` — со значением);
  его нет на `START stage=...` и `NETWORK` (другие файлы) и на `STOP stage=released`
  (издаётся из `HydraBoxService.stopInternal`).
- **NEGATIVE ASSERTIONS:** число `REBIND` не изменилось по сравнению с прогоном до
  задачи; ни одного нового перехода состояний; ни одной новой строки с hostname или
  IP; `grep -rn "activeConfigSha256" android/app/src/main` даёт совпадения только в
  `CoreRuntimeService.kt`; ни один файл вне `CoreRuntimeService.kt` не публикует ключ
  `prof`; `grep -rn "lastAndroidCallbackElapsedMs" android/app/src/main` даёт
  совпадения только в `HydraBoxDefaultNetworkMonitor.kt`; поведение выбора сети,
  debounce и rebind не изменилось — число `NETWORK` и `REBIND` в M07 совпадает с
  прогоном до задачи.
- **ROLLBACK:** revert; `HB-RW-001` остаётся.
- **DEFINITION OF DONE:** M01 и M07 дают последовательность из
  `EXPECTED STRUCTURED LOG`; по паре `ep` плюс `cg` из одного лога однозначно
  восстанавливается, какие стадии относятся к какой попытке подключения, и для каждой
  попытки её `prof` читается из её же строки `CONNECT`; строка `EPOCH` несёт
  `prof=none`; `HydraBoxEventCoverageTest` зелёный, включая проверки (б), (в), (г),
  (д); `NetworkCallbackTimestampTest` зелёный; `:app:testDebugUnitTest` и
  `:app:lintDebug` зелёные.
- **STOP CONDITIONS:** остановиться, если для получения `rg` либо `ng` в каком-то
  месте потребуется что-то помимо двух перечисленных read-only accessor-ов; если для
  `ep` либо `cg` окажется недостаточно смены видимости `CoreProcessIdentity` на
  `internal` (например объект окажется в другом Gradle-модуле); если возникнет
  потребность расширить видимость `activeConfigSha256` либо вычислить `prof` вне
  `CoreRuntimeService`; если для `ms_since_last_callback` окажется, что запись
  времени в четырёх override-ах недостаточна (например Android доставляет callback,
  минуя объект `callback` монитора) либо что поле приходится читать в коде принятия
  решений. Во всех этих случаях владение состоянием менять **нельзя** — это задача
  `HB-RW-008` либо `HB-RW-018`, не эта.
  Отдельно: если статическая проверка (б) падает на конструкции, которая **не**
  является секретом и **не** устраняется выносом форматирования в `shortHex` либо
  `shortId` — остановиться и сообщить конструкцию; подгонять проверку под код
  запрещено, как и наоборот.
- **COMMIT BOUNDARY:** один коммит: смена видимости `CoreProcessIdentity` на
  `internal`; приватные хелперы `shortHex` и `shortId` (плюс локальный аналог
  `shortId` в трёх остальных файлах); новое приватное поле
  `lastAndroidCallbackElapsedMs` с константой `NO_CALLBACK_YET`, его запись в четырёх
  override-ах и импорт `SystemClock`; чистая функция `msSinceLastCallback`;
  добавление вызовов `event`; замена `native_start_marker`; два новых теста.
  Ничего больше.
- **NEXT TASK:** `HB-EXP-E11` становится исполнимым; далее `HB-RW-040` (начало
  удаления core-swap), а также независимые `HB-RW-019`, `HB-RW-023`, `HB-RW-016`.

---

## HC-RW-001 — Словарь кодов и stage-события в Hydra

Core

- **STATUS:** READY
- **GOAL:** ввести в HydraCore закрытый словарь safe error codes и события стадий
  dial-пути, идентичные Android-словарю, без изменения поведения.
- **INVARIANTS ESTABLISHED:** подготовка R18
- **REPOSITORY:** hydracore
- **BASELINE:** `9eefdec8`
- **PRECONDITIONS:** нет
- **FILES / SYMBOLS:**
  - новый `common/hydracore/error_codes.go` — `const` для каждого кода плюс
    `func AllErrorCodes() []string`
  - `transport/call/vk-parasite/client.go`: `DialPath` — события стадий
    `credentials`, `turn_gate`, `turn_allocate`, `dtls_gate`, `dtls_handshake`,
    `inner_auth`, `quic_dial` через существующий `metrics.RecordEvent`
  - `transport/call/vk-parasite/client_telemetry.go` — при необходимости расширить
    список метрик
  - новый `common/hydracore/error_codes_test.go`
- **CURRENT BEHAVIOR:** `metrics.RecordEvent` вызывается только в
  `recordInnerAuthFailure`; коды ошибок формируются как свободные строки в
  `transportFailure`.
- **TARGET BEHAVIOR:** все стадии dial-пути публикуют событие с `worker` и
  результатом; коды берутся из словаря.
- **IMPLEMENTATION:** добавить `RecordEvent` в каждую стадию `DialPath` (успех и
  ошибка); коды — константы из `error_codes.go`.
- **DELETE:** —
- **DO NOT CHANGE:** `APIVersion`, `CapabilitiesJSON()`, `HydraCoreTransportState`,
  число workers, любые таймауты, `sharedTransportSupervisor` лимиты.
- **BACKWARD COMPATIBILITY:** wire format не меняется; `verify_extended_core.py`
  должен проходить без изменений.
- **TESTS TO ADD FIRST:** `error_codes_test.go`: словарь непуст, без дубликатов,
  каждый код соответствует `^[a-z0-9._]{3,64}$`.
- **TESTS THAT MUST REMAIN UNCHANGED:** все в `transport/call/...`.
- **VALIDATION:** `go build ./...`, `go vet ./transport/call/... ./common/hydracore/...`,
  `go test ./transport/call/... ./common/hydracore/...`
- **MANUAL SCENARIO:** —
- **EXPECTED STRUCTURED LOG:** события телеметрии `turn_allocate`, `dtls_handshake`,
  `quic_dial` появляются в снимке телеметрии; в Android-логах пока не видны
  (нужен `HB-BUNDLE-001`).
- **NEGATIVE ASSERTIONS:** ни одного изменения в `capabilities.go`; ни одного
  изменения `schema_version`.
- **ROLLBACK:** revert; артефакт не пересобирается.
- **DEFINITION OF DONE:** go-валидация зелёная; словарь совпадает по составу с
  `HydraBoxEventCodes` (сверяется вручную и фиксируется в §8).
- **STOP CONDITIONS:** если добавление событий требует новых полей в
  `CapabilitiesJSON()` — остановиться (**R14**).
- **COMMIT BOUNDARY:** один коммит в hydracore.
- **NEXT TASK:** `HB-BUNDLE-001`.

---

## HB-RW-040 — Убрать core-swap из runtime-пути `:core`

- **STATUS:** IN_PROGRESS
- **GOAL:** снять с инициализации и со стадии READY побочные эффекты подсистемы
  сменяемого ядра, не удаляя пока сами классы.
- **INVARIANTS ESTABLISHED:** R1 (частично: у старта не остаётся сторонних writer-ов),
  R3 (с READY уходит файловый I/O)
- **REPOSITORY:** hydrabox
- **BASELINE:** merge `HB-RW-002`
- **PRECONDITIONS:** `HB-RW-002`
- **FILES / SYMBOLS:**
  - `runtime/CoreRuntimeService.kt`: `onCreate` (ветка
    `if (HydraNativeLoader.loadedSource() == "active") { ... markHealthy ... }`),
    `completeHealthyStart` (вызовы `CoreBundleManager(this).readState()` и
    `markHealthy`), все `startupFailure.markStage(..., HydraNativeLoader.loadedSource())`
  - `HydraBoxApplication.kt`: `onCreate` — ветвление по имени процесса,
    вызовы `CoreBundleManager(this).noteCoreProcessStart()` и
    `configureNativeLoader()`, `configureCandidateLoaderForProbe()`
- **CURRENT BEHAVIOR:** владелец runtime при инициализации и в точке достижения READY
  выполняет файловый ввод-вывод подсистемы бандлов; `HydraBoxApplication.onCreate`
  ветвится по трём процессам и конфигурирует загрузчик нативной библиотеки.
- **TARGET BEHAVIOR:** `CoreRuntimeService` не обращается к `CoreBundleManager` ни
  при инициализации, ни на READY; `HydraBoxApplication.onCreate` не конфигурирует
  загрузчик; `HydraNativeLoader` не получает кандидата и всегда загружает
  встроенную библиотеку, а `loadedSource()` возвращает `embedded`.
  `startupFailure.markStage(stage, source)` продолжает вызываться, но `source`
  берётся как константа `"embedded"`.
- **IMPLEMENTATION:**
  1. Удалить из `CoreRuntimeService.onCreate` весь блок с `loadedSource() == "active"`.
  2. В `completeHealthyStart` оставить только `commandSucceeded(...)`.
  3. Заменить `HydraNativeLoader.loadedSource()` на константу в вызовах
     `markStage` и в логах старта.
  4. В `HydraBoxApplication.onCreate` удалить ветки `:core` и `:core_probe`,
     оставив только `if (processName == packageName) { SubscriptionRefreshScheduler... }`.
- **DELETE:** блок `loadedSource() == "active"` в `onCreate`; два вызова
  `CoreBundleManager` в `completeHealthyStart`; вызовы `noteCoreProcessStart`,
  `configureNativeLoader`, `configureCandidateLoaderForProbe`.
- **DO NOT CHANGE:** сами классы `CoreBundleManager`, `CoreBundleUpdater`,
  `CoreBundleManifest`, `CoreBundleSignatureVerifier`, `CoreCandidateProbeClient`
  (удаляются в `HB-RW-041` и `HB-RW-042`); `CoreStartupFailureStore`;
  `CoreCapabilityContract`; файл `go/HydraNativeLoader.java`.
- **BACKWARD COMPATIBILITY:** после задачи ядро всегда встроенное. Ранее
  установленный кандидат на диске перестаёт использоваться; его файлы удаляет
  `HB-RW-042`.
- **TESTS TO ADD FIRST:** `EmbeddedCoreOnlyTest` (JVM): чистая функция
  `nativeSourceLabel()` возвращает `"embedded"`; тест-проверка исходников
  (в стиле `HydraBoxEventCoverageTest`), что `CoreRuntimeService.kt` не содержит
  подстроки `CoreBundleManager`.
- **TESTS THAT MUST REMAIN UNCHANGED:** `CoreBundleUpdaterTest` (удаляется в
  `HB-RW-042`), `CoreCapabilityContractTest`,
  `CoreRuntimeSnapshotCompatibilityTest`.
- **VALIDATION:** `./gradlew :app:testDebugUnitTest :app:lintDebug`,
  `python3 -B scripts/verify_client_boundaries.py`,
  `python3 -B scripts/verify_libbox.py`
- **MANUAL SCENARIO:** M01 — приложение подключается; в логе `EPOCH` содержит
  `native_source=embedded`.
- **EXPECTED STRUCTURED LOG:** `HB1 <ts >EPOCH ep=xxxxxxxx native_source=embedded api=2.1`

- **NEGATIVE ASSERTIONS:** на стадии READY нет файлового ввода-вывода подсистемы
  бандлов; `grep -n "CoreBundleManager" android/app/src/main/kotlin/io/hydrabox/client/runtime/CoreRuntimeService.kt`
  даёт ноль совпадений.
- **ROLLBACK:** revert; классы подсистемы ещё на месте, поведение возвращается.
- **DEFINITION OF DONE:** grep пустой; verify-скрипты зелёные; M01 проходит.
- **STOP CONDITIONS:** если `verify_libbox.py` начнёт требовать динамический
  загрузчик (то есть provenance всё ещё содержит `hydracore-bundle-manifest-v1.json`)
  — это ожидаемо и не является поводом для остановки: скрипт проверяет артефакт, а не
  код. Останавливаться, только если он падает по иной причине.
- **COMMIT BOUNDARY:** один коммит: два файла плюс тест.
- **NEXT TASK:** `HB-RW-041`.

---

## HB-RW-041 — Удалить процесс `:core_probe` и валидацию кандидата

- **STATUS:** BLOCKED(`HB-RW-040`)
- **GOAL:** сократить модель процессов до двух и убрать код валидации кандидата ядра.
- **INVARIANTS ESTABLISHED:** R20 (частично), упрощение R1
- **REPOSITORY:** hydrabox
- **BASELINE:** merge `HB-RW-040`
- **PRECONDITIONS:** `HB-RW-040`
- **FILES / SYMBOLS:**
  - удалить `android/app/src/main/kotlin/io/hydrabox/client/runtime/CoreProbeService.kt`
  - удалить `android/app/src/main/aidl/io/hydrabox/client/runtime/ICoreProbeService.aidl`
  - удалить `android/app/src/main/kotlin/io/hydrabox/client/core/CoreCandidateProbeClient.kt`
  - `android/app/src/main/AndroidManifest.xml`: удалить объявление сервиса
    `.runtime.CoreProbeService` вместе с `android:process=":core_probe"`
  - `scripts/verify_client_boundaries.py`: из `required_process_bindings` удалить
    `'android:name=".runtime.CoreProbeService"'` и `'android:process=":core_probe"'`
  - `android/app/src/androidTest/kotlin/io/hydrabox/client/runtime/CoreProcessIsolationInstrumentedTest.kt`:
    удалить `assertServiceProcess(CoreProbeService::class.java, ":core_probe")` и
    тест-кейс загрузки кандидата, использующий `CoreBundleUpdater`
  - `runtime/proto`: сообщения `CoreProbeRequest` и `CoreProbeReport` помечаются
    deprecated и **не удаляются** (protobuf-совместимость внутри одного APK не
    требует их удаления, а удаление номеров полей запрещено)
- **CURRENT BEHAVIOR:** третий процесс `:core_probe` поднимается только чтобы
  загрузить candidate-библиотеку, проверить капабилити и убить себя; клиент
  `CoreCandidateProbeClient` сверяет отчёт с манифестом.
- **TARGET BEHAVIOR:** процессов два — `default` и `:core`; кода валидации
  кандидата нет; `verify_client_boundaries.py` пинует только два процесса.
- **IMPLEMENTATION:** удалить перечисленные файлы и объявления; обновить два места
  в verify-скрипте; поправить инструментальный тест.
- **DELETE:** три файла, объявление сервиса в манифесте, две строки в verify-скрипте,
  два фрагмента инструментального теста.
- **DO NOT CHANGE:** объявления `.runtime.CoreRuntimeService` и `android:process=":core"`
  в манифесте и в verify-скрипте; проверку запрещённых разрешений; проверку
  `direct_libbox` для главного процесса.
- **BACKWARD COMPATIBILITY:** внешнего контракта нет. Deprecated protobuf-сообщения
  остаются, чтобы не переиспользовать номера полей.
- **TESTS TO ADD FIRST:** нет. Проверено при составлении плана: в `scripts/tests`
  находится единственный файл `test_fetch_libbox.py`, и он не проверяет состав
  `required_process_bindings`. Поэтому обновлять тесты скриптов не требуется;
  `python3 -B -m unittest discover -s scripts/tests` обязан остаться зелёным без правок.
- **TESTS THAT MUST REMAIN UNCHANGED:** остальные кейсы
  `CoreProcessIsolationInstrumentedTest`, `CoreCapabilityContractTest`.
- **VALIDATION:** `./gradlew :app:testDebugUnitTest :app:lintDebug`,
  `python3 -B scripts/verify_client_boundaries.py`,
  `python3 -B -m unittest discover -s scripts/tests -p "test_*.py"`,
  `python3 -B scripts/verify_libbox.py`
- **MANUAL SCENARIO:** M01; затем `adb shell ps | grep hydrabox` — ровно два
  процесса приложения.
- **EXPECTED STRUCTURED LOG:** без изменений.
- **NEGATIVE ASSERTIONS:** `grep -rn "core_probe" android lib scripts` даёт ноль
  совпадений (кроме сгенерированных артефактов в `build/` и `dist/`, которые не
  входят в diff).
- **ROLLBACK:** revert одного PR; манифест, скрипт и файлы возвращаются вместе.
- **DEFINITION OF DONE:** grep пустой; verify-скрипты зелёные; в системе два процесса.
- **STOP CONDITIONS:** правка `verify_client_boundaries.py` разрешена **только** в
  объёме двух перечисленных строк. Любая иная правка verify-скриптов — STOP.
- **COMMIT BOUNDARY:** один PR; отдельная строка в commit message обосновывает
  изменение verify-скрипта ссылкой на решение C17.
- **NEXT TASK:** `HB-RW-042`.

---

## HB-RW-042 — Удалить Core Manager: API, UI и подсистему бандлов

- **STATUS:** BLOCKED(`HB-RW-041`)
- **GOAL:** убрать пользовательскую поверхность и оставшиеся классы сменяемого ядра.
- **INVARIANTS ESTABLISHED:** R20
- **REPOSITORY:** hydrabox
- **BASELINE:** merge `HB-RW-041`
- **PRECONDITIONS:** `HB-RW-041`
- **FILES / SYMBOLS:**
  - удалить `android/app/src/main/kotlin/io/hydrabox/client/core/CoreManagerHostApiHandler.kt`
  - удалить `android/app/src/main/kotlin/io/hydrabox/client/core/CoreBundleManager.kt`,
    `CoreBundleUpdater.kt`, `CoreBundleManifest.kt`
  - удалить `android/app/src/test/kotlin/io/hydrabox/client/core/CoreBundleUpdaterTest.kt`
  - удалить `lib/features/core_manager/core_manager_page.dart`,
    `lib/features/core_manager/core_manager_controller.dart`
  - `pigeons/singbox_api.dart`: удалить `CoreManagerHostApi`,
    `CoreManagerStateMessage`, `CoreBundleSlotMessage` и связанные сообщения;
    перегенерировать Pigeon
  - `MainActivity.kt`: удалить `CoreManagerHostApi.setUp(...)` и создание handler-а
  - `lib/app/app.dart`: удалить вызов `platform_bridge.CoreManagerHostApi().rollback()`
    и обвязку вокруг него
  - `lib/features/settings/settings_about_page.dart`: удалить `_openCoreManager`,
    `_AboutCoreManagerCard` и его использование
  - `lib/l10n/app_en.arb` и `lib/l10n/app_ru.arb`: удалить 22 ключа `coreManager*`
    (`coreManagerActivate`, `coreManagerActiveVersion`, `coreManagerCandidateVersion`,
    `coreManagerChannelDebug`, `coreManagerChannelStable`, `coreManagerChannelTitle`,
    `coreManagerCheck`, `coreManagerCheckedRelease`, `coreManagerDisconnectRequired`,
    `coreManagerDownload`, `coreManagerEmbeddedVersion`, `coreManagerNoTrustedKeys`,
    `coreManagerOpenAction`, `coreManagerOperationFailed`, `coreManagerPreviousVersion`,
    `coreManagerProbe`, `coreManagerProbeFailed`, `coreManagerProbePassed`,
    `coreManagerRollback`, `coreManagerSubtitle`, `coreManagerTitle`,
    `coreManagerUsingEmbedded`) вместе с их `@`-метаданными; затем `flutter gen-l10n`
  - `test/release_workflow_test.dart`: удалить кейсы, ссылающиеся на Core Manager
  - `scripts/verify_client_boundaries.py`: в `verify_platform_bridge_boot_order`
    удалить маркер `"CoreManagerHostApi.setUp(binaryMessenger, handler)"`
  - `HydraBoxApplication.kt`: при первом запуске удалить каталог кандидата ядра
    (одноразовая уборка диска)
- **CURRENT BEHAVIOR:** приложение имеет экран Core Manager, Pigeon-API с
  `activateCandidate` и `rollback`, вызов `rollback()` из `app.dart`, а также классы
  загрузки, манифеста и состояния бандлов.
- **TARGET BEHAVIOR:** ни API, ни экрана, ни классов подсистемы; ядро только
  встроенное; каталог кандидата удаляется один раз при обновлении.
- **IMPLEMENTATION:** удалить перечисленное; перегенерировать Pigeon и локализацию;
  обновить маркер в verify-скрипте; добавить одноразовую уборку каталога.
- **DELETE:** восемь файлов, Pigeon-API целиком, экран настроек, строки локализации,
  один маркер verify-скрипта.
- **DO NOT CHANGE:** `CoreBundleSignatureVerifier.kt` — он остаётся на месте и не
  переименовывается, потому что используется `update/AppUpdateManifestVerifier`
  для проверки подписи обновлений APK; `CoreCapabilityContract`;
  `CoreStartupFailureStore`; `go/HydraNativeLoader.java`; систему обновления APK.
- **BACKWARD COMPATIBILITY:** удаление Pigeon-API — граница внутри одного APK,
  поэтому Kotlin и Dart меняются одним PR. Пользователь теряет экран Core Manager;
  это фиксируется в `CHANGELOG.md`.
- **TESTS TO ADD FIRST:** `DiskCleanupTest` (JVM): чистая функция
  `staleCoreBundleDirs(root)` перечисляет каталоги к удалению и не затрагивает
  `singbox-config.json`, `runtime-desired.txt`, каталог `core-config-recovery`.
- **TESTS THAT MUST REMAIN UNCHANGED:** `app_update_service_test.dart`,
  `release_notes_card_test.dart`, `secure_hive_*`, `subscription_*`;
  `CoreBundleUpdaterTest` удаляется как тест удалённого кода.
- **VALIDATION:** `dart run pigeon --input pigeons/singbox_api.dart`,
  `flutter gen-l10n`, `dart format .`, `flutter analyze`, `flutter test`,
  `./gradlew :app:testDebugUnitTest :app:lintDebug`,
  `python3 -B scripts/verify_client_boundaries.py`,
  `python3 -B -m unittest discover -s scripts/tests -p "test_*.py"`
- **MANUAL SCENARIO:** M01; открыть «О приложении» — карточки Core Manager нет,
  остальные разделы работают; обновление APK по-прежнему проверяет подпись.
- **EXPECTED STRUCTURED LOG:** без изменений.
- **NEGATIVE ASSERTIONS:**
  `grep -rn "CoreManager

|CoreBundleManager|CoreBundleUpdater|CoreBundleManifest" lib android/app/src pigeons scripts`
  даёт ноль совпадений (кроме `CoreBundleSignatureVerifier`).
- **ROLLBACK:** revert одного PR.
- **DEFINITION OF DONE:** grep соответствует ожиданию; все validation-команды
  зелёные; `CHANGELOG.md` обновлён.
- **STOP CONDITIONS:** если обнаружится, что `CoreBundleSignatureVerifier` тянет за
  собой `CoreBundleManifest`, — STOP и сообщить: тогда нужно выделить из манифеста
  только парсер подписи, и это отдельная задача.
  Правка verify-скрипта разрешена только в объёме одного маркера.
- **COMMIT BOUNDARY:** один PR; отдельная строка в commit message обосновывает
  изменение verify-скрипта ссылкой на решение C17.
- **NEXT TASK:** `HB-RW-003`.

---

## HB-BUNDLE-001 — Bump submodule и артефакта ядра (после `HC-RW-001`)

- **STATUS:** BLOCKED(`HC-RW-001`)
- **GOAL:** довести изменения HydraCore до приложения: новый коммит submodule,
  новый `libbox.aar`, обновлённые provenance и sha.
- **INVARIANTS ESTABLISHED:** —
- **REPOSITORY:** hydrabox
- **BASELINE:** merge `HB-RW-002`
- **PRECONDITIONS:** `HC-RW-001` смержен в hydracore и опубликован артефакт CI
- **FILES / SYMBOLS:** `hydracore/` (указатель submodule),
  `android/app/libs/libbox.aar`, `android/app/libs/libbox.sha256`,
  `android/app/libs/libbox.provenance.json`,
  `hydracore/release/UPSTREAM_BASELINE`, `HYDRACORE_VERSION`
- **CURRENT BEHAVIOR:** приложение использует ядро на `9eefdec8`.
- **TARGET BEHAVIOR:** приложение использует ядро с новым HEAD; provenance и sha
  соответствуют артефакту; оба verify-скрипта проходят.
- **IMPLEMENTATION:** обновить указатель submodule; получить артефакт из CI
  (`scripts/fetch_libbox.py` — только если это явно требуется); обновить
  `libbox.sha256` и `libbox.provenance.json` из данных сборки.
- **DELETE:** —
- **DO NOT CHANGE:** ничего в `lib/`, `android/app/src/`.
- **BACKWARD COMPATIBILITY:** обязательна: `verify_extended_core.py` подтверждает
  `APIVersion = 2` и `CoreID`; при расхождении — STOP.
- **TESTS TO ADD FIRST:** —
- **TESTS THAT MUST REMAIN UNCHANGED:** `scripts/tests/*`.
- **VALIDATION:**
  `python3 -B scripts/verify_libbox.py`,
  `python3 -B scripts/verify_extended_core.py --source-only`,
  `python3 -B -m unittest discover -s scripts/tests -p "test_*.py"`,
  `./gradlew :app:testDebugUnitTest :app:lintDebug`
- **MANUAL SCENARIO:** M01 — приложение стартует, `EPOCH` содержит новый
  `native_source=embedded`.
- **EXPECTED STRUCTURED LOG:** `HB1 ... EPOCH ep=... native_source=embedded api=2.1`
  (значение `embedded` — следствие `HB-RW-040`, который выполняется раньше по порядку §7)
- **NEGATIVE ASSERTIONS:** ни одного изменения в поведении runtime; `apiMajor`
  остаётся 2.
- **ROLLBACK:** revert коммита bump; предыдущий артефакт восстанавливается целиком.
- **DEFINITION OF DONE:** оба verify-скрипта зелёные; приложение подключается.
- **STOP CONDITIONS:** sha или provenance не совпали с артефактом — STOP, **не
  подгонять** значения под файл.
- **COMMIT BOUNDARY:** один коммит: submodule плюс артефакт плюс provenance.
- **NEXT TASK:** `HB-EXP-E9` становится исполнимым только после `HB-BUNDLE-002`;
  далее `HB-RW-003`.

---

## HB-RW-019 — `interfaceIndex == -1` не должен публиковаться как «сети нет»

- **STATUS:** READY
- **GOAL:** прекратить приостановку runtime из-за временно нечитаемого индекса
  сетевого интерфейса.
- **INVARIANTS ESTABLISHED:** R4 (частично)
- **REPOSITORY:** hydrabox
- **BASELINE:** merge `HB-RW-002`
- **PRECONDITIONS:** `HB-RW-002` (нужно событие `NETWORK` для проверки)
- **FILES / SYMBOLS:**
  `singbox/HydraBoxDefaultNetworkMonitor.kt`: `notifyListenerInternal` (блок ожидания
  индекса), `currentInterfaceState`
- **CURRENT BEHAVIOR:** если после 10 попыток по 100 ms `NetworkInterface.getByName`
  вернул `-1`, вызывается `notifyListeners(currentListeners, "", -1)`, что в Go даёт
  `notifyInterfaceUpdate(nil)` → `pauseManager.NetworkPause()`, то есть весь runtime
  встаёт, хотя `effectiveNetwork` существует.
- **TARGET BEHAVIOR:** при существующем `effectiveNetwork` и `index < 0` монитор
  **не** публикует «нет интерфейса»: он логирует
  `event("NETWORK", trigger=<t>, branch=index_unavailable, result=skip)` и планирует
  повторный слепок через существующий debounce-путь. Публикация `("", -1)`
  выполняется **только** когда `effectiveNetwork == null`.
- **IMPLEMENTATION:**
  1. Выделить из `notifyListenerInternal` блок ожидания индекса в приватную
     функцию `resolveInterfaceIndex(name): Int`.
  2. При `index < 0` и непустом `effectiveNetwork`: не менять `lastNotificationKey`,
     не вызывать `notifyListeners`, не вызывать `setUnderlyingNetwork(null)`;
     запланировать повторный проход `notifyListener()` (без `force`).
  3. Ограничить число таких повторов тремя, после чего опубликовать `NONE` —
     иначе появится неограниченный цикл (**R9**).
- **DELETE:** —
- **DO NOT CHANGE:** число попыток внутри `resolveInterfaceIndex` (10 × 100 ms),
  величину debounce, порядок выбора сети.
- **BACKWARD COMPATIBILITY:** поведение при реальной потере сети не меняется.
- **TESTS TO ADD FIRST:** `EffectiveNetworkIndexTest` (JVM, чистая функция):
  (а) `effectiveNetwork != null`, `index < 0` → решение `RETRY_SNAPSHOT`;
  (б) три повтора подряд → решение `PUBLISH_NONE`;
  (в) `effectiveNetwork == null` → `PUBLISH_NONE` немедленно.
  Для этого решение выносится в чистую функцию `decideInterfacePublication(...)`
  в том же файле.
- **TESTS THAT MUST REMAIN UNCHANGED:** `DefaultNetworkSelectionTest`,
  `IdentityListenerRegistryTest`.
- **VALIDATION:** `./gradlew :app:testDebugUnitTest :app:lintDebug`
- **MANUAL SCENARIO:** M09 (Wi-Fi → нет сети 60 s → cellular): в логе ровно один
  `NETWORK` с `branch=none`, и ни одного `branch=none` при живом cellular.
- **EXPECTED STRUCTURED LOG:**
  `HB1 ... NETWORK ng=<n >trigger=callback branch=index_unavailable result=skip`
  затем `HB1 ... NETWORK ng=<n+1 >trigger=callback branch=changed iface_idx=<n>`

- **NEGATIVE ASSERTIONS:** при handover в логе ядра нет строки
  `missing default interface`, если физическая сеть присутствует.
- **ROLLBACK:** revert; независимая задача.
- **DEFINITION OF DONE:** `EffectiveNetworkIndexTest` зелёный; M09 без ложного
  `branch=none`.
- **STOP CONDITIONS:** если окажется, что `notifyListeners("", -1)` требуется ядру
  для иных целей (кроме сигнала «нет сети») — STOP.
- **COMMIT BOUNDARY:** один коммит, один файл плюс тест.
- **NEXT TASK:** `HB-RW-023`.

---

## HB-RW-023 — Очистка `managedProbeAliases`

- **STATUS:** READY
- **GOAL:** устранить утечку карты алиасов probe-сессий.
- **INVARIANTS ESTABLISHED:** подготовка R15
- **REPOSITORY:** hydrabox
- **BASELINE:** merge `HB-RW-002`
- **PRECONDITIONS:** нет
- **FILES / SYMBOLS:** `runtime/CoreRuntimeService.kt`: `startProbe`, `cancelProbe`,
  `updateProbeSessions`, поле `managedProbeAliases`
- **CURRENT BEHAVIOR:** запись добавляется в `startProbe` и не удаляется никогда.
- **TARGET BEHAVIOR:** запись удаляется при переходе сессии в любое терминальное
  состояние (`COMPLETED`, `PARTIAL`, `CANCELLED`, `TIMED_OUT`) и при обнулении
  runtime.
- **IMPLEMENTATION:** в `updateProbeSessions` после разбора состояния удалять
  соответствующий ключ, если состояние терминальное; в `cancelProbe` — удалять по
  найденному `nativeId`.
- **DELETE:** —
- **DO NOT CHANGE:** логику выбора managed/ephemeral, тайминги probe.
- **BACKWARD COMPATIBILITY:** внешнее поведение не меняется.
- **TESTS TO ADD FIRST:** `ManagedProbeAliasTest` (JVM): чистая функция
  `pruneAliases(aliases, sessions)` возвращает карту без терминальных сессий.
- **TESTS THAT MUST REMAIN UNCHANGED:** `ProbeExecutionModeTest`.
- **VALIDATION:** `./gradlew :app:testDebugUnitTest :app:lintDebug`
- **MANUAL SCENARIO:** M17 — 20 подряд URLTest, затем экспорт
  `PERFORMANCE_COUNTERS`: карта не растёт (добавить счётчик в тот же вывод).
- **EXPECTED STRUCTURED LOG:** —
- **NEGATIVE ASSERTIONS:** размер карты после 20 завершённых сессий равен нулю.
- **ROLLBACK:** revert.
- **DEFINITION OF DONE:** тест зелёный; счётчик размера карты после прогона равен 0.
- **STOP CONDITIONS:** если удаление алиаса ломает доставку последних результатов
  сессии — STOP и сообщить.
- **COMMIT BOUNDARY:** один коммит.
- **NEXT TASK:** `HB-RW-003`.

---

## HB-RW-003 — Удалить пять синтезированных полей снимка и их читателей

- **STATUS:** BLOCKED(`HB-RW-042`)
- **GOAL:** убрать поля, создающие иллюзию независимых проверок, и перевести Dart на
  чтение `state`.
- **INVARIANTS ESTABLISHED:** R2 (частично)
- **REPOSITORY:** hydrabox
- **BASELINE:** merge `HB-RW-042`
- **PRECONDITIONS:** `HB-RW-042` (и транзитивно `HB-RW-002`)
- **FILES / SYMBOLS:**
  - `MainActivity.kt`: `toLegacyRuntimeMap` — удалить ключи `recordedServiceAlive`,
    `activeRuntimeOwner`, `runtimeIntentFresh`, `nativeRecoveryPending`,
    `runtimeSnapshotAuthoritative`
  - `lib/app/runtime_lifecycle_controller.dart`: `_isStartedRuntimeStatus`,
    `_waitForStoppedRuntime`
  - `lib/app/runtime_recovery_controller.dart`: `nativeRuntimeRecoveryPending`
  - `lib/app/app.dart`: `_syncRuntimeState`, `_logRuntimeRecoveryStatus`
  - `lib/app/singbox_config_coordinator.dart`: `_resolveRuntimeApplyPolicy`
- **CURRENT BEHAVIOR:** `toLegacyRuntimeMap` вычисляет пять полей из того же `state`;
  Dart проверяет их как независимые условия (`running && mode && recordedServiceAlive
  && activeRuntimeOwner && generation >0`).

- **TARGET BEHAVIOR:** `_isStartedRuntimeStatus` сводится к
  `state == 'RUNTIME_STATE_RUNNING' && mode == expected`;
  `_waitForStoppedRuntime` — к `state == 'RUNTIME_STATE_STOPPED'`;
  `nativeRuntimeRecoveryPending` удалена, вместо неё
  `state in {RUNTIME_STATE_STARTING, RUNTIME_STATE_RECOVERING}`;
  `serviceMayBeAlive` в `_resolveRuntimeApplyPolicy` вычисляется из `state`.
- **IMPLEMENTATION:** удалить ключи в Kotlin; в Dart заменить предикаты; в
  `_syncRuntimeState` убрать чтение удалённых полей, оставив сам метод (он удаляется
  в `HB-RW-007`).
- **DELETE:** пять ключей; функция `nativeRuntimeRecoveryPending`.
- **DO NOT CHANGE:** `_syncRuntimeState` как таковой; `decideStatus`;
  `runtimeStatusMap` (удаляется в `HB-RW-004`).
- **BACKWARD COMPATIBILITY:** Kotlin и Dart меняются **в одном PR**: Map-ключи
  исчезают, и Dart-читатели должны исчезнуть одновременно, иначе возникнет окно,
  где `status['recordedServiceAlive']` равно `null` и предикат всегда false.
- **TESTS TO ADD FIRST:**
  - `CoreRuntimeSnapshotCompatibilityTest` — расширить: пять ключей отсутствуют;
  - `test/runtime_snapshot_reducer_test.dart` (новый): чистая функция
    «снимок → `AppConnectionPhase`» без polling; кейсы для всех шести состояний;
  - `test/runtime_snapshot_reducer_test.dart`: противоречивая пара снимков
    (`running=true`, затем `STOPPED` без edge) не сбрасывает UI-состояние.
- **TESTS THAT MUST REMAIN UNCHANGED:** `runtime_session_coordinator_test.dart`,
  `runtime_operation_coordinator_test.dart`, `runtime_intent_controller_test.dart`.
  Кейсы `runtime_lifecycle_controller_test.dart` и
  `runtime_recovery_controller_test.dart`, проверявшие удалённые поля, **переносятся**
  на новые предикаты; в commit message указать, что это перенос спецификации,
  а не её ослабление, с перечислением перенесённых кейсов.
- **VALIDATION:** `flutter analyze`, `flutter test`,
  `./gradlew :app:testDebugUnitTest :app:lintDebug`,
  `python3 -B scripts/verify_client_boundaries.py`
- **MANUAL SCENARIO:** M01, M03, M19
- **EXPECTED STRUCTURED LOG:** без изменений против `HB-RW-002`.
- **NEGATIVE ASSERTIONS:**
  `grep -rn "recordedServiceAlive\

|activeRuntimeOwner\|runtimeIntentFresh\|nativeRecoveryPending\|runtimeSnapshotAuthoritative" lib android/app/src/main`
  даёт ноль совпадений.
- **ROLLBACK:** revert одного PR (Kotlin и Dart вместе).
- **DEFINITION OF DONE:** grep пустой; все тесты зелёные; M03 проходит.
- **STOP CONDITIONS:** если обнаружится читатель удалённых полей вне перечисленных
  файлов — STOP и сообщить список.
- **COMMIT BOUNDARY:** один PR, один коммит; Kotlin и Dart вместе.
- **NEXT TASK:** `HB-RW-004`.

---

## HB-RW-004 — Удалить legacy-ветку `runtimeStatusMap`

- **STATUS:** BLOCKED(`HB-RW-003`)
- **GOAL:** убрать путь, в котором главный процесс выводит live-состояние из файла и
  из полей `SingboxController`, недостижимых в этом процессе.
- **INVARIANTS ESTABLISHED:** R2, R20 (частично)
- **REPOSITORY:** hydrabox
- **BASELINE:** merge `HB-RW-003`
- **PRECONDITIONS:** `HB-RW-003`
- **FILES / SYMBOLS:** `MainActivity.kt`: `runtimeStatusMap`,
  `logsWithNativeDiagnostics` (использует `runtimeStatusMap`), обработчик
  method-channel, возвращающий `runtimeStatusMap()`
- **CURRENT BEHAVIOR:** при отсутствии кэшированного снимка возвращается ветка,
  читающая `HydraBoxApplication.readServiceState()`, `isRecordedServiceAlive()`,
  `HydraBoxService.hasActiveRuntimeOwner()` и `SingboxController.*` — всё это в
  главном процессе даёт `false`, `null` и пустые строки.
- **TARGET BEHAVIOR:** при отсутствии снимка возвращается
  `{"state": "RUNTIME_STATE_UNKNOWN", "processEpoch": ""}`; `logsWithNativeDiagnostics`
  печатает `runtime snapshot: unavailable`, если снимка нет.
- **IMPLEMENTATION:** заменить тело `runtimeStatusMap()` на две строки: кэшированный
  снимок либо `UNKNOWN`-карта. Добавить `RUNTIME_STATE_UNKNOWN` в Dart-редьюсер как
  «состояние неизвестно, фазу не менять».
- **DELETE:** legacy-ветка целиком (около 30 ключей).
- **DO NOT CHANGE:** `HydraBoxApplication` API (удаляется в `HB-RW-013`).
- **BACKWARD COMPATIBILITY:** Dart обязан корректно обрабатывать
  `RUNTIME_STATE_UNKNOWN` — тест обязателен.
- **TESTS TO ADD FIRST:** `test/runtime_snapshot_reducer_test.dart`: снимок
  `RUNTIME_STATE_UNKNOWN` не меняет текущую фазу и не сбрасывает состояние.
- **TESTS THAT MUST REMAIN UNCHANGED:** все.
- **VALIDATION:** `flutter analyze`, `flutter test`,
  `./gradlew :app:testDebugUnitTest :app:lintDebug`
- **MANUAL SCENARIO:** запустить приложение при принудительно убитом `:core`
  (`adb shell am kill`) и открыть экран логов: экспорт не падает.
- **EXPECTED STRUCTURED LOG:** —
- **NEGATIVE ASSERTIONS:** в `MainActivity.kt` нет ни одного обращения к
  `isRecordedServiceAlive`, `readServiceState`, `hasActiveRuntimeOwner`,
  `SingboxController.running`.
- **ROLLBACK:** revert.
- **DEFINITION OF DONE:** grep по перечисленным символам в `MainActivity.kt` пуст;
  экспорт логов работает без снимка.
- **STOP CONDITIONS:** если экран логов зависит от конкретных ключей legacy-ветки —
  STOP и перечислить их.
- **COMMIT BOUNDARY:** один коммит.
- **NEXT TASK:** `HB-RW-006` (не зависит от экспериментов) и, после `HB-EXP-E1` и
  `HB-EXP-E11`, `HB-RW-005`.

---

## HB-RW-006 — Статус нотификации как проекция `runtimeState`

- **STATUS:** BLOCKED(`HB-RW-004`)
- **GOAL:** прекратить показ «Connected» до того, как runtime признан готовым.
- **INVARIANTS ESTABLISHED:** R10
- **REPOSITORY:** hydrabox
- **BASELINE:** merge `HB-RW-004`
- **PRECONDITIONS:** `HB-RW-004`
- **FILES / SYMBOLS:**
  - `singbox/HydraBoxService.kt`: все вызовы `showForeground("...")`
  - `runtime/CoreRuntimeService.kt`: `updateState`
  - `singbox/HydraBoxForegroundNotification.kt`: `buildForForeground`
- **CURRENT BEHAVIOR:** `startOrReloadInternal` вызывает
  `showForeground("Connected")` сразу после возврата `startOrReloadService`, то есть
  до проверки транспорта; `awaitTransportReady` может идти после этого ещё до 120 s.
- **TARGET BEHAVIOR:** `HydraBoxService` выставляет только `"Connecting"`,
  `"Disconnecting"` и `"Waiting for network"`. Переход в `"Connected"` и в
  `"Failed"` делает **только** `CoreRuntimeService.updateState` через новый
  статический вход `HydraBoxService.applyRuntimeStatus(state)`.
- **IMPLEMENTATION:**
  1. В `HydraBoxService` добавить `companion fun applyRuntimeStatus(state: String)`,
     проходящий по `activeServices` и вызывающий `showForeground(state)`.
  2. Заменить `showForeground("Connected")` в `startOrReloadInternal` на
     `showForeground("Connecting")`.
  3. В `CoreRuntimeService.updateState` вызывать `applyRuntimeStatus` с проекцией:
     STARTING и RECOVERING → `"Connecting"`, RUNNING → `"Connected"`,
     STOPPING → `"Disconnecting"`, FAILED → `"Failed"`, STOPPED → нотификация
     снимается существующим путём.
- **DELETE:** `showForeground("Connected")` в `HydraBoxService`.
- **DO NOT CHANGE:** presentation-часть нотификации (заголовок, латентность, тексты),
  `NOTIFICATION_ID`, канал, `updateTraffic`.
- **BACKWARD COMPATIBILITY:** нотификация обязана появиться до первого long-running
  шага, иначе Android убьёт `startForegroundService` — поэтому `"Connecting"`
  выставляется на том же месте, где раньше выставлялось `"Starting"`.
- **TESTS TO ADD FIRST:** `RuntimeStatusProjectionTest` (JVM): чистая функция
  `notificationStatusFor(state)` возвращает ожидаемую строку для всех шести
  состояний, и для `RUNNING` — и только для него — строку «Connected».
- **TESTS THAT MUST REMAIN UNCHANGED:** все.
- **VALIDATION:** `./gradlew :app:testDebugUnitTest :app:lintDebug`
- **MANUAL SCENARIO:** M13 (CAPTCHA): нотификация показывает «Connecting» всё время
  ожидания капчи и переходит в «Connected» только после подъёма линий.
- **EXPECTED STRUCTURED LOG:** между `START stage=libbox_start result=ok` и `READY`
  не должно быть ни одного события со `stage=connected`.
- **NEGATIVE ASSERTIONS:** при профиле с `vk_parasite` и заблокированным TURN
  нотификация **никогда** не показывает «Connected».
- **ROLLBACK:** revert.
- **DEFINITION OF DONE:** тест зелёный; M13 подтверждает поведение визуально.
- **STOP CONDITIONS:** если Android требует `startForeground` до создания
  `CommandServer` с иным текстом — STOP и сообщить.
- **COMMIT BOUNDARY:** один коммит.
- **NEXT TASK:** `HB-RW-005` при выполненных `HB-EXP-E1` и `HB-EXP-E11`.

---

## HB-RW-005 — Единственный владелец дедлайна старта

- **STATUS:** BLOCKED(`HB-EXP-E11`). `HB-EXP-E1` выполнен, ветка **P2**: её требования включены в `IMPLEMENTATION` ниже как обязательный пункт
- **GOAL:** сделать `CoreRuntimeService` единственным владельцем дедлайнов старта и
  передать ему признак интерактивного профиля.
- **INVARIANTS ESTABLISHED:** R19 (частично), подготовка R3
- **REPOSITORY:** hydrabox
- **BASELINE:** merge `HB-RW-006`
- **PRECONDITIONS:** `HB-RW-006`; `HB-EXP-E1` и `HB-EXP-E11` выполнены, evidence в §8
- **FILES / SYMBOLS:**
  - `pigeons/singbox_api.dart` — в `start`/`startPrepared`/`applyConfig`/
    `applyPreparedConfig` добавить `interactiveDeadlineMillis: int`
  - `runtime/proto` (`CoreRuntimeProtocol.StartRuntime`) — поле
    `interactive_deadline_millis`
  - `MainActivity.kt`, `runtime/CoreRuntimeClient.kt` — проброс поля
  - `runtime/CoreRuntimeService.kt` — константы дедлайнов, использование поля
  - `lib/app/runtime_lifecycle_controller.dart` — `startTimeoutForBuild` теперь
    только вычисляет значение для передачи
- **CURRENT BEHAVIOR:** три независимых дедлайна: `:core` 30 s + 30 s + 120 s;
  Dart 15 s либо 5 m 15 s; `CoreRuntimeClient` 165 s.
- **TARGET BEHAVIOR:** `CoreRuntimeService` владеет `START_DEADLINE = 45 s`,
  `CHALLENGE_DEADLINE = 120 s`, `RECOVERY_DEADLINE = 60 s`;
  `CoreRuntimeClient.START_COMMAND_RESULT_DEADLINE_MILLIS` переименован в
  `IPC_LIVENESS_DEADLINE_MILLIS = START_DEADLINE + CHALLENGE_DEADLINE + 15 s` и его
  истечение трактуется как `runtime.ipc.lost`, а не как провал старта;
  `interactiveDeadlineMillis` от Dart используется только чтобы выбрать
  `CHALLENGE_DEADLINE` вместо обычного (профиль без интерактивного VK не получает
  120-секундного окна).
- **IMPLEMENTATION:**
  1. Расширить Pigeon и protobuf аддитивно; перегенерировать Pigeon.
  2. В `CoreRuntimeService.start` сохранить `interactiveDeadline` в поле команды.
  3. Свести `START_DEADLINE_MILLIS` и `TRANSPORT_START_DEADLINE_MILLIS` в одну
     константу 45 s; стадия ожидания сети входит в неё.
  4. Если `HB-EXP-E11` дал ветку **P2** — дополнительно ввести внутренний предел
     стадии `network_wait` = 8 s с публикацией `network.no_interface`.
  5. **Обязательно, следствие `HB-EXP-E1` (ветка P2).** Неудача подключения
     диагностического `CommandClient` **не** приводит к откату старта: стадия
     публикует `START stage=command_client result=fail`, и старт продолжается.
     Дополнительно `verifyHealthAndCompleteStart` перестаёт вызывать
     `failStartAndRollback` при отказе `getRuntimeSnapshot`: снимок ядра —
     диагностика, а не условие готовности. Причина: путь `beginConnect` в `null`
     при непустом `reconnectPendingEpoch` достижим и сегодня уничтожает здоровый
     runtime.
- **DELETE:** `TRANSPORT_START_DEADLINE_MILLIS` (сливается со `START_DEADLINE`).
- **DO NOT CHANGE:** значения 120 s и 60 s; интервалы опроса.
- **BACKWARD COMPATIBILITY:** protobuf-поле аддитивное; отсутствие поля читается как
  «профиль неинтерактивный».
- **TESTS TO ADD FIRST:** `StartDeadlineTest` (JVM): чистая функция
  `deadlineFor(interactive: Boolean, waitingUser: Boolean)` возвращает 45 s / 120 s
  по таблице; `singbox_runtime_test.dart` — поле передаётся.
- **TESTS THAT MUST REMAIN UNCHANGED:** `CoreRuntimeSnapshotCompatibilityTest`,
  `hydracore_compatibility_test.dart`.
- **VALIDATION:** `dart run pigeon --input pigeons/singbox_api.dart`,
  `dart format .`, `flutter analyze`, `flutter test`,
  `./gradlew :app:testDebugUnitTest :app:lintDebug`
- **MANUAL SCENARIO:** M13 — при CAPTCHA старт не отменяется до 120 s;
  M02 — при недостижимом сервере старт падает через 45 s, а не через 15 s и не через 165 s.
- **EXPECTED STRUCTURED LOG:**
  `HB1 ... START rg=0 stage=network_wait result=ok elapsed_ms=<n>` и при провале
  `HB1 ... STOP rg=<n >reason=deadline stage=requested` ровно один раз.

- **NEGATIVE ASSERTIONS:** в логе нет `STOP reason=start_timeout` (Dart-источник);
  нет двух разных дедлайнов, сработавших на одном старте.
- **ROLLBACK:** revert; Pigeon перегенерировать обратно.
- **DEFINITION OF DONE:** `StartDeadlineTest` зелёный; M02 и M13 проходят; в логе
  ровно один источник дедлайна.
- **STOP CONDITIONS:** если `HB-EXP-E1` или `HB-EXP-E11` не выполнены — не начинать.
- **COMMIT BOUNDARY:** один PR: Pigeon плюс proto плюс Kotlin плюс Dart.
- **NEXT TASK:** `HB-RW-007`.

---

## HB-RW-007 — Удалить Dart-супервизор старта, стопа и polling

- **STATUS:** BLOCKED(`HB-RW-005`). `HB-EXP-E1` выполнен, ветка **P2**
- **GOAL:** оставить в Dart ровно один путь получения runtime-состояния — снимок и
  события.
- **INVARIANTS ESTABLISHED:** R2, R11
- **REPOSITORY:** hydrabox
- **BASELINE:** merge `HB-RW-005`
- **PRECONDITIONS:** `HB-RW-005`; `HB-EXP-E1` выполнен
- **FILES / SYMBOLS:**
  - `lib/app/runtime_lifecycle_controller.dart`: удалить `_armStartWatchdog`,
    `_handleStartWatchdogTimeout`, `_handleImmediateStartTimeout`,
    `_claimStartTimeoutHandling`, `_waitForStartedRuntime`,
    `_isStartedRuntimeStatus`, `_waitForStoppedRuntime`, `_waitForHealthyRuntime`,
    `startWatchdogActive`, `cancelStartWatchdog`, `_startWatchdogTimer`,
    `_startWatchdogGeneration`, `_handledStartTimeoutGeneration`,
    `RuntimeTimeoutHook`, параметры `onWatchdogTimeout`
  - `lib/app/app.dart`: удалить `_syncRuntimeState`, `_logRuntimeRecoveryStatus`,
    `_runtimeRecoveryStatusLogInterval`, обработчик watchdog-таймаута, ссылку на
    `startWatchdogActive` в `localTransitionPending`; в
    `_reconcileRuntimeAfterResume` оставить только `_syncRuntimePerformanceFlags`
    и проверку интерфейса
  - `lib/app/runtime_session_coordinator.dart`: удалить `decideStatus`,
    `shouldLogRecoveryStatus`, `_lastRecoveryStatusLogAt`
- **CURRENT BEHAVIOR:** Dart независимо подтверждает старт и стоп polling-ом
  `status()`, держит собственный watchdog и может вызвать stop с причиной
  `start_timeout` в момент, когда `:core` ещё внутри 120-секундного
  challenge-дедлайна.
- **TARGET BEHAVIOR:** `startRuntimeWithBuild` отправляет START и ждёт
  `CommandResult`; `stopRuntime` отправляет STOP и ждёт `CommandResult`; фаза
  пишется только редьюсером снимка.
- **IMPLEMENTATION:** свести оба метода к «команда → результат»; удалить
  перечисленные символы; в `applyRuntimeBuild` заменить `_waitForHealthyRuntime` на
  проверку результата команды `RELOAD`.
- **DELETE:** перечисленные символы, около 250 строк.
- **DO NOT CHANGE:** `startTimeoutForBuild`; `RuntimeSessionCoordinator.stop`
  (дедупликация остаётся); `RuntimeIntentController`;
  `_scheduleInvalidOutboundRetry`.
- **BACKWARD COMPATIBILITY:** если `:core` не доставит `CommandResult` ни по одному
  пути, UI останется в Connecting до `IPC_LIVENESS_DEADLINE_MILLIS`. Перед мержем
  обязателен чек-лист: каждый терминальный путь в
  `CoreRuntimeService.start`, `awaitRunning`, `verifyHealthAndCompleteStart`,
  `awaitTransportReady`, `failStartAndRollback`, `stop` вызывает `commandSucceeded`
  либо `commandFailed`. Найденные пути без результата закрываются в этой же задаче.
- **TESTS TO ADD FIRST:**
  - `test/runtime_lifecycle_controller_test.dart` переписывается на новую
    поверхность; кейсы про watchdog **переносятся** в JVM-тесты `StartDeadlineTest`
    и `RuntimeStateMachineTest` (создаётся в `HB-RW-008`; до тех пор кейс помечается
    `skip` со ссылкой на `HB-RW-008` и снимается там);
  - `test/activity_recreate_test.dart` (новый): пересоздание Activity восстанавливает
    UI из снимка, не из локальных флагов, и не отправляет ни одной команды.
- **TESTS THAT MUST REMAIN UNCHANGED:** `runtime_session_coordinator_test.dart`
  (кейсы `decideStateEvent`), `runtime_intent_controller_test.dart`,
  `runtime_connection_controller_test.dart`, `traffic_status_reducer_test.dart`.
- **VALIDATION:** `flutter analyze`, `flutter test`
- **MANUAL SCENARIO:** M02, M13, M19
- **EXPECTED STRUCTURED LOG:** при успешном старте с CAPTCHA — ни одной строки
  `STOP reason=start_timeout`; ровно один `READY`.
- **NEGATIVE ASSERTIONS:**
  `grep -rn "startWatchdog

|_waitForStartedRuntime|_syncRuntimeState|decideStatus" lib`
  даёт ноль совпадений.
- **ROLLBACK:** revert; риск высокий, поэтому отдельный PR без иных изменений.
- **DEFINITION OF DONE:** grep пустой; M02 и M13 проходят; чек-лист
  `CommandResult` приложен к PR.
- **STOP CONDITIONS:** обнаружен терминальный путь без `CommandResult`, который нельзя
  закрыть в рамках этой задачи — STOP и сообщить путь.
- **COMMIT BOUNDARY:** один PR, только Dart, плюс закрытие найденных путей без
  результата в `CoreRuntimeService`.
- **NEXT TASK:** `HB-RW-008`.

---

## HB-RW-008 — Serializer как event loop с единственным writer состояния

- **STATUS:** BLOCKED(`HB-RW-007`)
- **GOAL:** сделать `commandExecutor` единственным писателем состояния и единственным
  издателем событий и убрать из него любые ожидания.
- **INVARIANTS ESTABLISHED:** R1, R3, R12, R19
- **REPOSITORY:** hydrabox
- **BASELINE:** merge `HB-RW-007`
- **PRECONDITIONS:** `HB-RW-007`
- **FILES / SYMBOLS:** `runtime/CoreRuntimeService.kt`: `commandExecutor`, `execute`,
  `updateState`, `emit`, `eventBuilder`, `snapshotEvent`, `refreshFromController`,
  `handleControllerEvent`, `refreshTransportHealth`, `transportHealthPoll`,
  `awaitRunning`, `verifyHealthAndCompleteStart`, `awaitTransportReady`,
  `awaitRuntimeServicesReleased`, `binder.registerListener`
- **CURRENT BEHAVIOR:** `state` пишется из `commandExecutor` и из `mainHandler`
  (три пути); `emit` вызывается из двух потоков, что может дать
  `IllegalStateException` в `RemoteCallbackList.beginBroadcast`; `sequence` может
  нарушить порядок доставки; все ожидания реализованы как
  `mainHandler.postDelayed`-циклы.
- **TARGET BEHAVIOR:** введён внутренний тип
  `sealed interface RuntimeInput` с вариантами `Command` и `Event`, и единая точка
  `submitInternal(input)`, кладущая вход в `commandExecutor`. Все записи `state`,
  `mode`, generation, `lastError`, все `emit` и все `eventBuilder()` выполняются
  только внутри задач `commandExecutor`. `registerListener` не вызывает `emit`, а
  публикует `Event.Replay(listener)`. Опрос health переносится на
  `ScheduledExecutorService`, публикующий `Event.Health(...)`. Циклы `awaitRunning`,
  `awaitTransportReady`, `awaitRuntimeServicesReleased` удаляются; вместо них таймеры,
  публикующие `Event.Deadline(commandGeneration)`. `PREPARING` больше не выставляется.
- **IMPLEMENTATION:**
  1. Добавить `RuntimeInput` и `submitInternal`; `binder.submit` кладёт `Command`,
     все внутренние источники — `Event`.
  2. Перенести stage-переходы старта в обработчики событий `Launched`, `Health`,
     `Deadline`, `Released`. До прихода `HB-RW-009` роль `LaunchTask` играет
     существующий `dispatchStart` плюс событие `Launched`, публикуемое из стока
     событий `SingboxController`.
  3. Удалить `refreshFromController()`: состояние больше не выводится из
     `SingboxController.running`; сток событий превращается в
     `Event.ControllerEvent`, обрабатываемый на serializer.
  4. Добавить чистую функцию `reduce(state, input, ctx): Decision` в том же файле —
     только вычисление перехода, без побочных эффектов; действия выполняет вызывающий.
- **DELETE:** `refreshFromController`, `awaitRunning`, `awaitTransportReady`,
  `awaitRuntimeServicesReleased`, `transportHealthPoll` как `Runnable` на
  `mainHandler`, установка `RUNTIME_STATE_PREPARING`.
- **DO NOT CHANGE:** protobuf-схему снимка; дедлайны; `HydraBoxService`;
  probe-путь (он получит свой executor в `HB-RW-021`).
- **BACKWARD COMPATIBILITY:** значение `RUNTIME_STATE_PREPARING` остаётся в enum как
  deprecated; Dart-редьюсер обязан продолжать его понимать.
- **TESTS TO ADD FIRST:**
  - `RuntimeStateMachineTest` (JVM, на чистой `reduce`): START из STOPPED → STARTING;
    `Health` с READY → RUNNING; `Health` с challenge не меняет состояние и
    перевооружает дедлайн; `Deadline` → FAILED; `Launched` с устаревшим `cg`
    игнорируется.
  - `EmitSingleThreadTest`: `emit` вызывается только из потока с именем
    `HydraCoreRuntimeCommands` (через подменяемый hook на имя потока).
- **TESTS THAT MUST REMAIN UNCHANGED:** `CoreRuntimeSnapshotCompatibilityTest`,
  `ProbeExecutionModeTest`, `CoreCapabilityContractTest`.
- **VALIDATION:** `./gradlew :app:testDebugUnitTest :app:lintDebug`,
  `flutter test test/runtime_snapshot_reducer_test.dart`
- **MANUAL SCENARIO:** M01, M03, M13, M15
- **EXPECTED STRUCTURED LOG:** `sequence` в снимках возрастает без пропусков в
  пределах одного `ep`.
- **NEGATIVE ASSERTIONS:** ни одного `IllegalStateException` из `RemoteCallbackList`;
  ни одной записи `state` вне `commandExecutor`; в `CoreRuntimeService` нет
  `mainHandler.postDelayed`, кроме доставки тех Android-вызовов, которые требуют
  главного потока.
- **ROLLBACK:** revert; отдельный PR.
- **DEFINITION OF DONE:** тесты зелёные; M03 десять прогонов без противоречивых
  снимков; в файле нет `refreshFromController`.
- **STOP CONDITIONS:** если какой-либо Android-вызов из stage-переходов обязан
  выполняться на главном потоке и не может быть fire-and-forget — STOP и перечислить.
- **COMMIT BOUNDARY:** один PR, только `CoreRuntimeService.kt` плюс тесты.
- **NEXT TASK:** `HB-RW-009` при выполненных `HB-EXP-E2A` и `HB-EXP-E2B`.

---

## HB-RW-009 — Отменяемая задача запуска `LaunchTask`

- **STATUS:** BLOCKED(`HB-EXP-E2B`, `HB-RW-008`). `HB-EXP-E2A` выполнен, ветка **P1**
- **GOAL:** сделать незавершённый старт отменяемым объектом, чтобы STOP никогда не
  ждал блокирующий `startOrReloadService`.
- **INVARIANTS ESTABLISHED:** R3 (полностью), R9 (частично)
- **REPOSITORY:** hydrabox
- **BASELINE:** merge `HB-RW-008`
- **PRECONDITIONS:** `HB-RW-008`; `HB-EXP-E2A` и `HB-EXP-E2B` выполнены, ветка
  зафиксирована в §8
- **FILES / SYMBOLS:**
  - `singbox/HydraBoxService.kt` → переименовать файл и класс в
    `singbox/RuntimeSession.kt` / `RuntimeSession`; слить `startInternal`,
    `startOrReloadInternal`, `restartCoreInternal` в `run(plan, generation)`;
    добавить поле `activeLaunch: LaunchTask?`, методы `cancel(generation)`,
    `close(generation)`
  - `runtime/CoreRuntimeService.kt`: `dispatchStart`, `serviceClass`,
    `shutdownRuntimeServices` — переход на `RuntimeSession.run` / `cancel` / `close`
  - все ссылки на `HydraBoxService` в `CoreRuntimeService`, `HydraBoxVpnService`,
    `HydraBoxProxyService`, `SingboxController`, `MainActivity`
- **CURRENT BEHAVIOR:** `startOrReloadService` выполняется на
  `HydraBoxService.executor`; `stopInternal` попадает в тот же single-thread executor
  и ждёт завершения старта; `shutdownRuntimeServices` упирается в дедлайн 5 s и
  возвращает `stopped=false`, после чего Dart возвращает фазу в connected.
- **TARGET BEHAVIOR:** `run(plan, generation)` исполняется на выделенном потоке
  `RuntimeLaunch`; между стадиями проверяется `cancelled`; результат публикуется как
  `Event.Launched` либо `Event.LaunchFailed`. `cancel(generation)` — неблокирующий:
  выставляет `cancelled` и, по ветке `HB-EXP-E2B`, вызывает `closeService()` из
  потока отмены. Освобождение ресурсов делает `close(generation)` на потоке
  `RuntimeClose`, публикуя `Event.Released` либо `Event.ReleaseFailed`.
- **IMPLEMENTATION:**
  1. `LaunchTask` — приватный класс из трёх полей: `generation`, `thread`,
     `cancelled: AtomicBoolean`. Никаких менеджеров.
  2. Стадии `run`: `foreground`, `native_setup`, `network_wait`, `command_server`,
     `libbox_start`, `command_client`; перед каждой — проверка `cancelled` (точки
     уже существуют как `startTokenCurrent(token)`).
  3. `CloseTask` — та же структура на потоке `RuntimeClose`: `disconnectClientBlocking`,
     `closeService`, `close`, `stopForeground`, `monitor.stop()`.
  4. Ветка `HB-EXP-E2B` **P1**: `cancel` вызывает `closeService()` и `join(CLOSE_DEADLINE)`.
     Ветка **P2**: `cancel` только выставляет флаг; освобождение целиком у `CloseTask`;
     `join` без дедлайна запрещён.
- **DELETE:** `restartCoreInternal`, `runCleanupStep` (его роль берёт `CloseTask`),
  `retryExecutor` как отдельный механизм ожидания сети (ожидание становится стадией
  `network_wait` внутри `run`).
- **DO NOT CHANGE:** `prepareRuntimeConfig`, split-tunnel логику, `openTun`,
  wake-lock, notification presentation, число retry ожидания сети.
- **BACKWARD COMPATIBILITY:** переименование класса — внутреннее; манифест не
  меняется, потому что `HydraBoxVpnService` и `HydraBoxProxyService` остаются
  Android-компонентами и лишь создают `RuntimeSession`.
- **TESTS TO ADD FIRST:**
  - `RuntimeStateMachineTest`: STOP во время STARTING → STOPPING → STOPPED, START
    получает `runtime.cancelled`;
  - `LaunchCancellationInstrumentedTest` — созданный в `HB-EXP-E2B`, остаётся как
    regression;
  - `RuntimeSessionStageTest` (JVM): последовательность стадий и прерывание на
    каждой из шести стадий даёт `CANCELLED`, а не `LAUNCH_FAILED`.
- **TESTS THAT MUST REMAIN UNCHANGED:** `VpnServiceLifecyclePolicyTest`,
  `SplitTunnelPackagesTest`, `RuntimeTrafficRateTrackerTest`.
- **VALIDATION:** `./gradlew :app:testDebugUnitTest :app:lintDebug`;
  на устройстве `./gradlew :app:connectedAndroidTest`
- **MANUAL SCENARIO:** M02 (stop в течение 1 s после connect), M03 (start/stop/start
  пять раз по 0.5 s)
- **EXPECTED STRUCTURED LOG:**  

```
  HB1 <ts> CONNECT rg=0 prof=xxxxxxxx mode=vpn source=ui
  HB1 <ts> START rg=0 stage=libbox_start result=ok
  HB1 <ts> STOP rg=<n> reason=user stage=requested
  HB1 <ts> STOP rg=<n> reason=user stage=cancelled_launch elapsed_ms=<n>
  HB1 <ts> STOP rg=<n> reason=user stage=released elapsed_ms=<n>
```

- **NEGATIVE ASSERTIONS:** ни одного `runtime.stop.unconfirmed` в M02 и M03;
  фаза UI **не** возвращается в connected после STOP.
- **ROLLBACK:** revert; самый рискованный PR плана, мержится отдельно и первым в
  своём спринте.
- **DEFINITION OF DONE:** M02 и M03 по десять прогонов без
  `runtime.stop.unconfirmed`; `connectedAndroidTest` зелёный.
- **STOP CONDITIONS:** ветка `HB-EXP-E2B` = FAIL и `HC-RW-007` не смержен — STOP;
  реализовывать `join` без дедлайна запрещено.
- **COMMIT BOUNDARY:** один PR: переименование плюс `LaunchTask` плюс `CloseTask`.
- **NEXT TASK:** `HB-RW-010`.

---

## HB-RW-010 — Идемпотентность и дедупликация команд

- **STATUS:** BLOCKED(`HB-EXP-E2B`, `HB-RW-009`)
- **GOAL:** сделать результат любой последовательности START и STOP определённым.
- **INVARIANTS ESTABLISHED:** R19
- **REPOSITORY:** hydrabox
- **BASELINE:** merge `HB-RW-009`
- **PRECONDITIONS:** `HB-RW-009`
- **FILES / SYMBOLS:** `runtime/CoreRuntimeService.kt`: `execute`, `start`, `stop`,
  `reduce`, `commandSucceeded`, `commandFailed`; новое поле
  `activeCommand: ActiveCommand?` (`kind`, `configSha256`, `mode`, `commandGeneration`,
  `commandIds: MutableList<String>`)
- **CURRENT BEHAVIOR:** повторный START с тем же планом создаёт вторую попытку;
  двойной STOP даёт два независимых прохода `shutdownRuntimeServices`; вытесненная
  команда не получает результата (все stage-колбэки просто выходят по проверке
  generation).
- **TARGET BEHAVIOR:** по таблице §2.2: повторный START с тем же
  `(configSha256, mode)` не создаёт действий, а его `commandId` присоединяется к
  `activeCommand.commandIds`, и оба получают один результат; START с другим планом
  вытесняет предыдущий с `runtime.superseded`; двойной STOP присоединяется к тому же
  результату; `NETWORK_CHANGED` во время STOPPING отбрасывается; `SELECT_OUTBOUND` и
  `RELOAD` вне RUNNING отклоняются с явными кодами.
- **IMPLEMENTATION:** ввести `activeCommand`; в `reduce` добавить решения `NoOp`,
  `Join`, `Supersede`, `Reject`; `commandSucceeded` и `commandFailed` рассылают
  результат всем `commandIds`.
- **DELETE:** —
- **DO NOT CHANGE:** формат `CommandReceipt`; `validateCommand`; дедлайны.
- **BACKWARD COMPATIBILITY:** клиент уже умеет получать `CommandResult` по
  `commandId`; рассылка одного исхода нескольким id не требует изменений в
  `CoreRuntimeClient`.
- **TESTS TO ADD FIRST:** `RuntimeStateMachineTest`, дополнительные кейсы:
  START/STOP/START серией → одна финальная STARTING и ни одного висящего результата;
  STOP дважды → один результат на обе команды; START с тем же digest во время
  STARTING → `NoOp` плюс `Join`; смена профиля во время STARTING → `Supersede`;
  `NETWORK_CHANGED` во время STOPPING → `Reject`.
- **TESTS THAT MUST REMAIN UNCHANGED:** все существующие JVM- и Dart-тесты.
- **VALIDATION:** `./gradlew :app:testDebugUnitTest :app:lintDebug`
- **MANUAL SCENARIO:** M03, M16
- **EXPECTED STRUCTURED LOG:** в M03 значение `rg` монотонно возрастает и ровно один
  `READY`; для вытесненной команды в логе есть `STOP reason=superseded`.
- **NEGATIVE ASSERTIONS:** ни одной команды без `CommandResult`; ни одного второго
  `LaunchTask` при повторном START с тем же планом.
- **ROLLBACK:** revert.
- **DEFINITION OF DONE:** пять новых кейсов зелёные; M03 проходит.
- **STOP CONDITIONS:** если `CoreRuntimeClient` не может сопоставить результат
  нескольким `commandId` — STOP и сообщить.
- **COMMIT BOUNDARY:** один коммит.
- **NEXT TASK:** `HB-RW-011`.

---

## HB-RW-011 — Удалить токены старта

- **STATUS:** BLOCKED(`HB-RW-010`)
- **GOAL:** оставить одну величину инвалидации вместо двух.
- **INVARIANTS ESTABLISHED:** R6
- **REPOSITORY:** hydrabox
- **BASELINE:** merge `HB-RW-010`
- **PRECONDITIONS:** `HB-RW-010`
- **FILES / SYMBOLS:**
  - `singbox/SingboxController.kt`: удалить `nextStartToken`, `cancelStartTokens`,
    `isStartTokenCurrent`, `runtimeStartGeneration`
  - `singbox/RuntimeSession.kt`: удалить `startRequestGeneration`, `nextStartToken`,
    `cancelStartRequests`, `startTokenCurrent`, `cancelPendingStartRetry`
- **CURRENT BEHAVIOR:** старт инвалидируется двумя независимыми счётчиками:
  `runtimeStartGeneration` в `SingboxController` и `commandGeneration` в
  `CoreRuntimeService`.
- **TARGET BEHAVIOR:** единственная величина — `commandGeneration`, передаваемая в
  `run(plan, generation)`; проверки `startTokenCurrent(token)` заменяются на
  `launch.generation == currentCommandGeneration && !cancelled`.
- **IMPLEMENTATION:** заменить проверки; удалить символы.
- **DELETE:** восемь перечисленных символов.
- **DO NOT CHANGE:** `activeRuntimeGeneration` (это `runtimeGeneration`, удаляется
  из `SingboxController` только в `HB-RW-029`).
- **BACKWARD COMPATIBILITY:** внешнего контракта не касается.
- **TESTS TO ADD FIRST:** `RuntimeSessionStageTest` — прерывание по `commandGeneration`
  вместо токена.
- **TESTS THAT MUST REMAIN UNCHANGED:** все.
- **VALIDATION:** `./gradlew :app:testDebugUnitTest :app:lintDebug`
- **MANUAL SCENARIO:** M03
- **EXPECTED STRUCTURED LOG:** без изменений.
- **NEGATIVE ASSERTIONS:** `grep -rn "startToken|runtimeStartGeneration" android/app/src/main`
  даёт ноль совпадений.
- **ROLLBACK:** revert.
- **DEFINITION OF DONE:** grep пустой; M03 проходит.
- **STOP CONDITIONS:** если найдётся место, где токен несёт смысл, отличный от
  `commandGeneration` — STOP.
- **COMMIT BOUNDARY:** один коммит.
- **NEXT TASK:** `HB-RW-012`.

---

## HB-RW-012 — Durable desired state и reconciliation

- **STATUS:** BLOCKED(`HB-RW-004`)
- **GOAL:** ввести единственный durable файл желаемого состояния и детерминированное
  восстановление после смерти процесса.
- **INVARIANTS ESTABLISHED:** R7, R8, R9, R20
- **REPOSITORY:** hydrabox
- **BASELINE:** merge `HB-RW-004`
- **PRECONDITIONS:** `HB-RW-004`
- **FILES / SYMBOLS:**
  - `HydraBoxApplication.kt`: добавить `desiredRuntimeFile`, `DesiredRuntime`,
    `readDesiredRuntime()`, `writeDesiredRuntime(...)`; оставить пока
    `runtimeIntentFile` для одноразовой миграции
  - `runtime/CoreRuntimeService.kt`: `onCreate` — добавить `reconcile()`;
    `start`, `stop`, `failRuntime` — единственные писатели desired state
- **CURRENT BEHAVIOR:** желаемое состояние выводится из
  `singbox-runtime-intent.txt` с полями `pid`, `mode`, `reason`, без TTL; писателей
  пять (`CoreRuntimeService.shutdownRuntimeServices`, `HydraBoxService.startInternal`,
  `startOrReloadInternal`, `stopInternal`, `HydraBoxVpnService.onRevoke`);
  восстановление после смерти процесса делает `shouldRestoreStickyStart` без
  ограничения числа попыток.
- **TARGET BEHAVIOR:** файл `runtime-desired.txt` по схеме §2.5; единственный
  писатель — serializer; `reconcile()` по алгоритму §2.7; `recoveryAttempt`
  ограничивает автоматические попытки двумя.
- **IMPLEMENTATION:**
  1. Реализовать чтение и запись файла через существующий `writeAtomicText`.
  2. Одноразовая миграция: если `runtime-desired.txt` отсутствует, а
     `singbox-runtime-intent.txt` существует, прочитать из него `mode` и считать
     `wantRunning=true`, `recoveryAttempt=0`, `configSha256` — из фактического файла
     конфига. Пометить комментарием «удаляется в `HB-RW-033`».
  3. `reconcile()` вызывается в конце `onCreate` через `submitInternal(Event.Reconcile)`,
     то есть выполняется на serializer.
  4. `failRuntime` (любой вход в FAILED) выставляет `wantRunning=false`.
- **DELETE:** —
- **DO NOT CHANGE:** `configFile`; `serviceStateFile` (удаляется в `HB-RW-013`);
  quarantine-логику.
- **BACKWARD COMPATIBILITY:** миграция обязательна, иначе после обновления
  приложения работающий VPN не восстановится при первом же убийстве процесса.
- **TESTS TO ADD FIRST:** `DesiredStateTest` (JVM, на чистых функциях):
  `wantRunning=false` → `reconcile` возвращает `Decision.None`;
  `configSha256` не совпал → `FAILED(config.stale)` без запуска;
  `recoveryAttempt=3` → `FAILED(runtime.recovery.exhausted)`;
  таблица переходов durable состояния из §2.5 проверяется целиком;
  парсер файла игнорирует неизвестные ключи и отвергает `schema != 1`.
- **TESTS THAT MUST REMAIN UNCHANGED:** `RuntimeServiceModeResolverTest`,
  `CoreCapabilityContractTest`, `CoreRuntimeSnapshotCompatibilityTest`.
  (`CoreBundleUpdaterTest` к этому моменту уже удалён задачей `HB-RW-042`.)
- **VALIDATION:** `./gradlew :app:testDebugUnitTest :app:lintDebug`
- **MANUAL SCENARIO:** M05 (`adb shell am kill` процесса `:core`), M06 (отзыв
  VPN-разрешения)
- **EXPECTED STRUCTURED LOG:**  

```
  HB1 <ts> EPOCH ep=<new> native_source=embedded api=2.1
  HB1 <ts> CONNECT rg=0 prof=xxxxxxxx mode=vpn source=recovery attempt=1
```
  а при `wantRunning=false` — только `EPOCH` и ни одного `CONNECT`.
- **NEGATIVE ASSERTIONS:** после входа в FAILED и последующего убийства процесса в
  логе **нет** `CONNECT source=recovery`; после трёх подряд неудачных
  автовосстановлений — нет четвёртого.
- **ROLLBACK:** revert; при откате читается старый intent-файл, поведение
  возвращается к текущему.
- **DEFINITION OF DONE:** `DesiredStateTest` зелёный; M05 и M06 проходят;
  запрещённый сценарий «FAILED → смерть процесса → retry» воспроизвести не удаётся.
- **STOP CONDITIONS:** если `onCreate` не может выполнить `reconcile` до первого
  binder-вызова без гонки — STOP и сообщить.
- **COMMIT BOUNDARY:** один PR.
- **NEXT TASK:** `HB-RW-013`, `HB-RW-014` (параллельно); `HB-RW-012B` после
  `HB-RW-009`.

---

## HB-RW-012

B — Sticky restart через serializer

- **STATUS:** BLOCKED(`HB-RW-009`, `HB-RW-012`)
- **GOAL:** убрать самостоятельное решение `RuntimeSession` о sticky-restart.
- **INVARIANTS ESTABLISHED:** R1, R7
- **REPOSITORY:** hydrabox
- **BASELINE:** merge `HB-RW-012` и `HB-RW-009`
- **PRECONDITIONS:** обе указанные задачи
- **FILES / SYMBOLS:** `singbox/RuntimeSession.kt`: `onStartCommand`
  (ветка `action == null`), `shouldRestoreStickyStart`;
  `runtime/CoreRuntimeService.kt`: обработчик `Event.StickyRestart`
- **CURRENT BEHAVIOR:** при `onStartCommand(null)` сервис сам читает
  `isRuntimeIntentFresh(mode)` и файл конфига и сам решает запускаться.
- **TARGET BEHAVIOR:** `onStartCommand(null)` показывает foreground-нотификацию со
  статусом «Connecting» и публикует `Event.StickyRestart(mode)` в serializer;
  решение принимает `reconcile()`-логика (§2.7).
- **IMPLEMENTATION:** заменить тело ветки; удалить `shouldRestoreStickyStart`.
- **DELETE:** `shouldRestoreStickyStart`.
- **DO NOT CHANGE:** возвращаемое значение `START_STICKY` / `START_NOT_STICKY`
  для остальных ветвей.
- **BACKWARD COMPATIBILITY:** нотификация обязана быть показана до любой
  асинхронной работы, иначе Android убьёт сервис.
- **TESTS TO ADD FIRST:** `DesiredStateTest` — кейс sticky-restart при
  `wantRunning=false` не запускает runtime.
- **TESTS THAT MUST REMAIN UNCHANGED:** `VpnServiceLifecyclePolicyTest`.
- **VALIDATION:** `./gradlew :app:testDebugUnitTest :app:lintDebug`
- **MANUAL SCENARIO:** M05, M06
- **EXPECTED STRUCTURED LOG:** `HB1 ... CONNECT ... source=sticky attempt=<n>`
- **NEGATIVE ASSERTIONS:** при `wantRunning=false` sticky-restart не поднимает runtime.
- **ROLLBACK:** revert.
- **DEFINITION OF DONE:** M05 и M06 проходят; grep по `shouldRestoreStickyStart` пуст.
- **STOP CONDITIONS:** если `CoreRuntimeService` в момент `onStartCommand(null)` может
  быть не создан — STOP и сообщить (тогда нужен явный `startService` на себя).
- **COMMIT BOUNDARY:** один коммит.
- **NEXT TASK:** `HB-RW-013`.

---

## HB-RW-013 — Удалить persisted «сервис жив» и Dart-флаги желания

- **STATUS:** BLOCKED(`HB-RW-012`)
- **GOAL:** убрать все persisted утверждения о живости и свести Dart-intent к проекции
  durable состояния.
- **INVARIANTS ESTABLISHED:** R20, R7
- **REPOSITORY:** hydrabox
- **BASELINE:** merge `HB-RW-012`
- **PRECONDITIONS:** `HB-RW-012`
- **FILES / SYMBOLS:**
  - `HydraBoxApplication.kt`: удалить `ServiceState`, `serviceStateFile`,
    `writeServiceState`, `clearServiceState`, `readServiceState`,
    `isRecordedServiceAlive`, `describeRecordedServiceState`
  - `singbox/RuntimeSession.kt`: удалить вызовы `writeServiceState`,
    `clearServiceState`
  - `singbox/HydraBoxVpnService.kt`: `onRevoke` — вместо `clearRuntimeIntent()`
    отправить `STOP(reason=vpn_revoked)` в serializer
  - `lib/app/runtime_intent_controller.dart`: удалить
    `restoreDesiredFromObservedRuntime`, `_retryOnResume`, `consumeRetryOnResume`,
    `deferRetryUntilResume`, `clearRetryOnResume`, `_queuedRestartSuppressed`,
    `_explicitStopInProgress`; `_desiredByUser` становится проекцией
    `snapshot.desiredRuntime.wantRunning`
  - `lib/app/app.dart`: снять все вызовы удалённых методов
- **CURRENT BEHAVIOR:** файл с pid и `/proc`-проверкой служит утверждением «сервис
  жив» и читается из главного процесса; Dart держит шесть независимых флагов желания.
- **TARGET BEHAVIOR:** файла нет; Dart-intent — проекция снимка плюс
  `_manualStartGeneration` и очередь «start after stop».
- **IMPLEMENTATION:** добавить `desiredRuntime` в protobuf-снимок и в Pigeon
  (аддитивно), перегенерировать Pigeon; удалить перечисленное.
- **DELETE:** семь символов в `HydraBoxApplication`, семь в
  `RuntimeIntentController`, файл `singbox-service-state.txt` перестаёт создаваться.
- **DO NOT CHANGE:** `_manualStartGeneration`, `queueStartAfterStop`,
  `completeSuccessfulStop`, `_scheduleInvalidOutboundRetry`.
- **BACKWARD COMPATIBILITY:** оставшийся на устройстве старый файл игнорируется;
  удалять его не нужно.
- **TESTS TO ADD FIRST:**
  - `test/runtime_intent_controller_test.dart` — расширить: intent следует за
    `wantRunning` из снимка; `restoreDesiredFromObservedRuntime` отсутствует;
  - `test/binder_reconnect_test.dart` (новый): потеря и восстановление binder при том
    же `processEpoch` не меняет фазу и не меняет intent.
- **TESTS THAT MUST REMAIN UNCHANGED:** `runtime_session_coordinator_test.dart`.
- **VALIDATION:** `dart run pigeon --input pigeons/singbox_api.dart`, `dart format .`,
  `flutter analyze`, `flutter test`,
  `./gradlew :app:testDebugUnitTest :app:lintDebug`,
  `python3 -B scripts/verify_client_boundaries.py`
- **MANUAL SCENARIO:** M05, M06
- **EXPECTED STRUCTURED LOG:** при `onRevoke` — `HB1 ... STOP reason=vpn_revoked
  stage=requested`, затем `stage=released`.
- **NEGATIVE ASSERTIONS:**
  `grep -rn "serviceStateFile

|isRecordedServiceAlive|describeRecordedServiceState|restoreDesiredFromObservedRuntime|_retryOnResume" lib android/app/src/main`
  даёт ноль совпадений.
- **ROLLBACK:** revert одного PR.
- **DEFINITION OF DONE:** grep пустой; M05 и M06 проходят.
- **STOP CONDITIONS:** если Quick Settings tile ещё читает удалённые методы —
  выполнить `HB-RW-015` первым и сообщить об изменении порядка.
- **COMMIT BOUNDARY:** один PR: Kotlin, Pigeon, Dart.
- **NEXT TASK:** `HB-RW-014`, `HB-RW-015`.

---

## HB-RW-014 — Событие смены `processEpoch` и обнуление кэшей UI

- **STATUS:** BLOCKED(`HB-RW-012`)
- **GOAL:** сделать смерть процесса `:core` наблюдаемой для UI и заставить UI
  сбрасывать локальные кэши.
- **INVARIANTS ESTABLISHED:** R2, R6
- **REPOSITORY:** hydrabox
- **BASELINE:** merge `HB-RW-012`
- **PRECONDITIONS:** `HB-RW-012`
- **FILES / SYMBOLS:**
  - `runtime/CoreRuntimeClient.kt`: `listener.onEvent`, `cachedProcessEpoch`;
    добавить выдачу события `epochChanged` в `eventConsumers`
  - `lib/app/runtime_event_controller.dart`: обработка `epochChanged`
  - `lib/app/app.dart`: реакция — обнулить `_runtimeOperations`, latency-кэши,
    `_pendingVkCaptchaId`, `_pendingVkCaptchaUri`, `_lastVkCaptchaId`,
    `_runtimeStartupUrlTestGate`, `_networkInterfaceGeneration`
- **CURRENT BEHAVIOR:** `processEpoch` присутствует в снимке и в
  `cachedProcessEpoch()`, но ни один Dart-читатель его не сравнивает; после смерти
  процесса UI продолжает считать актуальными latency, выбранный outbound и
  ожидающую CAPTCHA.
- **TARGET BEHAVIOR:** при получении снимка с новым `processEpoch` клиент публикует
  `epochChanged`; UI обнуляет перечисленные кэши и строит фазу заново из снимка.
- **IMPLEMENTATION:** хранить последний `processEpoch` в `CoreRuntimeClient`;
  при изменении публиковать событие **до** прочих событий этого снимка.
- **DELETE:** —
- **DO NOT CHANGE:** `latestSnapshot` как кэш; порядок остальных событий.
- **BACKWARD COMPATIBILITY:** событие аддитивное; старый Dart-код его игнорирует.
- **TESTS TO ADD FIRST:**
  - `test/runtime_event_controller_test.dart` — расширить: `epochChanged`
    доставляется первым при смене epoch и не доставляется при том же epoch;
  - `ProcessEpochTest` (JVM): последовательность двух снимков с разными epoch даёт
    ровно одно событие.
- **TESTS THAT MUST REMAIN UNCHANGED:** `test/latency_coordinator_test.dart`,
  `test/proxy_runtime_controller_test.dart`.
- **VALIDATION:** `flutter analyze`, `flutter test`,
  `./gradlew :app:testDebugUnitTest :app:lintDebug`
- **MANUAL SCENARIO:** M05 — после убийства `:core` список задержек очищается,
  ожидающая CAPTCHA не открывается повторно, фаза строится из нового снимка.
- **EXPECTED STRUCTURED LOG:** `HB1 ... EPOCH ep=<new>` и следом реакция UI в
  журнале приложения.
- **NEGATIVE ASSERTIONS:** после смены epoch UI не показывает задержки, измеренные
  до смерти процесса; не открывает старый captcha-URL.
- **ROLLBACK:** revert.
- **DEFINITION OF DONE:** тесты зелёные; M05 проходит.
- **STOP CONDITIONS:** если обнуление кэшей ломает восстановление выбранного
  outbound — STOP: выбранный outbound приходит из снимка и обнуляться не должен.
- **COMMIT BOUNDARY:** один PR.
- **NEXT TASK:** `HB-RW-015`, `HB-RW-016`.

---

## HB-RW-015 — Quick Settings tile читает снимок

- **STATUS:** BLOCKED(`HB-RW-012`)
- **GOAL:** убрать из тайла файловый источник истины и три таймера обновления.
- **INVARIANTS ESTABLISHED:** R2, R20
- **REPOSITORY:** hydrabox
- **BASELINE:** merge `HB-RW-012`
- **PRECONDITIONS:** `HB-RW-012`
- **FILES / SYMBOLS:** `HydraBoxQuickSettingsTileService.kt`: `activeRuntimeMode`,
  `scheduleRefreshes`, `onStartListening`, `onStopListening`, `updateTile`,
  `startRuntime`, `stopRuntime`
- **CURRENT BEHAVIOR:** состояние тайла вычисляется как
  `isRecordedServiceAlive(mode)` по файлу и `/proc`; обновление — три `postDelayed`
  на 350, 1200 и 2500 ms; целевой режим определяется парсингом `configFile`.
- **TARGET BEHAVIOR:** на `onStartListening` тайл вызывает
  `coreRuntimeClient.connect()` и регистрирует слушателя; состояние — из
  `snapshot.state`; целевой режим — из `snapshot.desiredRuntime.mode`, а при
  отсутствии желаемого — из парсинга конфига (как сейчас); на `onStopListening`
  слушатель снимается.
- **IMPLEMENTATION:** заменить `activeRuntimeMode()` на чтение снимка; удалить
  `scheduleRefreshes`; добавить регистрацию и снятие слушателя.
- **DELETE:** `activeRuntimeMode`, `scheduleRefreshes`.
- **DO NOT CHANGE:** `readActiveTileLabel`, `formatActiveLabel`, `openApp`,
  `openIntent`, работу с `VpnService.prepare`.
- **BACKWARD COMPATIBILITY:** если binder не успел подключиться, тайл показывает
  прежнее состояние и обновится по событию, а не по таймеру.
- **TESTS TO ADD FIRST:** `QuickTileStateTest` (JVM): чистая функция
  `tileActiveFor(state)` возвращает `true` только для `RUNNING`, `STARTING`,
  `RECOVERING`; `false` для остальных.
- **TESTS THAT MUST REMAIN UNCHANGED:** `RuntimeServiceModeResolverTest`.
- **VALIDATION:** `./gradlew :app:testDebugUnitTest :app:lintDebug`
- **MANUAL SCENARIO:** M20 — старт и стоп из тайла, состояние обновляется без
  видимой задержки и без «дребезга».
- **EXPECTED STRUCTURED LOG:** `HB1 ... CONNECT ... source=tile`
- **NEGATIVE ASSERTIONS:** в файле нет ни одного `postDelayed`; нет обращений к
  `isRecordedServiceAlive`.
- **ROLLBACK:** revert.
- **DEFINITION OF DONE:** M20 проходит; grep по `postDelayed` в файле пуст.
- **STOP CONDITIONS:** если `TileService` не позволяет держать binder между
  `onStartListening` и `onStopListening` — STOP и сообщить.
- **COMMIT BOUNDARY:** один коммит.
- **NEXT TASK:** `HB-RW-016`.

---

## HB-RW-016 — Ограниченный rebind binder-клиента

- **STATUS:** READY
- **GOAL:** устранить неограниченный цикл bind → crash → bind.
- **INVARIANTS ESTABLISHED:** R9
- **REPOSITORY:** hydrabox
- **BASELINE:** merge `HB-RW-002`
- **PRECONDITIONS:** `HB-RW-002`
- **FILES / SYMBOLS:** `runtime/CoreRuntimeClient.kt`: `connection.onBindingDied`,
  `onNullBinding`, `onServiceConnected`, `connect`, `disconnect`
- **CURRENT BEHAVIOR:** `onBindingDied` безусловно вызывает `connect()`. Если
  `CoreRuntimeService.onCreate` бросает исключение, цикл повторяется бесконечно,
  без счётчика и без backoff.
- **TARGET BEHAVIOR:** счётчик `rebindAttempt`: `onBindingDied` вызывает `connect()`
  не более трёх раз подряд без успешного `onServiceConnected`; на четвёртой попытке
  публикуется `CoreRuntimeException("runtime.ipc.unavailable", stage="ipc",
  retryable=false)` с причиной из `CoreStartupFailureStore.readFresh()`, и автопопытки
  прекращаются. Счётчик сбрасывается в `onServiceConnected`. Явный вызов `connect()`
  из UI (например при нажатии Connect) сбрасывает счётчик и разрешает новую серию.
- **IMPLEMENTATION:** добавить поле-счётчик под тем же `lock`; в `onBindingDied`
  проверять предел; ввести `fun reconnectFromUser()` для явного сброса, вызываемый из
  `MainActivity` перед отправкой пользовательской команды START.
- **DELETE:** —
- **DO NOT CHANGE:** `SERVICE_BIND_DEADLINE_MILLIS`; поведение `onServiceDisconnected`
  (это не смерть биндинга, а временный разрыв, там `connect` не вызывается).
- **BACKWARD COMPATIBILITY:** при нормальной работе поведение не меняется.
- **TESTS TO ADD FIRST:** `BoundedRebindTest` (JVM, чистая функция
  `shouldRebind(attempt: Int): Boolean` плюс класс-обёртка счётчика): три попытки
  разрешены, четвёртая нет; успешное подключение сбрасывает счётчик; явный
  пользовательский вызов сбрасывает счётчик.
- **TESTS THAT MUST REMAIN UNCHANGED:** `CommandClientLifecycleTest`.
- **VALIDATION:** `./gradlew :app:testDebugUnitTest :app:lintDebug`
- **MANUAL SCENARIO:** искусственно сломать `:core` (например переименовать
  `libbox.aar`-класс в тестовой сборке нельзя, поэтому использовать
  `CoreStartupFailureStore`-фикстуру): убедиться, что после трёх попыток UI получает
  `runtime.ipc.unavailable`, а не зависает в бесконечном цикле.
- **EXPECTED STRUCTURED LOG:** три строки о попытке bind и одна финальная с кодом
  `runtime.ipc.unavailable`.
- **NEGATIVE ASSERTIONS:** в logcat нет более трёх подряд `bindService` без
  `onServiceConnected`.
- **ROLLBACK:** revert; независимая задача.
- **DEFINITION OF DONE:** `BoundedRebindTest` зелёный; ручной сценарий подтверждает
  остановку после трёх попыток.
- **STOP CONDITIONS:** если ветка `onNullBinding` в реальности встречается при
  нормальном старте — STOP и сообщить.
- **COMMIT BOUNDARY:** один коммит.
- **NEXT TASK:** `HB-RW-017`.

---

## HB-RW-017 — `NETWORK_CHANGED` становится командой

- **STATUS:** BLOCKED(`HB-RW-010`)
- **GOAL:** убрать конкуренцию сетевых событий со START и STOP.
- **INVARIANTS ESTABLISHED:** R1, R3
- **REPOSITORY:** hydrabox
- **BASELINE:** merge `HB-RW-011`
- **PRECONDITIONS:** `HB-RW-011`
- **FILES / SYMBOLS:**
  - `runtime/proto` — добавить `COMMAND_KIND_NETWORK_CHANGED` и payload
    `NetworkChanged { network_generation, interface_name, interface_index, available }`
  - `runtime/CoreRuntimeService.kt` — обработчик команды: `setUnderlyingNetworks`,
    `updateDefaultInterface`, обновление `networkSnapshot`, публикация события
  - `singbox/HydraBoxDefaultNetworkMonitor.kt` — вместо прямых вызовов
    `HydraBoxVpnService.setUnderlyingNetwork` и `notifyListeners` публиковать команду
    через новый внутрипроцессный вход `CoreRuntimeService.submitInternalNetwork(...)`
  - `singbox/SingboxController.kt` — удалить `emitNetworkChanged`
  - `singbox/HydraBoxVpnService.kt` — убрать fallback-политику из
    `setUnderlyingNetwork`
- **CURRENT BEHAVIOR:** монитор напрямую вызывает `setUnderlyingNetworks`, напрямую
  доставляет `updateDefaultInterface` в libbox и напрямую эмитит событие через
  `SingboxController`; всё это может произойти между стадиями старта.
- **TARGET BEHAVIOR:** монитор только вычисляет решение и публикует команду; всё
  применение — в serializer, с guard-ами §2.2 (в STOPPING отбрасывается, в STARTING
  применяется underlying, но `RebindNetwork` не вызывается).
- **IMPLEMENTATION:** добавить kind и payload аддитивно; перенести три действия в
  обработчик; в мониторе оставить расчёт и публикацию.
- **DELETE:** `SingboxController.emitNetworkChanged`; fallback-ветка в
  `HydraBoxVpnService.setUnderlyingNetwork` (логика переезжает в обработчик).
- **DO NOT CHANGE:** алгоритм выбора сети, debounce, heartbeat (это `HB-RW-018`).
- **BACKWARD COMPATIBILITY:** `NetworkSnapshot` в снимке сохраняет формат.
- **TESTS TO ADD FIRST:** `RuntimeStateMachineTest` — кейсы `NETWORK_CHANGED` в
  STOPPING отбрасывается; в STARTING применяет underlying и не вызывает
  `RebindNetwork`; в RUNNING делает и то и другое.
- **TESTS THAT MUST REMAIN UNCHANGED:** `DefaultNetworkSelectionTest`,
  `IdentityListenerRegistryTest`, `EffectiveNetworkIndexTest`.
- **VALIDATION:** `./gradlew :app:testDebugUnitTest :app:lintDebug`,
  `flutter test`
- **MANUAL SCENARIO:** M10 (handover в момент initial connect), M07
- **EXPECTED STRUCTURED LOG:** в M10 присутствует `NETWORK`, но `REBIND` отсутствует
  до `READY`.
- **NEGATIVE ASSERTIONS:** в `HydraBoxDefaultNetworkMonitor` нет ни одного вызова
  `HydraBoxVpnService` и ни одного вызова `InterfaceUpdateListener` напрямую.
- **ROLLBACK:** revert.
- **DEFINITION OF DONE:** M10 проходит; grep подтверждает отсутствие прямых вызовов.
- **STOP CONDITIONS:** если `updateDefaultInterface` обязан вызываться из потока
  монитора по требованию libbox — STOP и сообщить.
- **COMMIT BOUNDARY:** один PR.
- **NEXT TASK:** `HB-RW-018` при выполненном `HB-EXP-E4`; `HC-RW-002`.

---

## HB-RW-018 — Один детерминированный сетевой переход

- **STATUS:** BLOCKED(`HB-RW-017`). `HB-EXP-E4` выполнен, ветка **P1** плюс находка о мёртвом поле
- **GOAL:** свести восемь механизмов монитора к одному переходу и одной
  `networkGeneration`.
- **INVARIANTS ESTABLISHED:** R4, R6
- **REPOSITORY:** hydrabox
- **BASELINE:** merge `HB-RW-017`
- **PRECONDITIONS:** `HB-RW-017`; `HB-EXP-E4` выполнен, ветка зафиксирована
- **FILES / SYMBOLS:** `singbox/HydraBoxDefaultNetworkMonitor.kt`: `updateNetwork`,
  `notifyListener`, `notifyListenerInternal`, `markInterfaceState`,
  `reassertDefaultInterface`, `heartbeatTick`, `addListener`, `notificationGeneration`,
  `resolveBestNetwork`; `singbox/RuntimeSession.kt` — удалить вызовы
  `reassertDefaultInterface` после `startOrReloadService` и отложенный повтор
- **CURRENT BEHAVIOR:** `EffectiveUnderlyingNetwork` вычисляется дважды — в
  `updateNetwork` и повторно в `notifyListenerInternal` спустя 1500 ms;
  `notificationGeneration` инкрементируется при каждом `notifyListener`, включая
  `reassert` и `addListener`; существуют параметры `force`, `notifyDuplicate`,
  `targetListener`; публичный `reassertDefaultInterface` вызывается из шести мест.
- **TARGET BEHAVIOR:** один вход `onSnapshot(trigger: String)`; один расчёт
  `EffectiveUnderlyingNetwork` на слепок; `networkGeneration` растёт **только** при
  семантическом неравенстве кортежа (`androidNetworkId`, `interfaceName`,
  `interfaceIndex`); подключение нового listener обслуживается отдельной операцией
  `replayTo(listener)` без инкремента; `heartbeatTick` сводится к
  `onSnapshot("heartbeat")`; публичный `reassertDefaultInterface` удаляется.
- **IMPLEMENTATION:**
  1. Ввести `data class NetworkIdentity` и `PhysicalNetworkSnapshot`.
  2. Слить `updateNetwork` и `notifyListenerInternal` в `onSnapshot`.
  3. Заменить `notificationGeneration` на `networkGeneration` с новым условием
     инкремента.
  4. Удалить `force`, `notifyDuplicate`, `targetListener`; добавить `replayTo`.
  5. `HB-EXP-E4` дал ветку **P1**: удалить слагаемое `isActive` (+40) из
     `networkScore`. Дополнительная находка того же эксперимента: поле
     `DefaultNetworkCandidate.isActive` **вообще не читается** в
     `selectDefaultNetworkCandidate`, который использует только `isValidated`,
     `hasUsableInterface`, `score` и `value`. Поэтому поле удаляется вместе с
     параметром конструктора и его заполнением в `resolveBestNetwork`.
- **DELETE:** `reassertDefaultInterface` (публичный), три параметра доставки,
  второй вызов `resolveBestNetwork`, отложенный reassert в `RuntimeSession`.
- **DO NOT CHANGE:** `DefaultNetworkSelection.selectDefaultNetworkCandidate` порядок
  предпочтений; величину debounce; интервал heartbeat; `HydraBoxLocalResolver`.
- **BACKWARD COMPATIBILITY:** `NetworkSnapshot.generation` в снимке продолжает
  заполняться, но теперь монотонно и семантически.
- **TESTS TO ADD FIRST:** `EffectiveNetworkTest` (JVM, на чистых функциях):
  два идентичных слепка → один `networkGeneration` и ноль `updateDefaultInterface`;
  Wi-Fi → cellular → инкремент, один underlying, один rebind;
  Wi-Fi → NONE → cellular → ровно один `updateDefaultInterface("", -1)`;
  подключение нового listener не меняет `networkGeneration`.
- **TESTS THAT MUST REMAIN UNCHANGED:** `DefaultNetworkSelectionTest`,
  `EffectiveNetworkIndexTest`, `IdentityListenerRegistryTest`,
  `RuntimeEventCadenceTest`.
- **VALIDATION:** `./gradlew :app:testDebugUnitTest :app:lintDebug`
- **MANUAL SCENARIO:** M07, M08, M09, M10 — по три прогона, обязательно включая
  Xiaomi/HyperOS либо realme.
- **EXPECTED STRUCTURED LOG:** в M07 ровно три `NETWORK` с `branch=changed` и ровно
  три `REBIND`.
- **NEGATIVE ASSERTIONS:** ни одного `REBIND` без соответствующего `NETWORK`;
  ни одного `NETWORK` с `branch=changed` при семантически неизменной сети.
- **ROLLBACK:** revert; отдельный PR, высокий риск на OEM-прошивках.
- **DEFINITION OF DONE:** число `REBIND` строго равно числу семантических смен сети
  во всех прогонах M07 и M08.
- **STOP CONDITIONS:** если на любом устройстве после задачи трафик не восстанавливается
  за 30 s после handover — STOP, не «добавлять reassert обратно».
- **COMMIT BOUNDARY:** один PR, только монитор плюс снятие вызовов в `RuntimeSession`.
- **NEXT TASK:** `HC-RW-004` при выполненном `HB-EXP-E10`.

---

## HC-RW-002 — Один writer transport health, per-generation, домены сбоя

- **STATUS:** BLOCKED(`HC-RW-001`)
- **GOAL:** сделать `healthLoop` единственным писателем health, привязать снимки к
  generation и добавить домен и признак терминальности — аддитивно.
- **INVARIANTS ESTABLISHED:** R5, R14, R18
- **REPOSITORY:** hydracore
- **BASELINE:** merge `HC-RW-001`
- **PRECONDITIONS:** `HC-RW-001`
- **FILES / SYMBOLS:**
  - `common/hydracore/runtime_transport.go`: `runtimeTransportState`,
    `PublishTransportHealth`, `CurrentTransportHealth`, `TransportHealthSnapshot`,
    `TransportFailure`, `ResetRuntimeTransportState`
  - `transport/call/vk/vk_auth.go`: `solveVKCaptcha`
  - `transport/call/vk-parasite/supervisor.go`: `transportFailure`
  - `experimental/libbox/hydracore_capabilities.go`: `HydraCoreTransportState`
- **CURRENT BEHAVIOR:** `runtimeTransportState` — package-global с единственным
  слотом; писателей два (`publishObservedHealth` и `solveVKCaptcha`), при этом
  комментарий в `supervisor.go` утверждает, что публикатор один;
  `TransportFailure` не несёт домена и признака терминальности.
- **TARGET BEHAVIOR:** `PublishTransportHealth(generation uint64, snapshot)`
  отбрасывает снимки с `generation` меньше текущей;
  `SetRuntimeGeneration(uint64)` устанавливает текущую;
  `TransportHealthSnapshot` получает поля `Applicable`, `RuntimeGeneration`,
  `NetworkGeneration`; `TransportFailure` получает `Domain` и `Terminal`;
  `solveVKCaptcha` больше не публикует health.
- **IMPLEMENTATION:**
  1. Добавить поля в структуры с JSON-тегами `applicable`, `runtime_generation`,
     `network_generation`, `domain`, `terminal`. `schema_version` остаётся `2`.
  2. Ввести `generation` в `runtimeTransportState` и guard в `PublishTransportHealth`.
  3. Удалить вызов `HC.PublishTransportHealth` из `solveVKCaptcha`; оставить
     `PublishRuntimeChallenge`.
  4. `transportFailure(err)` заполняет `Domain` из `ControlPlaneError.Kind` и `Stage`
     по таблице: `captcha` → `AUTH` + `Terminal=false`; `credentials` → `CREDENTIALS`;
     `turn` → `TURN`; `dtls` → `DTLS`; `quic` → `QUIC`; сетевые ошибки → `NETWORK`;
     остальное → `INTERNAL`.
- **DELETE:** вызов `HC.PublishTransportHealth` в `solveVKCaptcha`.
- **DO NOT CHANGE:** значения `state`; `schema_version`; `APIVersion`;
  `CapabilitiesJSON()`; число workers; тайминги.
- **BACKWARD COMPATIBILITY:** обязательна. Новые ключи аддитивны, старый Android
  читает `schema_version == 2` и игнорирует их. Ключи в `features` капабилити не
  добавляются вовсе, поэтому `bundleApiMajor()` не может вернуть 1.
- **TESTS TO ADD FIRST:** `common/hydracore/runtime_transport_test.go`:
  снимок с устаревшим `generation` отбрасывается; после `ClearRuntimeChallenge`
  снимок не содержит captcha-failure; JSON содержит `schema_version: 2` и все новые
  ключи; при `Failure == nil` ключ `failure` отсутствует.
- **TESTS THAT MUST REMAIN UNCHANGED:** `transport/call/vk/captcha_flow_test.go`
  (он проверяет `PublishRuntimeChallenge`, а не health) — обязателен зелёный прогон
  без правок.
- **VALIDATION:** `go build ./...`, `go vet ./transport/call/... ./common/hydracore/...`,
  `go test ./transport/call/... ./common/hydracore/...`
- **MANUAL SCENARIO:** —
- **EXPECTED STRUCTURED LOG:** —
- **NEGATIVE ASSERTIONS:** `grep -rn "PublishTransportHealth" transport/call/vk/`
  даёт ноль совпадений; `schema_version` в исходниках равен 2.
- **ROLLBACK:** revert; артефакт не пересобирается до `HB-BUNDLE-003`.
- **DEFINITION OF DONE:** go-тесты зелёные; `captcha_flow_test.go` зелёный без правок.
- **STOP CONDITIONS:** если добавление полей требует смены `schema_version` из-за
  строгой валидации где-либо в ядре — STOP (**R14**).
- **COMMIT BOUNDARY:** один коммит в hydracore.
- **NEXT TASK:** `HC-RW-003`.

---

## HC-RW-003 — `healthSnapshot` без самопротиворечий

- **STATUS:** BLOCKED(`HC-RW-002`)
- **GOAL:** прекратить публикацию failure при живых линиях и залипание кода ошибки
  после снятия challenge.
- **INVARIANTS ESTABLISHED:** R18
- **REPOSITORY:** hydracore
- **BASELINE:** merge `HC-RW-002`
- **PRECONDITIONS:** `HC-RW-002`
- **FILES / SYMBOLS:** `transport/call/vk-parasite/supervisor.go`: `healthSnapshot`,
  `recordPathFailure`, `publishObservedHealth`; `client.go`: `lastFailure`,
  `dialTrackedPath`
- **CURRENT BEHAVIOR:** `lastFailure` очищается только при успешном dial, поэтому
  после `ClearRuntimeChallenge` снимки продолжают нести captcha-failure; при
  `activeLanes >0` и `state == degraded` в снимок подставляется `lastFailure`.

- **TARGET BEHAVIOR:** `healthSnapshot` сбрасывает `lastFailure` при переходе
  `challenge != nil` → `nil`; при `activeLanes >0` поле `Failure` не заполняется;
  `Applicable` выставляется в `true` (клиент vk_parasite публикует health по факту
  своего существования).
- **IMPLEMENTATION:** добавить в `Client` поле `sawChallenge atomic.Bool`; в
  `healthSnapshot` при `challenge == nil && sawChallenge.Load()` вызвать
  `lastFailure.Store(nil)` и `sawChallenge.Store(false)`; условие подстановки
  `Failure` дополнить `activeLanes == 0`.
- **DELETE:** —
- **DO NOT CHANGE:** периодичность `healthLoop` (1 s); пороги
  `transportDegradedLimit` и `transportFailureLimit`; `sawPath`.
- **BACKWARD COMPATIBILITY:** старый Android продолжает читать те же `state` и
  `active_lanes`.
- **TESTS TO ADD FIRST:** `supervisor_test.go`, дополнительные кейсы:
  `activeLanes >0` ⇒ `Failure == nil`; после снятия challenge следующий снимок не
  содержит captcha-failure; `sawPath == false` и `activeLanes == 0` даёт `starting`,
  а не `recovering`.
- **TESTS THAT MUST REMAIN UNCHANGED:** существующие в `supervisor_test.go`,
  `captcha_flow_test.go`.
- **VALIDATION:** `go build ./...`, `go test ./transport/call/... ./common/hydracore/...`
- **MANUAL SCENARIO:** M13 — после решения капчи в снимках нет `auth_failed`
  (проверяется после `HB-BUNDLE-003`).
- **EXPECTED STRUCTURED LOG:** после `AUTH stage=captcha_solved` ни одной строки с
  `code=vk.captcha.*`.
- **NEGATIVE ASSERTIONS:** нет снимка, в котором одновременно `active_lanes >0` и
  непустой `failure`.
- **ROLLBACK:** revert.
- **DEFINITION OF DONE:** go-тесты зелёные, включая три новых кейса.
- **STOP CONDITIONS:** если сброс `lastFailure` скрывает реальную терминальную ошибку
  аутентификации — STOP и сообщить: тогда сброс должен зависеть от `Terminal`.
- **COMMIT BOUNDARY:** один коммит.
- **NEXT TASK:** `HC-RW-004` при выполненном `HB-EXP-E10`.

---

## HC-RW-004 — `RebindNetwork(generation)` и отмена in-flight dial

- **STATUS:** BLOCKED(`HC-RW-003`). `HB-EXP-E10` выполнен, ветка **P1**
- **GOAL:** сделать rebind идемпотентным по generation и отменять попытки соединения,
  относящиеся к прежней сети.
- **INVARIANTS ESTABLISHED:** R4, R5, R6
- **REPOSITORY:** hydracore
- **BASELINE:** merge `HC-RW-003`
- **PRECONDITIONS:** `HC-RW-003`; `HB-EXP-E10` выполнен, ветка зафиксирована
- **FILES / SYMBOLS:**
  - `transport/call/vk-parasite/quic_relay.go`: `RebindNetwork`, `initPath`,
    `reconnectPath`, `addPath`, новое поле `appliedNetworkGeneration`,
    новое поле `generationCtx`
  - `transport/call/vk-parasite/client.go`: `RebindNetwork`, удалить `rebindMu`
    и `rebindCancel`
  - `transport/call/config.go`: интерфейс `networkRebinder`, `Bridge.RebindNetwork`
  - `protocol/call/outbound.go`: `InterfaceUpdated`
  - `common/hydracore/`: по ветке `HB-EXP-E10` **P1** — `SetNetworkGeneration` и
    `CurrentNetworkGeneration`
- **CURRENT BEHAVIOR:** `RebindNetwork()` без параметров закрывает только пути из
  `r.paths`; пути, находящиеся в процессе dial (в том числе застрявшие на CAPTCHA
  или на TURN), не отменяются и продолжают попытки по мёртвой сети до собственных
  таймаутов. `rebindMu` и `rebindCancel` объявлены и не используются.
- **TARGET BEHAVIOR:** `RebindNetwork(generation uint64)` игнорирует вызов при
  `generation <= appliedNetworkGeneration`; при принятии — закрывает пути **и**
  отменяет `generationCtx`, от которого производны все `pathCtx`, после чего
  создаёт новый `generationCtx`. `reconnectPath` и `initPath` используют `pathCtx`,
  производный от `generationCtx`.
- **IMPLEMENTATION:**
  1. Добавить в `QUICRelay` поля `appliedNetworkGeneration atomic.Uint64` и
     `generationCtx` с `generationCancel` под `pathsMu`.
  2. `initPath` и `reconnectPath` создают `pathCtx` от `generationCtx`, не от `r.ctx`.
  3. `RebindNetwork(gen)`: CAS на `appliedNetworkGeneration`; при успехе — отменить
     старый `generationCtx`, создать новый, закрыть все пути.
  4. Проброс generation — **вариант A** (`HB-EXP-E10`, ветка P1, обязательно):
     новый файл `common/hydracore/network_generation.go` с
     `SetNetworkGeneration(uint64)` и `CurrentNetworkGeneration() uint64` на
     `atomic.Uint64`; аддитивный libbox-экспорт
     `HydraCoreSetNetworkGeneration(int64)` в
     `experimental/libbox/hydracore_capabilities.go`; `Outbound.InterfaceUpdated`
     читает `CurrentNetworkGeneration()` и передаёт значение в
     `bridge.RebindNetwork(gen)`. Вариант B (расширение интерфейса) **запрещён**:
     в репозитории 11 реализаций `InterfaceUpdated()`.
  5. Удалить `rebindMu` и `rebindCancel`.
- **DELETE:** `rebindMu`, `rebindCancel`.
- **DO NOT CHANGE:** backoff `reconnectPath` (0.5→5 s); `pathDialTimeout`;
  число путей; логику `pickPath`; `AttachServerConn`.
- **BACKWARD COMPATIBILITY:** `RebindNetwork(0)` обязан вести себя как безусловный
  rebind, чтобы старые вызывающие (если найдутся) не сломались.
- **TESTS TO ADD FIRST:** `quic_relay_test.go`, дополнительные кейсы:
  `RebindNetwork(gen)` при `gen <= applied` — no-op; `RebindNetwork(gen+1)` отменяет
  `pathCtx` ещё не добавленного пути (проверяется через `dialPath`, блокирующийся на
  `ctx.Done()`); `RebindNetwork(0)` работает безусловно.
- **TESTS THAT MUST REMAIN UNCHANGED:** `TestRebindNetworkReplacesPaths`
  (существующий regression, обязателен зелёный без правок).
- **VALIDATION:** `go build ./...`, `go vet ./transport/call/...`,
  `go test ./transport/call/...`
- **MANUAL SCENARIO:** M07, M11 (handover во время CAPTCHA) — после `HB-BUNDLE-002`.
- **EXPECTED STRUCTURED LOG:** `HB1 ... REBIND ng=<n >paths_closed=<k>` ровно один
  раз на семантическую смену сети.
- **NEGATIVE ASSERTIONS:** после handover в логах ядра нет попыток dial по прежнему
  интерфейсу дольше 1 s.
- **ROLLBACK:** revert; `RebindNetwork(0)`-совместимость делает откат безопасным.
- **DEFINITION OF DONE:** новые кейсы зелёные; существующий regression зелёный;
  мёртвые поля удалены.
- **STOP CONDITIONS:** ветка `HB-EXP-E10` = **P2** и число реализаций
  `InterfaceUpdated` превышает пять — STOP и сообщить: тогда нужно решение о форке.
- **COMMIT BOUNDARY:** один коммит в hydracore, включающий требования карточки
  `HC-RW-006` (публикация `code=vk.captcha.cancelled` с `terminal=false` в момент
  отмены `generationCtx`).
- **NEXT TASK:** `HC-RW-005`, затем `HB-BUNDLE-002`.

---

## HC-RW-005 — `reconnectPath` уважает домен и терминальность

- **STATUS:** BLOCKED(`HC-RW-004`)
- **GOAL:** прекратить автоматический повтор сбоев, повтор которых бессмыслен.
- **INVARIANTS ESTABLISHED:** R5, R9
- **REPOSITORY:** hydracore
- **BASELINE:** merge `HC-RW-004`
- **PRECONDITIONS:** `HC-RW-004`
- **FILES / SYMBOLS:** `transport/call/vk-parasite/quic_relay.go`: `reconnectPath`,
  `initPath`; `client.go`: `dialTrackedPath`, `recordPathFailure`
- **CURRENT BEHAVIOR:** `reconnectPath` повторяет попытки бесконечно с backoff
  0.5→5 s независимо от причины: и «DTLS handshake failed» (осмысленно), и «captcha
  required» (бессмысленно, потому что `solveVKCaptcha` уже держит 120-секундный
  блокирующий вызов, и повторный вход создаёт очередь на `captchaFlowGate`).
- **TARGET BEHAVIOR:** `dialTrackedPath` возвращает вместе с ошибкой её домен и
  признак терминальности; `reconnectPath` при `Terminal == true` завершается,
  не входя в backoff, оставляя пул с меньшим числом линий и `lastFailure`,
  сообщающим домен. При `Terminal == false` поведение не меняется.
- **IMPLEMENTATION:** ввести приватный тип `dialOutcome { err error; failure *HC.TransportFailure }`;
  `reconnectPath` проверяет `failure.Terminal`.
- **DELETE:** —
- **DO NOT CHANGE:** значения backoff; максимальное число линий; `pickPath`.
- **BACKWARD COMPATIBILITY:** при отсутствии домена (ошибка не классифицирована)
  считать `Terminal == false`, то есть сохранять текущее поведение.
- **TESTS TO ADD FIRST:** `client_test.go` (новый): `failureDomain=AUTH` с
  `Terminal=true` не приводит ко второй попытке; `Terminal=false` приводит;
  неклассифицированная ошибка приводит (обратная совместимость).
- **TESTS THAT MUST REMAIN UNCHANGED:** `quic_relay_test.go` целиком,
  `supervisor_test.go`.
- **VALIDATION:** `go build ./...`, `go test ./transport/call/...`
- **MANUAL SCENARIO:** M12 (закрыть CAPTCHA не решив) — после `HB-BUNDLE-003`.
- **EXPECTED STRUCTURED LOG:** после `vk.captcha.cancelled` нет повторных
  `AUTH stage=captcha_required` для того же worker.
- **NEGATIVE ASSERTIONS:** ни одного повторного входа в `solveVKCaptcha` после
  терминальной отмены.
- **ROLLBACK:** revert.
- **DEFINITION OF DONE:** три новых кейса зелёные; существующие тесты без правок.
- **STOP CONDITIONS:** если после выхода из `reconnectPath` пул навсегда остаётся
  без линии и это блокирует весь outbound — STOP и сообщить: тогда нужен явный
  переход в `LOST` с последующим единственным повтором по команде пользователя.
- **COMMIT BOUNDARY:** один коммит.
- **NEXT TASK:** `HB-BUNDLE-003` (`HC-RW-006` уже выполнена внутри `HC-RW-004`).

---

## HC-RW-006 — Явный код отмены CAPTCHA (часть PR `HC-RW-004`)

- **STATUS:** **MERGED INTO `HC-RW-004`.** Отдельной задачей не выдаётся: `HB-EXP-E12`
  (ветка P2, §8.1) показал, что механизмом отмены является `generationCtx` из
  `HC-RW-004`, поэтому эта карточка — спецификация подчасти того же PR. Исполнитель
  берёт `HC-RW-004` и выполняет оба набора требований.
- **GOAL:** сделать исчезновение challenge наблюдаемым событием, а не тишиной.
- **INVARIANTS ESTABLISHED:** R18
- **REPOSITORY:** hydracore
- **BASELINE:** merge `HC-RW-003` (тот же baseline, что у `HC-RW-004`)
- **PRECONDITIONS:** `HC-RW-002` (поля `domain` и `terminal`), `HC-RW-003`
- **FILES / SYMBOLS:** `transport/call/vk/vk_auth.go`: `solveVKCaptcha`;
  `transport/call/vk/control_plane_error.go`
- **CURRENT BEHAVIOR:** при отмене `challengeContext` пользователем
  `GetCaptchaResultContext` возвращает пустую строку, и `solveVKCaptcha` формирует
  `ControlPlaneError` без различения причины. При смене сети challenge сегодня вообще
  не отменяется (`HB-EXP-E12`, ветка P2, §8.1).
- **TARGET BEHAVIOR:** различаются три исхода: решено; отменено пользователем
  (`code=vk.captcha.cancelled`, `Terminal=true`); отменено сменой сети
  (`code=vk.captcha.cancelled`, `Terminal=false`). Второй и третий случай различаются
  по причине отмены контекста: пользовательская отмена приходит через
  `CancelRuntimeChallenge`, сетевая — через отмену `generationCtx` из `HC-RW-004`.
- **IMPLEMENTATION:** передать причину отмены через тип, возвращаемый
  `CancelRuntimeChallenge` и через отмену `generationCtx` (`HC-RW-004`); заполнить
  `Domain=AUTH` и соответствующий `Terminal`.
- **DELETE:** —
- **DO NOT CHANGE:** `captchaFlowGate`; таймаут 120 s; сам captcha-proxy;
  переписывание HTML.
- **BACKWARD COMPATIBILITY:** новые коды аддитивны; старый Android увидит их как
  неизвестный `code` и деградирует к текущему поведению.
- **TESTS TO ADD FIRST:** `captcha_flow_test.go`, новые кейсы: отмена пользователем
  даёт `Terminal=true`; отмена по контексту generation даёт `Terminal=false`.
  Существующие кейсы не меняются.
- **TESTS THAT MUST REMAIN UNCHANGED:** оба существующих теста в `captcha_flow_test.go`.
- **VALIDATION:** `go build ./...`, `go test ./transport/call/vk/...`
- **MANUAL SCENARIO:** M11, M12
- **EXPECTED STRUCTURED LOG:** `HB1 ... AUTH stage=captcha_cancelled result=fail
  code=vk.captcha.cancelled terminal=<bool>`
- **NEGATIVE ASSERTIONS:** challenge никогда не исчезает без события.
- **ROLLBACK:** revert.
- **DEFINITION OF DONE:** новые кейсы зелёные; существующие без правок.
- **STOP CONDITIONS:** если причину отмены невозможно различить без изменения
  `context` API — STOP: тогда публикуется единый `Terminal=true`, и это
  фиксируется в §8 как принятое ограничение.
- **COMMIT BOUNDARY:** **тот же PR, что и `HC-RW-004`.** Отдельного коммита нет.
- **NEXT TASK:** `HC-RW-005`.

---

## HB-BUNDLE-002 — Bundle bump после `HC-RW-004`

- **STATUS:** BLOCKED(`HC-RW-004`, `HB-RW-018`)
- **GOAL:** довести до приложения `RebindNetwork(gen)` и отмену in-flight dial.
- **INVARIANTS ESTABLISHED:** —
- **REPOSITORY:** hydrabox
- **BASELINE:** merge `HB-RW-018`
- **PRECONDITIONS:** `HC-RW-004` и `HC-RW-005` смержены; `HB-RW-018` смержен
- **FILES / SYMBOLS:** как в `HB-BUNDLE-001`, плюс
  `singbox/HydraBoxDefaultNetworkMonitor.kt` — передача `networkGeneration` в новый
  libbox-экспорт (по ветке `HB-EXP-E10` **P1**)
- **CURRENT BEHAVIOR:** `RebindNetwork` без generation.
- **TARGET BEHAVIOR:** Android передаёт `networkGeneration` в ядро перед
  `updateDefaultInterface`; ядро применяет guard.
- **IMPLEMENTATION:** bump submodule и артефакта; добавить вызов
  `Libbox.hydraCoreSetNetworkGeneration(ng)` в обработчике `NETWORK_CHANGED`
  (аддитивный экспорт, добавленный в `HC-RW-004`).
- **DELETE:** —
- **DO NOT CHANGE:** порядок применения underlying и `updateDefaultInterface`.
- **BACKWARD COMPATIBILITY:** если экспорт отсутствует (откат ядра), Android обязан
  деградировать к вызову без generation. Реализовать через `runCatching`.
- **TESTS TO ADD FIRST:** `EffectiveNetworkTest` — кейс «generation передана до
  `updateDefaultInterface`».
- **TESTS THAT MUST REMAIN UNCHANGED:** `scripts/tests/*`.
- **VALIDATION:** `python3 -B scripts/verify_libbox.py`,
  `python3 -B scripts/verify_extended_core.py --source-only`,
  `python3 -B -m unittest discover -s scripts/tests -p "test_*.py"`,
  `./gradlew :app:testDebugUnitTest :app:lintDebug`
- **MANUAL SCENARIO:** M07, M08, M09 — по три прогона на трёх устройствах.
- **EXPECTED STRUCTURED LOG:** `NETWORK` и `REBIND` в отношении один к одному.
- **NEGATIVE ASSERTIONS:** ни одного `REBIND` с `ng`, меньшим предыдущего.
- **ROLLBACK:** revert bump; Android деградирует к вызову без generation.
- **DEFINITION OF DONE:** verify-скрипты зелёные; M07 даёт ровно три `REBIND`.
- **STOP CONDITIONS:** verify-скрипты не проходят — STOP, значения не подгонять.
- **COMMIT BOUNDARY:** один коммит: submodule, артефакт, provenance, вызов экспорта.
- **NEXT TASK:** `HB-EXP-E9` становится исполнимым; далее `HB-BUNDLE-003`.

---

## HB-BUNDLE-003 — Bundle bump после `HC-RW-005`

- **STATUS:** BLOCKED(`HC-RW-005`)
- **GOAL:** довести до приложения health с доменами, единственным writer и кодами
  отмены CAPTCHA.
- **INVARIANTS ESTABLISHED:** —
- **REPOSITORY:** hydrabox
- **BASELINE:** merge `HB-BUNDLE-002`
- **PRECONDITIONS:** `HC-RW-002`, `HC-RW-003`, `HC-RW-004` (включает `HC-RW-006`),
  `HC-RW-005` смержены
- **FILES / SYMBOLS:** как в `HB-BUNDLE-001`
- **CURRENT BEHAVIOR:** приложение получает health без домена.
- **TARGET BEHAVIOR:** приложение получает health с `domain`, `terminal`,
  `applicable`, `runtime_generation`, `network_generation`; читает их в `HB-RW-020`.
- **IMPLEMENTATION:** bump submodule и артефакта.
- **DELETE:** —
- **DO NOT CHANGE:** ничего в `lib/` и `android/app/src/`.
- **BACKWARD COMPATIBILITY:** `TransportHealthBridge` до `HB-RW-020` игнорирует
  новые ключи, потому что читает только известные.
- **TESTS TO ADD FIRST:** —
- **TESTS THAT MUST REMAIN UNCHANGED:** `scripts/tests/*`,
  `hydracore_capabilities_test.dart`, `hydracore_compatibility_test.dart`.
- **VALIDATION:** те же четыре команды, что в `HB-BUNDLE-002`.
- **MANUAL SCENARIO:** M13 — после решения капчи нет `auth_failed`.
- **EXPECTED STRUCTURED LOG:** —
- **NEGATIVE ASSERTIONS:** `TransportHealthBridge.parse` не бросает на новом JSON.
- **ROLLBACK:** revert bump.
- **DEFINITION OF DONE:** verify-скрипты зелёные; M13 проходит.
- **STOP CONDITIONS:** `TransportHealthBridge.parse` бросает — STOP: значит ключ
  добавлен не аддитивно.
- **COMMIT BOUNDARY:** один коммит.
- **NEXT TASK:** `HB-RW-020` при выполненном `HB-EXP-E6`.

---

## HB-RW-020 — Единственный порог readiness и dual-read health

- **STATUS:** BLOCKED(`HB-BUNDLE-003`). `HB-EXP-E6` выполнен, ветка **P2**
- **GOAL:** перенести решение о готовности в `CoreRuntimeService`, оставив
  `TransportHealthBridge` чистым парсером, и читать новые поля health.
- **INVARIANTS ESTABLISHED:** R10, R18
- **REPOSITORY:** hydrabox
- **BASELINE:** merge `HB-BUNDLE-003`
- **PRECONDITIONS:** `HB-BUNDLE-003`; `HB-EXP-E6` выполнен
- **FILES / SYMBOLS:**
  - `runtime/TransportHealthBridge.kt`: `parse`, `isConnected`,
    `effectiveRuntimeState`, `configRequiresHealth`
  - `runtime/CoreRuntimeService.kt`: `refreshTransportHealth`, `buildSnapshot`,
    `reduce`
  - `runtime/proto` — добавить в `TransportHealthSnapshot` поля `failure_domain`,
    `failure_terminal`, `runtime_generation`, `network_generation`
  - `lib/app/runtime_event_controller.dart` — `RuntimeTransportHealthEvent`
    получает `failureDomain`, `terminal`
- **CURRENT BEHAVIOR:** `TransportHealthBridge` содержит три политики:
  `isConnected` (HEALTHY либо DEGRADED), `effectiveRuntimeState` (перезапись RUNNING)
  и `configRequiresHealth` (JSON-скан конфига); `parse` требует
  `schema_version == 2` жёстким равенством.
- **TARGET BEHAVIOR:** `parse` читает `schema_version == 2` и новые ключи при их
  наличии; `isConnected` и `effectiveRuntimeState` удаляются, их место занимает одна
  функция `isReady(health)` в `CoreRuntimeService` по §2.3; `applicable` берётся из
  ядра, а при отсутствии ключа — из локального `configRequiresHealth`, который
  остаётся как fallback.
- **IMPLEMENTATION:**
  1. Расширить protobuf аддитивно; перегенерировать Pigeon для Dart-события.
  2. Перенести порог в `CoreRuntimeService.isReady`.
  3. Удалить `effectiveRuntimeState`: `buildSnapshot` больше не перезаписывает
     `state`, потому что переходы делает `reduce`.
  4. **Обязательно, следствие `HB-EXP-E6` (ветка P2).** Push-канала для health в
     libbox нет: `RuntimeEvents` несёт только `Sequence`, `Reset`, `Snapshot` и
     список событий, а `RuntimeSnapshot` — `SchemaVersion`, `Sequence`,
     `ObservedAt`, `Service`, `StartedAt`, `Status`, `ClashMode`, `groups`,
     `urlTests`. Добавление health в `RuntimeSnapshot` потребовало бы поднять
     `runtime.snapshot_schema_version`, что запрещено **R14**. Поэтому опрос
     сохраняется, но переносится на `ScheduledExecutorService`, публикующий
     `Event.Health`, и **вооружается только в STARTING и RECOVERING**, снимаясь в
     STOPPED, RUNNING и FAILED. Интервал 250 ms не меняется.
- **DELETE:** `isConnected`, `effectiveRuntimeState`; по ветке **P1** — опрос health
  целиком.
- **DO NOT CHANGE:** порог `>= 1` активная линия; интервал опроса 250 ms;
  `configRequiresHealth` как fallback.
- **BACKWARD COMPATIBILITY:** обязателен **переходный** dual-read: приложение должно
  работать и с артефактом без новых ключей. Причина после решения C17 — не доставка
  ядра на устройство (она удалена), а окно внутри истории репозитория: hydracore-задача
  смержена, а `HB-BUNDLE-003` ещё нет, плюс возможный откат bundle-bump. Снятие
  dual-read — отдельное решение после `HB-BUNDLE-003`; задачи на него план не содержит.
- **TESTS TO ADD FIRST:** `TransportHealthBridgeTest`: парсинг JSON без новых ключей
  и с ними; отсутствие `domain` читается как `INTERNAL`; отсутствие `applicable`
  приводит к использованию `configRequiresHealth`. `ReadinessThresholdTest`:
  0 линий не READY; 1 из 8 READY; `applicable=false` READY; `waiting_user`
  не READY и перевооружает дедлайн.
- **TESTS THAT MUST REMAIN UNCHANGED:** `CoreRuntimeSnapshotCompatibilityTest`,
  `hydracore_capabilities_test.dart`, `hydracore_compatibility_test.dart`.
- **VALIDATION:** `dart run pigeon --input pigeons/singbox_api.dart`, `dart format .`,
  `flutter analyze`, `flutter test`,
  `./gradlew :app:testDebugUnitTest :app:lintDebug`
- **MANUAL SCENARIO:** M13, M14 (все линии умерли), M15 (частичное восстановление)
- **EXPECTED STRUCTURED LOG:** `HB1 ... READY rg=<n >active_lanes=<n >target_lanes=<n>`
  и при сбое `HB1 ... RECOVERY rg=<n >reason=transport_lost`.

- **NEGATIVE ASSERTIONS:** ни одного снимка со `state=RUNNING` при `active_lanes=0`
  и `applicable=true`.
- **ROLLBACK:** revert; при откате бандл остаётся новым, что безопасно из-за
  аддитивности.
- **DEFINITION OF DONE:** тесты зелёные; M14 даёт FAILED через 60 s без цикла;
  M15 остаётся RUNNING.
- **STOP CONDITIONS:** если удаление `effectiveRuntimeState` меняет наблюдаемое
  состояние в каком-то сценарии — STOP и перечислить сценарий.
- **COMMIT BOUNDARY:** один PR.
- **NEXT TASK:** `HB-RW-021`.

---

## HB-RW-021 — Изоляция probe: отдельный executor и отдельная ошибка

- **STATUS:** BLOCKED(`HB-RW-020`)
- **GOAL:** физически исключить влияние probe на runtime-поддерево снимка.
- **INVARIANTS ESTABLISHED:** R15
- **REPOSITORY:** hydrabox
- **BASELINE:** merge `HB-RW-020`
- **PRECONDITIONS:** `HB-RW-020`
- **FILES / SYMBOLS:** `runtime/CoreRuntimeService.kt`: `execute`, `startProbe`,
  `cancelProbe`, `startEphemeralProbe`, `finishEphemeralProbe`, `failRuntime`,
  `buildSnapshot`; `runtime/proto` — добавить `probe_last_error`
- **CURRENT BEHAVIOR:** probe-команды идут через `commandExecutor`;
  `failRuntime` записывает `lastError` **до** проверки
  `if (!stage.startsWith("probe") && stage != "selector")`, поэтому probe-ошибка
  попадает в `lastError` снимка, и Dart читает её как ошибку runtime.
- **TARGET BEHAVIOR:** отдельный `probeExecutor`; probe-команды не проходят через
  serializer; `failProbe` пишет только `probeLastError`; `failRuntime` не вызывается
  из probe-путей; строковая проверка префикса удалена.
- **IMPLEMENTATION:**
  1. Добавить `probeExecutor` (single-thread, имя `HydraCoreProbe`).
  2. В `execute` направить `START_PROBE` и `CANCEL_PROBE` на `probeExecutor`.
  3. Ввести `failProbe(commandId, code, stage, safeMessage, retryable)`; заменить
     probe-вызовы `failRuntime` на него.
  4. Добавить `probe_last_error` в снимок; Dart читает его отдельно от `lastError`.
- **DELETE:** проверка `stage.startsWith("probe")` в `failRuntime`; ветка
  `stage != "selector"` заменяется отдельным `failCommand` для селектора.
- **DO NOT CHANGE:** тайминги probe; формат `ProbeSession` и `ProbeResult`.
- **BACKWARD COMPATIBILITY:** `probe_last_error` аддитивен; старый Dart его
  игнорирует, но в этом же PR Dart обновляется.
- **TESTS TO ADD FIRST:** `ProbeIsolationTest` (JVM): probe-ошибка не меняет
  `lastError` и не меняет `state`; probe-ошибка заполняет `probeLastError`;
  ошибка селектора не переводит состояние в FAILED.
- **TESTS THAT MUST REMAIN UNCHANGED:** `ProbeExecutionModeTest`,
  `preconnect_url_test_policy_test.dart`.
- **VALIDATION:** `dart run pigeon --input pigeons/singbox_api.dart`,
  `flutter analyze`, `flutter test`,
  `./gradlew :app:testDebugUnitTest :app:lintDebug`
- **MANUAL SCENARIO:** M17 (probe при подключённом runtime), M18 (probe при
  отключённом)
- **EXPECTED STRUCTURED LOG:** при probe-ошибке в логе нет строки, меняющей
  `runtimeState`.
- **NEGATIVE ASSERTIONS:** `grep -n 'startsWith("probe")' android/app/src/main`
  даёт ноль совпадений; при неудачном probe UI не показывает ошибку подключения.
- **ROLLBACK:** revert.
- **DEFINITION OF DONE:** `ProbeIsolationTest` зелёный; M17 и M18 проходят.
- **STOP CONDITIONS:** если разделение executor-ов приводит к параллельному доступу
  к `snapshotLock` с блокировкой дольше 5 ms — STOP и сообщить.
- **COMMIT BOUNDARY:** один PR.
- **NEXT TASK:** `HB-RW-022` при выполненном `HB-EXP-E3`.

---

## HB-RW-022 — Матрица режимов probe и точки отмены

- **STATUS:** BLOCKED(`HB-RW-021`)
- **GOAL:** запретить второй native runtime рядом с работающим VPN и определить все
  точки отмены probe.
- **INVARIANTS ESTABLISHED:** R15
- **REPOSITORY:** hydrabox
- **BASELINE:** merge `HB-RW-021`
- **PRECONDITIONS:** `HB-RW-021`; `HB-EXP-E3` выполнен, ветка зафиксирована
- **FILES / SYMBOLS:** `runtime/CoreRuntimeService.kt`: `selectProbeExecutionMode`,
  `startProbe`, `startEphemeralProbe`, обработчики `STOP` и `NETWORK_CHANGED`;
  `runtime/CoreRuntimeClient.kt`: `preconnectProbe`, `startProbe`,
  `latestPreconnectSessionId`; `lib/singbox/singbox_runtime.dart`:
  `preconnectUrlTest`, `startManagedUrlTest`
- **CURRENT BEHAVIOR:** `compiledConfigBytes >0` даёт `EPHEMERAL` даже при
  работающем runtime, то есть поднимает второй native runtime в `:core`; ephemeral
  probe отменяется только при смене сети и по дедлайну, но не при `STOP`;
  managed probe не отменяется ни при смене сети, ни при смене `runtimeGeneration`.
- **TARGET BEHAVIOR:** матрица §2.10; ephemeral отменяется при `STOP` и при переходе
  `STOPPED → STARTING`; managed отменяется при `NETWORK_CHANGED` и при смене
  `runtimeGeneration`; `preconnectProbe` и `startProbe` в клиенте объединяются в один
  метод `probe(disconnected: Boolean, ...)`.
- **IMPLEMENTATION:**
  1. Переписать `selectProbeExecutionMode` по матрице; добавить проверку наличия
     outbound в активном плане (по `outboundGroups` снимка).
  2. Добавить вызовы отмены в обработчики `STOP` и `NETWORK_CHANGED` и при
     установке нового `runtimeGeneration`.
  3. По `HB-EXP-E3` **P1** не добавлять ожидание отмены ephemeral probe в `CloseTask`;
     при `started == false` `HydraBoxDefaultNetworkMonitor.require()` немедленно
     возвращает ошибку вместо ожидания как независимую дешёвую страховку.
  4. Слить два метода клиента в один; обновить Dart-фасад.
- **DELETE:** `preconnectProbe` как отдельный метод клиента;
  `latestPreconnectSessionId` (заменяется общим реестром сессий).
- **DO NOT CHANGE:** тайминги probe; `concurrency`; формат результатов.
- **BACKWARD COMPATIBILITY:** Pigeon-метод `preconnectUrlTest` сохраняется как
  тонкая обёртка над `probe(disconnected: true, ...)` до `HB-RW-031`, чтобы не
  ломать вызывающих в UI одним PR.
- **TESTS TO ADD FIRST:** `ProbeExecutionModeTest` — расширить всеми четырьмя
  строками матрицы; существующие кейсы **не удалять**, изменённые ожидания
  зафиксировать в commit message как новую спецификацию с обоснованием.
  `ProbeCancellationTest` (JVM): `STOP` отменяет ephemeral; `NETWORK_CHANGED`
  отменяет managed; смена `runtimeGeneration` отменяет managed.
- **TESTS THAT MUST REMAIN UNCHANGED:** `preconnect_url_test_policy_test.dart`,
  `universal_url_test_plan_test.dart`, `group_url_test_scheduler_test.dart`.
- **VALIDATION:** `flutter analyze`, `flutter test`,
  `./gradlew :app:testDebugUnitTest :app:lintDebug`
- **MANUAL SCENARIO:** M17, M18, плюс probe в момент `STOP`
- **EXPECTED STRUCTURED LOG:** при попытке ephemeral probe на работающем runtime —
  отказ с `code=probe.requires_stopped_runtime`.
- **NEGATIVE ASSERTIONS:** в процессе `:core` никогда не существует двух native
  runtime одновременно; `STOP` не задерживается probe.
- **ROLLBACK:** revert.
- **DEFINITION OF DONE:** матрица покрыта тестами; M17 и M18 проходят; probe в
  момент `STOP` не даёт `runtime.stop.unconfirmed`.
- **STOP CONDITIONS:** если UI полагается на ephemeral probe при работающем runtime
  (например для проверки сервера из другого профиля) — STOP и сообщить: тогда
  требуется отдельное решение продукта, а не техническое.
- **COMMIT BOUNDARY:** один PR.
- **NEXT TASK:** `HB-RW-024`.

---

## HB-RW-024 — Cadence без пересоздания command client

- **STATUS:** BLOCKED(`HB-RW-021`)
- **GOAL:** прекратить пересоздание libbox `CommandClient` из-за UI-событий.
- **INVARIANTS ESTABLISHED:** R16
- **REPOSITORY:** hydrabox
- **BASELINE:** merge `HB-RW-022`
- **PRECONDITIONS:** `HB-RW-022`
- **FILES / SYMBOLS:** `singbox/SingboxController.kt`:
  `reconnectClientForCadenceChange`, `setUiForeground`, `setScreenInteractive`,
  `clearEventSink`, `runtimeEventIntervalMillis`, `drainStatusEvent`,
  `drainGroupsEvent`
- **CURRENT BEHAVIOR:** `setUiForeground`, `setScreenInteractive` и `clearEventSink`
  вызывают `reconnectClientForCadenceChange`, который делает
  `disconnectClientOnExecutor` плюс `connectClient` — то есть полностью пересоздаёт
  libbox-клиент, единственный источник traffic и groups.
- **TARGET BEHAVIOR:** cadence меняется только на выдаче: `drainStatusEvent` и
  `drainGroupsEvent` используют текущее значение throttle;
  `runtimeEventIntervalMillis` задаётся один раз при создании клиента и берётся
  как наиболее консервативное значение `RuntimeEventCadence.IDLE_EVENT_INTERVAL_MS`;
  `CommandClient` не пересоздаётся ни при одном UI-событии.
- **IMPLEMENTATION:** удалить `reconnectClientForCadenceChange` и три её вызова;
  в `drain*` вычислять throttle из `uiForeground`, `screenInteractive`,
  `performanceMode` через существующий `RuntimeEventCadence`.
- **DELETE:** `reconnectClientForCadenceChange`.
- **DO NOT CHANGE:** `RuntimeEventCadence.intervalMillis` (функция и её тест),
  значения интервалов, `CommandClientLifecycle`.
- **BACKWARD COMPATIBILITY:** частота событий в foreground не должна ухудшиться:
  фильтрация на выдаче даёт ту же наблюдаемую частоту, что и раньше.
- **TESTS TO ADD FIRST:** `test/app_lifecycle_foreground_test.dart` (новый):
  переход foreground → background → foreground не порождает ни одной
  runtime-мутирующей команды; `CadenceWithoutReconnectTest` (JVM): смена
  `uiForeground` не меняет `commandClientLifecycle.currentEpoch()`.
- **TESTS THAT MUST REMAIN UNCHANGED:** `RuntimeEventCadenceTest`,
  `CommandClientLifecycleTest`, `RuntimeEventSinkRegistryTest`.
- **VALIDATION:** `flutter analyze`, `flutter test`,
  `./gradlew :app:testDebugUnitTest :app:lintDebug`
- **MANUAL SCENARIO:** M04 (10 минут в фоне), M19 (пересоздание Activity пять раз)
- **EXPECTED STRUCTURED LOG:** после ухода в фон в диагностике нет
  `command_stream_connecting`.
- **NEGATIVE ASSERTIONS:** `currentEpoch()` не меняется при переключениях
  foreground и screen; traffic в нотификации не прерывается.
- **ROLLBACK:** revert.
- **DEFINITION OF DONE:** M04 и M19 проходят; grep по
  `reconnectClientForCadenceChange` пуст.
- **STOP CONDITIONS:** если `runtimeEventIntervalMillis` нельзя изменить после
  создания клиента и консервативное значение ухудшает UI-отзывчивость сильнее, чем
  на одну секунду — STOP и сообщить (менять интервал запрещено).
- **COMMIT BOUNDARY:** один PR.
- **NEXT TASK:** `HB-RW-025` при выполненном `HB-EXP-E7`.

---

## HB-RW-025 — Удалить `requestRuntimeRecovery` и его триггеры

- **STATUS:** BLOCKED(`HB-EXP-E7`, `HB-RW-024`)
- **GOAL:** прекратить порождение runtime-действий из UI- и системных
  wake-сигналов.
- **INVARIANTS ESTABLISHED:** R5, R9, R16
- **REPOSITORY:** hydrabox
- **BASELINE:** merge `HB-RW-024`
- **PRECONDITIONS:** `HB-RW-024`; `HB-EXP-E7` выполнен, ветка зафиксирована в §8
- **FILES / SYMBOLS:** `singbox/RuntimeSession.kt`: `receiver`,
  `registerRuntimeReceiver`, `unregisterRuntimeReceiver`, `updateDeviceIdleMode`,
  `requestRuntimeRecovery`, `recoveryGate`, `recoveryExecutor`;
  `singbox/RuntimeRecoveryGate.kt`; `singbox/HydraBoxVpnService.kt`: `onTaskRemoved`
- **CURRENT BEHAVIOR:** пять источников вызывают `requestRuntimeRecovery`:
  `SCREEN_ON`, `USER_PRESENT`, выход из doze, `onTaskRemoved`,
  `existing_runtime:<source>`; каждый делает `monitor.start()`,
  `reassertDefaultInterface` до и после `server.wake()`.
- **TARGET BEHAVIOR:** ни одно системное wake-событие и ни одно UI-событие не
  порождает runtime-действий. Конкретный объём удаления выбирается веткой
  `HB-EXP-E7`, см. два подпункта ниже.
- **TARGET BEHAVIOR, ветка `HB-EXP-E7` P1:** broadcast receiver,
  `requestRuntimeRecovery`, `RuntimeRecoveryGate`, `recoveryExecutor`,
  `updateDeviceIdleMode` удалены целиком; `onTaskRemoved` оставляет только
  AlarmManager; `screenInteractive` для cadence читается через
  `PowerManager.isInteractive` по требованию.
- **TARGET BEHAVIOR, ветка `HB-EXP-E7` P2:** остаётся один триггер
  `device_idle_exit` и одно действие `server.wake()`; вызовы `monitor.start()` и
  `reassertDefaultInterface` из него удаляются; `RuntimeRecoveryGate` и его тест
  сохраняются; триггеры `SCREEN_ON`, `USER_PRESENT`, `task_removed`,
  `existing_runtime` удаляются в любом случае.
- **IMPLEMENTATION:** по выбранной ветке; в обоих случаях удалить вызов
  `requestRuntimeRecovery("existing_runtime:...")` из `startInternal`-пути, потому что
  повторный START теперь обрабатывается как `NoOp` в `HB-RW-010`.
- **DELETE:** по ветке **P1** — шесть символов плюс файл `RuntimeRecoveryGate.kt`
  плюс `RuntimeRecoveryGateTest.kt` (тест удалённого кода); по ветке **P2** — четыре
  триггера.
- **DO NOT CHANGE:** AlarmManager в `onTaskRemoved`; `VpnServiceLifecyclePolicy`;
  wake-lock.
- **BACKWARD COMPATIBILITY:** нет внешнего контракта.
- **TESTS TO ADD FIRST:** `test/app_lifecycle_foreground_test.dart` — расширить:
  ни одно системное wake-событие не приводит к команде;
  `VpnServiceLifecyclePolicyTest` — кейс `onTaskRemoved` при работающем runtime
  по-прежнему ставит AlarmManager.
- **TESTS THAT MUST REMAIN UNCHANGED:** `VpnServiceLifecyclePolicyTest`
  (существующие кейсы), `RuntimeEventCadenceTest`.
- **VALIDATION:** `./gradlew :app:testDebugUnitTest :app:lintDebug`, `flutter test`
- **MANUAL SCENARIO:** M04, M09, плюс вход и выход из doze — на трёх устройствах,
  включая Xiaomi/HyperOS либо realme.
- **EXPECTED STRUCTURED LOG:** после выхода из doze в логе есть `NETWORK`, но нет
  `RECOVERY`, если сеть не менялась.
- **NEGATIVE ASSERTIONS:** ни одного `server.wake()` из UI-событий; трафик после
  10 минут в фоне не прерывается.
- **ROLLBACK:** revert; риск высокий, отдельный PR.
- **DEFINITION OF DONE:** M04 и M09 проходят на всех трёх устройствах; grep по
  `requestRuntimeRecovery` соответствует выбранной ветке.
- **STOP CONDITIONS:** если на любом устройстве трафик не восстанавливается — STOP
  и откатить PR; не «добавлять таймер».
- **COMMIT BOUNDARY:** один PR.
- **NEXT TASK:** `HB-RW-026` при выполненном `HB-EXP-E9`.

---

## HB-RW-026 — Судьба лог-скрапинга сетевых сбоев

- **STATUS:** BLOCKED(`HB-EXP-E9`, `HB-RW-025`)
- **GOAL:** убрать зависимость поведения от текста логов ядра.
- **INVARIANTS ESTABLISHED:** R5, R18
- **REPOSITORY:** hydrabox
- **BASELINE:** merge `HB-RW-025`
- **PRECONDITIONS:** `HB-RW-025`; `HB-EXP-E9` выполнен, ветка зафиксирована
- **FILES / SYMBOLS:** `singbox/SingboxController.kt`:
  `maybeReassertDefaultInterfaceFromCoreLog`, `classifyCoreInterfaceFailure`,
  `recordInterfaceDialFailure`, `clearInterfaceDialFailures`,
  `INTERFACE_DIAL_FAILURE_REGEX`, `lastNoInterfaceReassertUptimeMs`,
  `interfaceDialFailureUptimes`, `NO_INTERFACE_REASSERT_THROTTLE_MS`,
  `INTERFACE_DIAL_FAILURE_WINDOW_MS`, `INTERFACE_DIAL_FAILURE_THRESHOLD`
- **CURRENT BEHAVIOR:** `writeLogs` разбирает текст логов ядра регулярным выражением
  и при четырёх совпадениях за 8 s вызывает `reassertDefaultInterface`; любое
  изменение формулировки в HydraCore ломает детектор молча.
- **TARGET BEHAVIOR:** поведение приложения не зависит от текста логов ядра.
  Конкретная реализация выбирается веткой `HB-EXP-E9`, см. два подпункта ниже.
- **TARGET BEHAVIOR, ветка `HB-EXP-E9` P1:** все перечисленные символы удалены;
  роль сигнала берёт `failureDomain == NETWORK` из health, обрабатываемый как
  триггер слепка в мониторе.
- **TARGET BEHAVIOR, ветка `HB-EXP-E9` P2:** regex сохраняется, но его действием
  становится публикация внутреннего события `NETWORK_RECHECK`, которое монитор
  обрабатывает как ещё один триггер `onSnapshot("core_log")`; прямой вызов
  `reassertDefaultInterface` не восстанавливается (его больше нет после `HB-RW-018`).
- **IMPLEMENTATION:** по выбранной ветке.
- **DELETE:** по ветке **P1** — десять перечисленных символов.
- **DO NOT CHANGE:** `writeLogs` как таковой; передачу логов в
  `HydraBoxDiagnostics`.
- **BACKWARD COMPATIBILITY:** —
- **TESTS TO ADD FIRST:** по ветке **P2** — `CoreLogNetworkSignalTest` (JVM):
  четыре совпадения за 8 s дают ровно одно `NETWORK_RECHECK`; по ветке **P1** —
  `EffectiveNetworkTest` кейс «health с `domain=NETWORK` вызывает `onSnapshot`».
- **TESTS THAT MUST REMAIN UNCHANGED:** все.
- **VALIDATION:** `./gradlew :app:testDebugUnitTest :app:lintDebug`
- **MANUAL SCENARIO:** M07 плюс сценарий «Wi-Fi без интернета»
- **EXPECTED STRUCTURED LOG:** `HB1 ... NETWORK trigger=core_log branch=<b>` в
  ветке **P2**; отсутствие такого события в ветке **P1**.
- **NEGATIVE ASSERTIONS:** ни один путь не вызывает `reassertDefaultInterface`
  (его нет); поведение не зависит от формулировки логов в ветке **P1**.
- **ROLLBACK:** revert.
- **DEFINITION OF DONE:** соответствие выбранной ветке; M07 проходит.
- **STOP CONDITIONS:** `HB-EXP-E9` не выполнен — не начинать.
- **COMMIT BOUNDARY:** один коммит.
- **NEXT TASK:** `HB-RW-027`.

---

## HB-RW-027 — Отмена DNS-запросов при смене `networkGeneration`

- **STATUS:** BLOCKED(`HB-RW-018`)
- **GOAL:** запретить in-flight DNS-запросам переживать смену сети и обозначить
  DNS как отдельный домен сбоя.
- **INVARIANTS ESTABLISHED:** R17, R18
- **REPOSITORY:** hydrabox
- **BASELINE:** merge `HB-RW-026`
- **PRECONDITIONS:** `HB-RW-018` (нужна семантическая `networkGeneration`)
- **FILES / SYMBOLS:**
  - `singbox/HydraBoxPlatformInterface.kt`: `HydraBoxLocalResolver.exchange`,
    `HydraBoxLocalResolver.lookup`
  - `singbox/HydraBoxDefaultNetworkMonitor.kt`: новый реестр
    `pendingDnsSignals: MutableSet<CancellationSignal>` под существующим `lock`,
    методы `registerDnsSignal`, `unregisterDnsSignal`, отмена при инкременте
    `networkGeneration`
- **CURRENT BEHAVIOR:** резолвер получает `Network` через
  `HydraBoxDefaultNetworkMonitor.require()` и ждёт до 15 s на `CountDownLatch`;
  `networkGeneration` не участвует; `ctx.onCancel(signal::cancel)` срабатывает только
  если отмену инициирует ядро; при handover запрос продолжает ждать по мёртвой сети.
- **TARGET BEHAVIOR:** резолвер захватывает пару (`Network`, `networkGeneration`),
  регистрирует свой `CancellationSignal` в реестре и снимает регистрацию в
  `finally`; при инкременте `networkGeneration` монитор отменяет все
  зарегистрированные сигналы; отменённый запрос возвращает
  `ctx.errnoCode(ECANCELED)` и публикует
  `event("DNS", class=..., result=skip, code=network.generation_stale)`.
- **IMPLEMENTATION:**
  1. Расширить `currentInterfaceState`-путь так, чтобы `require()` возвращал пару
     значений (добавить `requireWithGeneration()`; старый `require()` сохранить для
     совместимости внутри файла).
  2. Реестр сигналов и его отмена в точке инкремента `networkGeneration`.
  3. События `DNS`: `class=bootstrap` для `lookup`/`exchange` от
    `default_domain_resolver`, `class=app` для прочих. Различение — по наличию
    `network` аргумента в `lookup` и по вызову `exchange`; если различить невозможно,
    писать `class=unknown` и зафиксировать это в §8.
- **DELETE:** —
- **DO NOT CHANGE:** таймаут 15 s; `DnsResolver.FLAG_EMPTY`; путь для API ниже Q;
  `route.default_domain_resolver` в конфиге.
- **BACKWARD COMPATIBILITY:** при отсутствии смены сети поведение идентично текущему.
- **TESTS TO ADD FIRST:** `DnsCancellationTest` (JVM, на чистой обёртке реестра):
  инкремент generation отменяет все зарегистрированные сигналы; сигнал, снятый в
  `finally`, не отменяется повторно; регистрация после инкремента получает новую
  generation.
- **TESTS THAT MUST REMAIN UNCHANGED:** `settings_dns_page_test.dart`,
  `fakeip_config_test.dart`.
- **VALIDATION:** `./gradlew :app:testDebugUnitTest :app:lintDebug`, `flutter test`
- **MANUAL SCENARIO:** M07 (handover) и M21 (DNS bootstrap timeout)
- **EXPECTED STRUCTURED LOG:**
  `HB1 ... DNS class=bootstrap result=fail code=dns.bootstrap.timeout ng=<n>` и при
  handover `HB1 ... DNS class=bootstrap result=skip code=network.generation_stale ng=<n>`
- **NEGATIVE ASSERTIONS:** после handover в логе нет DNS-ответов с `ng`, меньшим
  текущего; ни один запрос не висит дольше 15 s после смены сети.
- **ROLLBACK:** revert.
- **DEFINITION OF DONE:** `DnsCancellationTest` зелёный; M21 даёт код `dns.*`, а не
  общий «connection failed».
- **STOP CONDITIONS:** если `CancellationSignal.cancel()` из чужого потока не
  прерывает `DnsResolver` — STOP и сообщить: тогда отмена сводится к игнорированию
  результата, и это фиксируется как ограничение.
- **COMMIT BOUNDARY:** один PR.
- **NEXT TASK:** `HB-RW-028` при выполненном `HB-EXP-E5`.

---

## HB-RW-028 — Запрет `dns-remote` до READY

- **STATUS:** BLOCKED(`HB-RW-027`)
- **GOAL:** исключить попадание DNS-запросов в неготовый proxy-detour.
- **INVARIANTS ESTABLISHED:** R17
- **REPOSITORY:** hydrabox
- **BASELINE:** merge `HB-RW-027`
- **PRECONDITIONS:** `HB-RW-027`; `HB-EXP-E5` выполнен
- **FILES / SYMBOLS:** `lib/singbox/singbox_config_builder.dart` — секция `dns`,
  `dns.rules`, `route.default_domain_resolver`
- **CURRENT BEHAVIOR:** `dns-remote` (`https://dns.cloudflare.com/dns-query`) имеет
  `detour = <selected proxy>` и является `final` при наличии прокси; до готовности
  транспорта запросы в него не могут быть выполнены.
- **TARGET BEHAVIOR:** пока `runtimeState != RUNNING`, ни один DNS-запрос не идёт в
  `dns-remote`. Конкретная реализация либо отмена задачи выбирается веткой
  `HB-EXP-E5`, см. подпункты ниже.
- **TARGET BEHAVIOR, ветка `HB-EXP-E5` P1:** добавляется правило, направляющее
  запросы в `dns-direct`, пока транспорт не готов.
  **P1b:** `dns-remote` получает явный `domain_resolver: dns-local` и не является
  `final` до READY. Выбор между P1 и P1b определяет наличие реального reload в
  логах: если правило требует reload на каждом старте — применяется P1b.
- **TARGET BEHAVIOR, ветка `HB-EXP-E5` FAIL:** задача **отменяется**, файл не
  меняется, и в §8 фиксируется, что наблюдавшийся
  `lookup dns.cloudflare.com: connection timed out` относится к bootstrap-пути и
  закрыт `HB-RW-027`.
- **IMPLEMENTATION:** по выбранной ветке; в любом случае — без изменения
  `default_domain_resolver`.
- **DELETE:** —
- **DO NOT CHANGE:** `default_domain_resolver = 'dns-local'`; DNS-пресеты
  пользователя; `fakeip`-диапазоны; правила `russiaRouteData` и adblock.
- **BACKWARD COMPATIBILITY:** сгенерированный конфиг обязан оставаться валидным для
  `Libbox.checkConfig` и для старого ядра (на случай откатa бандла).
- **TESTS TO ADD FIRST:** `test/settings_dns_page_test.dart` — расширить:
  сгенерированный конфиг содержит ожидаемое правило; `test/fakeip_config_test.dart`
  остаётся зелёным; новый `test/dns_pre_ready_routing_test.dart`: при
  `hasProxies == true` правило присутствует, при `false` — отсутствует.
- **TESTS THAT MUST REMAIN UNCHANGED:** `core_config_migration_test.dart`,
  `route_exclude_russia_test.dart`, `call_vk_parasite_schema_test.dart`.
- **VALIDATION:** `flutter analyze`, `flutter test`,
  `python3 -B scripts/verify_client_boundaries.py`
- **MANUAL SCENARIO:** M21 плюс холодный старт с `vk_parasite` десять раз
- **EXPECTED STRUCTURED LOG:** до `READY` в логах нет запросов, разрешённых через
  `dns-remote`.
- **NEGATIVE ASSERTIONS:** ни одного `no active QUIC paths` из DNS-пути.
- **ROLLBACK:** revert; конфиг возвращается к текущему виду.
- **DEFINITION OF DONE:** соответствие выбранной ветке; десять холодных стартов без
  DNS-ошибок до READY.
- **STOP CONDITIONS:** если правило требует reload конфигурации на каждом старте —
  выбрать P1b и зафиксировать; если и P1b невозможен — STOP.
- **COMMIT BOUNDARY:** один PR.
- **NEXT TASK:** `HB-RW-029`.

---

## HB-RW-029 — Убрать runtime-состояние из `SingboxController`

- **STATUS:** BLOCKED(`HB-RW-020`, `HB-RW-011`)
- **GOAL:** оставить `SingboxController` фасадом libbox-RPC без собственного
  состояния runtime.
- **INVARIANTS ESTABLISHED:** R1, R6
- **REPOSITORY:** hydrabox
- **BASELINE:** merge `HB-RW-028`
- **PRECONDITIONS:** `HB-RW-020`, `HB-RW-011`
- **FILES / SYMBOLS:** `singbox/SingboxController.kt`: `running`, `serviceMode`,
  `activeRuntimeGeneration`, `lastRuntimeError`, `setRunning`, `markServiceStarted`,
  `markServiceStopped`, `forceMarkServiceStopped`, `clearRuntimeError`,
  `shouldCommandClientBeConnected`; `runtime/CoreRuntimeService.kt` — принимает эти
  величины на себя; все вызывающие
- **CURRENT BEHAVIOR:** фактический владелец `running` — `SingboxController`;
  `CoreRuntimeService` выводит из него своё состояние; `lastRuntimeError` читается
  только из главного процесса, где он всегда пуст.
- **TARGET BEHAVIOR:** `running` вычисляется как
  `runtimeSession.commandServer != null && runtimeSession.serviceGeneration != 0` и
  живёт в `CoreRuntimeService`; `serviceMode` — производная от `mode`;
  `runtimeGeneration` живёт в `CoreRuntimeService`; `lastRuntimeError` удалён.
  `shouldCommandClientBeConnected` получает значение параметром от
  `CoreRuntimeService`, а не читает поле.
- **IMPLEMENTATION:** перенести поля; заменить чтения на параметры и на снимок;
  удалить `lastRuntimeError`.
- **DELETE:** четыре поля и пять методов в `SingboxController`.
- **DO NOT CHANGE:** traffic-счётчики и `RuntimeTrafficRateTracker`;
  `CommandClientLifecycle`; throttling выдачи.
- **BACKWARD COMPATIBILITY:** снимок сохраняет все поля.
- **TESTS TO ADD FIRST:** `RuntimeRunningDerivationTest` (JVM): чистая функция
  `isRunning(commandServerPresent, serviceGeneration)`.
- **TESTS THAT MUST REMAIN UNCHANGED:** `RuntimeTrafficRateTrackerTest`,
  `CommandClientLifecycleTest`, `RuntimeEventCadenceTest`.
- **VALIDATION:** `./gradlew :app:testDebugUnitTest :app:lintDebug`, `flutter test`
- **MANUAL SCENARIO:** полный прогон M01, M02, M03, M07
- **EXPECTED STRUCTURED LOG:** без изменений.
- **NEGATIVE ASSERTIONS:** `grep -n "SingboxController.running

|activeRuntimeGeneration|lastRuntimeError" android/app/src/main`
  даёт совпадения только внутри `CoreRuntimeService` (или ноль).
- **ROLLBACK:** revert.
- **DEFINITION OF DONE:** grep соответствует ожиданию; прогон M01–M03 и M07 зелёный.
- **STOP CONDITIONS:** если `HydraBoxVpnService.protectSocket`-путь зависит от
  `SingboxController.running` — STOP и сообщить.
- **COMMIT BOUNDARY:** один PR.
- **NEXT TASK:** `HB-RW-030`.

---

## HB-RW-030 — Переименование generation по контракту §2.4

- **STATUS:** BLOCKED(`HB-RW-029`)
- **GOAL:** исключить использование одного имени в двух смыслах.
- **INVARIANTS ESTABLISHED:** R6
- **REPOSITORY:** hydrabox
- **BASELINE:** merge `HB-RW-029`
- **PRECONDITIONS:** `HB-RW-029`
- **FILES / SYMBOLS:** `runtime/CoreRuntimeService.kt`: `CoreProcessIdentity.generation`
  → `commandGeneration`, `sequence` → `eventSequence`; новое поле `runtimeGeneration`;
  `singbox/HydraBoxDefaultNetworkMonitor.kt`: `notificationGeneration` →
  `networkGeneration` (если не переименовано в `HB-RW-018`)
- **CURRENT BEHAVIOR:** `generation` означает то команду, то runtime, в зависимости от
  места; `notificationGeneration` фактически счётчик отмен доставки.
- **TARGET BEHAVIOR:** пять имён из §2.4, каждое в одном смысле.
- **IMPLEMENTATION:** механическое переименование плюс приведение условий инкремента
  к §2.4; поля protobuf `generation` и `last_sequence` **сохраняют имена** (wire
  format), меняются только Kotlin-идентификаторы, а маппинг документируется
  комментарием.
- **DELETE:** —
- **DO NOT CHANGE:** имена полей protobuf и Pigeon; Dart-читатели.
- **BACKWARD COMPATIBILITY:** wire format неизменен.
- **TESTS TO ADD FIRST:** `GenerationSemanticsTest` (JVM): `commandGeneration`
  растёт на каждой мутирующей команде; `runtimeGeneration` растёт только на
  `LAUNCHED`; `networkGeneration` — только на семантической смене.
- **TESTS THAT MUST REMAIN UNCHANGED:** `CoreRuntimeSnapshotCompatibilityTest`.
- **VALIDATION:** `./gradlew :app:testDebugUnitTest :app:lintDebug`, `flutter test`
- **MANUAL SCENARIO:** M03, M07
- **EXPECTED STRUCTURED LOG:** `rg` в логе меняется только при реальном создании
  runtime.
- **NEGATIVE ASSERTIONS:** `rg` не меняется при приёме команды START.
- **ROLLBACK:** revert.
- **DEFINITION OF DONE:** `GenerationSemanticsTest` зелёный.
- **STOP CONDITIONS:** если переименование требует изменения wire format — STOP.
- **COMMIT BOUNDARY:** один коммит.
- **NEXT TASK:** `HB-RW-031`.

---

## HB-RW-031 — Типизированный Pigeon вместо legacy Map

- **STATUS:** BLOCKED(`HB-RW-030`)
- **GOAL:** убрать обратную трансляцию protobuf в нетипизированные Map на границе
  Dart.
- **INVARIANTS ESTABLISHED:** R2
- **REPOSITORY:** hydrabox
- **BASELINE:** merge `HB-RW-030`
- **PRECONDITIONS:** `HB-RW-030`
- **FILES / SYMBOLS:** `runtime/CoreRuntimeClient.kt`: `toLegacyEventMaps`,
  `toLegacyStateMap`, `toLegacyTransportHealthMap`; `MainActivity.kt`:
  `toLegacyRuntimeMap`; `pigeons/singbox_api.dart`; `lib/app/runtime_event_controller.dart`;
  `lib/singbox/singbox_runtime.dart`
- **CURRENT BEHAVIOR:** типизированный protobuf декодируется и снова превращается в
  `Map<String, Any?>` перед выдачей в Dart; Dart разбирает Map.
- **TARGET BEHAVIOR:** Pigeon-структуры `RuntimeSnapshotMessage`,
  `RuntimeEventMessage`, `TransportHealthMessage` передаются напрямую; Map не
  пересекает границу.
- **IMPLEMENTATION:** описать структуры в `pigeons/singbox_api.dart`;
  перегенерировать; заменить читателей.
- **DELETE:** четыре функции трансляции.
- **DO NOT CHANGE:** состав полей (только их типизация); поведение UI.
- **BACKWARD COMPATIBILITY:** это последняя задача, где Map ещё существует;
  выполняется одним PR, потому что частичный переход даёт двоевластие типов.
- **TESTS TO ADD FIRST:** `test/runtime_event_controller_test.dart` переписывается на
  типизированные структуры; кейсы сохраняются один к одному, что фиксируется в
  commit message.
- **TESTS THAT MUST REMAIN UNCHANGED:** `test/traffic_status_reducer_test.dart`,
  `test/proxy_runtime_controller_test.dart` (входные данные адаптируются, ожидания нет).
- **VALIDATION:** `dart run pigeon --input pigeons/singbox_api.dart`, `dart format .`,
  `flutter analyze`, `flutter test`,
  `./gradlew :app:testDebugUnitTest :app:lintDebug`
- **MANUAL SCENARIO:** полный прогон M01–M21
- **EXPECTED STRUCTURED LOG:** без изменений.
- **NEGATIVE ASSERTIONS:** `grep -rn "toLegacy" android/app/src/main` даёт ноль
  совпадений.
- **ROLLBACK:** revert одного PR.
- **DEFINITION OF DONE:** grep пустой; полный прогон зелёный.
- **STOP CONDITIONS:** если какой-то Dart-читатель полагается на динамические ключи
  Map — STOP и перечислить.
- **COMMIT BOUNDARY:** один PR.
- **NEXT TASK:** `HB-RW-032`.

---

## HB-RW-032 — Удалить `awaitStopped` и `stopWaiters`

- **STATUS:** BLOCKED(`HB-RW-010`)
- **GOAL:** убрать механизм ожидания стопа, задачу которого выполняет serializer.
- **INVARIANTS ESTABLISHED:** R3
- **REPOSITORY:** hydrabox
- **BASELINE:** merge `HB-RW-031`
- **PRECONDITIONS:** `HB-RW-010`
- **FILES / SYMBOLS:** `singbox/SingboxController.kt`: `awaitStopped`,
  `notifyStopWaiters`, `stopWaiters`, `stopWaiterLock`;
  `runtime/CoreRuntimeService.kt`: `dispatchStart` (ветка смены режима)
- **CURRENT BEHAVIOR:** смена режима vpn↔proxy выполняется как
  `requestStopAll` плюс `awaitStopped(5 s)` плюс `startForegroundService`.
- **TARGET BEHAVIOR:** смена режима — две команды: `STOP` затем отложенная `START`
  (механизм отложенной START уже введён в `HB-RW-010`).
- **IMPLEMENTATION:** заменить ветку; удалить четыре символа.
- **DELETE:** четыре символа.
- **DO NOT CHANGE:** `requestStopAll`; поведение при совпадающем режиме.
- **BACKWARD COMPATIBILITY:** —
- **TESTS TO ADD FIRST:** `RuntimeStateMachineTest` — кейс «START с другим режимом
  во время RUNNING даёт STOP затем START».
- **TESTS THAT MUST REMAIN UNCHANGED:** `RuntimeServiceModeResolverTest`.
- **VALIDATION:** `./gradlew :app:testDebugUnitTest :app:lintDebug`
- **MANUAL SCENARIO:** переключение VPN → proxy → VPN трижды.
- **EXPECTED STRUCTURED LOG:** `STOP stage=released` затем `CONNECT source=mode_switch`.
- **NEGATIVE ASSERTIONS:** `grep -n "awaitStopped|stopWaiters" android/app/src/main`
  даёт ноль совпадений.
- **ROLLBACK:** revert.
- **DEFINITION OF DONE:** grep пустой; переключение режимов работает.
- **STOP CONDITIONS:** если отложенная START не поддерживает смену режима — STOP.
- **COMMIT BOUNDARY:** один коммит.
- **NEXT TASK:** `HB-RW-033`.

---

## HB-RW-033 — Удалить миграцию desired state

- **STATUS:** BLOCKED(`HB-RW-012`, плюс не ранее одного релиза после него)
- **GOAL:** убрать одноразовую миграцию со старого intent-файла.
- **INVARIANTS ESTABLISHED:** R20
- **REPOSITORY:** hydrabox
- **BASELINE:** merge `HB-RW-032`
- **PRECONDITIONS:** `HB-RW-012` вышел хотя бы в одном публичном релизе
- **FILES / SYMBOLS:** `HydraBoxApplication.kt`: `runtimeIntentFile`,
  `RuntimeIntentState`, `readRuntimeIntent`, `describeRuntimeIntent`,
  `writeRuntimeIntent`, `clearRuntimeIntent`, блок миграции
- **CURRENT BEHAVIOR:** при отсутствии `runtime-desired.txt` читается
  `singbox-runtime-intent.txt`.
- **TARGET BEHAVIOR:** старый файл не читается; при его наличии удаляется.
- **IMPLEMENTATION:** удалить символы; при первом запуске удалить файл, если он есть.
- **DELETE:** шесть символов плюс блок миграции.
- **DO NOT CHANGE:** `runtime-desired.txt` и его схему.
- **BACKWARD COMPATIBILITY:** пользователь, обновившийся через версию, потеряет
  только автоматическое восстановление после первого убийства процесса — приемлемо,
  потому что VPN восстанавливается по нажатию Connect.
- **TESTS TO ADD FIRST:** `DesiredStateTest` — кейс «старый файл игнорируется и
  удаляется».
- **TESTS THAT MUST REMAIN UNCHANGED:** все.
- **VALIDATION:** `./gradlew :app:testDebugUnitTest :app:lintDebug`
- **MANUAL SCENARIO:** обновление поверх версии с `HB-RW-012`.
- **EXPECTED STRUCTURED LOG:** —
- **NEGATIVE ASSERTIONS:** `grep -n "runtimeIntentFile" android/app/src/main` даёт
  ноль совпадений.
- **ROLLBACK:** revert.
- **DEFINITION OF DONE:** grep пустой.
- **STOP CONDITIONS:** если `HB-RW-012` ещё не вышел в релизе — не начинать.
- **COMMIT BOUNDARY:** один коммит.
- **NEXT TASK:** `HB-RW-034`.

---

## HB-RW-034 — Асинхронный `lookupOutboundExternalInfo`

- **STATUS:** BLOCKED(`HB-RW-008`)
- **GOAL:** прекратить блокировку binder-потока на 10 s.
- **INVARIANTS ESTABLISHED:** R3
- **REPOSITORY:** hydrabox
- **BASELINE:** merge `HB-RW-033`
- **PRECONDITIONS:** `HB-RW-008`
- **FILES / SYMBOLS:** `runtime/CoreRuntimeService.kt`: `executeCoreUtility`
  (ветка `LOOKUP_OUTBOUND_EXTERNAL_INFO`), `lookupOutboundExternalInfo`;
  `runtime/CoreRuntimeClient.kt`: `lookupOutboundExternalInfo`
- **CURRENT BEHAVIOR:** `lookupOutboundExternalInfo` в `:core` блокирует binder-поток
  на `CountDownLatch.await(10 s)`; при нескольких параллельных вызовах может исчерпать
  binder-пул процесса.
- **TARGET BEHAVIOR:** utility-запрос возвращает `requestId` немедленно; результат
  приходит отдельным `RuntimeEvent`; клиент сопоставляет по `requestId` и хранит
  дедлайн на своей стороне.
- **IMPLEMENTATION:** добавить `RuntimeEvent.utility_result` (аддитивно);
  в `:core` выполнять запрос на `ipc`-executor и публиковать результат событием;
  в клиенте — реестр ожидающих `requestId`.
- **DELETE:** `CountDownLatch` в `lookupOutboundExternalInfo`.
- **DO NOT CHANGE:** `UTILITY_DEADLINE_MILLIS`; остальные utility-ветки.
- **BACKWARD COMPATIBILITY:** старый клиент, ожидающий синхронный ответ, сломается,
  поэтому Kotlin и Dart меняются одним PR.
- **TESTS TO ADD FIRST:** `UtilityAsyncTest` (JVM): ответ приходит событием;
  повторный запрос с тем же `requestId` отклоняется.
- **TESTS THAT MUST REMAIN UNCHANGED:** `test/active_proxy_ip_controller_test.dart`.
- **VALIDATION:** `flutter analyze`, `flutter test`,
  `./gradlew :app:testDebugUnitTest :app:lintDebug`
- **MANUAL SCENARIO:** обновление IP активного outbound при плохой сети — UI не
  подвисает.
- **EXPECTED STRUCTURED LOG:** —
- **NEGATIVE ASSERTIONS:** нет `CountDownLatch` в `CoreRuntimeService`.
- **ROLLBACK:** revert одного PR.
- **DEFINITION OF DONE:** тест зелёный; UI не подвисает.
- **STOP CONDITIONS:** если событийный канал не гарантирует доставку при отключённом
  UI — STOP: тогда результат должен оставаться в снимке.
- **COMMIT BOUNDARY:** один PR.
- **NEXT TASK:** `HB-RW-035`.

---

## HB-RW-035 — `pendingSelection` вместо второго владельца выбора

- **STATUS:** BLOCKED(`HB-RW-008`)
- **GOAL:** сделать ядро единственным владельцем выбранного outbound.
- **INVARIANTS ESTABLISHED:** R1, R13
- **REPOSITORY:** hydrabox
- **BASELINE:** merge `HB-RW-034`
- **PRECONDITIONS:** `HB-RW-008`
- **FILES / SYMBOLS:** `runtime/CoreRuntimeService.kt`: `selectOutbound`,
  `updateOutboundGroups`, `selectedOutbounds`, `buildSnapshot`; `runtime/proto` —
  добавить `pending_selected_outbound_ids`; `lib/app/proxy_selection_controller.dart`
  и `lib/app/app.dart` — отображение «выбор применяется»
- **CURRENT BEHAVIOR:** `selectOutbound` пишет `selectedOutbounds` после успеха RPC,
  а `updateOutboundGroups` очищает карту и перезаполняет из снимка ядра; порядок не
  определён, поэтому успешный выбор может быть перезаписан устаревшим событием.
- **TARGET BEHAVIOR:** `selectedOutbounds` заполняется **только** из
  `updateOutboundGroups`; `selectOutbound` пишет `pendingSelection[groupId]` вместе с
  `commandGeneration`; запись снимается при подтверждении ядром либо при устаревании
  `commandGeneration`; снимок несёт оба поля; UI показывает «применяется», пока есть
  `pendingSelection`.
- **IMPLEMENTATION:** ввести поле `pendingSelection`; изменить два места записи;
  расширить снимок аддитивно; обновить Dart.
- **DELETE:** запись `selectedOutbounds` в `selectOutbound`.
- **DO NOT CHANGE:** `RuntimeCommandCoordinator` (в Dart retry по-прежнему запрещён);
  таймаут выбора 20 s.
- **BACKWARD COMPATIBILITY:** поле аддитивное.
- **TESTS TO ADD FIRST:** `PendingSelectionTest` (JVM): успешная команда создаёт
  `pendingSelection`; событие ядра с тем же выбором его снимает; событие с другим
  выбором и более новым `commandGeneration` снимает без применения;
  устаревший `commandGeneration` снимает.
- **TESTS THAT MUST REMAIN UNCHANGED:** `runtime_command_coordinator_test.dart`,
  `proxy_selection_controller_test.dart`.
- **VALIDATION:** `dart run pigeon --input pigeons/singbox_api.dart`,
  `flutter analyze`, `flutter test`,
  `./gradlew :app:testDebugUnitTest :app:lintDebug`
- **MANUAL SCENARIO:** M16 — смена outbound на работающем runtime; выбор не
  «отскакивает» назад.
- **EXPECTED STRUCTURED LOG:** —
- **NEGATIVE ASSERTIONS:** выбранный outbound в UI никогда не возвращается к
  предыдущему значению после успешной команды.
- **ROLLBACK:** revert.
- **DEFINITION OF DONE:** `PendingSelectionTest` зелёный; M16 без отскока.
- **STOP CONDITIONS:** если ядро не подтверждает выбор событием в течение 20 s —
  STOP и сообщить: тогда `pendingSelection` нужен явный дедлайн.
- **COMMIT BOUNDARY:** один PR.
- **NEXT TASK:** `HB-RW-036`.

---

## HB-RW-036 — Удалить скрытый fallback `safeCoreRestart` в `fullServiceRestart`

- **STATUS:** BLOCKED(`HB-RW-007`)
- **GOAL:** убрать второй recovery-путь для сбоя, который уже обрабатывает
  `CoreRuntimeService`.
- **INVARIANTS ESTABLISHED:** R5, R9
- **REPOSITORY:** hydrabox
- **BASELINE:** merge `HB-RW-035`
- **PRECONDITIONS:** `HB-RW-007`
- **FILES / SYMBOLS:** `lib/app/runtime_lifecycle_controller.dart`:
  `applyRuntimeBuild` (ветки после неуспеха и после исключения),
  `RuntimeApplyPolicy`
- **CURRENT BEHAVIOR:** при неуспехе `safeCoreRestart` Dart сам инициирует
  `fullServiceRestart`; при исключении — тоже; это второй путь восстановления для
  того же сбоя, который уже обрабатывает `failStartAndRollback` в `:core`.
- **TARGET BEHAVIOR:** `RELOAD` либо успешен, либо нет. При неуспехе возвращается
  `RuntimeLifecycleResult.failure` с кодом из `CommandResult`; решение о полном
  рестарте принимает пользователь или явная команда, но не скрытый fallback.
- **IMPLEMENTATION:** удалить обе fallback-ветки; сохранить `fullServiceRestart` как
  публичный метод, вызываемый явно (например при смене профиля).
- **DELETE:** две fallback-ветки и вызовы `_waitForHealthyRuntime` (уже удалён в
  `HB-RW-007`).
- **DO NOT CHANGE:** `RuntimeApplyPolicy` как перечисление; `fullServiceRestart`
  как метод; `_scheduleInvalidOutboundRetry`.
- **BACKWARD COMPATIBILITY:** при неуспешном применении конфига пользователь увидит
  ошибку вместо молчаливого перезапуска — это намеренное изменение поведения,
  фиксируется в `CHANGELOG.md`.
- **TESTS TO ADD FIRST:** `test/runtime_lifecycle_controller_test.dart` — кейсы:
  неуспешный `RELOAD` возвращает failure и **не** вызывает `stop`+`start`;
  явный `fullServiceRestart` работает как раньше.
- **TESTS THAT MUST REMAIN UNCHANGED:** `singbox_config_coordinator_test.dart`.
- **VALIDATION:** `flutter analyze`, `flutter test`
- **MANUAL SCENARIO:** изменить настройку, требующую reload, при работающем runtime;
  при искусственно сломанном конфиге — увидеть ошибку, а не перезапуск.
- **EXPECTED STRUCTURED LOG:** ни одного `CONNECT` без пользовательского действия
  после неуспешного `RELOAD`.
- **NEGATIVE ASSERTIONS:** нет двух `CONNECT` подряд на одно изменение настройки.
- **ROLLBACK:** revert.
- **DEFINITION OF DONE:** тесты зелёные; `CHANGELOG.md` обновлён.
- **STOP CONDITIONS:** если существует настройка, для которой reload заведомо не
  работает и требуется рестарт — STOP и перечислить: тогда такая настройка должна
  явно выбирать `fullServiceRestart`, а не полагаться на fallback.
- **COMMIT BOUNDARY:** один коммит плюс `CHANGELOG.md`.
- **NEXT TASK:** нет; после этой задачи выполняется gate §W аудита.

---

# §5. MIGRATION DAG

## 5.1 Граф

```
HB-RW-001 (HB1 API)
   |
   +--> HB-RW-002 (разметка событиями)
   |        |
   |        +--> HB-EXP-E11 (network_wait latency)  [C]
   |        +--> HB-RW-019 (index==-1)      ──┐
   |        +--> HB-RW-023 (aliases)        ──┤ независимые correctness-фиксы
   |        +--> HB-RW-016 (bounded rebind) ─┘
   |        |
   |        +--> HB-RW-040 (core-swap из runtime)   [решение C17]
   |                 |
   |                 ||+--> HB-RW-041 (удалить :core_probe)
   |||                          |
   |                          +--> HB-RW-042 (удалить Core Manager)
   |                                   |
   |                                      
                                               
   |                                            +  
                                                        
                           --------------------------+
   |                        |
   |                        +--> HB-RW-003(5полей)-->HB-RW-004(runtimeStatusMap)|||+-->HB-RW-006 (нотификация)
   |                        |        |
   |                        |        +--> [E1,E11] HB-RW-005 (дедлайн)
   |                        |                 |
   |                        |                 +--> HB-RW-007 (Dart supervisor)
   |                        |                          |
   |                        |                          +--> HB-RW-008 (serializer)
   |                        |                                   |
   |                        |         +-----------------------+
   |                        |         |
   |                        |         +--> [E2B] HB-RW-009 (LaunchTask)
   |                        |         |        |
   |                        |         |        +--> [E2B] HB-RW-010 (идемпотентность)
   |                        |         |                 |
   |                        |         |                 +--> HB-RW-011 (токены)
   |                        |         |                 |        |
   |                        |         |                 |        +--> HB-RW-017 (NETWORK_CHANGED)
   |                        |         |                 |                 |
   |                        |         |                 |                 +--> HB-RW-018
   |                        |         |                 +--> HB-RW-032
   |                        |         +--> HB-RW-034, HB-RW-035
   |                        +--> HB-RW-012 (desired state)
   |                                 |
   |                                 +--> HB-RW-013, HB-RW-014, HB-RW-015
   |                                 +--> HB-RW-012B (нужен также HB-RW-009)
   |
   +--> HC-RW-001 (коды и события Go)
            |
            +--> HB-BUNDLE-001
            +--> HC-RW-002 (health: один writer)
                     |
                     +--> HC-RW-003 (healthSnapshot)
                              |
                              +--> HC-RW-004 (RebindNetwork(gen) + captcha cancel,
                                              включает HC-RW-006)
                                       
                              |         +--> HC-RW-005 (domain-aware backoff)
                              |||                  |
                              |                  +--> HB-BUNDLE-003
                              |                           |
                              |                           +--> HB-RW-020
                              |                                    |
                              |                                    +--> HB-RW-021
                              |                                             |
                              |                                             +--> [E3] HB-RW-022
                              |                                                      |
                              |                                                      +--> HB-RW-024
                              |                                                               |
                              |+-->[E7]HB-RW-025||+--> HB-BUNDLE-002 (нужен также HB-RW-018)                      |
                                       |                                                      |
                                       +--> HB-EXP-E9  [C] -------------------------------   
                                                                                              
                                                                           ----------->+
                                                                                  |
                                                                     [E9] HB-RW-026 <-----+
                                                                                  |
                                                                                  +--> HB-RW-027
                                                                                           |
                                                                                           +--> [E5] HB-RW-028
                                                                                                    |
                                                                           HB-RW-029 <---------------+
                                                                               |
                                                                               +--> HB-RW-030 --> HB-RW-031
                                                                                                     |
                                                                                      HB-RW-033 <-----+
                                                                                                     |
                                                                                      HB-RW-036 <-----+
                                                                                                     |
                                                                                            GATE §W --+
```
Эксперименты класса A (`E1`, `E2A`, `E4`, `E6`, `E10`, `E12`) **выполнены** при
составлении документа; их evidence в §8.1, а выбранные ветки вписаны в
`IMPLEMENTATION` соответствующих задач. Остались только эксперименты класса C.

## 5.2 Таблица зависимостей

| TASK | repo | depends_on | blocks | can_parallelize_with |
|---|---|---|---|---|
| HB-EXP-E1 | hydrabox | — | **DONE (P2)**, см. §8.1 | — |
| HB-EXP-E2A | hydracore | — | **DONE (P1)**, см. §8.1 | — |
| HB-EXP-E2B | hydrabox | — | HB-RW-009, HB-RW-010 | E3, E5, E7, E8, E9, E11 |
| HB-EXP-E3 | hydrabox | — | **DONE (P1)**, см. §8.1 | E2B, E5, E7, E8, E11 |
| HB-EXP-E4 | hydrabox | — | **DONE (P1)**, см. §8.1 | — |
| HB-EXP-E5 | hydrabox | — | **DONE (P1)**, см. §8.1 | E2B, E3, E7, E8, E11 |
| HB-EXP-E6 | hydracore | — | **DONE (P2)**, см. §8.1 | — |
| HB-EXP-E7 | hydrabox | — | HB-RW-025 | E2B, E3, E5, E8, E11 |
| HB-EXP-E8 | hydrabox | HB-RW-002 | — (post-gate) | всё |
| HB-EXP-E9 | hydrabox | HB-BUNDLE-002 | HB-RW-026 | E8 |
| HB-EXP-E10 | hydracore | — | **DONE (P1)**, см. §8.1 | — |
| HB-EXP-E11 | hydrabox | HB-RW-002 | HB-RW-005 | E2B, E3, E5, E7, E8 |
| HB-EXP-E12 | hydracore | — | **DONE (P2)**, см. §8.1 | — |
| HB-RW-001 | hydrabox | — | HB-RW-002 | HC-RW-001, все эксперименты A |
| HB-RW-002 | hydrabox | HB-RW-001 | HB-RW-040, HB-RW-016, HB-RW-019, HB-RW-023, E8, E11 | HC-RW-001, HC-RW-002 |
| HB-RW-040 | hydrabox | HB-RW-002 | HB-RW-041 | HB-RW-016, HB-RW-019, HB-RW-023, HC-* |
| HB-RW-041 | hydrabox | HB-RW-040 | HB-RW-042 | HB-RW-016, HB-RW-019, HB-RW-023, HC-* |
| HB-RW-042 | hydrabox | HB-RW-041 | HB-RW-003 | HB-RW-016, HB-RW-019, HB-RW-023, HC-* |
| HC-RW-001 | hydracore | — | HB-BUNDLE-001, HC-RW-002 | HB-RW-001, HB-RW-002 |
| HB-BUNDLE-001 | hydrabox | HC-RW-001, HB-RW-002 | — | HB-RW-003 и далее |
| HB-RW-019 | hydrabox | HB-RW-002 | — | HB-RW-023, HB-RW-016, HB-RW-003 |
| HB-RW-023 | hydrabox | HB-RW-002 | — | HB-RW-019, HB-RW-016, HB-RW-003 |
| HB-RW-016 | hydrabox | HB-RW-002 | — | HB-RW-019, HB-RW-023, HB-RW-003 |
| HB-RW-003 | hydrabox | HB-RW-042 | HB-RW-004 | HC-RW-002, HC-RW-003 |
| HB-RW-004 | hydrabox | HB-RW-003 | HB-RW-006, HB-RW-012 | HC-RW-002, HC-RW-003 |
| HB-RW-006 | hydrabox | HB-RW-004 | HB-RW-005 | HB-RW-012, HC-* |
| HB-RW-005 | hydrabox | HB-RW-006, E11 | HB-RW-007 | HB-RW-012, HC-* |
| HB-RW-007 | hydrabox | HB-RW-005 | HB-RW-008, HB-RW-036 | HB-RW-012, HC-* |
| HB-RW-008 | hydrabox | HB-RW-007 | HB-RW-009, HB-RW-034, HB-RW-035 | HC-* |
| HB-RW-009 | hydrabox | HB-RW-008, E2B | HB-RW-010, HB-RW-012B | HC-* |
| HB-RW-010 | hydrabox | HB-RW-009, E2B | HB-RW-011, HB-RW-017, HB-RW-032 | HC-* |
| HB-RW-011 | hydrabox | HB-RW-010 | HB-RW-017, HB-RW-029 | HC-* |
| HB-RW-012 | hydrabox | HB-RW-004 | HB-RW-013, HB-RW-014, HB-RW-015, HB-RW-012B, HB-RW-033 | HB-RW-005..011, HC-* |
| HB-RW-012B | hydrabox | HB-RW-012, HB-RW-009 | — | HB-RW-013..015 |
| HB-RW-013 | hydrabox | HB-RW-012 | — | HB-RW-014, HB-RW-015 |
| HB-RW-014 | hydrabox | HB-RW-012 | — | HB-RW-013, HB-RW-015 |
| HB-RW-015 | hydrabox | HB-RW-012 | — | HB-RW-013, HB-RW-014 |
| HB-RW-017 | hydrabox | HB-RW-011 | HB-RW-018 | HC-RW-004 (Go-часть) |
| HB-RW-018 | hydrabox | HB-RW-017 | HB-BUNDLE-002, HB-RW-027 | HC-RW-004 |
| HC-RW-002 | hydracore | HC-RW-001 | HC-RW-003 | вся Android-ветка до HB-BUNDLE-003 |
| HC-RW-003 | hydracore | HC-RW-002 | HC-RW-004 | вся Android-ветка |
| HC-RW-004 | hydracore | HC-RW-003 | HC-RW-005, HB-BUNDLE-002 | HB-RW-005..018 |
| HC-RW-005 | hydracore | HC-RW-004 | HB-BUNDLE-003 | HB-RW-005..018 |
| HC-RW-006 | hydracore | **выполняется внутри `HC-RW-004`** | — | — |
| HB-BUNDLE-002 | hydrabox | HC-RW-004, HC-RW-005, HB-RW-018 | HB-EXP-E9 | — |
| HB-BUNDLE-003 | hydrabox | HC-RW-004 (включает HC-RW-006), HC-RW-005, HB-BUNDLE-002 | HB-RW-020 | — |
| HB-RW-020 | hydrabox | HB-BUNDLE-003 | HB-RW-021, HB-RW-029 | — |
| HB-RW-021 | hydrabox | HB-RW-020 | HB-RW-022, HB-RW-024 | — |
| HB-RW-022 | hydrabox | HB-RW-021, E3 | HB-RW-024 | — |
| HB-RW-024 | hydrabox | HB-RW-022 | HB-RW-025 | — |
| HB-RW-025 | hydrabox | HB-RW-024, E7 | HB-RW-026 | — |
| HB-RW-026 | hydrabox | HB-RW-025, E9 | HB-RW-027 | — |
| HB-RW-027 | hydrabox | HB-RW-018, HB-RW-026 | HB-RW-028 | — |
| HB-RW-028 | hydrabox | HB-RW-027, E5 | HB-RW-029 | — |
| HB-RW-029 | hydrabox | HB-RW-020, HB-RW-011, HB-RW-028 | HB-RW-030 | — |
| HB-RW-030 | hydrabox | HB-RW-029 | HB-RW-031 | — |
| HB-RW-031 | hydrabox | HB-RW-030 | HB-RW-033, HB-RW-036 | — |
| HB-RW-032 | hydrabox | HB-RW-010 | — | HB-RW-013..018 |
| HB-RW-033 | hydrabox | HB-RW-012 плюс один публичный релиз | — | HB-RW-034..036 |
| HB-RW-034 | hydrabox | HB-RW-008 | — | HB-RW-035 |
| HB-RW-035 | hydrabox | HB-RW-008 | — | HB-RW-034 |
| HB-RW-036 | hydrabox | HB-RW-007, HB-RW-031 | GATE §W | — |

## 5.3 Что можно делать параллельно между репозиториями

**Полностью параллельно, без координации:**- вся цепочка `HC-RW-001 → HC-RW-002 → HC-RW-003` в hydracore и цепочка

  `HB-RW-001 → HB-RW-002 → HB-RW-040 → HB-RW-041 → HB-RW-042 → HB-RW-003 →
  HB-RW-004 → HB-RW-006 → HB-RW-005 → HB-RW-007 → HB-RW-008 → HB-RW-009 →
  HB-RW-010 → HB-RW-011` в hydrabox.
  Причина: изменения ядра аддитивны, Android их не читает до `HB-RW-020`.- ветка desired state (`HB-RW-012` … `HB-RW-015`) параллельна ветке serializer
  (`HB-RW-005` … `HB-RW-011`), кроме `HB-RW-012B`.- эксперименты класса A (`E1`, `E2A`, `E4`, `E6`, `E10`, `E12`) параллельны всему.

**Требуют конкретной версии второго репозитория:**

| Задача hydrabox | Требует в hydracore |
|---|---|
| `HB-BUNDLE-001` | merge `HC-RW-001` и опубликованный артефакт |
| `HB-BUNDLE-002` | merge `HC-RW-004` и `HC-RW-005` |
| `HB-BUNDLE-003` | merge `HC-RW-004` (включает `HC-RW-006`) и `HC-RW-005` |
| `HB-RW-020` | `HB-BUNDLE-003` (то есть ядро с `domain`, `terminal`, `applicable`) |
| `HB-RW-018` | ничего: `RebindNetwork(0)`-совместимость позволяет мержить Android раньше ядра |
| `HB-EXP-E9` | `HB-BUNDLE-002` |

**Никогда не требуется атомарный merge двух репозиториев.** Это обеспечено двумярешениями: (1) все изменения ядра аддитивны при неизменных версиях схемы (**R14**);(2) `RebindNetwork(0)` ведёт себя как безусловный rebind, поэтому Android-сторонаможет опережать ядро.

---

# §6. INTERMEDIATE COMPATIBILITY

## 6.0 Что вообще является «версией» после решения C17

Ядро поставляется **только** внутри APK: пин submodule плюс артефакт
`android/app/libs/libbox.aar` с `libbox.sha256` и `libbox.provenance.json`.
Подсистема доставки ядра на устройство удалена (`HB-RW-040` … `HB-RW-042`).
Следствие: конфигурация «старая версия приложения плюс новое ядро» в production
не существует.

Остаётся ровно **одно** окно рассинхронизации, и оно внутри истории репозиториев:
задача в hydracore смержена, а соответствующий `HB-BUNDLE-*` в hydrabox ещё нет.
Все правила совместимости ниже обслуживают только это окно.

| Комбинация | Существует в production? | Кто её обеспечивает |
|---|---|---|
| APK и его артефакт из одного релиза | да, единственная | `verify_libbox.py`, `verify_extended_core.py` |
| hydrabox HEAD плюс ещё не обновлённый артефакт | да, во время разработки | аддитивность (**R14**), `runCatching` на новых экспортах, `RebindNetwork(0)` |
| старый APK плюс новый артефакт | **нет** | подсистема удалена |

## 6.1 Таблица по задачам

Колонки: «HB опережает HC» — hydrabox-задача смержена, артефакт ещё старый;«HC опережает HB» — hydracore-задача смержена, bundle bump ещё не сделан.

| TASK | HB опережает HC | HC опережает HB | coordinated release | schema backward compatible | temporary dual-read | когда убрать legacy |
|---|---|---|---|---|---|---|
| HB-RW-001 | не касается HC | — | нет | не меняет | нет | — |
| HB-RW-002 | да | — | нет | не меняет | нет | — |
| HC-RW-001 | — | да: только телеметрия внутри ядра | нет | не меняет | нет | — |
| HB-BUNDLE-001 | — | — | нет | не меняет | нет | — |
| HB-RW-040 | да | — | нет | не меняет | нет | — |
| HB-RW-041 | да | — | нет | protobuf-сообщения probe остаются deprecated | нет | номера полей не переиспользуются никогда |
| HB-RW-042 | да | — | нет | Pigeon-API удаляется целиком, обе стороны в одном PR | нет | — |
| HB-RW-019 | да | — | нет | не меняет | нет | — |
| HB-RW-023 | да | — | нет | не меняет | нет | — |
| HB-RW-016 | да | — | нет | не меняет | нет | — |
| HB-RW-003 | да | — | нет | снимок теряет 5 ключей, читатели удалены тем же PR | нет | — |
| HB-RW-004 | да | — | нет | добавляется трактовка `RUNTIME_STATE_UNKNOWN` | нет | — |
| HB-RW-006 | да | — | нет | не меняет | нет | — |
| HB-RW-005 | да | — | нет | аддитивное `interactive_deadline_millis`; отсутствие равно «неинтерактивный» | нет | — |
| HB-RW-007 | да | — | нет | не меняет | нет | — |
| HB-RW-008 | да | — | нет | `PREPARING` остаётся в enum как deprecated | да: Dart обязан понимать `PREPARING` | когда `PREPARING` перестанут присылать все поддерживаемые сборки |
| HB-RW-009 | да | — | нет | не меняет | нет | — |
| HB-RW-010 | да | — | нет | `REQUEST_RECOVERY` отвечает `runtime.command.unsupported` | нет | значение enum остаётся навсегда |
| HB-RW-011 | да | — | нет | не меняет | нет | — |
| HB-RW-012 | да | — | нет | аддитивное `desired_runtime` в снимке | да: чтение старого intent-файла | `HB-RW-033`, не ранее одного публичного релиза |
| HB-RW-012B | да | — | нет | не меняет | нет | — |
| HB-RW-013 | да | — | нет | не меняет | нет | — |
| HB-RW-014 | да | — | нет | аддитивное событие `epochChanged` | нет | — |
| HB-RW-015 | да | — | нет | не меняет | нет | — |
| HB-RW-017 | да | — | нет | аддитивный `COMMAND_KIND_NETWORK_CHANGED` | нет | — |
| HB-RW-018 | **да, критично**: `RebindNetwork(0)` эквивалентен текущему поведению, поэтому Android можно мержить раньше ядра | — | нет | не меняет | да: вызов экспорта generation обёрнут в `runCatching` | после `HB-BUNDLE-002` |
| HC-RW-002 | — | **да**: ключи аддитивны при `schema_version: 2`; текущий `TransportHealthBridge` читает `== 2` и игнорирует новые ключи | нет | да, аддитивно | да, до `HB-BUNDLE-003` | переходно; снимается отдельным решением |
| HC-RW-003 | — | да | нет | не меняет | нет | — |
| HC-RW-004 | — | **да**: новый экспорт generation не вызывается, пока Android его не знает | нет | не меняет wire format | да | после `HB-BUNDLE-002` |
| HC-RW-005 | — | да | нет | не меняет | нет | — |
| HC-RW-006 (в PR `HC-RW-004`) | — | да: новые коды аддитивны, неизвестный код читается как generic | нет | не меняет | нет | — |
| HB-BUNDLE-002 | — | — | нет | не меняет | закрывает dual-read `HB-RW-018` и `HC-RW-004` | — |
| HB-BUNDLE-003 | — | — | нет | не меняет | закрывает dual-read `HC-RW-002` | — |
| HB-RW-020 | да | — | нет | да | да, переходный: чтение health и без `domain`, и с ним | отдельным решением после `HB-BUNDLE-003`; задачи в плане нет |
| HB-RW-021 | да | — | нет | аддитивное `probe_last_error` | нет | — |
| HB-RW-022 | да | — | нет | не меняет | да: `preconnectUrlTest` остаётся обёрткой | `HB-RW-031` |
| HB-RW-024 | да | — | нет | не меняет | нет | — |
| HB-RW-025 | да | — | нет | не меняет | нет | — |
| HB-RW-026 | да | — | нет | не меняет | нет | — |
| HB-RW-027 | да | — | нет | не меняет | нет | — |
| HB-RW-028 | да | — | нет | конфиг остаётся валидным для схемы 1 | нет | — |
| HB-RW-029 | да | — | нет | не меняет | нет | — |
| HB-RW-030 | да | — | нет | имена полей wire format не меняются | нет | — |
| HB-RW-031 | да | — | нет | Pigeon-структуры заменяют Map; граница внутри одного APK | нет | закрывает dual-read `HB-RW-022` |
| HB-RW-032 | да | — | нет | не меняет | нет | — |
| HB-RW-033 | да | — | нет | не меняет | закрывает dual-read `HB-RW-012` | — |
| HB-RW-034 | да | — | нет | аддитивный `utility_result` в событии | нет | — |
| HB-RW-035 | да | — | нет | аддитивное `pending_selected_outbound_ids` | нет | — |
| HB-RW-036 | да | — | нет | не меняет | нет | — |

## 6.2 Правила, обеспечивающие отсутствие атомарных двухрепозиторных мержей

1. **Аддитивность (R14).** Ни одна задача не повышает `api_version`,

   `runtime.version`, `runtime.snapshot_schema_version`, `schema_version`,
   `APIVersion`. Все расширения — новые ключи и новые поля protobuf.
2. **Нулевая generation как «без guard».** `RebindNetwork(0)` ведёт себя как
   безусловный rebind, поэтому Android может опережать ядро.
3. **Опциональные экспорты через `runCatching`.** Любой новый libbox-экспорт
   вызывается защищённо; отсутствие экспорта означает деградацию к прежнему
   поведению, а не сбой.
4. **Bundle-bump — отдельная задача.** Изменение ядра и его доставка в приложение
   никогда не находятся в одном PR.
5. **Kotlin и Dart в одном PR там, где меняется форма данных.** Задачи
   `HB-RW-003`, `HB-RW-013`, `HB-RW-021`, `HB-RW-031`, `HB-RW-034`, `HB-RW-035`,
   `HB-RW-042` меняют обе стороны Pigeon-границы одним PR: она внутри одного APK,
   и частичный переход даёт двоевластие типов.
6. **Номера полей protobuf не переиспользуются.** Удалённые сообщения остаются
   deprecated (`CoreProbeRequest`, `CoreProbeReport`, `REQUEST_RECOVERY`,
   `RUNTIME_STATE_PREPARING`).

---

# §7. FINAL EXECUTION ORDER

`RISK`: L низкий, M средний, H высокий, XH очень высокий.

`PR`: ожидаемый размер diff (S до 150 строк, M до 500, L до 1500).

`STATUS` рассчитан от состояния «ничего не выполнено».

#

| TASK ID | STATUS | REPO | RISK | DEPENDS ON | BLOCKING EXP | PR | INVARIANT | DONE CHECK |
|---|---|---|---|---|---|---|---|---|---|
| 1 | HB-EXP-E1 | **DONE (P2)** | hydrabox | L | — | — | — | — | evidence в §8.1 |
| 2 | HB-EXP-E2A | **DONE (P1)** | hydracore | L | — | — | — | — | evidence в §8.1 |
| 3 | HB-EXP-E4 | **DONE (P1)** | hydrabox | L | — | — | — | — | evidence в §8.1 |
| 4 | HB-EXP-E6 | **DONE (P2)** | hydracore | L | — | — | — | — | evidence в §8.1 |
| 5 | HB-EXP-E10 | **DONE (P1)** | hydracore | L | — | — | — | — | evidence в §8.1 |
| 6 | HB-EXP-E12 | **DONE (P2)** | hydracore | L | — | — | — | — | evidence в §8.1 |
| 7 | HB-RW-001 | READY | hydrabox | L | — | — | S | R18 | `HydraBoxEventFormatTest` зелёный |
| 8 | HC-RW-001 | READY | hydracore | L | — | — | M | R18 | go-тесты зелёные, словари совпадают |
| 9 | HB-RW-002 | READY | hydrabox | L | 7 | — | M | R12, R18 | M01 и M07 дают полную цепочку §Q.3 |
| 10 | HB-EXP-E11 | BLOCKED(HB-RW-002) | hydrabox | L | 9 | — | S | — | P95 `network_wait` в §8 |
| 11 | HB-EXP-E2B | READY | hydrabox | M | — | — | S | — | пять измерений отмены в §8 |
| 12 | HB-EXP-E3 | **RESOLVED (P1)** | hydrabox | L | — | — | S | — | последовательность probe против `monitor stop` |
| 13 | HB-EXP-E5 | **RESOLVED (P1)** | hydrabox | L | — | — | S | — | статический маршрут DNS до READY |
| 14 | HB-EXP-E7 | READY | hydrabox | M | — | — | S | — | матрица «устройство × сценарий» |
| 15 | HB-RW-040 | READY | hydrabox | L | 9 | — | S | R1, R3 | grep `CoreBundleManager` в `CoreRuntimeService` пуст |
| 16 | HB-RW-041 | BLOCKED(HB-RW-040) | hydrabox | L | 15 | — | S | R20 | два процесса приложения, verify зелёный |
| 17 | HB-RW-042 | BLOCKED(HB-RW-041) | hydrabox | M | 16 | — | L | R20 | grep Core Manager пуст, CHANGELOG обновлён |
| 18 | HB-RW-019 | READY | hydrabox | L | 9 | — | S | R4 | `EffectiveNetworkIndexTest`, M09 без ложного NONE |
| 19 | HB-RW-023 | READY | hydrabox | L | 9 | — | S | R15 | карта алиасов пуста после 20 сессий |
| 20 | HB-RW-016 | READY | hydrabox | L | 9 | — | S | R9 | не более трёх подряд bind без connect |
| 21 | HB-BUNDLE-001 | BLOCKED(HC-RW-001) | hydrabox | L | 8, 9 | — | S | — | оба verify-скрипта зелёные |
| 22 | HB-RW-003 | BLOCKED(HB-RW-042) | hydrabox | M | 17 | — | M | R2 | grep пяти полей пуст |
| 23 | HB-RW-004 | BLOCKED(HB-RW-003) | hydrabox | M | 22 | — | S | R2, R20 | grep legacy-символов в `MainActivity` пуст |
| 24 | HB-RW-006 | BLOCKED(HB-RW-004) | hydrabox | L | 23 | — | S | R10 | «Connected» только при RUNNING |
| 25 | HB-RW-005 | BLOCKED(E11) | hydrabox | M | 24, 10 | E11 | M | R19 | один источник дедлайна в логе |
| 26 | HB-RW-007 | BLOCKED(HB-RW-005) | hydrabox | H | 25 | — | L | R2, R11 | grep watchdog и polling пуст |
| 27 | HB-RW-008 | BLOCKED(HB-RW-007) | hydrabox | H | 26 | — | L | R1, R3, R12, R19 | `RuntimeStateMachineTest`, `EmitSingleThreadTest` |
| 28 | HB-RW-009 | BLOCKED(E2B) | hydrabox | XH | 27, 11 | E2B | L | R3, R9 | M02 и M03 десять прогонов без `stop.unconfirmed` |
| 29 | HB-RW-010 | BLOCKED(E2B) | hydrabox | M | 28 | E2B | M | R19 | пять кейсов идемпотентности |
| 30 | HB-RW-011 | BLOCKED(HB-RW-010) | hydrabox | L | 29 | — | S | R6 | grep `startToken` пуст |
| 31 | HB-RW-012 | BLOCKED(HB-RW-004) | hydrabox | M | 23 | — | M | R7, R8, R9, R20 | запрещённый сценарий невоспроизводим |
| 32 | HB-RW-013 | BLOCKED(HB-RW-012) | hydrabox | M | 31 | — | M | R7, R20 | grep service-state пуст |
| 33 | HB-RW-014 | BLOCKED(HB-RW-012) | hydrabox | L | 31 | — | S | R2, R6 | M05: кэши обнулены по смене epoch |
| 34 | HB-RW-015 | BLOCKED(HB-RW-012) | hydrabox | L | 31 | — | S | R2, R20 | grep `postDelayed` в тайле пуст |
| 35 | HB-RW-012B | BLOCKED(HB-RW-009, HB-RW-012) | hydrabox | M | 28, 31 | — | S | R1, R7 | grep `shouldRestoreStickyStart` пуст |
| 36 | HB-RW-032 | BLOCKED(HB-RW-010) | hydrabox | L | 29 | — | S | R3 | grep `awaitStopped` пуст |
| 37 | HB-RW-034 | BLOCKED(HB-RW-008) | hydrabox | M | 27 | — | M | R3 | нет `CountDownLatch` в `CoreRuntimeService` |
| 38 | HB-RW-035 | BLOCKED(HB-RW-008) | hydrabox | M | 27 | — | M | R1, R13 | M16 без отскока выбора |
| 39 | HB-RW-017 | BLOCKED(HB-RW-011) | hydrabox | M | 30 | — | M | R1, R3 | монитор не вызывает VpnService напрямую |
| 40 | HB-RW-018 | BLOCKED(HB-RW-017) | hydrabox | H | 39 | — | L | R4, R6 | число REBIND равно числу смен сети |
| 41 | HC-RW-002 | BLOCKED(HC-RW-001) | hydracore | M | 8 | — | M | R5, R14, R18 | `captcha_flow_test.go` зелёный без правок |
| 42 | HC-RW-003 | BLOCKED(HC-RW-002) | hydracore | L | 41 | — | S | R18 | нет снимка с `lanes>0` и failure |
| 43 | HC-RW-004 | BLOCKED(HC-RW-003) | hydracore | M | 42 | — | M | R4, R5, R6 | `TestRebindNetworkReplacesPaths` зелёный |
| 44 | HC-RW-005 | BLOCKED(HC-RW-004) | hydracore | M | 43 | — | S | R5, R9 | terminal не входит в backoff |
| 45 | HC-RW-006 | **MERGED в 43** | hydracore | — | 42 | — | — | R18 | проверяется в DoD задачи 43: challenge не исчезает без события |
| 46 | HB-BUNDLE-002 | BLOCKED(HC-RW-004, HB-RW-018) | hydrabox | M | 43, 44, 40 | — | S | — | M07 даёт ровно три REBIND |
| 47 | HB-EXP-E9 | BLOCKED(HB-BUNDLE-002) | hydrabox | M | 46 | — | S | — | три числа покрытия regex в §8 |
| 48 | HB-BUNDLE-003 | BLOCKED(HC-RW-005) | hydrabox | L | 43, 44, 46 | — | S | — | `TransportHealthBridge.parse` не бросает |
| 49 | HB-RW-020 | BLOCKED(HB-BUNDLE-003) | hydrabox | M | 48 | — | M | R10, R18 | M14 даёт FAILED через 60 s без цикла |
| 50 | HB-RW-021 | BLOCKED(HB-RW-020) | hydrabox | L | 49 | — | M | R15 | grep `startsWith("probe")` пуст |
| 51 | HB-RW-022 | BLOCKED(HB-RW-021) | hydrabox | M | 50, 12 | E3 | M | R15 | матрица режимов покрыта тестами |
| 52 | HB-RW-024 | BLOCKED(HB-RW-022) | hydrabox | M | 51 | — | M | R16 | epoch клиента не меняется при foreground |
| 53 | HB-RW-025 | BLOCKED(E7) | hydrabox | H | 52, 14 | E7 | M | R5, R9, R16 | M04 и M09 на трёх устройствах |
| 54 | HB-RW-026 | BLOCKED(E9) | hydrabox | M | 53, 47 | E9 | S | R5, R18 | соответствие выбранной ветке |
| 55 | HB-RW-027 | BLOCKED(HB-RW-018, HB-RW-026) | hydrabox | M | 40, 54 | — | M | R17, R18 | нет DNS-ответов с устаревшей `ng` |
| 56 | HB-RW-028 | BLOCKED(HB-RW-027) | hydrabox | M | 55, 13 | E5 | M | R17 | десять холодных стартов без DNS-ошибок |
| 57 | HB-RW-029 | BLOCKED(HB-RW-020, HB-RW-011) | hydrabox | M | 49, 30, 56 | — | M | R1, R6 | grep состояния в `SingboxController` пуст |
| 58 | HB-RW-030 | BLOCKED(HB-RW-029) | hydrabox | L | 57 | — | M | R6 | `GenerationSemanticsTest` зелёный |
| 59 | HB-RW-031 | BLOCKED(HB-RW-030) | hydrabox | M | 58 | — | L | R2 | grep `toLegacy` пуст |
| 60 | HB-RW-033 | BLOCKED(релиз с HB-RW-012) | hydrabox | L | 31 плюс релиз | — | S | R20 | grep `runtimeIntentFile` пуст |
| 61 | HB-RW-036 | BLOCKED(HB-RW-007, HB-RW-031) | hydrabox | M | 26, 59 | — | S | R5, R9 | нет двух CONNECT на одно изменение настройки |
| 62 | HB-EXP-E8 | BLOCKED(HB-RW-002) | hydrabox | L | 9 | — | S | — | таблица частот heartbeat в §8 |
| 63 | GATE §W | — | оба | — | 1..62 | — | — | все | G1..G14 зафиксированы в `docs/android-lifecycle-soak.md` |

## 7.1 Что можно вести параллельно прямо сейчас

- **Поток A — эксперименты класса A (STATIC).** Закрыт: E1, E2A, E4, E6, E10, E12
  выполнены, evidence в §8.1, их ветки уже вписаны в соответствующие задачи.
- **Поток B — observability в hydrabox.** `HB-RW-001` затем `HB-RW-002`.
- **Поток C — hydracore.** `HC-RW-001` затем `HC-RW-002` затем `HC-RW-003`.
- **Поток D — эксперименты класса C (DEVICE).** `HB-EXP-E2B`, `HB-EXP-E3`,
  `HB-EXP-E5`, `HB-EXP-E7`: нужен девайс, но не нужен код.

Потоки A, B, C, D независимы. После `HB-RW-002` открывается пятый поток: удаление
core-swap (`HB-RW-040` → `HB-RW-041` → `HB-RW-042`) плюс три независимых
correctness-фикса (`HB-RW-019`, `HB-RW-023`, `HB-RW-016`), которые можно делать
параллельно друг другу.

## 7.2 NEXT ACTION NOW

Первой coding-agent задаче отдать **`HB-RW-001`** — «Структурированные события `HB1`
и словарь safe error codes». Она `READY`, без предусловий, не меняет ни одного
поведения, и без неё нельзя валидировать ни одну последующую задачу.

Второму исполнителю — **`HB-RW-016`** (ограниченный rebind binder-клиента) либо
**`HB-RW-019`** (`interfaceIndex == -1` не должен публиковаться как «сети нет»):
обе `READY` после `HB-RW-002`, обе независимы, обе закрывают доказанные дефекты
корректности.

Если доступно устройство — параллельно запустить **`HB-EXP-E2B`**: он блокирует
`HB-RW-009`, самую рискованную задачу плана; чем раньше известна его ветка
(P1 или P2), тем меньше вероятность переделки. Остальные ожидающие эксперименты
класса C (`E3`, `E5`, `E7`, `E9`, `E11`) можно раздавать в любом порядке — они
независимы друг от друга.

**                                                            

Чего не делать сейчас:** не начинать `HB-RW-003` и далее, пока не смержены
`HB-RW-040` … `HB-RW-042`; не начинать `HB-RW-005` (ждёт `E11`), `HB-RW-009` и
`HB-RW-010` (ждут `E2B`), `HB-RW-022` (ждёт `E3`), `HB-RW-025` (ждёт `E7`),
`HB-RW-026` (ждёт `E9`), `HB-RW-028` (ждёт `E5`). Задачи `HB-RW-007`, `HB-RW-018`,
`HB-RW-020` и `HC-RW-004` **больше не ждут экспериментов** — только своих
предшественников по коду. `HC-RW-006` отдельной задачей не выдаётся: она входит в PR
`HC-RW-004`.

---

# §8. EVIDENCE LOG

Раздел заполняется **исполнителями экспериментов   
         

**. До появления записисоответствующие задачи не могут иметь статус `READY`. Формат записи фиксирован.

```
### <EXP ID> — <дата> — <исполнитель>
CLASS: A

| B | C
BRANCH SELECTED: P1

| P1b | P2
EVIDENCE:
  <факты: имена функций, числа, таблицы измерений>
CONSEQUENCE:
  <какие задачи разблокированы и какая их ветка реализации выбрана>
INSTRUMENTATION CLEANED: yes

| no | n/a
```
#

# 8.1 Выполненные эксперименты

### HB-EXP-E1 — 2026-08-26 — составитель плана

CLASS: A. BRANCH SELECTED: **P2**.

EVIDENCE:

- `experimental/libbox/command_client.go:Connect()` синхронен: `dialWithRetry`, затем

  `handler.Connected()`, затем `dispatchCommands()`, затем return. Значит обычной
  гонки по асинхронности между `connectClient()` и `getRuntimeSnapshot()` нет: обе
  задачи идут по FIFO одного `SingboxController.commandExecutor`, и подключение
  завершается внутри первой задачи.- `CommandClientLifecycle.beginConnect(shouldConnect)` возвращает `null` при
  `!shouldConnect`, при `reconnectPendingEpoch != null` и при
  `state != DISCONNECTED`. После `markServiceStarted` первое условие ложно, так как
  `running == true`.- Путь `reconnectPendingEpoch != null` **достижим**: `onDisconnected` в ветке
  `UNEXPECTED` выставляет `reconnectPendingEpoch` и планирует reconnect с задержкой
  250..5000 ms. Если в это окно происходит новый старт либо `RESTART_CORE`,
  `markServiceStarted` вызывает `connectClient()`, `beginConnect` отдаёт `null`,
  клиент не создаётся, и `commandClient` остаётся `null`.- Далее `verifyHealthAndCompleteStart` вызывает `SingboxController.getRuntimeSnapshot`,
  который через `withPersistentCommandClient` бросает
  `IllegalStateException("HydraCore command client is not connected")`, и `onFailure`
  вызывает `failStartAndRollback("runtime.start.snapshot")`, то есть **уничтожает
  полностью здоровый runtime**.- Чистый пользовательский стоп это окно закрывает (`disconnectClientBlocking`, затем
  `cancelCommandClientReconnect`, затем `cancelReconnect()`), поэтому сценарий требует
  неожиданного EOF командного клиента при живом runtime.

CONSEQUENCE: `HB-RW-005` получает обязательный пункт 5; `HB-RW-007` разблокирована.Диагностический `CommandClient` и снимок ядра перестают быть условием готовности.

INSTRUMENTATION CLEANED: n/a.

### HB-EXP-E2

A — 2026-08-26 — составитель плана

CLASS: A. BRANCH SELECTED: **P1**.

EVIDENCE:

- `experimental/libbox/command_server.go:StartOrReloadService` делегирует в

  `daemon/started_service.go:StartOrReloadService`.- Там последовательно: `HC.ResetRuntimeTransportState()`; при реконфигурации —
  синхронный `oldInstance.Close()`; `newInstance(profileContent, options)`; затем
  `serviceAccess.Unlock()`; затем `instance.Start()`.- `box.go:Start()` и `box.start()` идут по стадиям `StartStateInitialize`,
  `StartStateStart`, `StartStatePostStart`, `StartStateStarted`.- `protocol/call/outbound.go:Start(StartStatePostStart)` выполняет `go o.startHandler()`
  и возвращает управление; `vkparasite.ConnectClient` вызывает `relay.Start()`,
  который запускает N горутин `initPath` и их не дожидается.- Вывод: `startOrReloadService` **возвращается до появления первой QUIC-линии**.
  Кандидаты на длительную блокировку: `oldInstance.Close()`, `newInstance` и стадия
  `StartStateStart` для inbound, то есть создание TUN через `openTun`.

CONSEQUENCE: `HB-RW-009` проектируется по ветке P1 — окно блокировки короткое, адлительное ожидание READY уже вне JNI-вызова. Дополнительно уточнён `HB-EXP-E2B`:`CloseService()` не блокируется локом во время `instance.Start()`, поэтому экспериментобязан проверить безопасность одновременных `Start()` и `Close()`.

INSTRUMENTATION CLEANED: n/a.

### HB-EXP-E4 — 2026-08-26 — составитель плана

CLASS: A. BRANCH SELECTED: **P1**, плюс дополнительная находка.

EVIDENCE:

- `HydraBoxDefaultNetworkMonitor.resolveBestNetwork` строит кандидатов из

  `connectivity.allNetworks` с фильтром `isBaseUsableNetwork`, который отбрасывает
  `TRANSPORT_VPN`; `isActive` вычисляется как `active == network`, где
  `active = connectivity.activeNetwork`.- Пока TUN активен, `activeNetwork` — сам VPN, а он отфильтрован. Значит
  `isActive == true` недостижим ни для одного кандидата в этот период.
- **Дополнительно:** `DefaultNetworkSelection.selectDefaultNetworkCandidate`
  **не читает** `isActive` вообще: он использует только `isValidated`,
  `hasUsableInterface`, `score` и `value`. Единственный потребитель семантики
  «активная сеть» — слагаемое `+40` в `networkScore` внутри монитора.- `DefaultNetworkSelectionTest` не содержит ни одного кейса, зависящего от `isActive`
  отдельно от `isValidated`.

CONSEQUENCE: `HB-RW-018` удаляет слагаемое `+40` **и** мёртвое поле`DefaultNetworkCandidate.isActive` вместе с его заполнением.

INSTRUMENTATION CLEANED: n/a.

### HB-EXP-E6 — 2026-08-26 — составитель плана

CLASS: A. BRANCH SELECTED: **P2**.

EVIDENCE:

- `experimental/libbox/command_types.go:RuntimeEvents` содержит `Sequence`, `Reset`,

  `Snapshot *RuntimeSnapshot` и приватный `events []*RuntimeEvent`.- `RuntimeSnapshot` содержит `SchemaVersion`, `Sequence`, `ObservedAt`, `Service`,
  `StartedAt`, `Status`, `ClashMode`, `groups`, `urlTests`. Transport health
  отсутствует.- `CommandClient` поддерживает команды `CommandLog`, `CommandStatus`, `CommandGroup`,
  `CommandClashMode`, `CommandConnections`, `CommandRuntimeEvents`; канала health
  среди них нет.- Добавление health в `RuntimeSnapshot` потребовало бы поднять
  `runtime.snapshot_schema_version`, который жёстко запинен в
  `CoreCapabilityContract.supportedProtocolIds` равенством двум. Это запрещено **R14**.

CONSEQUENCE: `HB-RW-020` сохраняет опрос health, но переносит его на`ScheduledExecutorService` и вооружает только в STARTING и RECOVERING. Задача`HC-RW-008` (push-канал health) **не создаётся**.

INSTRUMENTATION CLEANED: n/a.

### HB-EXP-E10 — 2026-08-26 — составитель плана

CLASS: A. BRANCH SELECTED: **P1, вариант A**.

EVIDENCE:

- `adapter.InterfaceUpdateListener.InterfaceUpdated()` не имеет параметров;

  `route/network.go:ResetNetwork()` вызывает его без контекста.- В репозитории **11** реализаций `InterfaceUpdated()`: `protocol/call`, `hysteria`,
  `hysteria2`, `naive`, `shadowsocks`, `ssh`, `sudoku`, `trojan`, `tuic`, `vless`,
  `vmess`. Расширение интерфейса затронуло бы их все, что превышает установленный в
  `HC-RW-004` порог из пяти реализаций.- `common/hydracore` уже является процессным реестром, который план расширяет
  (`runtime_transport.go`), поэтому размещение `SetNetworkGeneration` и
  `CurrentNetworkGeneration` там не создаёт нового механизма.- Функций `SetNetworkGeneration`, `CurrentNetworkGeneration`,
  `InterfaceUpdatedWithGeneration` в репозитории сейчас нет.

CONSEQUENCE: `HC-RW-004` реализует вариант A; вариант B запрещён.

INSTRUMENTATION CLEANED: n/a.

### HB-EXP-E12 — 2026-08-26 — составитель плана

CLASS: A. BRANCH SELECTED: **P2**.

EVIDENCE:

- `quic_relay.go:initPath` вызывает `r.dialPath(pathCtx, workerID)` и добавляет путь в

  `r.paths` через `addPath` **только после успеха**.- CAPTCHA возникает внутри `dialPath`, на шаге `Credentials(ctx, joinLink)`, далее
  `vk.TURNCredentialProvider.Fetch`, далее `solveVKCaptcha`, то есть **до** `addPath`.- `RebindNetwork()` итерируется по `r.paths` и закрывает только их. Путь в стадии
  CAPTCHA в `r.paths` отсутствует, его `pathCtx`, производный от `r.ctx`, не
  отменяется.- Следствие: CAPTCHA **переживает** смену сети, а `reconnectPath` параллельно
  дозванивается по новой сети. Более общий вывод: `RebindNetwork` не отменяет **ни
  один** in-flight dial, что независимо подтверждает необходимость per-generation
  `pathCtx` в `HC-RW-004`.

CONSEQUENCE: `HC-RW-006` сливается с `HC-RW-004` и выполняется в том же PR: отмена`generationCtx` становится механизмом, а `HC-RW-006` сводится к публикации`code=vk.captcha.cancelled` с `terminal=false` в момент отмены контекста.

INSTRUMENTATION CLEANED: n/a.

### HB-EXP-E2B — 2026-08-28 — Codex

CLASS: C (DEVICE RUNTIME). BRANCH SELECTED: **P2**.

EVIDENCE:

- Device: Samsung SM-S931B, Android 16. Fixture: `type=call`, `mode=vk_parasite`, `server=203.0.113.1` from androidTest resources. Cancellation was issued after 2000 ms from a separate thread.
- Run 1 reached `startOrReloadService`: return time **89 ms**; concurrent `closeService()` returned in **48 ms**, but cleanup reported `cleanupComplete=false`.
- Runs 2–5 did not reach `startOrReloadService` after the first concurrent close; therefore their return measurements are **not available**. The runtime remained in a stale state (`running=true`, absent command server, stale empty stops ignored). Five-run minimum/median/maximum is consequently n/a, not a valid P1 sample.
- No Go `panic`, `SIGSEGV`, or `SIGABRT` was observed. A Java `RemoteCallbackList.beginBroadcast()` crash occurred in `:core`; no TUN descriptor was left observable after the test process stopped.

CONSEQUENCE: a concurrent `closeService()` is unsafe for cancellation. `HB-RW-009` takes P2: cancellation only sets a nonblocking flag and enters STOPPING; resource release belongs to `CloseTask` with `CLOSE_DEADLINE`. `join` without a deadline remains forbidden.

INSTRUMENTATION CLEANED: yes.

### HB-EXP-E3 — 2026-08-30 — Codex

CLASS: C (DEVICE RUNTIME). BRANCH SELECTED: **P1** (решение тимлида по
недостижимости FAIL-сценария, не по прямому наблюдению).

EVIDENCE:

- Device: Samsung SM-S931B (`RFCY60344JL`), Android 16 (API 36); HydraBox `1.0.2`
  (versionCode 2105). Временная instrumentation: commit `73c5032` в `exp/e3`, APK из
  CI run `33300912447`.
- `VLESS`, runtime остановлен: `before_session_run` `1788079214321`,
  `monitor_require` `1788079214412`, `after_session_run` и `session_finally`
  `1788079214422` — **101 ms**; `monitor_stop` отсутствует.
- `Обход БС` (`vk_parasite`), runtime остановлен: `before_session_run`
  `1788079691281`, `monitor_require` `1788079691349`/`1396`, `after_session_run`
  `1788079692157`, `session_finally` `1788079692158` — **877 ms**; probe отменён на
  START с `reason=network_changed`, до STOP не дожил.
- `Обход БС` (`vk_parasite`), runtime работает: `before_session_run`
  `1788080652679`, `monitor_require` `1788080652738`, `after_session_run` и
  `session_finally` `1788080652747` — **68 ms** (кеш credentials), до STOP не дожил.
- `E3-blackhole` (VLESS, `203.0.113.1:443`), runtime остановлен:
  `before_session_run` `1788081076579`, `after_session_run` и `session_finally`
  `1788081076683` — **104 ms**; `monitor_require` и `monitor_stop` отсутствуют.
  Позднейший TCP timeout относится к уже запущенному runtime, не к standalone session.

CONSEQUENCE: ephemeral probe ни в одной доступной конфигурации не доживает до
`monitor stop`; при остановленном runtime standalone-сессия завершается примерно за
100 ms, а blackhole-вариант не вызывает `monitor.require()`; при работающем runtime
`vk_parasite` завершается за 68 ms из кеша credentials. Состояние «probe в полёте через
`monitor stop`» не удалось сконструировать VLESS, blackhole `203.0.113.1`,
`vk_parasite` при остановленном и при работающем runtime. Поэтому P1 выбран по
недостижимости FAIL-условия, а не по прямому наблюдению отсутствия обращений к монитору.

Для `HB-RW-022`: отмена ephemeral probe реализуется при STOP и при переходе
`STOPPED → STARTING`; подшаг ожидания отмены в `CloseTask` не вводится. Как независимая
дешёвая страховка `HydraBoxDefaultNetworkMonitor.require()` при `started == false`
возвращает ошибку, а не ждёт. Для `vk_parasite` URL-test методологически неверен:
он поднимает worker и расходует квоту VK control-plane; post-gate заявка на замер
доставки магического пакета уже зафиксирована.

ОТКЛОНЕНИЕ: `timeoutMillis=15000` вместо карточных 30000, потому что UI жёстко передаёт
`LatencyCoordinator.perOutboundTimeoutMillis`; изменение значения вне scope.

INSTRUMENTATION CLEANED: yes.

### HB-EXP-E5 — 2026-08-30 — Codex

CLASS: C (DEVICE RUNTIME). BRANCH SELECTED: **P1** (решение тимлида).

EVIDENCE:

- Device: Samsung SM-S931B (`RFCY60344JL`), Android 16 (API 36); HydraBox `1.0.2`
  (versionCode 2105), debug APK at `8d35c65` baseline. Уровень native-log временно
  переключался через UI на Debug и возвращён в Warning; raw logcat не сохранён в Git.
- Tag DNS-транспорта в native debug-логе отсутствует: строки имеют форму
  `dns: lookup` / `dns: exchanged`. `ExchangeContext` не несёт tag, а
  `HydraBoxLocalResolver` является `dns-local`; Android не может распределить эти
  события между `dns-remote`, `dns-direct` и `dns-local`.
- Статически `lib/singbox/singbox_config_builder.dart:311` задаёт
  `dnsFinal = hasProxies ? 'dns-remote' : 'dns-direct'`; `dns-remote` создаётся
  в строках 325–328 с detour выбранного proxy. Следовательно DNS-запросы до READY,
  не пойманные более специфичным правилом, направляются в ещё неготовый proxy-detour
  по построению конфигурации.
- Эмпирически холодный старт дал ошибки классов `no available network interface` и
  timeout до READY; доменные имена, адреса и сырые строки не записывались.

CONSEQUENCE: `HB-RW-028` выполняется по P1, не отменяется. Выбор P1 против P1b
оставлен тимлиду: он зависит от необходимости реального reload при READY и решается
при реализации `HB-RW-028`.

INSTRUMENTATION CLEANED: n/a; `exp/e5` удалена, изменений кода и сборки не было.

### HB-EXP-E9 — 2026-08-30 — Codex

CLASS: C (DEVICE RUNTIME). BRANCH SELECTED: **P1**.

EVIDENCE:

- Device: Samsung SM-S931B (`RFCY60344JL`), Android 16; HydraBox `1.0.2`,
  instrumentation commits `a783f2c`, `15ac1bc`.
- Выборка сокращена с трёх устройств до одного по решению тимлида.
- 50 handover-ов Wi-Fi ↔ cellular: regex-срабатываний 0; health с
  `domain=NETWORK` 45; покрытых и непокрытых regex-срабатываний 0 / 0.
- 10 прогонов без сети для пакета (`cmd connectivity set-package-networking-enabled`):
  regex-срабатываний 0; health с `domain=NETWORK` 10; покрытых и непокрытых
  regex-срабатываний 0 / 0. Каждый прогон удерживал запрет 20 s.
- После handover-серии runtime оказался в FAILED с `runtime.transport.unhealthy`
  по пути failed start, а не с `runtime.recovery.exhausted` по R9.

CONSEQUENCE: P1 — `HB-RW-026` удаляет log-scraping целиком. В обоих сценариях
regex не сработал; непокрытых случаев нет.

INSTRUMENTATION CLEANED: yes. Фактический reassert возвращён через replay текущего
default interface всем зарегистрированным listener'ам. Raw-логи не коммитились.

### HB-EXP-E11 — 2026-08-28 — Codex

CLASS: C (DEVICE RUNTIME). BRANCH SELECTED: **P1**.

EVIDENCE:

- Device: Samsung SM-S931B, Android 16 (API 36), build `BP4A.251205.006.S931BXXSBCZG3`; HydraBox `1.0.2` (versionCode 2105), Wi-Fi `Keenetic-7157` (5.2 GHz).
- Smoke confirmed `HB1 ... START ep=<...> cg=<...> rg=<...> ng=<...> stage=network_wait result=ok elapsed_ms=11 attempt=0` from process `:core`.
- 20 cold Wi-Fi connections: every run used `adb shell am force-stop io.hydrabox.client` before launch and an explicit UI connection; all results were `result=ok`.
- Sample size is **20**, reduced from the card's 50 runs on three devices with team-lead approval. `elapsed_ms`: 10, 9, 9, 10, 10, 7, 12, 9, 15, 10, 11, 10, 12, 24, 13, 12, 11, 11, 11, 12.
- Median **11 ms**; P95 **15 ms** (nearest-rank, n=20); maximum **24 ms**; retry rate **0/20 (0%)** (`attempt > 0`: 0).

CONSEQUENCE: P95 is materially below 3000 ms, so `HB-RW-005` takes P1: `START_DEADLINE = 45 s` is accepted unchanged and includes `network_wait`. No cellular extension is required by the E11 decision rule.

INSTRUMENTATION CLEANED: n/a (permanent instrumentation).

## 8.2 Ожидающие записи

| EXP | Класс | Статус записи | Разблокирует |
|---|---|---|---|
| HB-EXP-E2B | C | **RESOLVED — P2** | HB-RW-009, HB-RW-010 |
| HB-EXP-E3 | C | **RESOLVED — P1** | HB-RW-022 |
| HB-EXP-E5 | C | **RESOLVED — P1** | HB-RW-028 |
| HB-EXP-E7 | C | **ожидается** | HB-RW-025 |
| HB-EXP-E8 | C | **ожидается** | post-gate решение о heartbeat |
| HB-EXP-E9 | C | **RESOLVED — P1** | HB-RW-026 |
| HB-EXP-E11 | C | **RESOLVED — P1** | HB-RW-005 |

Класс A (E1, E2A, E4, E6, E10, E12) закрыт — см. §8.
1. Осталось семь записей, всекласса C.

## 8.3 Прочие записи, обязательные к внесению

| Что | Кем | Когда |
|---|---|---|
| Совпадение словарей safe error codes между Kotlin и Go | `HC-RW-001` | при мерже |
| Выбор P1 либо P1b для DNS-правила | `HB-RW-028` | при мерже |
| Класс DNS-запроса, если `bootstrap` и `app` не различимы | `HB-RW-027` | при мерже |
| Ограничение «единый `Terminal=true` для CAPTCHA», если причина отмены неразличима | `HC-RW-006` | при мерже |
| Результаты G1..G14 | GATE §W | перед возвратом к оптимизациям |

---

# ФИНАЛЬНЫЕ БЛОКИ

## 1. INTERNAL CONTRADICTIONS FOUND AND RESOLVED

#

| Противоречие в `HYDRABOX_RUNTIME_REWORK_PLAN.md` | Разрешение |
|---|---|---|
| C1 | Phase 3 требовала ждать READY на single-thread `commandExecutor`, что снова сделало бы STOP недоступным во время старта — та же патология, что чинится | Serializer сериализует только переходы состояний; ожидания вынесены в `LaunchTask` и `CloseTask`, дедлайны — таймеры, публикующие внутренние события. Инвариант **R3**, задачи `HB-RW-008`, `HB-RW-009` |
| C2 | **Новая находка:** `emit()` вызывается из `commandExecutor` и из `mainHandler`, что может дать `IllegalStateException` в `RemoteCallbackList.beginBroadcast`; `state` пишется из трёх путей, а `refreshFromController` перезаписывает STARTING на RUNNING минуя readiness | Все записи состояния и все `emit` — только на потоке serializer; `registerListener` публикует `Event.Replay`. Инварианты **R1**, **R12**, задача `HB-RW-008` |
| C3 | `runtimeGeneration` определялась как «+1 при успешном создании runtime», но таблица переходов инкрементировала её при приёме START, а §K.3 использовала её как признак вытеснения команды | Пять величин, пять семантик (§2.4): `commandGeneration` — на приём команды, `runtimeGeneration` — только на `LAUNCHED`. Инвариант **R6**, задача `HB-RW-030` |
| C4 | Phase 1 переводила Dart на чтение `state`, но polling `_syncRuntimeState` жил до Phase 9: два writer-а фазы UI по разным правилам | Удаление polling перенесено в `HB-RW-007`, в тот же PR, что и удаление watchdog. Инварианты **R2**, **R11** |
| C5 | Phase 4 требовала `RuntimeSession`, появляющийся только в Phase 3, но prerequisite указывал Phase 1 | Phase 4 разделена: `HB-RW-012`/`HB-RW-013` зависят от Phase 1, sticky-restart вынесен в `HB-RW-012B` с зависимостью от `HB-RW-009` |
| C6 | Два владельца `selectedOutbounds`: команда и событие ядра, порядок не определён | Ядро authoritative, команда пишет `pendingSelection`. Инвариант **R13**, задача `HB-RW-035` |
| C7 | **Новая находка:** `CoreRuntimeClient.onBindingDied` безусловно вызывает `connect()`, а `CoreRuntimeService.onCreate` перебрасывает исключение — неограниченный цикл bind → crash → bind | Ограниченный rebind: три попытки, затем `runtime.ipc.unavailable` с причиной из `CoreStartupFailureStore`. Инвариант **R9**, задача `HB-RW-016` |
| C8 | Четырнадцать автоматических retry-механизмов без единого владельца домена | Нормативная таблица владельцев (§2.6) плюс перечень судьбы каждого механизма. Инварианты **R5**, **R9** |
| C9 | `wantRunning` определялся как «желание пользователя», сохранялся после retryable FAILED и запускал runtime после смерти процесса — это и есть запрещённый сценарий из постановки | `wantRunning` переопределён как разрешение на автовосстановление; любой FAILED его снимает; отдельный `autoRecoverAllowed` запрещён инвариантом; добавлен `recoveryAttempt <= 2` против бесконечного воскрешения через START_STICKY. Инварианты **R7**, **R8**, **R9** |
| C10 | Phase 6 (Android) требовала Go-изменений, но шла до Phase 7, при этом обе Go-задачи трогали один файл и один артефакт | Строгий линейный порядок `HC-RW-001..005`; удаление мёртвых полей перенесено в `HC-RW-004`; Android-задачи зависят от `HB-BUNDLE-*`, а не от «Phase N» |
| C11 | Ни одна фаза не содержала шага «обновить submodule и артефакт», без которого изменения ядра не наблюдаются | Введён тип задачи `HB-BUNDLE-<n>` с явными verify-командами |
| C12 | §M.1 предлагала `schema_version: 3`, но `TransportHealthBridge.parse` требует строгого равенства 2, а `CoreCapabilityContract` и `verify_extended_core.py` пинуют версию 2 | Версии не повышаются; все расширения аддитивны внутри `schema_version: 2`. Инвариант **R14** |
| C13 | Итоговая таблица аудита не отражала блокировки E1, E3, E9, E10, E11, E12 | Нормативная матрица §3.0 плюс поле `STATUS` в каждой задаче; таблица §7 сгенерирована из матрицы |
| C14 | `interfaceIndex == -1` при живой сети публиковался в ядро как «сети нет» и приостанавливал runtime | Выделено в раннюю независимую задачу `HB-RW-019` |
| C15 | `PREPARING` и `RECOVERING` не были разграничены по необходимости | `PREPARING` не выставляется (значение enum остаётся deprecated), `RECOVERING` сохранён с обоснованием |
| C16 | Не был перечислён список промежуточных окон с двумя источниками истины | Полный список с указанием допустимой длительности и закрывающей задачи |
| C17 | **Решение владельца:** сменяемое ядро внутри приложения — избыточный debug-эксперимент, при этом подсистема добавляла файловый I/O в инициализацию `:core` и в точку достижения READY | Удаление тремя задачами `HB-RW-040..042`; `HydraNativeLoader`, `CoreBundleSignatureVerifier`, `CoreCapabilityContract`, `CoreStartupFailureStore` сохранены с обоснованием; правка двух мест в `verify_client_boundaries.py` — единственное разрешённое исключение из правила 11 |

Дополнительно устранены как дефекты, а не как обходные пути: перезапись `lastError`probe-ошибкой до проверки префикса стадии (`HB-RW-021`); утечка`managedProbeAliases` (`HB-RW-023`); мёртвые поля `rebindMu` и `rebindCancel`(`HC-RW-004`); `SingboxController.lastRuntimeError`, единственный читатель которогонаходится в другом процессе (`HB-RW-029`); блокировка binder-потока на 10 s в`lookupOutboundExternalInfo` (`HB-RW-034`).

## 2. UNRESOLVED BLOCKERS

Изначально было тринадцать. **Шесть закрыто** при составлении документа: все
эксперименты класса A выполнены статическим анализом, evidence записан в §8.1, а
выбранные ветки вписаны прямо в `IMPLEMENTATION` соответствующих задач. Осталось
**семь**, все класса C — все требуют устройства. Каждый имеет обе ветки, поэтому ни
одна задача не содержит формулировки «агент решает».

**                                         

Закрыто (класс A):**

| EXP | Ответ | Что это изменило в плане |
|---|---|---|
| `HB-EXP-E1` | **P2**: путь `beginConnect → null` при непустом `reconnectPendingEpoch` достижим и уничтожает здоровый runtime | `HB-RW-005` получил обязательный пункт: отказ диагностического клиента и снимка ядра больше не откатывает старт |
| `HB-EXP-E2A` | **P1**: `startOrReloadService` возвращается до появления первой QUIC-линии; блокировка возможна в `oldInstance.Close()`, `newInstance` и `openTun` | `HB-RW-009` реализует отмену через `closeService()` плюс `join(CLOSE_DEADLINE)`; `HB-EXP-E2B` дополнен проверкой одновременных `Start()` и `Close()` |
| `HB-EXP-E4` | **P1** плюс находка: `isActive` недостижим при активном TUN, а поле `DefaultNetworkCandidate.isActive` вообще не читается | `HB-RW-018` удаляет и слагаемое `+40`, и мёртвое поле |
| `HB-EXP-E6` | **P2**: push-канала для health нет, добавление потребовало бы поднять `snapshot_schema_version` | `HB-RW-020` сохраняет опрос, вооружая его только в STARTING и RECOVERING; задача `HC-RW-008` не создаётся |
| `HB-EXP-E10` | **P1, вариант A**: 11 реализаций `InterfaceUpdated()`, поэтому расширение интерфейса запрещено | `HC-RW-004` использует `SetNetworkGeneration` и `CurrentNetworkGeneration` в `common/hydracore` плюс аддитивный libbox-экспорт |
| `HB-EXP-E12` | **P2**: CAPTCHA переживает смену сети, потому что dialing-путь ещё не в `r.paths`; `RebindNetwork` не отменяет ни один in-flight dial | `HC-RW-006` сливается с `HC-RW-004`: механизмом становится отмена `generationCtx` |**Осталось (класс C — нужен Android-девайс):**| EXP | Вопрос | Что выбирает результат |
|---|---|---|
| `HB-EXP-E2B` | прерывает ли `closeService()` висящий `startOrReloadService` и безопасны ли одновременные `Start()` и `Close()` | отменяемый старт на Android либо дедлайн внутри ядра (`HC-RW-007`) |
| `HB-EXP-E3` | переживает ли ephemeral probe остановку runtime | нужен ли `CloseTask` подшаг ожидания отмены probe |
| `HB-EXP-E5` | попадают ли DNS-запросы в `dns-remote` до READY | реализуется `HB-RW-028` или отменяется целиком |
| `HB-EXP-E7` | снимается ли пауза libbox без `server.wake()` | удаляется `requestRuntimeRecovery` целиком или сужается до одного триггера |
| `HB-EXP-E8` | сколько раз heartbeat находит то, чего не дал callback | post-gate решение об удалении heartbeat |
| `HB-EXP-E9` | совпадают ли regex-срабатывания с `failureDomain=NETWORK` | удаляется лог-скрапинг или меняет действие |
| `HB-EXP-E11` | фактическая длительность стадии `network_wait` | нужен ли отдельный внутренний предел стадии |

**Известные ограничения, не являющиеся блокерами, но требующие записи в §8.3 приреализации:** различимость `bootstrap` и `app` DNS-запросов (`HB-RW-027`);различимость причины отмены CAPTCHA (`HC-RW-006`); выбор P1 либо P1b для DNS-правила (`HB-RW-028`).

**Проверено и снято как вопрос:** в `scripts/tests` нет теста, пинующего
`required_process_bindings`, поэтому `HB-RW-041` не требует правок тестов скриптов;
имена файлов локализации (`lib/l10n/app_en.arb`, `lib/l10n/app_ru.arb`) и полный
список 22 ключей `coreManager*` перечислены в `HB-RW-042` явно.

**Ни один блокер не требует атомарного merge двух репозиториев** — это обеспечено
аддитивностью (**R14**), совместимостью `RebindNetwork(0)` и защищёнными вызовами
новых libbox-экспортов.

## 3. FIRST READY TASK

```
HB-RW-001 — Структурированные события HB1 и словарь safe error codes
STATUS:     READY
REPOSITORY: hydrabox
BASELINE:   6c4bf26045583bbc996b2f218c56f000a1bd49a4
PR SIZE:    S
RISK:       низкий (только добавление API, ни одного изменения поведения)
INVARIANT:  R18
```
Полный текст задачи — §4, первая карточка. Обоснование выбора: она не имеет
предусловий, не меняет поведения, и без неё нельзя валидировать ни одну последующую
задачу — все `EXPECTED STRUCTURED LOG` и `DEFINITION OF DONE` остальных задач
ссылаются на формат `HB1`.

Параллельно: второму исполнителю — `HB-RW-016` либо `HB-RW-019` (обе становятся
`READY` сразу после `HB-RW-002`, обе независимы, обе закрывают доказанные дефекты
корректности). При наличии устройства — `HB-EXP-E2B`, снимающий блокировку с самой
рискованной задачи плана (`HB-RW-009`, риск XH).

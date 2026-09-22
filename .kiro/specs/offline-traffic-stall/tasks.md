# Tasks: оффлайн-проба вешает трафик

**Bugfix:** `bugfix.md`
**Status:** planned — root cause не подтверждён устройством
**Executor:** deepseek v4.1 flash high (`opencode-go/deepseek-v4.1-flash`) для кода;
диагностика на устройстве — владелец

## Progress

| Task | Status | Evidence |
| --- | --- | --- |
| TSK-301 — диагностический журнал rebind/underlying | ✅ Готово | `:platform:android:compileDebugKotlin` SUCCESSFUL |
| TSK-302 — H4: rebind не привязывает к мёртвому интерфейсу | ✅ Готово (проверка на устройстве) | компиляция зелёная; эффект — TSK-305 |
| TSK-303 — H1: baseline vs реальный handover | ✅ Готово (рефактор + тест) | `MeasurementBaselineTest` PASS |
| TSK-304 — регрессионный тест reducer/сервис | ✅ Готово | `:core:runtime:allTests` + `:platform:android:testDebugUnitTest` SUCCESSFUL |
| TSK-305 — воспроизведение на устройстве (владелец) | pending | — |

## Dependency graph

```text
TSK-301 → TSK-305 (диагностика подтверждает гипотезу)
TSK-302 + TSK-303 → TSK-304
TSK-305 → приёмка фикса
```

Порядок: сначала диагностика (301) и защитные фиксы с тестом (302–304) — они провабельны
кодом. Финальная приёмка — после воспроизведения на устройстве (305).

## Tasks

- [x] **TSK-301 — Диагностический журнал перехода**
  - **Hypothesis:** H4, H1, H3
  - **Files:** `platform/android/.../HydraVpnService.kt` (rebind, onChanged, measureNow,
    startCore).
  - **Deliverables:** в `rebind()` логировать generation и `currentNetwork` (null/объект);
    в `onChanged` — распознан ли callback как baseline или как handover; в `measureNow` —
    generation старта замера и ждём ли uplink; в `startCore` — generation и сеть, на которой
    поднимается туннель. Уровень `info`, зона `network`. Поведение не менялось.
  - **Факт:** `:platform:android:compileDebugKotlin` — BUILD SUCCESSFUL. AAR оказался
    гидрирован локально (`platform/android/libs/libbox.aar`), так что модуль собирается
    и на этой машине, вопреки более ранней заметке спеки.

- [x] **TSK-302 — H4: rebind не привязывает туннель к мёртвому интерфейсу**
  - **Hypothesis:** H4 (основная — баг на обычных конфигах)
  - **Files:** `platform/android/.../HydraVpnService.kt` (`rebind`).
  - **Deliverables:** при `monitor.currentNetwork == null` — НЕ звать `setUnderlyingNetworks`
    (null означает «системная сеть по умолчанию», а при отсутствии uplink это сам туннель или
    ничего — известная петля VPN). Порядок rebind сохранён: binding → generation → publish.
    Generation в ядре всё равно продвигается, publish остаётся no-op при null.
  - **Факт:** компиляция зелёная. Поведенческий эффект — только на устройстве (TSK-305).
  - **Граница:** намеренный порядок rebind не менялся; пропущено только обнуление underlying.

- [x] **TSK-303 — H1: различить baseline и реальный handover**
  - **Hypothesis:** H1
  - **Files:** `platform/android/.../HydraVpnService.kt` (поле + onChanged + measureNow),
    новый `platform/android/.../MeasurementBaseline.kt`.
  - **Deliverables:** булев `awaitingMeasurementBaseline` заменён на
    `awaitingMeasurementBaselineGeneration` (AtomicLong; `-1` = нет baseline) +
    вынесенная чистая `isOfflineMeasurementBaseline(callbackGeneration, baselineGeneration)`.
    Baseline — первый callback новее generation, с которой стартовал замер; всё после —
    handover.
  - **Факт:** `MeasurementBaselineTest` — 4/4 PASS; компиляция зелёная.
  - **Честно (doubt-first):** при чтении кода выяснилось, что булев флаг был ФУНКЦИОНАЛЬНО
    КОРРЕКТЕН: `NetworkChanged` уходит в reducer ВСЕГДА (независимо от флага), поэтому
    handover доходит до rebind в любом случае, а сам проход дополнительно защищён
    `EdgeSweep.stillCurrent`/`OfflineSweep.networkStillCurrent`. То есть посылка H1
    («handover съеден и не доходит до rebind») — неверна. Это изменение — приведение к
    generation-виду, тестируемость и явность, а НЕ доказанный фикс. Поведение эквивалентно.

- [x] **TSK-304 — Регрессионный тест**
  - **Hypothesis:** H4 + H1
  - **Files:** `core/runtime/src/commonTest/.../NetworkChangeTest.kt` (добавлен кейс),
    `platform/android/src/test/.../MeasurementBaselineTest.kt` (новый).
  - **Deliverables:** reducer-кейс «изменение, увиденное при остановленном замере, не
    запоминается, поэтому изменение под работающим туннелем всё ещё ребиндит»; платформенный
    тест на различение baseline/handover.
  - **Факт:** `:core:runtime:allTests` BUILD SUCCESSFUL (jvmTest + android unit);
    `:platform:android:testDebugUnitTest` BUILD SUCCESSFUL (весь набор, не только новый тест).
  - **Честно (граница red-first):** reducer-кейс — характеризующий (зелёный и до правок),
    потому что фактический фикс (TSK-302) живёт в сервисе и на reducer не выражается.
    Настоящий red-first для сервисного гарда требует устройства/интеграции — вынесено
    в TSK-305.

- [ ] **TSK-305 — Воспроизведение на устройстве (владелец)**
  - **Hypothesis:** подтверждение root cause
  - **Deliverables:** на обычном конфиге (vless/trojan): airplane ON → «Измерить»/подключение
    → airplane OFF; снять журнал `network` (TSK-301); подтвердить, какая гипотеза реальна;
    после фикса — серия OFF→ON→OFF без залипания трафика.
  - **Acceptance:** зафиксированная в журнале причина; трафик восстанавливается сам без
    ручного рестарта, N повторов без залипания.
  - **Граница:** делает владелец на устройстве — агент не имеет доступа к телефону.

## Findings (по коду, 2026-09-21)

- **H1 — опровергнута как причина остановки трафика.** `monitor.onChanged` ВСЕГДА зовёт
  `runtime.submit(NetworkChanged)` независимо от baseline-флага (`HydraVpnService.kt:415-428`),
  а reducer для RUNNING всегда даёт `RebindNetwork` (`RuntimeReducer.kt:305-311`). Значит
  handover не может быть «съеден» до потери rebind — флаг влияет только на `cancelSweep`
  (отмену замера), а сам проход ещё и самозащищён `stillCurrent`.
- **Наиболее вероятный транспорт-независимый кандидат (H4):** асимметрия путей при смене
  сети во время старта. `NetworkChanged` в STARTING/RECOVERING даёт только `PublishNetwork`
  (публикует интерфейс, но НЕ трогает underlying) — `RuntimeReducer.kt:308-310`,
  `NetworkChangeTest` так и документирует («a starting tunnel is only told where to dial»).
  `startCore` же выставляет underlying один раз, из `monitor.currentNetwork`, который в
  оффлайне == null (`HydraVpnService.kt`). Окно: туннель поднят оффлайн → сеть появляется
  между `setUnderlyingNetworks` в `startCore` и переходом в RUNNING → `PublishNetwork`
  не поправит underlying → туннель RUNNING без рабочего underlying. Узкое и
  «плавающее» — совпадает с «подключение в оффлайне» и с плавающим характером бага.
- **Не менял намеренный контракт reducer:** STARTING→`PublishNetwork` — осознанное решение
  (зеркало 1.x), трогать без подтверждения журналом нельзя. Вместо этого — диагностика
  (TSK-301) и защитный гард rebind (TSK-302). Если журнал подтвердит окно STARTING,
  следующий шаг — расширить обработку `PublishNetwork` в сервисе (ставить underlying), не
  ломая reducer.

## Completion criteria

- Причина остановки трафика зафиксирована журналом на обычном конфиге.
- rebind не оставляет туннель на мёртвом интерфейсе; baseline не съедает реальный handover.
- Регрессионный тест доказывает фикс; изоляция OfflineSweep и порядок rebind не нарушены.
- Владелец подтвердил на устройстве: OFF→ON→OFF без залипания.

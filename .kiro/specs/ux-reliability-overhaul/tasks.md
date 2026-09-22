# Tasks: устойчивость и ясность UX

**Status:** Planned — ждёт утверждения Tasks phase
**Requirements:** `requirements.md`
**Design:** `design.md` (approved)

## Dependency graph

```text
TSK-001 ping isolation ──────────┐
TSK-002 readable server row ─────┤
TSK-003 subscription UI cleanup ─┼─> TSK-008 QA / device validation
TSK-004 subscription edit/meta ──┤
TSK-005 explicit update download ┤
TSK-006 three appearance schemes ┤
TSK-007 launcher icon ───────────┤
TSK-009 Home route clarity ───────┤
TSK-010 repeat-connect guard ─────┤
TSK-011 subscription flags ───────┘
```

## Progress

| Task | Status | Evidence |
| --- | --- | --- |
| TSK-001 — State изоляция ping | ✅ Готово | `OfflineSweepTest` 8/8 PASS; RED-проверка: без изоляции падает именно isolation-тест |
| TSK-002 — Строка сервера | ✅ Готово | `ServerRowRenderTest` 2/2 PASS; RED-проверка: старая раскладка даёт 5203 изменённых пикселя внутри имени |
| TSK-003 — Чистка UI подписок | ✅ Готово | `:ui:app:jvmTest` PASS (RussianCopyTest: мёртвых строк нет); сборка PASS |
| TSK-004 — Правка ссылки и идентификаторы | ✅ Готово | `SubscriptionEditTest` 6/6, `SubscriptionIdentifiersTest` 4/4; `ciCheck` BUILD SUCCESSFUL |
| TSK-006 — Три схемы оформления | ✅ Готово | `SettingsAppearanceMigrationTest` 4/4; `ApertureRenderTest` PASS на новой палитре; `ciCheck` BUILD SUCCESSFUL |
| TSK-007 — Иконка Flow | ✅ Готово | 5 плотностей, логотип 62% канвы, foreground 78% прозрачен; canary APK `2.0.0-canary.3` собран, все launcher-записи в ресурсах |
| TSK-009 — Ясный маршрут Home | ✅ Готово | `ScreenProjectionTest` 23/23; краснота доказана: с `resolvedLabel = tag` падают оба новых теста |
| TSK-010 — Guard быстрых connect | ✅ Готово | `HomeActionTest` 4/4; краснота доказана: со старым условием падает тест четырёх тапов (`disconnects` = 3) |
| TSK-011 — Флаг в leading slot | ✅ Готово | `ServerFlagTest` 2/2; UI на девайсе — в TSK-008 |
| TSK-012 — Падение ядра (пустой батч) | ✅ Готово | Тест красный→зелёный на той же панике; релиз ядра `debug-3` запушен |
| TSK-008 — QA на устройстве | ✅ Готово | Проверено на `SM-S931B`: маршрут, флаги, «О программе», темы, замер, 4 быстрых подключения; результат подтверждён владельцем |
| TSK-005 — Проверка и загрузка обновления | ✅ Готово | `UpdateSummaryTest` 6/6 PASS; `startDownload` имеет ровно один вызов — в `onDownloadUpdate` |

## Tasks

- [x] **TSK-001 — Изолировать результаты offline ping**
  - **Requirement:** R1
  - **Files:** `platform/android/.../OfflineSweep.kt`, `HydraVpnService.kt`, `OfflineSweepTest.kt`.
  - **Deliverables:** RED-тест переходов A/B/C в `checking`; timeout/connection error/exception B меняет только B на «не отвечает»; A и C независимо публикуют RTT; убрать sweep-wide deadline, сохранить individual timeout и guards нового ping/Stop/смены сети.
  - **Acceptance:** старт не превращает ни одну строку в «не отвечает»; в последовательности `A RTT → B timeout → C RTT` меняется только закончившийся tag; выбранная concurrency не влияет на этот контракт; существующие URL-test и TURN-edge различимы.
  - **Decision:** `.kiro/decisions/0021-failure-isolation-over-sweep-speed.md` (уточняет 0017).
  - **Факт:** 2026-09-19 — `./gradlew :platform:android:testDebugUnitTest --tests OfflineSweepTest` → 8 tests, 0 failures. Краснота доказана: с временно убранным `runCatching` падает `a server whose measurement throws is that server's outcome alone`. Общий бюджет (`withinDeadline`/`reportSkipped`) удалён вместе с проводкой в сервисе; progress сообщает набор открытых вопросов; `latencyLabel` показывает «проверяю…» для строк в наборе.
  - **Граница:** на устройстве не проверялось (нужен тест на телефоне): проверено правилами и тестами sweep, не UI на девайсе.

- [x] **TSK-002 — Разнести имя сервера и диагностику по строкам**
  - **Requirement:** R2
  - **Files:** `ui/app/.../ServersScreen.kt`, `ui/app/.../HomeScreen.kt`, `ui/app/.../Strings.kt`, `ui/design/.../Controls.kt`, `ui/design/src/jvmTest/.../ServerRowRenderTest.kt`.
  - **Deliverables:** title остаётся названием, `latencyLabel` становится supporting line; trailing slot содержит только progress/selection; добавить проверку длинных name + stale/RTT.
  - **Acceptance:** `«устарело»` и RTT не могут перекрыть имя ни в выбранной, ни в измеряемой строке.
  - **Факт:** 2026-09-19 — `ServerRowRenderTest` 2/2 PASS (диагностика не меняет ни одного пикселя внутри прямоугольника имени). Краснота доказана: с диагностикой в trailing-слоте тест падает — 5203 изменённых пикселя внутри имени (`x=121,y=53,512×31`). Параметр `latency` у `ServerRow` удалён: единственные два вызова передавали бы `null`.

- [x] **TSK-003 — Убрать лишние состояния и controls подписок**
  - **Requirement:** R4, R5.1, R5.4, R5.5
  - **Files:** `ui/app/.../SourcesScreen.kt`, `OnboardingFlow.kt`, `AppActions.kt`, `platform/android/.../RuntimeControlActivity.kt`, UI strings.
  - **Deliverables:** удалить верхний `LoadingRows(1)`, file-import button/action/launcher/handler и мёртвые ресурсы; убрать shield; форматировать protocol count как `PROTOCOL ×N`.
  - **Acceptance:** обновление не рисует фантомный контейнер; файл нельзя импортировать ни одним UI-путём; shield отсутствует; два VLESS отображаются как `VLESS ×2`.
  - **Факт:** 2026-09-19 — `./gradlew :ui:app:jvmTest :platform:android:testDebugUnitTest` PASS, включая `RussianCopyTest`, который падает на любой строке без потребителя: `sources_add_file`, `sources_encrypted` и `MAX_SOURCE_BYTES` удалены, подсказка больше не обещает файл, `LoadingRows` ушёл из `SourcesScreen`.
  - **Граница:** формат `×N` не покрыт тестом (одна строка форматирования) — проверен глазами на компиляции; UI на девайсе не смотрели.

- [x] **TSK-004 — Сделать безопасное редактирование ссылки и метаданные**
  - **Requirement:** R5.2, R5.3
  - **Files:** `core/projection/.../ScreenState.kt`, `ui/app/.../SourcesScreen.kt`, `AppActions.kt`, `platform/android/.../RuntimeControlActivity.kt`, `AppStore.kt`, `HydraDeviceIdentity.kt`, `SubscriptionEdit.kt`, тесты.
  - **Deliverables:** `SubscriptionIdentifier` + allow-list non-secret fields; detail UI; edit dialog with name+URL; `onEditSource`; fetch/parse-before-commit и atomic migration по новому `SubscriptionId`.
  - **Acceptance:** source IDs вроде HWID показываются только при наличии и не раскрывают secrets; успешная смена URL сохраняет name/enabled; invalid/unreachable URL не меняет старую подписку.
  - **Decision:** `.kiro/decisions/0019-atomic-subscription-url-replacement.md`.
  - **Факт:** 2026-09-19 — `ciCheck` BUILD SUCCESSFUL (unit-тесты, Android lint, kmp). `SubscriptionEditTest` 6/6 — включая отказ (`TAKEN`), когда адрес уже занят другой подпиской; `SubscriptionIdentifiersTest` 4/4 — источник без идентификатора не показывает ничего, невыводимое значение не выдумывается. Порядок в `moveSubscription`: `retrieve` + `parseCatalog` + `inspect` до транзакции, затем одна транзакция (сохранение нового id, перенос name/enabled, удаление старого id), выбор сервера перепривязывается по `(source, originalTag)`.
  - **Границы:** сама транзакция БД тестом не покрыта — у `AppStore` нет тестового харнесса (нужен Context + SQLDelight + codec), так что атомарность доказана структурой кода и правилом-решением, а не прогоном. Случай «адрес занят» показывает общий отказ, точная причина — в журнале (`SourceFailure.UNKNOWN` + detail). HWID на девайсе не смотрели.

- [x] **TSK-005 — Разделить проверку и загрузку обновления**
  - **Requirement:** R3
  - **Files:** `ui/app/.../AppActions.kt`, `SettingsScreen.kt`, `platform/android/.../RuntimeControlActivity.kt`, `core/projection/.../ScreenState.kt`, `core/projection/src/commonTest/.../UpdateSummaryTest.kt`, strings.
  - **Deliverables:** `onCheckUpdate` только проверяет manifest; `onDownloadUpdate` явно запускает `DownloadManager`; UI показывает отдельную кнопку «Скачать» и существующие download/install states.
  - **Acceptance:** check никогда не создаёт download id; download начинается только после tap; SHA-256 verification перед installer сохранена.
  - **Decision:** `.kiro/decisions/0018-explicit-update-download.md`.
  - **Факт:** 2026-09-19 — `./gradlew :core:projection:jvmTest :ui:app:jvmTest :platform:android:testDebugUnitTest` PASS. `UpdateSummaryTest` фиксирует правило: найденный релиз → `DOWNLOAD`, скачанный → `INSTALL`, идущая загрузка/проверка/установка → `NONE`. `rg 'startDownload' platform ui` — ровно один вызов, в `onDownloadUpdate` (`RuntimeControlActivity.kt:1111`), то есть проверка физически не может начать загрузку.
  - **Граница:** проверка «check не создаёт download id» — кодом (единственный call site), а не тестом: путь лежит в Activity и требует устройства/инструментов. На девайсе не смотрели.

- [x] **TSK-006 — Заменить HydraBox theme тремя схемами**
  - **Requirement:** R6
  - **Files:** `core/settings/.../Settings.kt`, projection settings mapping/tests, `ui/app/.../DetailScreens.kt`, `HydraApp.kt`, `ui/design/.../UiTheme.kt`, `HydraColors.kt` (удалён), strings.
  - **Deliverables:** убрать UI и storage usage `dynamicColour`; system/light/dark как единственные варианты; neutral fixed palettes; backward-compatible decode/migration legacy settings.
  - **Acceptance:** тема HydraBox не предлагается; доступно ровно три схемы; старые записи настроек декодируются без crash.
  - **Decision:** `.kiro/decisions/0020-appearance-three-schemes.md`.
  - **Факт:** 2026-09-19 — `ciCheck` BUILD SUCCESSFUL (unit, Android lint, kmp). `SettingsAppearanceMigrationTest` 4/4: `dynamic_colour=1` при любом `theme_mode` → `SYSTEM`, флаг больше не пишется, round-trip стабилен. Брендовая палитра удалена файлом `HydraColors.kt` (проверено: ссылок не осталось), нейтральные схемы — стандартные Material `lightColorScheme()`/`darkColorScheme()`; `ApertureRenderTest` (сравнение кадров состояний) проходит на них, то есть «подключено» и «нет» по-прежнему рисуются различно. Секция «Цвет» и 5 строк выбора палитры убраны.
  - **Границы:** на телефоне внешний вид не смотрели (TSK-008); проверено рендер-тестом и сборкой, не глазами.

- [x] **TSK-007 — Внедрить Flow launcher icon**
  - **Requirement:** R7
  - **Files:** `platform/android/src/androidMain/res/mipmap-*/` (foreground, monochrome, legacy), adaptive XML не менялся.
  - **Deliverables:** сгенерировать density foreground с safe-zone из `C:\Users\user\Downloads\HydraBox_Flow_icon_1024.png`; заменить launcher/round/monochrome resources; удалить неиспользуемые прежние foreground assets.
  - **Acceptance:** resource build проходит; знак не обрезан в launcher/settings/installer на устройстве; notification status icon не изменён.
  - **Факт:** 2026-09-19 — генерация (PowerShell + System.Drawing, скрипт `.pi/tasks/make-icon.ps1`, исходник вне репозитория): логотип вырезан из белой плитки (near-white+unsaturated → прозрачность), посажен в центр канвы 108 dp с контентом 62% (как в проверенном ранее артворке, поля 19%). Измерено по сгенерированным PNG: `ic_launcher_foreground.png` 77–78% пикселей прозрачны (плитки нет), нарисовано 22%; `ic_launcher_monochrome.png` — та же альфа-маска, 100% нарисованных пикселей белые (система тонирует сама). Легаси `ic_launcher.png` — целый артворк по плотностям (48/72/96/144/192 px).
  - **Факт сборки:** `./gradlew :platform:android:assembleRelease` → BUILD SUCCESSFUL in 2m 11s; в собранном APK есть `ic_launcher`, `ic_launcher_background`, `ic_launcher_foreground`, `ic_launcher_monochrome`, `ic_launcher_round` (проверено по `resources.arsc`). `ic_hydrabox_status` не тронут — отдельная иконка шторки.
  - **Границы:** на устройстве не смотрели (TSK-008): проверено числами и глазами по сгенерированному foreground, но не установкой APK.

- [x] **TSK-009 — Сделать маршрут Home читаемым и пользовательским**
  - **Requirement:** R8, R10
  - **Files:** `ui/app/.../HomeScreen.kt`, `ui/app/.../Strings.kt`, `ui/design/.../Rows.kt`, `core/projection/.../ScreenProjection.kt`, `ScreenProjectionTest.kt`.
  - **Deliverables:** opt-in multi-line detail в `FactRow` (только route-строка); `resolvedName` разделён на `resolvedTag` (ключ для latency) и `resolvedLabel` (имя для человека).
  - **Acceptance:** Home не рисует обрезанное правило автовыбора; показывается имя сервера, а не raw tag; latency по-прежнему ищется по tag; неизвестный tag не выходит в UI.
  - **Факт:** 2026-09-19 — `:core:projection:jvmTest` + `:ui:app:jvmTest` + `:ui:design:jvmTest` PASS (`ScreenProjectionTest` 23/23); `ciCheck` exit=0. Краснота доказана поведенчески: с `resolvedLabel = tag` (старое поведение) падают `automatic selection names the server it landed on` и `an automatic choice the catalogue cannot name is not shown as its tag`. Тест ловит именно тот баг, что виден на телефоне: `anytls-gr33nimax` вместо `🇫🇮 AnyTLS`.
  - **Уточнение (2026-09-19, после проверки на телефоне):** попытка решить обрезку через две строки (`FactRow(detailMaxLines)`) не помогла: в колонке всё равно резалось. По решению владельца правило заменено коротким состоянием «Не выбрано» (`server_auto_none`), ресурс `server_auto_detail` удалён, `detailMaxLines` убран как ненужный; `ciCheck` exit=0. См. R8.
  - **Граница:** на устройстве не проверялось — входит в TSK-008; переименование `resolvedName` → `resolvedTag` механическое (6 мест), поведение latency lookup не менялось.

- [x] **TSK-010 — Заблокировать повторный connect во время перехода**
  - **Requirement:** R9
  - **Files:** `ui/app/.../HomeScreen.kt`, `HomeActionTest.kt`.
  - **Deliverables:** `apertureEnabled()` — aperture закрыт для `Connecting`/`Reconnecting`; secondary Cancel остаётся единственным выходом; regression-тест на четыре быстрых нажатия.
  - **Acceptance:** повторное нажатие во время старта не превращается в Stop; реальный failure по-прежнему retryable; когда Connected — aperture по-прежнему останавливает туннель.
  - **Факт:** 2026-09-19 — `HomeActionTest` 4/4 PASS. Краснота доказана поведенчески: со старым условием (`primaryAction != NONE`) тест четырёх тапов падает — `connects=1, disconnects=3`, то есть три лишних тапа гасили только что поднятый туннель; тот же прогон краснит матрицу состояний. Причина на устройстве: `Connecting.primaryAction == CANCEL`, поэтому та же кнопка отправляла `onDisconnect`.
  - **Граница:** на устройстве не проверялось — входит в TSK-008; сам `RuntimeReducer`/`prepareAndStart` не менялись: guard только в UI-точке входа.
  - **Важно (2026-09-19):** заявленный владельцем симптом «подключено → тут же отключено» этим фиксом НЕ закрыт — его причина найдена позже на устройстве: паника Go-ядра (`index out of range [0] with length 0` в WireGuard-сендере) роняла процесс `:core`. См. R9 «Корневая причина» и TSK-012.

- [x] **TSK-012 — Починить падение ядра на пустом WireGuard-батче**
  - **Requirement:** R9 (корневая причина), NFR «надёжность»
  - **Files:** `hydracore/forks/wireguard-go/conn/bind_std.go`, `conn/bind_std_test.go`, `release/HYDRACORE_VERSION`, `release/HYDRACORE_RELEASE_NOTES.md`.
  - **Deliverables:** не отдавать пустой батч платформенному writer'у; тест на этот случай; релиз ядра `hydracore-sbe-1.14.0-debug-3`.
  - **Acceptance:** пустой батч — no-op, а не abort; тест краснеет паникой до фикса и зеленеет после; процесс `:core` переживает подключение.
  - **Факт:** 2026-09-19 — тест `TestSendEmptyBatchIsNotAnError` до фикса: `panic: runtime error: index out of range [0] with length 0` (FAIL), после: PASS; весь сьют форка зелёный (`conn`, `device`); гейты ядра (`verify_release_notes`, `verify_release_version`, `verify_release_version_test`, `verify_upstream_baseline`) — OK; коммиты `762de10ef` + `d6666ff5b` в `gr33nimax/hydracore` на ветке `debug`.
  - **Граница:** тест живёт в модуле форка и не запускается из `go test ./...` самого ядра (replace-модуль) — то есть CI ядра его не гоняет; прогон локальный, `go test ./...` внутри `forks/wireguard-go`. На устройстве с новым AAR не проверялось (TSK-008).

- [x] **TSK-011 — Вынести флаг сервера в leading slot**
  - **Requirement:** R11
  - **Files:** `ui/app/.../ServersScreen.kt`, `ui/design/.../Rows.kt`, `ui/design/.../Controls.kt`, `ServerFlagTest.kt`.
  - **Deliverables:** `serverFlag()` распознаёт только ведущую пару regional indicators и отделяет её от имени; `HydraRow(leadingFlag)`/`ServerRow(flag)` рисуют флаг вместо generic glyph; fallback без флага не меняется.
  - **Acceptance:** `🇫🇮 AnyTLS` → флаг слева + `AnyTLS` в title; сервер без флага сохраняет `HydraIcons.Server`; латиница (`FI AnyTLS`) флагом не считается.
  - **Факт:** 2026-09-19 — `ServerFlagTest` 2/2 PASS (валидный флаг, имя без флага, пустое имя, «флаг без имени», латинские буквы); `ciCheck` exit=0.
  - **Граница:** краснота только компиляционная (функции не существовало), поведенческого red нет — честно. Render-тест на эмодзи не делал: на JVM эмодзи может рисоваться tofu-глифом, и тест доказывал бы не то. На девайсе не проверялось — входит в TSK-008.

- [ ] **TSK-008 — Прогнать QA и закрыть spec**
  - **Requirement:** R1–R11, NFR
  - **Files:** `requirements.md`, `tasks.md`.
  - **Deliverables:** запустить затронутые unit/UI tests, Android resource/build gate и ручные device scenarios; обновить status requirements и Progress с evidence; устранить любое красное до закрытия.
  - **Acceptance:** каждый requirement имеет PASS/evidence; UI остаётся отзывчивым при одном failed ping и при четырёх быстрых connect tap; auto route имеет полный критерий и человеческое имя; флаг не дублируется с generic icon; нет незакрытых known-red без владельца/даты.
  - **Факт (2026-09-19, устройство `SM-S931B`, canary.9 → canary.10):**
    - Маршрут без подключения: `Автовыбор` / `Не выбрано` (короткое состояние, без обрезки) — скриншот.
    - Маршрут подключённый: `🇫🇮 AnyTLS · 201 мс` и `🇫🇮 Hysteria2 · 139 мс` — человеческое имя, не `anytls-gr33nimax` (R10 на устройстве).
    - Список серверов: флаг в левом слоте вместо серых прямоугольников, имена без эмодзи (R11).
    - «О программе»: три ссылки с адресами (HydraBox / Hydra Ultimate / HydraCore) и подпись `by gr33nimax with l<3ve`; там же видна версия ядра `hydracore-sbe-1.14.0-debug-3`.
    - Темы: ровно три («Как в системе / Светлая / Тёмная»), светлая применяется целиком.
    - Замер: каждая строка получила свою цифру (139 / 202 / 207 / 225 мс), зависших «проверяю…» нет.
    - **Четыре быстрых подключения подряд: `Подключено`, процесс `:core` жив, в crash-буфере 0 строк `FATAL`/`SIGABRT`/`panic`, смертей процесса 0.** До фикса ядро падало здесь через ~120 мс.
    - Итог подтверждён владельцем на своём устройстве: «всё как нужно».
  - **Не проверено (честно):** проверка обновления с последующей загрузкой (мы на версии канала — предлагать нечего); иконка в самом лаунчере (проверена в ресурсах APK, не глазами в лаунчере); экраны подписок визуально в этом заходе не смотрели (покрыты тестами и кодом).

## Task checklist

- [x] Все требования R1–R7 трассированы.
- [x] Архитектурные решения связаны с принятыми ADR.
- [x] Тесты и device validation включены.
- [x] Задачи упорядочены по независимым вертикальным срезам.

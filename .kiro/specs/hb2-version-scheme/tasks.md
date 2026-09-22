# Tasks: чистая схема версии HydraBox 2.x

**Requirements:** `requirements.md` · **Design:** `design.md`
**Status:** planned
**Executor:** deepseek v4.1 flash high (`opencode-go/deepseek-v4.1-flash`)

## Progress

| Task | Status | Evidence |
| --- | --- | --- |
| TSK-201 — versionName = чистый semver | ✅ canary; ⏳ stable в worktree | `grep hydraboxVersion gradle.properties` → `2.1.0`; `build.gradle.kts:76` дефолт = `2.1.0`; stable-worktree: `C:/Users/user/AppData/Local/Temp/hb2-stable-wt` |
| TSK-202 — тег строится в workflow | ✅ canary; `stable` — см. Заметку | `bash -n` resolve-шага OK; счётчик проверен симуляцией кейсов A–F (2.0.0-canary.10 → 11; stable.3 → 4; v-тег перебивает старый) |
| TSK-203 — совместимость парсера/клиента | ✅ | `./gradlew :core:update:check` → BUILD SUCCESSFUL (lint+тесты); UpdateManifestTest 10/10, UpdateDecisionTest 7/7, 0 failures |

## Dependency graph

```text
TSK-201 → TSK-202 → TSK-203
```

## Tasks

- [x] **TSK-201 — versionName это чистый semver**
  - **Requirement:** R1, R3
  - **Files:** `gradle.properties` (ветки `canary` и `stable`),
    `platform/android/build.gradle.kts:76`.
  - **Deliverables:** `hydraboxVersionName=2.1.0` на обеих ветках (было `2.0.0-canary.10` /
    `2.0.0-stable.3`); дефолт в `build.gradle.kts` заменить `2.0.0-alpha1` → `2.1.0`;
    `versionCode` не трогать (canary 218, stable 210).
  - **Acceptance:** `assembleRelease` даёт APK с `versionName=2.1.0`; About/Runtime
    показывает `2.1.0`. versionCode строго > последнего опубликованного в канале
    (canary >217, stable >208).
  - **Факт:** canary — `gradle.properties` в рабочем дереве: `hydraboxVersionName=2.1.0`
    (code 218 не тронут); `build.gradle.kts:76` дефолт → `2.1.0`. stable — правка сделана в
    отдельном worktree (без переключения ветки и без порчи основного дерева):
    `C:/Users/user/AppData/Local/Temp/hb2-stable-wt`, `hydraboxVersionName=2.1.0` (code 210),
    изменение uncommitted. Сам `assembleRelease` локально не гонялся —
    `:platform:android` требует гидрированного libbox AAR, он есть только в CI
    (`verifyLibboxProvenance`). Проверка APK badging — в CI.

- [x] **TSK-202 — Тег и имена строятся в workflow, не из versionName**
  - **Requirement:** R2
  - **Depends on:** TSK-201
  - **Files:** `.github/workflows/android-release.yml`.
  - **Deliverables:** в шаге `Resolve the release version` вычислять
    `tag=v${name}-${channel}.${counter}` (counter — вход с дефолтом-инкрементом от
    последнего тега канала); прокинуть `tag` в `$GITHUB_OUTPUT`. Заменить использование
    `outputs.name` на `outputs.tag` там, где имелся в виду **тег**: `gh release create`,
    имя APK (`hydrabox-$TAG-arm64-v8a.apk`), `apkUrl` и `releaseTag` в манифесте. Оставить
    `name` (semver) в: `versionName` манифеста, verify APK badging.
  - **Acceptance:** dry-run на ветке `canary` даёт тег `v2.1.0-canary.<n>`, манифест с
    `versionName=2.1.0` и `releaseTag=v2.1.0-canary.<n>`; проверка «канал==ветка»
    (`Channel and branch disagree`) сохранена и срабатывает на рассинхроне.
  - **Факт:** canary — шаг переписан: канал берётся из ветки (`basename $GITHUB_REF`) с
    ранним отказом при рассинхроне канал/ветка (до сборки); новый вход `counter` с
    дефолтом-инкрементом от максимального тега `*-<channel>.<n>` через `gh release list`;
    добавляется `outputs.channel` и `outputs.tag`. `outputs.tag` использован в: имя APK
    (`Collect the artifacts`), имя upload-артефакта, `gh release view/upload/edit/create`,
    заголовок/тело релиза, манифесты `releaseTag` и `apkUrl`, сообщение коммита канала.
    `outputs.name` (semver) оставлен в: `Build the release APK` (`-PhydraboxVersionName`),
    `Verify the built APK` (badging compare), манифест `versionName`. Логика счётчика
    проверена изолированной симуляцией: A max 10→11, B stable .3→4, C `v2.1.0-canary.11`
    перебивает `2.0.0-canary.10`→12, D override 5→5, E пусто→1, F нечисло→ошибка.
    `bash -n` resolve-скрипта — OK, YAML валиден. Реальный dry-run даёт конкретный тег — в CI.
  - **Заметка (stable):** ветка `stable` отстаёт от canary в этом же файле (в ней нет
    более раннего фикса `--target "$GITHUB_SHA"`), поэтому правку TSK-202 туда НЕ копировал
    вслепую — это отдельное решение о промоушене (перенести workflow canary→stable целиком).
    Пока TSK-202 применён только на canary.

- [x] **TSK-203 — Совместимость парсера манифеста и клиента**
  - **Requirement:** R4
  - **Depends on:** TSK-202
  - **Files:** `core/update/src/commonMain/.../UpdateManifest.kt` (проверка, правка только
    если есть допущение versionName==releaseTag); тесты
    `core/update/src/commonTest/.../UpdateManifestTest.kt`, `UpdateDecisionTest.kt`.
  - **Deliverables:** убедиться, что `UpdateManifestParser` не требует
    `versionName == releaseTag` и не парсит канал из versionName; добавить/поправить тест на
    манифест новой формы (semver `versionName` + `v…-channel.n` `releaseTag`); подтвердить,
    что `decideUpdate` решает по `versionCode`. `UpdateClient.fileName` не трогать (косметика,
    скачивание по `apkUrl`).
  - **Acceptance:** `./gradlew :core:update:allTests` зелёный, включая новый кейс новой
    формы манифеста; старая форма (`2.0.0-canary.9`) по-прежнему парсится.
  - **Факт:** правка кода парсера НЕ потребовалась — `UpdateManifestParser` читает
    `versionName` и `releaseTag` как независимые поля и канал берёт только из поля `channel`;
    допущения `versionName == releaseTag` нигде нет (проверено чтением `UpdateManifest.kt`).
    Добавлены тесты-сторожа: в `UpdateManifestTest` — новая форма (`versionName="2.1.0"`,
    `releaseTag="v2.1.0-canary.11"`) и старая форма (`2.0.0-canary.9` у обоих полей); в
    `UpdateDecisionTest` — решение по `versionCode` для новой формы (219 > 218 → Available,
    218 == 218 → NoUpdate). `./gradlew :core:update:check` → BUILD SUCCESSFUL
    (jvm + debug + release, lint): UpdateManifestTest 10/10, UpdateDecisionTest 7/7, 0 failures.
    `UpdateClient.fileName` не тронут. `red-first` здесь не применим: парсер уже принимал обе
    формы, тесты — регрессионный сторож новой схемы, а не фикс.

## Открытое / вне этих задач

- **stable-ветка workflow:** правка TSK-202 пока только на canary. `stable` отстаёт на
  более ранний фикс `--target` — переносить туда этот файл нужно целиком (промоушен), а не
  точечно. Требует решения владельца о промоушене.
- **`:platform:android:assembleRelease`** локально не проверяется (нужен гидрированный
  libbox AAR) — фактическая проверка `versionName=2.1.0` в APK и dead-verify подписи
  только в CI.
- **Реальный dry-run workflow** (конкретный тег `v2.1.0-canary.<n>` из `gh release list`)
  проверяется только в CI — локально `gh`/раннер недоступны.

## Completion criteria

- versionName — чистый semver `2.1.0`, канал только в теге/манифесте.
- Тег `v<semver>-<channel>.<n>`, строится в workflow, сверяется с веткой.
- versionCode монотонный; старые клиенты обновляются, старые манифесты валидны.

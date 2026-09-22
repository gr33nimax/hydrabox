# Design: чистая схема версии HydraBox 2.x

**Phase:** Design (фаза 2 из 3)
**Requirements:** `requirements.md` (R1–R4)

## Суть

Разорвать три роли, которые сейчас несёт одна строка `versionName`:

| Роль | Было | Станет | Источник |
| --- | --- | --- | --- |
| Версия продукта (юзеру, semver) | `2.0.0-canary.10` | `2.1.0` | `hydraboxVersionName` |
| Канал + счётчик | внутри строки | `v2.1.0-canary.10` | тег, строится в workflow |
| Порядок сборки | `hydraboxVersionCode` | без изменений, монотонный | `hydraboxVersionCode` |

Канал больше не хранится в номере — он и так известен из ветки запуска.

## D1 — Свойства версии (R1, R3)

`gradle.properties` на обеих ветках:

- `canary`: `hydraboxVersionName=2.1.0`, `hydraboxVersionCode=218` (было `2.0.0-canary.10`).
- `stable`: `hydraboxVersionName=2.1.0`, `hydraboxVersionCode=210` (было `2.0.0-stable.3`).

`platform/android/build.gradle.kts:76` — дефолт заменить с `2.0.0-alpha1` на `2.1.0`.

`versionName` теперь валидный semver `MAJOR.MINOR.PATCH` без суффикса канала (R1.1).
Пользователь в About/Runtime видит `2.1.0` (R1.2) — код не трогаем, он и так читает
`BuildConfig.VERSION_NAME`.

## D2 — Тег строится в workflow, не берётся из versionName (R2)

`android-release.yml`, шаг `Resolve the release version` — добавить вычисление тега:

```bash
name="${INPUT_NAME:-$from_file_name}"        # 2.1.0 (чистый semver)
code="${INPUT_CODE:-$from_file_code}"         # 218
channel="${INPUT_CHANNEL:-canary}"            # из ветки/входа
counter="${INPUT_COUNTER:-...}"               # <n> внутри канала
tag="v${name}-${channel}.${counter}"          # v2.1.0-canary.10
echo "tag=$tag"      >> "$GITHUB_OUTPUT"
echo "name=$name"    >> "$GITHUB_OUTPUT"
echo "code=$code"    >> "$GITHUB_OUTPUT"
```

Дальше по файлу заменить использование `steps.version.outputs.name` там, где имелся в виду
**тег** (создание релиза, имя APK, `releaseTag` в манифесте), на `steps.version.outputs.tag`.
Оставить `name` (semver) там, где имелась в виду **версия** (`versionName` в манифесте, APK
badging verify).

Разбор ролей в текущем файле:

| Место | Сейчас | Станет |
| --- | --- | --- |
| APK версия (verify badging) | `NAME` | `NAME` (semver) — без изменений |
| Имя APK | `hydrabox-$NAME-arm64-v8a.apk` | `hydrabox-$TAG-arm64-v8a.apk` |
| `gh release create` тег | `$NAME` | `$TAG` |
| Манифест `versionName` | `$NAME` | `$NAME` (semver) |
| Манифест `releaseTag` | `$NAME` | `$TAG` |
| Манифест `apkUrl` | `.../$NAME/hydrabox-$NAME-...` | `.../$TAG/hydrabox-$TAG-...` |

Счётчик `<n>` (R2.1): источник — вход workflow `counter` или парс последнего тега канала
(`gh release list` → максимальный `v*-<channel>.*` → +1). Проще: явный вход, дефолт из
последнего манифеста канала. Решаем в задаче — не усложнять, счётчик как вход с
дефолтом-инкрементом.

Проверка «канал == ветка» уже есть (`Channel and branch disagree`, R2.3) — сохраняется.

## D3 — versionCode монотонный (R3)

Уже монотонный и сквозной (canary 218, stable 210 — общий счётчик по коммитам). Клиент
решает по `versionCode` (`decideUpdate` + `installedVersionCode`) — код не трогаем, только
следим, что первый релиз новой схемы > последнего опубликованного (R4.2): canary >217,
stable >208.

## D4 — Совместимость с установленными (R4)

- Старые теги (`2.0.0-canary.N`) и их манифесты в истории не трогаем — остаются валидны.
- Парсер манифеста клиента (`UpdateManifestParser`): проверить, что он **не** валидирует
  `versionName` как «должен равняться releaseTag» и не парсит канал из versionName. Если
  где-то есть такое допущение — снять. Прогнать `UpdateManifestTest`, `UpdateDecisionTest`.
- `UpdateClient.fileName` (`UpdateClient.kt:118`) строит имя из `manifest.versionName` —
  **проверить**: имя APK теперь от тега, значит клиент должен качать по имени-с-тегом.
  Либо `fileName` читает из тега (`releaseTag`), либо `apkUrl` уже полный (он полный в
  манифесте). Свериться: клиент качает по `apkUrl`, `fileName` только для локального файла.

## Риски

- **`fileName` из versionName** (`UpdateClient.kt:118`) — проверено: это только локальное
  имя файла в «Загрузках»; скачивание идёт по `manifest.apkUrl` (полный URL). Схема его
  не ломает — локальный файл просто будет `hydrabox-2.1.0.apk`. Косметика, правка не
  требуется. `apkState` сверяется по `versionName` — самосогласованно.
- Старые клиенты на `2.0.0-canary.9` обновляются по versionCode → новый релиз с бОльшим
  code подхватится, versionName в UI станет `2.1.0`.

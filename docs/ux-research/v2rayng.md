# v2rayNG — что перенять в HydraBox

Источник: `github.com/2dust/v2rayNG`, default_branch = `master` (проверено через GitHub API), ~63k stars, UPD 2026-09. Сырьё: `docs/ux-research/.raw/` (`v2rayng-readme.md`, `v2rayng-tree.json`, дампы `src/main-*.kt`, `src/x-*.kt`, `src/strings.xml`). Разбор — по потокам, без копирования кода.

## A. Стабильность (перенять первым)

1. **Один статус-автомат вместо флагов.** `MainStatus = Disconnected | Connected | Testing | TestProgress | ConnectionTest` — локаль-нейтральный, строку рендерит только UI (`MainContract.kt`, `MainViewModel.formatStatus`). Ни у одного экрана нет своей правды о состоянии. → В HydraBox: единственный `ConnectionState` как источник истины для домашнего экрана, уведомления, тайла и логов.

2. **Реконнект по handover, а не по каждому колбэку сети.** `NetworkMonitor.kt` явно называет cell↔WiFi «make-before-break»: новый network объявляется, пока старый ещё жив, сокет не рвётся и ядро продолжает жечь мёртвое соединение. Реконнект — только при смене upstream, с debounce 1000 ms и отменой предыдущей задачи; `onUnderlyingNetworksChanged` отдельно, чтобы VPN не отвязывался. → Это ровно тот класс багов «сегодня не коннектится после переключения на вайфай».

3. **Токены на асинхронные тесты.** `MainTestRequests.kt`: у каждого теста UUID; поздний ответ не может завершить более новый тест (`completeCurrent(id)` сверяет id). Перед массовым тестом — `cancelAllPing`, старые задержки сбрасываются в 0, чтобы UI не показывал устаревшие числа как валидные. → Без этого получаем «пинг завис / цифры от прошлого сервера».

4. **Подписки как per-sub задания с защитой от циклов.** `SubscriptionUpdater.kt`: уникальное имя задачи на `subId`, floor интервала, initialDelay считается от `lastUpdated + interval`, при forced-reschedule пол 5 s, constraint `NetworkType.CONNECTED`, политика `KEEP` на старте/boot и `REPLACE` после ручного обновления. → Не даёт «автообновление каждые 5 секунд» и потери расписания после перезагрузки.

5. **Частичный успех обновления — норма, а не ошибка.** Строка `Updated %1$d configs (%2$d success, %3$d failed, %4$d skipped)`; отдельно «No subscriptions». → Не прятать skipped/failed за «успех», показывать разбивку.

## B. Предсказуемость

6. **Идентичность по GUID, а не по позиции.** Селект, ключи списка, saved state и параметры действий — по `guid`/`groupId`; после фильтра, сортировки, пейджинга и замены подписки элемент ищется заново. Есть явный кейс «Selected server not found in current group» и действие **Find selected configuration** (переключить группу и проскроллить к выбранному). → В HydraBox это снимает «выбрал сервер, переключил группу — показан не тот».

7. **TCPing ≠ real delay, и это два разных пункта меню.** «Test TCP delays (TCPing)» — достижимость, «Test real delays» — реальная работа через прокси, отдельная настройка конкурентности. Сортировка по результатам — явное действие, не авто. → Пользователь различает «порт открыт» и «интернет есть».

8. **Разделение «туннель поднят» и «интернет работает».** После коннекта статус приглашает: `Connected. Tap to check connection.` → `Check connectivity` → `Connection succeeded in 1.2s` / `Connection test failed: %s` / `Internet unavailable` / `Error code: #N`. → Проверка исходящего IP/локации даёт мгновенный ответ «сломан DNS или мёртвый сервер».

9. **Опасные опции несут предупреждение в себе.** `Automated testing takes a long time…`, `Test results may not be accurate; deleted config cannot be recovered.`, `Depending on the device, this feature may not always work`, `Android may restrict background starts`. → Предупреждение рядом с тумблером, а не в вики; дефолт — выключено.

10. **Пресеты маршрутизации не убивают правки.** Именованные пресеты (China whitelist/blacklist, Global, Iran, Russia) + подтверждение «Existing rulesets will be deleted. Continue?» + флаг «locked; keep this rule when importing presets». Семантика (AND внутри правила, top-to-bottom, first match) выписана прямо на экране. → Импорт пресета не должен молча съедать ручные правила.

## C. UX

11. **Одна точка входа для серверов.** Меню импорта: QR, буфер, файл, вручную по каждому протоколу, policy group, proxy chain; массовый импорт сообщает **`Imported %d configs`**. Обслуживание — явные команды: delete duplicate / invalid / all, каждая с подтверждением. Шаринг — QR, ссылка профиля, полный конфиг. Резервные копии локально и в WebDAV. → Всё «профильное» живёт в одном меню, а не размазано по экрану.

12. **Диагностика как продукт.** Logcat: поиск, копировать, отправить файлом, очистить, отдельный уровень логирования. → Кнопка «поделиться логом» в один тап экономит половину обращений в поддержку.

13. **Уведомления разделены по каналам** (service / subscription updates / connection checks), у сервисного — действие **Stop**, прогресс обновления идёт в уведомление.

14. **Честные пустые состояния:** `No subscriptions`, `No data available`, у тайла — `Add a profile in the app before using this feature.`, «System VPN settings are unavailable» вместо молчания.

15. **Per-app: два режима, объяснённые словами** (checked = через прокси / checked = напрямую = bypass), плюс импорт списка пакетов из буфера и авто-подбор.

## Не перенимать

- Свалку из 92 preference-ключей в одном списке настроек: HydraBox должен держать basic-экран, всё это — под «Advanced».
- Культуру «результат теста = приговор» (авто-удаление невалидных): неверный тест удаляет рабочий сервер. У нас — помечать, не удалять.

## Резюме

Причина-строка: у v2rayNG сложность спрятана за одним статусом, идентичностью по GUID и честными предупреждениями, а не за новыми фичами.
Делать-строка: в HydraBox скопировать три вещи первыми — `ConnectionState` как единственный источник истины, handover-детект с debounce, и токены/сброс для latency-тестов.

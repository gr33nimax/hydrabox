// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Russian (`ru`).
class AppLocalizationsRu extends AppLocalizations {
  AppLocalizationsRu([String locale = 'ru']) : super(locale);

  @override
  String get profiles => 'Профили';

  @override
  String get close => 'Закрыть';

  @override
  String get homeTab => 'Главная';

  @override
  String get proxiesTab => 'Прокси';

  @override
  String get proxiesTitle => 'Прокси';

  @override
  String get proxySwitching => 'Переключение';

  @override
  String get proxySelectorTitle => 'Выбор';

  @override
  String get shareProxyTitle => 'Поделиться';

  @override
  String get shareProxyLinkLabel => 'Ссылка профиля';

  @override
  String get shareSingboxOutboundLabel => 'Конфиг sing-box';

  @override
  String copiedToClipboard(String label) {
    return '$label скопирован';
  }

  @override
  String get unavailableForThisType => 'Недоступно для этого типа';

  @override
  String get sort => 'Сортировка';

  @override
  String get sortByDefault => 'Как в подписке';

  @override
  String get sortByLatency => 'По задержке';

  @override
  String get sortByName => 'По имени';

  @override
  String get sortByCountry => 'По стране';

  @override
  String get settingsTitle => 'Настройки';

  @override
  String get generalSectionTitle => 'Общее';

  @override
  String get inboundTitle => 'Входящие соединения';

  @override
  String get dnsTitle => 'DNS';

  @override
  String get whitelistTitle => 'Белые списки';

  @override
  String get whitelistSubtitle => 'Резервные инструменты маршрутизации';

  @override
  String get experimentalTitle => 'Экспериментальные';

  @override
  String get experimentalSubtitle =>
      'Multipath, Fast Open и поведение переключения соединений';

  @override
  String get logsTitle => 'Логи';

  @override
  String get logsSubtitle => 'Конфиг sing-box и события приложения';

  @override
  String get urlTestTitle => 'Проверка серверов';

  @override
  String get urlTestSubtitle => 'Проверка задержки и выбор lowest';

  @override
  String get vpnInTitle => 'VPN TUN';

  @override
  String get proxyInTitle => 'Прокси-вход';

  @override
  String get dnsDirectTitle => 'Напрямую';

  @override
  String get dnsProxyTitle => 'Через прокси';

  @override
  String get dnsIpPreferenceTitle => 'Версия IP';

  @override
  String get aboutSectionTitle => 'О клиенте';

  @override
  String get aboutSectionSubtitle =>
      'Версия клиента, ядро, команда и служебная информация.';

  @override
  String get aboutHeroSubtitle =>
      'Android VPN-клиент с упором на скорость, стабильность и чистый ежедневный UX.';

  @override
  String get aboutDevelopedBy => 'Разработан командой MeowTeam.';

  @override
  String get aboutCoreSourceLabel => 'исходный код ядра';

  @override
  String get telegramChannelLabel => 'Telegram Etonify';

  @override
  String get legalTermsTitle => 'Пользовательское соглашение';

  @override
  String get legalPrivacyTitle => 'Политика конфиденциальности';

  @override
  String get legalTermsSummary =>
      'Правила ответственного использования и ограничения ответственности.';

  @override
  String get legalPrivacySummary =>
      'Что Etonify хранит локально и какие данные не собирает.';

  @override
  String get legalGateTitle => 'Перед использованием Etonify';

  @override
  String legalGateSubtitle(String version) {
    return 'Начиная с версии $version, нужно прочитать и принять соглашение и политику конфиденциальности.';
  }

  @override
  String get legalAcceptAction => 'Принять и продолжить';

  @override
  String get legalAcceptHint => 'Откройте оба документа, чтобы продолжить.';

  @override
  String get legalDocumentReadAction => 'Прочитал';

  @override
  String get legalContactAction => 'Связь';

  @override
  String get legalImportBlockedMessage =>
      'Примите соглашение и политику конфиденциальности перед импортом подписок.';

  @override
  String get legalTermsBody =>
      '# Пользовательское соглашение Etonify\n\nEtonify — Android VPN-клиент от MeowTeam для личного ежедневного доступа к сети. Приложение не выдаёт VPN-серверы само по себе. Вы сами отвечаете за подписки, профили и серверы, которые добавляете.\n\nИспользуйте Etonify законно и ответственно. Не используйте клиент для мошенничества, атак, травли, распространения вредоносного ПО или других незаконных действий. MeowTeam не отвечает за то, как пользователи применяют сторонние VPN-профили и сетевой доступ.\n\nEtonify предоставляется как есть. Мы работаем над стабильностью и безопасностью, но не можем гарантировать идеальную работу каждого провайдера, маршрута, DNS-резолвера, сети или прошивки Android. Если что-то ломается, отправляйте фидбэк через официальный Telegram-канал или контакты на странице MeowTeam.\n\nНекоторые функции требуют разрешения Android: VPN service создаёт системный VPN-туннель, камера сканирует QR-коды, уведомления показывают состояние сервиса, список приложений нужен для раздельной маршрутизации, а разрешение установки APK используется только для обновлений, которые запускает пользователь.\n\nПродолжая, вы подтверждаете, что понимаете эти правила и принимаете ответственность за собственное использование клиента.';

  @override
  String get legalPrivacyBody =>
      '# Политика конфиденциальности Etonify\n\nВ Etonify нет аналитики, рекламных SDK и скрытого трекинга. MeowTeam не продаёт ваши данные и не собирает ваши VPN-ключи на своих серверах.\n\nВаши подписки, импортированные профили, выбранный сервер, настройки и логи хранятся локально на устройстве. Экспорт и резервная копия могут создавать файлы с VPN-ключами. Храните такие файлы приватно, особенно если экспортируете профиль без шифрования паролем.\n\nКогда вы импортируете или обновляете подписку, Etonify подключается к URL, который вы указали. Happ-подписка может требовать HWID и Happ User-Agent; Etonify спрашивает перед отправкой HWID.\n\nЛоги нужны для диагностики. Мы стараемся скрывать секреты перед показом и экспортом логов, но перед публичной отправкой логов всё равно проверьте их сами.\n\nЕсли есть вопросы или нужно удалить из переписки данные, которые вы сами отправили для фидбэка, свяжитесь с нами через официальный Telegram-канал или контакты MeowTeam.';

  @override
  String get coreVersionLabel => 'Версия ядра';

  @override
  String get debugMenuTitle => 'Отладка';

  @override
  String get debugMenuSubtitle =>
      'Скрытый раздел для отладки и служебных действий.';

  @override
  String get debugNetworkHeartbeatTitle => 'Проверка сети';

  @override
  String debugNetworkHeartbeatSubtitle(int seconds) {
    return 'Повторно закрепляет сеть по умолчанию, если Android пропустил callback. Текущий интервал: $seconds с. Применится при следующем запуске VPN.';
  }

  @override
  String get debugWakeLockTitle => 'Частичный wake lock';

  @override
  String get debugWakeLockSubtitle =>
      'Держит CPU активным во время VPN. По умолчанию выключен, потому что на агрессивных прошивках может греть телефон.';

  @override
  String get debugRecordSnapshot => 'Записать снимок производительности';

  @override
  String get debugSnapshotDone => 'Снимок производительности добавлен в логи';

  @override
  String get teamPageTitle => 'MeowTeam';

  @override
  String get teamIntroTitle => 'Команда Etonify';

  @override
  String get teamIntroBody =>
      'Мы небольшой командой разрабатываем свой VPN-клиент и постепенно доводим его до стабильного ежедневного состояния.';

  @override
  String get teamTimelineForkTitle => 'Старт с форка Hiddify';

  @override
  String get teamTimelineForkBody =>
      'Первые версии унаследовали интерфейс и большой legacy-код Hiddify. Несколько тестовых релизов помогли понять, что именно нужно менять.';

  @override
  String get teamTimelineRefactorTitle => 'Большой рефактор';

  @override
  String get teamTimelineRefactorBody =>
      'Старый backend нёс слишком много технического долга, костылей, dead code и сложного поведения. Мы провели глубокий рефактор и перестроили runtime-слой вокруг более чистого Android-first подхода.';

  @override
  String get teamTimelineCoreTitle => 'Ядро MeowSingBox';

  @override
  String get teamTimelineCoreBody =>
      'Клиент использует модифицированное ядро sing-box с доработками URLTest, очистки соединений и управления ресурсами.';

  @override
  String get teamTimelineNowTitle => 'Etonify сейчас';

  @override
  String get teamTimelineNowBody =>
      'Etonify продолжает развиваться: мы упрощаем UX, улучшаем стабильность Android и убираем технический долг, сохраняя быстрый VPN-опыт.';

  @override
  String get teamDeveloperDdosxdRole => 'Разработчик MeowTeam';

  @override
  String get teamDeveloperYamixdevRole => 'Разработчик MeowTeam';

  @override
  String get teamTelegramRole => 'Официальный канал и новости релизов';

  @override
  String get languageSettingTitle => 'Язык';

  @override
  String get themeSettingTitle => 'Тема';

  @override
  String get accentColorTitle => 'Акцент';

  @override
  String get appearanceTitle => 'Оформление';

  @override
  String get languageSystem => 'Системный';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageRussian => 'Русский';

  @override
  String get themeSystem => 'Системная';

  @override
  String get themeLight => 'Светлая';

  @override
  String get themeDark => 'Тёмная';

  @override
  String get themeAmoled => 'AMOLED';

  @override
  String get aboutResourcesTitle => 'Ресурсы';

  @override
  String get aboutResourcesSubtitle =>
      'Снимок Android по запросу. В фоне эти данные не собираются.';

  @override
  String get aboutResourcePss => 'Память';

  @override
  String get aboutResourceNativeHeap => 'Native heap';

  @override
  String get aboutResourceJavaHeap => 'Java heap';

  @override
  String get aboutResourceSystemMemory => 'Свободная RAM системы';

  @override
  String get aboutResourceBatteryTemp => 'Температура батареи';

  @override
  String get updatesTitle => 'Обновления';

  @override
  String get updatesSubtitle =>
      'Проверка GitHub Releases и скачивание APK под устройство.';

  @override
  String get updatesChecking => 'Проверка обновлений…';

  @override
  String get updatesCheckAction => 'Проверить';

  @override
  String get updatesRetryAction => 'Повторить';

  @override
  String get updatesDownloadAction => 'Скачать обновление';

  @override
  String get updatesInstallAction => 'Установить APK';

  @override
  String get updatesDownloadWarning =>
      'Не закрывайте Etonify до завершения загрузки.';

  @override
  String get updatesOpeningInstaller => 'Открываем системный установщик…';

  @override
  String get updatesInstallPermissionHint =>
      'Разрешите установку APK для Etonify, затем нажмите «Установить APK» ещё раз.';

  @override
  String get updatesInstallPermissionTitle => 'Нужно разрешение';

  @override
  String get updatesInstallPermissionMessage =>
      'Чтобы Etonify мог открыть установку скачанного APK, разрешите установку неизвестных приложений для клиента. Без этого можно только скачать файл вручную.';

  @override
  String get updatesInstallPermissionOpen => 'Открыть настройки';

  @override
  String get updatesInstallPermissionGranted =>
      'Разрешение на установку APK включено.';

  @override
  String get updatesInstallModeTitle => 'Установка обновлений';

  @override
  String get updatesInstallModeAsk => 'Спрашивать каждый раз';

  @override
  String get updatesInstallModeAskSubtitle =>
      'Перед скачиванием Etonify предложит ручную или автоматическую установку.';

  @override
  String get updatesInstallModeManual => 'Вручную';

  @override
  String get updatesInstallModeManualSubtitle =>
      'Клиент скачает APK и покажет кнопку установки.';

  @override
  String get updatesInstallModeAuto => 'Автоматически';

  @override
  String get updatesInstallModeAutoSubtitle =>
      'Клиент скачает APK и сразу откроет системный установщик.';

  @override
  String get updatesInstallMethodTitle => 'Как установить обновление?';

  @override
  String get updatesInstallMethodManualTitle => 'Скачать вручную';

  @override
  String get updatesInstallMethodManualSubtitle =>
      'APK сохранится в кэше обновлений. Установку можно запустить позже.';

  @override
  String get updatesInstallMethodAutoTitle => 'Скачать и установить';

  @override
  String get updatesInstallMethodAutoSubtitle =>
      'После загрузки Etonify сразу откроет системный установщик Android.';

  @override
  String get updatesInstallMethodRemember => 'Запомнить выбор';

  @override
  String get updatesApkVerificationTitle => 'Проверка APK';

  @override
  String get updatesApkVerificationVerified => 'SHA-256 совпадает';

  @override
  String get updatesApkVerificationUnavailable => 'SHA-256 не указан в релизе';

  @override
  String get updatesApkVerificationFailed => 'SHA-256 не совпадает';

  @override
  String get updatesDownloadedFileMissing =>
      'Файл обновления не найден. Скачайте APK заново.';

  @override
  String get updatesDeleteCachedApkAction => 'Удалить установочный APK';

  @override
  String get updatesDeleteCachedApkTitle => 'Удалить установочный APK?';

  @override
  String updatesDeleteCachedApkMessage(Object version) {
    return 'Будет удалён скачанный APK обновления $version и старые временные APK-файлы Etonify из кэша приложения.';
  }

  @override
  String updatesDeleteCachedApkDone(int count) {
    return 'Кэш обновлений очищен. Удалено файлов: $count.';
  }

  @override
  String get updatesUpToDateTitle => 'Etonify обновлён';

  @override
  String updatesUpToDateSubtitle(String version) {
    return 'Установленная версия: $version';
  }

  @override
  String get updatesAvailableTitle => 'Доступно обновление';

  @override
  String updatesAvailableSubtitle(String version, String size) {
    return '$version · $size';
  }

  @override
  String get updatesAvailableSnack => 'Доступно обновление клиента';

  @override
  String updatesAvailableSnackVersion(Object version) {
    return 'Доступно обновление клиента $version';
  }

  @override
  String get updatesOpenAction => 'Открыть';

  @override
  String get updatesDownloadingTitle => 'Скачиваем обновление';

  @override
  String get updatesDownloadedTitle => 'Обновление скачано';

  @override
  String updatesDownloadedSubtitle(String fileName) {
    return 'Сохранено в кэше обновлений: $fileName';
  }

  @override
  String get updatesErrorTitle => 'Не удалось проверить обновления';

  @override
  String get updatesErrorSubtitle =>
      'Если GitHub заблокирован в этой сети, Etonify попробует снова завтра.';

  @override
  String get updatesCurrentVersion => 'Текущая версия';

  @override
  String get updatesLatestVersion => 'Новая версия';

  @override
  String get updatesAsset => 'APK';

  @override
  String updatesLastChecked(String time) {
    return 'Проверено: $time';
  }

  @override
  String get updatesReleaseNotesTitle => 'Что нового';

  @override
  String get updatesNoReleaseNotes => 'В релизе нет описания изменений.';

  @override
  String updatesProgressBytes(String downloaded, String total) {
    return '$downloaded / $total';
  }

  @override
  String updatesProgressSpeedEta(String speed, String eta) {
    return '$speed/с · осталось $eta';
  }

  @override
  String updatesEtaSeconds(int seconds) {
    return '$seconds с';
  }

  @override
  String updatesEtaMinutes(int minutes, int seconds) {
    return '$minutes мин $seconds с';
  }

  @override
  String get updatesUnknownSize => 'Размер неизвестен';

  @override
  String get appVersionLabel => 'Версия клиента';

  @override
  String get currentProfileLabel => 'Текущий профиль';

  @override
  String get selectedProxyLabel => 'Выбранный прокси';

  @override
  String get onboardingStatusLabel => 'Стартовый экран';

  @override
  String get onboardingSeen => 'Завершён';

  @override
  String get showOnboardingAgain => 'Показать стартовый экран снова';

  @override
  String get settingsFootnote =>
      'Эти настройки локальны для этого устройства и хранятся в Hive.';

  @override
  String get connected => 'Подключено';

  @override
  String get tapToConnect => 'Нажмите для подключения';

  @override
  String get resolvingIp => 'Определяем IP…';

  @override
  String get millisecondsUnit => ' мс';

  @override
  String get refreshLatency => 'Обновить задержку';

  @override
  String get checkingLatency => 'Проверка задержки';

  @override
  String get checkingLatencyShort => 'Проверка…';

  @override
  String get openTrafficDashboard => 'Открыть мониторинг трафика';

  @override
  String get refreshActiveSubscription => 'Обновить текущую подписку';

  @override
  String get refreshActiveSubscriptionUnavailable =>
      'Ручной импорт нельзя обновить';

  @override
  String activeSubscriptionRefreshComplete(String name) {
    return '$name обновлена';
  }

  @override
  String get trafficDashboardTitle => 'Мониторинг трафика';

  @override
  String get trafficDashboardSubtitle =>
      'Скорость, трафик за сессию и данные подключения';

  @override
  String get trafficDashboardDownload => 'Загрузка';

  @override
  String get trafficDashboardUpload => 'Отдача';

  @override
  String get trafficDashboardSessionTraffic => 'Трафик сессии';

  @override
  String get trafficDashboardConnectedFor => 'Время работы';

  @override
  String get trafficDashboardGraphTitle => 'Трафик в реальном времени';

  @override
  String trafficDashboardGraphMax(String speed) {
    return 'Пик $speed';
  }

  @override
  String get trafficDashboardNoSamples => 'Ждём данные трафика';

  @override
  String get trafficDashboardConnectionState => 'Подключение';

  @override
  String get trafficDashboardCurrentProfile => 'Профиль';

  @override
  String get trafficDashboardActiveProxy => 'Прокси';

  @override
  String get trafficDashboardServerIp => 'IP сервера';

  @override
  String get trafficDashboardDownloadTotal => 'Скачано';

  @override
  String get trafficDashboardUploadTotal => 'Отдано';

  @override
  String get trafficDashboardStateConnected => 'Подключено';

  @override
  String get trafficDashboardStateConnecting => 'Подключаемся';

  @override
  String get trafficDashboardStateDisconnected => 'Отключено';

  @override
  String trafficDashboardUptimeHours(int hours, int minutes) {
    return '$hours ч $minutes мин';
  }

  @override
  String trafficDashboardUptimeMinutes(int minutes, int seconds) {
    return '$minutes мин $seconds с';
  }

  @override
  String trafficDashboardUptimeSeconds(int seconds) {
    return '$seconds с';
  }

  @override
  String get notAvailableShort => 'н/д';

  @override
  String daysLeft(int days) {
    return 'Осталось $days дн.';
  }

  @override
  String get daysLeftUnlimited => 'Осталось ∞ дн.';

  @override
  String get unlimitedTraffic => 'Безлимит';

  @override
  String get unlimitedSymbol => '∞';

  @override
  String get welcomeGreeting => 'Привет';

  @override
  String get welcomeTitlePrefix => 'Добро пожаловать в';

  @override
  String get welcomeSubtitle => 'Быстрый Android VPN-клиент';

  @override
  String get welcomeTapHint => 'нажмите, чтобы продолжить';

  @override
  String get hapticTitle => 'Вибрация';

  @override
  String get hapticSubtitle => 'Лёгкая вибрация для важных действий';

  @override
  String get hideServerIpTitle => 'Скрывать IP сервера';

  @override
  String get hideServerIpSubtitle => 'Маскирует последние два октета IP-адреса';

  @override
  String get performanceModeTitle => 'Режим производительности';

  @override
  String get performanceModeCool => 'Cool';

  @override
  String get performanceModeStandard => 'Стандартный';

  @override
  String get performanceModeEconomy => 'Эконом';

  @override
  String get performanceModeBalanced => 'Balanced';

  @override
  String get performanceModePerformance => 'Performance';

  @override
  String get performanceModeCoolSubtitle =>
      'Минимальный нагрев и фоновая нагрузка для ежедневного Android-режима.';

  @override
  String get performanceModeStandardSubtitle =>
      'Стабильный ежедневный режим: авто-пинг раз в 5 минут, умеренная параллельность и меньше фоновой нагрузки.';

  @override
  String get performanceModeEconomySubtitle =>
      'Минимум лишних фоновых задач: авто-пинг раз в 5 минут, меньше параллельных проверок и без авто-геолокации серверов.';

  @override
  String get performanceModeBalancedSubtitle =>
      'Умеренные проверки и расход батареи.';

  @override
  String get performanceModePerformanceSubtitle =>
      'Более быстрые проверки, но выше CPU, трафик и нагрев.';

  @override
  String get performanceModeRecommendation =>
      'Рекомендуем оставлять стандартный режим. Эконом стоит включать, когда важнее батарея, чем быстрые фоновые проверки.';

  @override
  String get memoryLimitTitle => 'Ограничение памяти';

  @override
  String get memoryLimitEnabledSubtitle =>
      'Рекомендуется. sing-box остановится раньше, чем нехватка памяти начнёт ломать работу приложения. Изменение вступит в силу после перезапуска приложения.';

  @override
  String get memoryLimitDisabledSubtitle =>
      'Выключено. Может помочь при ложной ошибке лимита памяти, но повышает расход RAM и риск вылета. Вступит в силу после перезапуска приложения.';

  @override
  String get memoryLimitDisableWarningTitle => 'Выключить ограничение памяти?';

  @override
  String get memoryLimitDisableWarningMessage =>
      'Используйте это только если VPN не запускается с ошибкой лимита памяти. Без лимита может вырасти расход RAM, нагрев и шанс, что Android закроет приложение. Изменение вступит в силу после перезапуска Etonify.';

  @override
  String get memoryLimitDisableConfirm => 'Выключить';

  @override
  String get enableInboundTitle => 'Включить';

  @override
  String get vpnInDescription =>
      'VPN TUN — системный Android VPN для трафика телефона. Приложения могут видеть Android VPN, а правила решают, что идёт через прокси или напрямую.';

  @override
  String get vpnInboundEnabledSubtitle =>
      'Создаёт VPN TUN-вход и маршрутизирует трафик через него';

  @override
  String get inboundNoneEnabled =>
      'Включите VPN TUN или Proxy In перед запуском.';

  @override
  String get mtuTitle => 'MTU';

  @override
  String get mtuSubtitle => 'Размер пакета TUN-интерфейса';

  @override
  String get strictRouteTitle => 'Не допускать обход VPN';

  @override
  String get strictRouteSubtitle =>
      'Жёстко направляет трафик через VPN и снижает шанс утечек мимо туннеля';

  @override
  String get tunImplementationTitle => 'Реализация TUN';

  @override
  String get tunImplementationSubtitle => 'Способ обработки TUN внутри клиента';

  @override
  String get tunImplementationMixed => 'Mixed';

  @override
  String get tunImplementationMixedSubtitle =>
      'Автоматический режим. Выбирает более безопасный стек для текущего устройства и конфига.';

  @override
  String get tunImplementationSystem => 'System';

  @override
  String get tunImplementationSystemSubtitle =>
      'Системный Android-стек. Обычно легче, но зависит от прошивки устройства.';

  @override
  String get tunImplementationGvisor => 'gVisor';

  @override
  String get tunImplementationGvisorSubtitle =>
      'Пользовательский сетевой стек. Может быть совместимее, но иногда сильнее грузит CPU.';

  @override
  String get proxyInDescription =>
      'Proxy In / mixed — локальный HTTP/SOCKS вход для приложений или устройств, которые настроены вручную. Это не системный Android VPN.';

  @override
  String get proxyInboundEnabledSubtitle =>
      'Поднимает локальный mixed-inbound для приложений и устройств';

  @override
  String get allowLanConnectionsTitle =>
      'Разрешить соединения из локальной сети';

  @override
  String get allowLanConnectionsSubtitle =>
      'Если включено, слушать на 0.0.0.0, иначе на 127.0.0.1';

  @override
  String get portTitle => 'Порт';

  @override
  String get proxyPortSubtitle => 'Порт локального mixed-inbound';

  @override
  String get dnsUsePresetTitle => 'Использовать пресет';

  @override
  String get dnsResolverTitle => 'Резолвер';

  @override
  String get dnsDirectPresetSubtitle => 'Рекомендуется udp://1.1.1.1';

  @override
  String get dnsDirectResolverSubtitle => 'DNS для прямых запросов без прокси';

  @override
  String get dnsRussiaDirectTitle => 'DNS для маршрутов России';

  @override
  String get dnsRussiaDirectSubtitle =>
      'Используется только при включённых маршрутах России. Российские домены резолвятся напрямую через этот DNS, чтобы сайты и приложения быстрее попадали в direct.';

  @override
  String get dnsRussiaDirectResolverSubtitle =>
      'По умолчанию udp://77.88.8.8. Оставьте быстрый российский DNS, если используете режим “всё кроме РФ через VPN”.';

  @override
  String get dnsProxyPresetSubtitle =>
      'Рекомендуется https://dns.cloudflare.com/dns-query';

  @override
  String get dnsProxyResolverSubtitle => 'DNS для запросов через прокси';

  @override
  String get dnsResolverTypeTitle => 'Вариант резолвера';

  @override
  String get dnsPresetDevice => 'Сеть устройства';

  @override
  String get dnsPresetCustom => 'Свой';

  @override
  String get dnsPresetDeviceSubtitle =>
      'Использовать DNS текущей Android-сети.';

  @override
  String get dnsPresetCustomSubtitle =>
      'Введите свой резолвер: udp://, tcp://, tls:// или https://.';

  @override
  String get dnsPresetUdpSubtitle =>
      'Обычный UDP DNS. Быстрый, но без шифрования.';

  @override
  String get dnsPresetTcpSubtitle =>
      'Обычный TCP DNS. На некоторых сетях стабильнее, но без шифрования.';

  @override
  String get dnsPresetTlsSubtitle =>
      'DNS over TLS. Шифрованный DNS на порту 853.';

  @override
  String get dnsPresetHttpsSubtitle =>
      'DNS over HTTPS. Шифрованный DNS через HTTPS, часто лучше через прокси.';

  @override
  String get dnsPreferIpv6Title => 'Предпочитать IPv6';

  @override
  String get dnsPreferIpv6Subtitle =>
      'Приоритет IPv6, если доступны обе версии адреса';

  @override
  String get urlTestUrlTitle => 'URL проверки';

  @override
  String get urlTestUrlSubtitle =>
      'Если в подписке задано своё значение, используется оно';

  @override
  String get urlTestIntervalTitle => 'Интервал, сек.';

  @override
  String get urlTestIntervalSubtitle => 'Частота проверки прокси для lowest';

  @override
  String get urlTestTimeoutTitle => 'Таймаут проверки, сек.';

  @override
  String get urlTestTimeoutSubtitle =>
      'Сколько ждать ответа от одного прокси перед ошибкой';

  @override
  String get urlTestConcurrencyTitle => 'Поточность проверки';

  @override
  String get urlTestConcurrencySubtitle =>
      'Сколько прокси URLTest проверяет одновременно';

  @override
  String get urlTestSingleRetestTitle => 'Быстрая перепроверка, сек.';

  @override
  String get urlTestSingleRetestSubtitle =>
      'Через сколько сделать одну быструю перепроверку после сбоя прокси';

  @override
  String get locationLookupTitle => 'Локации';

  @override
  String get locationLookupSubtitle => 'IP и страна через сами прокси';

  @override
  String get locationLookupLimitTitle => 'Проверять лучших прокси';

  @override
  String get locationLookupLimitSubtitle =>
      'После URLTest приложение определит внешний IP и страну у этого количества самых быстрых аутбаундов';

  @override
  String get locationLookupTimeoutTitle => 'Таймаут запроса';

  @override
  String get locationLookupTimeoutSubtitle =>
      'Сколько ждать внешний IP и страну для одного сервера';

  @override
  String get locationLookupConcurrencyTitle => 'Параллельные запросы';

  @override
  String get locationLookupConcurrencySubtitle =>
      'Сколько запросов локации можно выполнять одновременно';

  @override
  String settingsSecondsShort(int seconds) {
    return '$seconds сек.';
  }

  @override
  String get serverRequestTitle => 'Запрос к серверу';

  @override
  String get sendHwidTitle => 'Отправлять HWID';

  @override
  String get sendHwidSubtitle => 'Добавляет HWID устройства в запрос подписки';

  @override
  String get useCustomHwidTitle => 'Использовать свой HWID';

  @override
  String get useCustomHwidSubtitle =>
      'Подменяет HWID устройства вашим значением';

  @override
  String get customUserAgentTitle => 'Свой User-Agent';

  @override
  String get customUserAgentSubtitle =>
      'Переопределяет стандартный Etonify user-agent для этой подписки';

  @override
  String get customHwidTitle => 'Свой HWID';

  @override
  String get customHwidSubtitle => 'Используется только если включён свой HWID';

  @override
  String get customRequestHeadersTitle => 'Свои заголовки';

  @override
  String get customRequestHeadersSubtitle =>
      'По одному заголовку на строку в формате Header: value';

  @override
  String get hwidTitle => 'HWID';

  @override
  String get hwidSubtitle =>
      'Идентификатор устройства, который используют некоторые провайдеры подписок';

  @override
  String get hwidValueTitle => 'Ваш HWID';

  @override
  String get coreStartFailedTitle => 'Не удалось запустить ядро';

  @override
  String coreStartFailedMessage(String message) {
    return 'Не удалось запустить sing-box.\n\n$message';
  }

  @override
  String get vpnStopFailed =>
      'VPN не удалось полностью выключить. Открой логи и попробуй ещё раз.';

  @override
  String get clearLogsTitle => 'Очистить логи';

  @override
  String get logsFilterTitle => 'Фильтр';

  @override
  String get logsFilterAll => 'Все';

  @override
  String get singBoxLogLevelTitle => 'Уровень логов sing-box';

  @override
  String get logLevelTrace => 'Trace';

  @override
  String get logLevelDebug => 'Debug';

  @override
  String get logLevelInfo => 'Info';

  @override
  String get logLevelWarning => 'Warning';

  @override
  String get logLevelError => 'Error';

  @override
  String get noLogsTitle => 'Логов пока нет';

  @override
  String get continueLabel => 'Начать';

  @override
  String get subscriptionsTab => 'Подписки';

  @override
  String get subscriptionsTitle => 'Подписки';

  @override
  String get settingsProfilesChecksTitle => 'Профили и проверка';

  @override
  String get settingsProfilesChecksSubtitle =>
      'Проверка серверов · HWID · параметры профилей';

  @override
  String get addSubscription => 'Добавить подписку';

  @override
  String get addSubscriptionQuickTitle => 'Добавить профиль';

  @override
  String get addSubscriptionQuickSubtitle =>
      'Выберите способ импорта подписки.';

  @override
  String get addSubscriptionFromClipboard => 'Буфер обмена';

  @override
  String get addSubscriptionManual => 'Вручную';

  @override
  String get addSubscriptionReadingClipboard => 'Читаем буфер обмена…';

  @override
  String get addSubscriptionReadingFile => 'Читаем файл…';

  @override
  String get addSubscriptionImporting => 'Импортируем подписку…';

  @override
  String get addSubscriptionSaving => 'Сохраняем профиль…';

  @override
  String get addSubscriptionDone => 'Подписка добавлена';

  @override
  String get clipboardEmpty => 'Буфер обмена пуст';

  @override
  String get scanQrCode => 'Сканировать QR';

  @override
  String get showQrCode => 'Показать QR';

  @override
  String get subscriptionQrTitle => 'QR подписки';

  @override
  String get subscriptionQrHint =>
      'Отсканируйте этот код на другом устройстве, чтобы импортировать подписку.';

  @override
  String get subscriptionQrUnsupported =>
      'Эту подписку пока нельзя показать как QR.';

  @override
  String get invalidQrSubscription =>
      'В QR-коде нет поддерживаемой ссылки подписки.';

  @override
  String get subscriptionUrl => 'URL подписки';

  @override
  String get subscriptionUrlOrContent => 'URL или содержимое';

  @override
  String get subscriptionUrlOrContentHint =>
      'Вставьте URL, vless://, пачку ссылок или конфиг';

  @override
  String get importFromFile => 'Из файла';

  @override
  String get invalidSubscriptionFile => 'Не удалось прочитать файл подписки';

  @override
  String get subscriptionName => 'Название (необязательно)';

  @override
  String get add => 'Добавить';

  @override
  String get cancel => 'Отмена';

  @override
  String get delete => 'Удалить';

  @override
  String get refresh => 'Обновить';

  @override
  String get reparseProxies => 'Перепарсить прокси';

  @override
  String get subscriptionLocalImportBadge => 'Локальный импорт';

  @override
  String get refreshAll => 'Обновить все';

  @override
  String subscriptionsRefreshAllComplete(int updated, int failed) {
    return 'Обновлено подписок: $updated, ошибок: $failed';
  }

  @override
  String get deleteSubscription => 'Удалить подписку?';

  @override
  String get deleteSubscriptionConfirm =>
      'Все прокси из этой подписки будут удалены.';

  @override
  String get subscriptionDetailsTitle => 'Подписка';

  @override
  String get subscriptionMovedTitle => 'Подписка переехала';

  @override
  String get ignoreAction => 'Игнорировать';

  @override
  String get updateUrlAction => 'Обновить URL';

  @override
  String get autoUpdateTitle => 'Автообновление';

  @override
  String get disableAutoUpdateTitle => 'Отключить автообновление';

  @override
  String get disabledLabel => 'Отключено';

  @override
  String refreshesEvery(String interval) {
    return 'Обновляется через: $interval';
  }

  @override
  String get usageTitle => 'Использование';

  @override
  String spentTraffic(String usage) {
    return 'Потрачено $usage';
  }

  @override
  String untilDate(String date) {
    return 'До $date';
  }

  @override
  String get infoTitle => 'Информация';

  @override
  String get supportUrlLabel => 'Поддержка';

  @override
  String get websiteLabel => 'Сайт';

  @override
  String get newUrlTitle => 'NewURL';

  @override
  String get movedSubscriptionMessage =>
      'Сервер сообщил, что подписка переехала на новый URL.';

  @override
  String get movedSubscriptionPrompt =>
      'Сервер сообщает новый URL подписки. Обновить его сейчас или оставить текущий?';

  @override
  String get noSubscriptions => 'Подписок пока нет';

  @override
  String get noProxies => 'Нет прокси';

  @override
  String get noSubscriptionsHint => 'Нажмите + чтобы добавить URL подписки';

  @override
  String outboundsCount(int count) {
    return '$count прокси';
  }

  @override
  String subscriptionServersCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count сервера',
      many: '$count серверов',
      few: '$count сервера',
      one: '$count сервер',
    );
    return '$_temp0';
  }

  @override
  String get subscriptionReparseRecommended => 'Нужно перепарсить';

  @override
  String get subscriptionProxyTypeLabel => 'Прокси';

  @override
  String moreProxies(int count) {
    return '…ещё $count прокси';
  }

  @override
  String lastUpdated(String time) {
    return 'Обновлено $time';
  }

  @override
  String trafficUsage(String used, String total) {
    return '$used / $total';
  }

  @override
  String get expired => 'Истекла';

  @override
  String get loading => 'Загрузка…';

  @override
  String get error => 'Ошибка';

  @override
  String get invalidUrl => 'Введите корректный URL';

  @override
  String get fetchFailed => 'Не удалось загрузить подписку';

  @override
  String get subscriptionSavedWithFetchWarning =>
      'Подписка сохранена, но сервер не ответил. Можно поменять HWID или заголовки и обновить её позже.';

  @override
  String get sourceLabel => 'Источник';

  @override
  String importedFromFileLabel(String name) {
    return 'Импортировано из файла: $name';
  }

  @override
  String get deepLinkImportTitle => 'Импорт подписки';

  @override
  String get deepLinkImportMessage =>
      'Вы действительно хотите импортировать эту подписку?';

  @override
  String get deepLinkImportNameLabel => 'Название';

  @override
  String get deepLinkImportAction => 'Импортировать';

  @override
  String get deepLinkImportSourceLabel => 'Исходная ссылка';

  @override
  String get deepLinkImportResolvedUrlLabel => 'Расшифрованный URL подписки';

  @override
  String get deepLinkImportHappBadge => 'Подписка Happ';

  @override
  String get deepLinkImportHappNotice =>
      'Эта подписка предназначена для приложения Happ и может требовать HWID устройства. Etonify отправит HWID и User-Agent Happ только если ты подтвердишь импорт.';

  @override
  String get deepLinkImportHappSendHwidAction =>
      'Отправить HWID и импортировать';

  @override
  String get deepLinkImportHappWithoutHwidAction => 'Импортировать без HWID';

  @override
  String get deepLinkImportHappCancelAction => 'Не импортировать';

  @override
  String get deepLinkImportUserAgentLabel => 'User-Agent';

  @override
  String get deepLinkImportHwidLabel => 'HWID';

  @override
  String get deepLinkImportHwidValue =>
      'Будет отправлен только после подтверждения';

  @override
  String deepLinkImportSuccess(String name) {
    return 'Подписка \"$name\" импортирована';
  }

  @override
  String get happCryptoLinkImportedLabel =>
      'Подписка импортирована через Happ Crypto Link';

  @override
  String get happCryptoLinkTitle => 'Happ Crypto Link';

  @override
  String get happCryptUnsupportedTitle => 'Happ crypt5';

  @override
  String get happCryptUnsupportedMessage =>
      'Данная версия Happ Crypto Link пока что не поддерживается.';

  @override
  String get happImportTitle => 'Подписка Happ';

  @override
  String get happImportMessage =>
      'Эта подписка предназначена для приложения Happ и может требовать HWID устройства. Можно отправить HWID сразу, импортировать без HWID или отменить. Если провайдер требует HWID, без него в списке ключей может появиться заглушка про неподдерживаемое устройство.';

  @override
  String get subscriptionOperationSlowWarning =>
      'Сервер подписки отвечает дольше обычного. Если это повторяется, проверь ссылку или сеть.';

  @override
  String get subscriptionOperationTimeout =>
      'Сервер подписки не ответил вовремя. Проверь ссылку или сеть и попробуй снова.';

  @override
  String get continueAction => 'Продолжить';

  @override
  String get routingTitle => 'Маршрутизация';

  @override
  String get routingSubtitle => 'Правила маршрутизации трафика';

  @override
  String get bypassLocalNetworkTitle => 'Обход локальной сети';

  @override
  String get bypassLocalNetworkSubtitle =>
      'Направляет приватные и LAN-адреса напрямую';

  @override
  String get russiaRoutesTitle => 'Маршруты России';

  @override
  String get russiaRoutesRunetFreedomBadge => 'runetfreedom';

  @override
  String get russiaRoutesDomainListBadge => 'domain-list-community';

  @override
  String get russiaRoutesSubtitle =>
      'Клиент скачивает live runetfreedom sing-box.zip, проверяет нужные rule set файлы и использует bundled fallback при сбое.';

  @override
  String get russiaRoutesInstallAction => 'Подготовить';

  @override
  String get russiaRoutesReinstallAction => 'Обновить';

  @override
  String get russiaRoutesUpdateAction => 'Обновить';

  @override
  String get russiaRoutesEnableTitle => 'Использовать маршруты России';

  @override
  String get russiaRoutesEnabledSubtitle =>
      'Нужные маршруты будут применены автоматически: российские доступные сервисы напрямую, остальное через VPN.';

  @override
  String get russiaRoutesMissingSubtitle =>
      'Сначала подготовь пакет маршрутов, чтобы его можно было включить.';

  @override
  String get russiaRoutesPreparingStatus =>
      'Подготавливаем локальные маршруты...';

  @override
  String get russiaRoutesMissingStatus =>
      'Локальные маршруты ещё не подготовлены';

  @override
  String get russiaRoutesMissingHint =>
      'Клиент скачает runetfreedom sing-box.zip, проверит обязательные `.srs`, а при сбое использует bundled fallback.';

  @override
  String russiaRoutesReadyStatus(String versionTag) {
    return 'Маршруты готовы, версия: $versionTag';
  }

  @override
  String get russiaRoutesLiveSource => 'runetfreedom sing-box.zip';

  @override
  String get russiaRoutesBundledSource => 'bundled fallback';

  @override
  String russiaRoutesSourceMeta(
    String source,
    String verifiedAt,
    int fileCount,
  ) {
    return 'Источник: $source · проверено: $verifiedAt · файлов: $fileCount';
  }

  @override
  String russiaRoutesMeta(
    String installedAt,
    String domainListUpdatedAt,
    int categoryCount,
    int domainCount,
  ) {
    return 'runetfreedom: $installedAt · domain-list-community: $domainListUpdatedAt · категорий: $categoryCount · доменов: $domainCount';
  }

  @override
  String get adBlockTitle => 'Блокировка рекламы';

  @override
  String get adBlockSubtitle =>
      'Клиент сам скачивает локальный rule set и подключает его в routing.';

  @override
  String get adBlockDownloadAction => 'Скачать';

  @override
  String get adBlockUpdateAction => 'Обновить';

  @override
  String get adBlockEnableTitle => 'Включить локальную блокировку';

  @override
  String get adBlockEnabledSubtitle =>
      'Использовать скачанный локальный rule set для DNS и route reject.';

  @override
  String get adBlockMissingSubtitle =>
      'Сначала скачай пакет фильтра, чтобы его можно было включить.';

  @override
  String get adBlockDownloadingStatus =>
      'Скачиваем и собираем локальный фильтр...';

  @override
  String get adBlockMissingStatus => 'Фильтр ещё не скачан';

  @override
  String get adBlockMissingHint =>
      'Скачиваем список с AdGuard и сохраняем его локально для sing-box.';

  @override
  String adBlockReadyStatus(int blockedCount) {
    return 'Фильтр готов, доменов: $blockedCount';
  }

  @override
  String adBlockMeta(String updatedAt, int allowedCount) {
    return 'Обновлено: $updatedAt · исключений: $allowedCount';
  }

  @override
  String get splitRoutingTitle => 'Раздельная маршрутизация';

  @override
  String get splitRoutingSubtitle =>
      'Направляет выбранные Android-приложения через VPN TUN или полностью вне VPN.';

  @override
  String get splitRoutingUnavailableTitle => 'Временно недоступно';

  @override
  String get splitRoutingUnavailableMessage =>
      'Split tunneling сейчас не работает должным образом. Мы работаем над исправлением. Следите за обновлениями!';

  @override
  String get splitRoutingTunOnly =>
      'Split tunneling по приложениям работает только при включённом VPN TUN. Локальный Proxy In не видит Android-пакеты приложений.';

  @override
  String get splitRoutingModeTitle => 'Режим';

  @override
  String get splitRoutingModeDisabled => 'Выкл';

  @override
  String get splitRoutingModeDisabledSubtitle =>
      'Использует обычную маршрутизацию для всех приложений';

  @override
  String get splitRoutingModeProxySelected => 'Через VPN';

  @override
  String get splitRoutingModeProxySelectedSubtitle =>
      'Только выбранные приложения попадут в VPN TUN и пойдут через выбранный сервер';

  @override
  String get splitRoutingModeBypassSelected => 'Вне VPN';

  @override
  String get splitRoutingModeBypassSelectedSubtitle =>
      'Выбранные приложения не попадут в VPN TUN и будут идти напрямую';

  @override
  String get splitRoutingAppsTitle => 'Приложения';

  @override
  String get splitRoutingPackagesTitle => 'Имена пакетов';

  @override
  String get splitRoutingPackagesHint => 'com.termux\norg.mozilla.firefox';

  @override
  String get splitRoutingPackagesHelper =>
      'Только package name, например org.telegram.messenger. Названия приложений игнорируются';

  @override
  String get splitRoutingPickAppsAction => 'Выбрать приложения';

  @override
  String get splitRoutingPickAppsTitle => 'Выбор приложений';

  @override
  String get splitRoutingSearchHint => 'Поиск по приложению или имени пакета';

  @override
  String get splitRoutingAndroidOnly =>
      'Выбор приложений доступен только на Android';

  @override
  String get splitRoutingLoadAppsFailed =>
      'Не удалось загрузить список приложений';

  @override
  String splitRoutingSelectedCount(int count) {
    return 'Выбрано: $count';
  }

  @override
  String get splitRoutingNoAppsTitle => 'Приложения ещё не выбраны';

  @override
  String get splitRoutingNoAppsSubtitle =>
      'Выбери Android-приложения, к которым нужно применить split routing';

  @override
  String get splitRoutingManualEditorTitle => 'Ручной список пакетов';

  @override
  String get splitRoutingManualEditorSubtitle =>
      'Используй это, если хочешь редактировать package names напрямую';

  @override
  String refreshIntervalDaysShort(int count) {
    return '$count дн.';
  }

  @override
  String refreshIntervalHoursShort(int count) {
    return '$count ч.';
  }

  @override
  String refreshIntervalMinutesShort(int count) {
    return '$count мин.';
  }

  @override
  String get happCrypt5Supported => 'Поддерживается';

  @override
  String get happCrypt5Unsupported => 'Не поддерживается';

  @override
  String get happCrypt5Checking =>
      'Проверяем поддержку декрипта happ://crypt5/...';

  @override
  String get happCrypt5SupportedDescription =>
      'Ваше устройство умеет расшифровывать Happ crypt5 crypto link прямо в приложении.';

  @override
  String get happCrypt5UnsupportedDescription =>
      'На этом устройстве декрипт Happ crypt5 сейчас недоступен.';

  @override
  String get subscriptionLikelyRequiresHwidTitle => 'Похоже, нужен HWID';

  @override
  String get subscriptionLikelyRequiresHwidWarning =>
      'Похоже, эта подписка требует HWID. Сервер вернул только один outbound с app/HWID в названии. Открой настройки подписки и включи отправку HWID.';

  @override
  String get subscriptionLikelyRequiresHwidMessage =>
      'Сервер вернул только один outbound, и его название похоже на заглушку про app или HWID.\n\nОбычно это значит, что подписка ожидает HWID устройства в запросе.\n\nВключить отправку HWID сейчас и сразу обновить подписку?';

  @override
  String get subscriptionLikelyRequiresHwidAction => 'Включить HWID';

  @override
  String get subscriptionHwidEnabledAndUpdated =>
      'Отправка HWID включена. Подписка обновлена.';

  @override
  String get noValidOutboundsTitle => 'Нет рабочих узлов';

  @override
  String get noValidOutboundsWarning =>
      'В этой подписке не осталось ни одного рабочего outbound. Они были отфильтрованы во время валидации. Проверь подписку или обнови её.';

  @override
  String get noValidOutboundsMessage =>
      'В этой подписке не осталось ни одного рабочего outbound.\n\nВсе узлы были отфильтрованы во время валидации ещё до запуска, поэтому клиент не будет пытаться стартовать sing-box с пустым набором прокси.\n\nПроверь подписку, обнови её или импортируй корректную.';

  @override
  String get noValidOutboundsAfterDropInvalidWarning =>
      'В выбранной подписке не осталось ни одного рабочего outbound после drop invalid. Проверь подписку, похоже с ней что-то не так.';

  @override
  String get noValidOutboundsAfterDropInvalidMessage =>
      'Все оставшиеся узлы в выбранной подписке были отброшены как невалидные во время запуска.\n\nКлиент остановился до того, как передать сломанный конфиг в sing-box.\n\nПроверь содержимое подписки и обнови или замени её.';

  @override
  String get experimentalTcpFastOpenTitle => 'TCP Fast Open';

  @override
  String get experimentalTcpFastOpenSubtitle =>
      'Может ускорить TCP handshake, но зависит от сети и поддержки сервера.';

  @override
  String get experimentalTcpMultiPathTitle => 'TCP Multipath';

  @override
  String get experimentalTcpMultiPathSubtitle =>
      'Пробует несколько сетевых путей. Может помочь при смене сети, но иногда греет телефон или работает нестабильно.';

  @override
  String get experimentalInterruptConnectionsTitle =>
      'Рвать активные соединения при смене узла';

  @override
  String get experimentalInterruptConnectionsSubtitle =>
      'Быстрее применяет смену прокси, но старые соединения приложений могут оборваться.';

  @override
  String get experimentalUrlTestStrictToleranceTitle =>
      'URLTest tolerance 1 мс';

  @override
  String get experimentalUrlTestStrictToleranceSubtitle =>
      'Строже выбирает самый быстрый прокси, но может чаще переключать сервер.';

  @override
  String get tlsFragmentationTitle => 'TLS fragmentation';

  @override
  String get tlsFragmentationSubtitle =>
      'Фрагментирует TLS handshake у прокси-аутбаундов. Может помочь при DPI, но иногда замедляет подключение.';

  @override
  String get tlsFragmentationModeDisabled => 'Выключено';

  @override
  String get tlsFragmentationModeDisabledSubtitle =>
      'Не меняет TLS настройки серверов.';

  @override
  String get tlsFragmentationModeRecord => 'TLS record fragment';

  @override
  String get tlsFragmentationModeRecordSubtitle =>
      'Более мягкий режим. Сначала пробуй его.';

  @override
  String get tlsFragmentationModeFragment => 'TLS fragment';

  @override
  String get tlsFragmentationModeFragmentSubtitle =>
      'Более агрессивный режим с fallback delay 300 мс.';

  @override
  String get blockLeaksTitle => 'Исправить некоторые утечки';

  @override
  String get blockLeaksSubtitle =>
      'Блокирует только STUN/WebRTC-трафик, который может обходить прокси';

  @override
  String get addSubscriptionCaption => 'Добавьте подписку по ссылке или файлу';

  @override
  String get pasteSubscriptionLink => 'Вставьте ссылку подписки';

  @override
  String get orManually => 'Или вручную';

  @override
  String get pasteAction => 'Вставить';

  @override
  String get cancelAction => 'Отмена';

  @override
  String get backupTitle => 'Данные и резервная копия';

  @override
  String get backupSubtitle =>
      'Экспорт настроек и перенос подписок без лишнего риска';

  @override
  String get backupExportSettings => 'Экспортировать настройки';

  @override
  String get backupExportSettingsSubtitle =>
      'Сохраняет только безопасные настройки клиента, без подписок и ключей';

  @override
  String get backupExportProfileEncrypted =>
      'Экспортировать подписки с паролем';

  @override
  String get backupExportProfileEncryptedSubtitle =>
      'Рекомендуется. Подписки, выбранные узлы и raw-данные шифруются AES-256-GCM';

  @override
  String get backupExportProfilePlain =>
      'Экспортировать подписки без шифрования';

  @override
  String get backupExportProfilePlainSubtitle =>
      'Только для доверенной локальной передачи. Файл содержит VPN-ключи';

  @override
  String get backupImportFile => 'Импортировать файл Etonify';

  @override
  String get backupImportFileSubtitle =>
      'Поддерживает .etonify-settings.json и .etonify-profile из Etonify 0.2.0+';

  @override
  String get backupPlainWarningTitle => 'Файл будет содержать VPN-ключи';

  @override
  String get backupPlainWarningMessage =>
      'Незашифрованный экспорт сможет прочитать любой, кто получит файл. Используйте шифрование, если не полностью доверяете месту хранения и передаче.';

  @override
  String get backupPlainImportTitle => 'Незашифрованный профиль';

  @override
  String get backupPlainImportMessage =>
      'Этот файл содержит подписки и VPN-ключи без шифрования. Импортируйте только если доверяете источнику.';

  @override
  String get backupPasswordCreateTitle => 'Создайте пароль для экспорта';

  @override
  String get backupPasswordEnterTitle => 'Введите пароль профиля';

  @override
  String get backupPasswordHint => 'Пароль';

  @override
  String get backupSaved => 'Файл резервной копии сохранён';

  @override
  String get backupImported => 'Импорт завершён';

  @override
  String get backupUnsupportedVersion =>
      'Этот формат резервной копии не поддерживается этой версией клиента.';

  @override
  String get backupNewerVersionTitle => 'Файл из более новой версии клиента';

  @override
  String backupNewerVersionMessage(String version) {
    return 'Этот файл создан в Etonify $version. Некоторые настройки могут примениться не полностью. Продолжить?';
  }

  @override
  String get splitRoutingEmptyWhitelist =>
      'Выберите хотя бы одно приложение или отключите раздельную маршрутизацию перед запуском VPN.';

  @override
  String get connectionStagePreparing => 'Подготовка VPN';

  @override
  String get connectionStageConfiguring => 'Сборка конфига';

  @override
  String get connectionStageStarting => 'Запуск ядра';

  @override
  String get connectionStageStopping => 'Остановка VPN';

  @override
  String get connectionStageRecovering => 'Восстановление';

  @override
  String get connectionStageSelectingProxy => 'Выбор сервера';

  @override
  String get vpnStartTimedOut =>
      'VPN не запустился за 15 секунд. Запуск остановлен.';

  @override
  String get vpnStartFailed => 'Не удалось запустить VPN.';
}

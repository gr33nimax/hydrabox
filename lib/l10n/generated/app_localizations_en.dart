// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get profiles => 'Profiles';

  @override
  String get close => 'Close';

  @override
  String get homeTab => 'Home';

  @override
  String get proxiesTab => 'Proxies';

  @override
  String get proxiesTitle => 'Proxies';

  @override
  String get proxySwitching => 'Switching';

  @override
  String get proxySelectorTitle => 'Selector';

  @override
  String get shareProxyTitle => 'Share';

  @override
  String get shareProxyLinkLabel => 'Share link';

  @override
  String get shareSingboxOutboundLabel => 'sing-box outbound';

  @override
  String copiedToClipboard(String label) {
    return '$label copied';
  }

  @override
  String get unavailableForThisType => 'Unavailable for this type';

  @override
  String get sort => 'Sort';

  @override
  String get sortByDefault => 'Source order';

  @override
  String get sortByLatency => 'By latency';

  @override
  String get sortByName => 'By name';

  @override
  String get sortByCountry => 'By country';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get generalSectionTitle => 'General';

  @override
  String get inboundTitle => 'Inbound';

  @override
  String get dnsTitle => 'DNS';

  @override
  String get whitelistTitle => 'Whitelist';

  @override
  String get whitelistSubtitle => 'Reserved routing tools';

  @override
  String get experimentalTitle => 'Experimental';

  @override
  String get experimentalSubtitle =>
      'Multipath, Fast Open, and connection switching behavior';

  @override
  String get logsTitle => 'Logs';

  @override
  String get logsSubtitle => 'Generated sing-box config and app events';

  @override
  String get urlTestTitle => 'Server checks';

  @override
  String get urlTestSubtitle => 'Latency check and lowest selection';

  @override
  String get vpnInTitle => 'VPN In';

  @override
  String get proxyInTitle => 'Proxy In';

  @override
  String get dnsDirectTitle => 'Direct';

  @override
  String get dnsProxyTitle => 'Via proxy';

  @override
  String get dnsIpPreferenceTitle => 'IP version';

  @override
  String get aboutSectionTitle => 'About client';

  @override
  String get aboutSectionSubtitle =>
      'Client version, core, team, and service information.';

  @override
  String get aboutHeroSubtitle =>
      'Android VPN client focused on speed, stability, and a clean daily experience.';

  @override
  String get aboutDevelopedBy => 'Developed by MeowTeam.';

  @override
  String get aboutCoreSourceLabel => 'core source code';

  @override
  String get telegramChannelLabel => 'Etonify Telegram';

  @override
  String get legalTermsTitle => 'Terms of Use';

  @override
  String get legalPrivacyTitle => 'Privacy Policy';

  @override
  String get legalTermsSummary =>
      'Rules for responsible use and project disclaimers.';

  @override
  String get legalPrivacySummary =>
      'What Etonify stores locally and what it does not collect.';

  @override
  String get legalGateTitle => 'Before using Etonify';

  @override
  String legalGateSubtitle(String version) {
    return 'Starting with version $version, please read and accept the Terms and Privacy Policy to continue.';
  }

  @override
  String get legalAcceptAction => 'Accept and continue';

  @override
  String get legalAcceptHint => 'Open both documents to enable continue.';

  @override
  String get legalDocumentReadAction => 'I have read it';

  @override
  String get legalContactAction => 'Contact';

  @override
  String get legalImportBlockedMessage =>
      'Accept Terms and Privacy Policy before importing subscriptions.';

  @override
  String get legalTermsBody =>
      '# Etonify Terms of Use\n\nEtonify is an Android VPN client made by MeowTeam for private, everyday network access. The app does not provide VPN servers by itself. You are responsible for the subscriptions, profiles, and servers you add.\n\nUse Etonify only in a legal and responsible way. Do not use the client for fraud, attacks, harassment, malware distribution, or other illegal activity. MeowTeam is not responsible for how users apply third-party VPN profiles or network access.\n\nEtonify is provided as-is. We work on stability and security, but we cannot guarantee that every provider, route, DNS resolver, network, or Android firmware will behave perfectly. If something breaks, send feedback through the official Telegram channel or the contacts on the MeowTeam page.\n\nSome features need Android permissions: VPN service creates the system VPN tunnel, camera scans QR codes, notifications show service state, package visibility helps split tunneling, and APK install permission is used only for user-requested updates.\n\nBy continuing, you confirm that you understand these rules and accept responsibility for your own use of the client.';

  @override
  String get legalPrivacyBody =>
      '# Etonify Privacy Policy\n\nEtonify does not include analytics, advertising SDKs, or hidden tracking. MeowTeam does not sell your data and does not collect your VPN keys on our servers.\n\nYour subscriptions, imported profiles, selected server, settings, and logs are stored locally on your device. Some backup/export features can create files that contain VPN keys. Keep exported profiles private, especially if you export without password encryption.\n\nWhen you import or refresh a subscription, Etonify connects directly to the URL you provided. A Happ subscription may require HWID and a Happ user agent; Etonify asks before sending HWID.\n\nLogs are meant for troubleshooting. We try to redact secrets before showing or exporting logs, but you should still review exported logs before sharing them publicly.\n\nIf you have questions or want something removed from feedback you sent manually, contact us through the official Telegram channel or MeowTeam contacts.';

  @override
  String get coreVersionLabel => 'Core version';

  @override
  String get debugMenuTitle => 'Debug';

  @override
  String get debugMenuSubtitle =>
      'Hidden area for debugging and service actions.';

  @override
  String get debugNetworkHeartbeatTitle => 'Network heartbeat';

  @override
  String debugNetworkHeartbeatSubtitle(int seconds) {
    return 'Re-asserts the default network if Android misses callbacks. Current interval: ${seconds}s. Applies on next VPN start.';
  }

  @override
  String get debugWakeLockTitle => 'Partial wake lock';

  @override
  String get debugWakeLockSubtitle =>
      'Keeps CPU awake while VPN runs. Off by default because it can heat the phone on aggressive firmware.';

  @override
  String get debugRecordSnapshot => 'Record performance snapshot';

  @override
  String get debugSnapshotDone => 'Performance snapshot added to logs';

  @override
  String get teamPageTitle => 'MeowTeam';

  @override
  String get teamIntroTitle => 'The team behind Etonify';

  @override
  String get teamIntroBody =>
      'We are a small team building our own VPN client and improving it step by step.';

  @override
  String get teamTimelineForkTitle => 'Started as a Hiddify fork';

  @override
  String get teamTimelineForkBody =>
      'The early client inherited the UI and a large legacy codebase from Hiddify. A few test versions helped us understand what had to change.';

  @override
  String get teamTimelineRefactorTitle => 'Large refactor';

  @override
  String get teamTimelineRefactorBody =>
      'The old backend carried too much technical debt, patches, dead code, and behavior that was hard to maintain. We moved the client through a deep refactor and rebuilt the runtime layer around a cleaner Android-first flow.';

  @override
  String get teamTimelineCoreTitle => 'MeowSingBox core';

  @override
  String get teamTimelineCoreBody =>
      'The app uses a modified sing-box core with extra work around URLTest, connection cleanup, and resource handling.';

  @override
  String get teamTimelineNowTitle => 'Etonify today';

  @override
  String get teamTimelineNowBody =>
      'Etonify is still evolving: we keep simplifying UX, improving Android stability, and cutting technical debt without losing the speed-focused VPN experience.';

  @override
  String get teamDeveloperDdosxdRole => 'MeowTeam developer';

  @override
  String get teamDeveloperYamixdevRole => 'MeowTeam developer';

  @override
  String get teamTelegramRole => 'Official channel and release news';

  @override
  String get languageSettingTitle => 'Language';

  @override
  String get themeSettingTitle => 'Theme';

  @override
  String get accentColorTitle => 'Accent color';

  @override
  String get appearanceTitle => 'Appearance';

  @override
  String get languageSystem => 'System';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageRussian => 'Russian';

  @override
  String get themeSystem => 'System';

  @override
  String get themeLight => 'Light';

  @override
  String get themeDark => 'Dark';

  @override
  String get themeAmoled => 'AMOLED';

  @override
  String get aboutResourcesTitle => 'Resources';

  @override
  String get aboutResourcesSubtitle =>
      'On-demand Android snapshot. It is not collected in the background.';

  @override
  String get aboutResourcePss => 'Memory';

  @override
  String get aboutResourceNativeHeap => 'Native heap';

  @override
  String get aboutResourceJavaHeap => 'Java heap';

  @override
  String get aboutResourceSystemMemory => 'Free system RAM';

  @override
  String get aboutResourceBatteryTemp => 'Battery temperature';

  @override
  String get updatesTitle => 'Updates';

  @override
  String get updatesSubtitle =>
      'Check GitHub Releases and download the matching APK.';

  @override
  String get updatesChecking => 'Checking for updates…';

  @override
  String get updatesCheckAction => 'Check now';

  @override
  String get updatesRetryAction => 'Retry';

  @override
  String get updatesDownloadAction => 'Download update';

  @override
  String get updatesInstallAction => 'Install APK';

  @override
  String get updatesDownloadWarning =>
      'Keep Etonify open until the download finishes.';

  @override
  String get updatesOpeningInstaller => 'Opening the system installer…';

  @override
  String get updatesInstallPermissionHint =>
      'Allow APK installs for Etonify, then tap “Install APK” again.';

  @override
  String get updatesInstallPermissionTitle => 'Permission required';

  @override
  String get updatesInstallPermissionMessage =>
      'Allow Etonify to install unknown apps before it can open the downloaded APK installer. Without this permission you can only download the file manually.';

  @override
  String get updatesInstallPermissionOpen => 'Open settings';

  @override
  String get updatesInstallPermissionGranted =>
      'APK install permission is enabled.';

  @override
  String get updatesInstallModeTitle => 'Update installation';

  @override
  String get updatesInstallModeAsk => 'Ask every time';

  @override
  String get updatesInstallModeAskSubtitle =>
      'Etonify will ask whether to download manually or install automatically.';

  @override
  String get updatesInstallModeManual => 'Manual';

  @override
  String get updatesInstallModeManualSubtitle =>
      'The client downloads the APK and shows an install button.';

  @override
  String get updatesInstallModeAuto => 'Automatic';

  @override
  String get updatesInstallModeAutoSubtitle =>
      'The client downloads the APK and opens the Android installer.';

  @override
  String get updatesInstallMethodTitle =>
      'How should this update be installed?';

  @override
  String get updatesInstallMethodManualTitle => 'Download manually';

  @override
  String get updatesInstallMethodManualSubtitle =>
      'The APK is saved in the update cache. You can install it later.';

  @override
  String get updatesInstallMethodAutoTitle => 'Download and install';

  @override
  String get updatesInstallMethodAutoSubtitle =>
      'After download, Etonify opens the Android system installer.';

  @override
  String get updatesInstallMethodRemember => 'Remember this choice';

  @override
  String get updatesApkVerificationTitle => 'APK check';

  @override
  String get updatesApkVerificationVerified => 'SHA-256 matches';

  @override
  String get updatesApkVerificationUnavailable =>
      'SHA-256 is not provided by this release';

  @override
  String get updatesApkVerificationFailed => 'SHA-256 does not match';

  @override
  String get updatesDownloadedFileMissing =>
      'The update file is missing. Download the APK again.';

  @override
  String get updatesDeleteCachedApkAction => 'Delete installer APK';

  @override
  String get updatesDeleteCachedApkTitle => 'Delete installer APK?';

  @override
  String updatesDeleteCachedApkMessage(Object version) {
    return 'This will delete the downloaded $version update APK and old temporary Etonify APK files from the app cache.';
  }

  @override
  String updatesDeleteCachedApkDone(int count) {
    return 'Update cache cleaned. Files deleted: $count.';
  }

  @override
  String get updatesUpToDateTitle => 'Etonify is up to date';

  @override
  String updatesUpToDateSubtitle(String version) {
    return 'Installed version: $version';
  }

  @override
  String get updatesAvailableTitle => 'Update available';

  @override
  String updatesAvailableSubtitle(String version, String size) {
    return '$version · $size';
  }

  @override
  String get updatesAvailableSnack => 'Client update available';

  @override
  String updatesAvailableSnackVersion(Object version) {
    return 'Client update $version is available';
  }

  @override
  String get updatesOpenAction => 'Open';

  @override
  String get updatesDownloadingTitle => 'Downloading update';

  @override
  String get updatesDownloadedTitle => 'Update downloaded';

  @override
  String updatesDownloadedSubtitle(String fileName) {
    return 'Saved to app update cache: $fileName';
  }

  @override
  String get updatesErrorTitle => 'Could not check updates';

  @override
  String get updatesErrorSubtitle =>
      'If GitHub is blocked on this network, Etonify will try again tomorrow.';

  @override
  String get updatesCurrentVersion => 'Current version';

  @override
  String get updatesLatestVersion => 'Latest version';

  @override
  String get updatesAsset => 'APK';

  @override
  String updatesLastChecked(String time) {
    return 'Last checked: $time';
  }

  @override
  String get updatesReleaseNotesTitle => 'What\'s new';

  @override
  String get updatesNoReleaseNotes => 'This release does not include notes.';

  @override
  String updatesProgressBytes(String downloaded, String total) {
    return '$downloaded / $total';
  }

  @override
  String updatesProgressSpeedEta(String speed, String eta) {
    return '$speed/s · $eta left';
  }

  @override
  String updatesEtaSeconds(int seconds) {
    return '${seconds}s';
  }

  @override
  String updatesEtaMinutes(int minutes, int seconds) {
    return '${minutes}m ${seconds}s';
  }

  @override
  String get updatesUnknownSize => 'Unknown size';

  @override
  String get appVersionLabel => 'Client version';

  @override
  String get currentProfileLabel => 'Current profile';

  @override
  String get selectedProxyLabel => 'Selected proxy';

  @override
  String get onboardingStatusLabel => 'Intro';

  @override
  String get onboardingSeen => 'Completed';

  @override
  String get showOnboardingAgain => 'Show intro again';

  @override
  String get settingsFootnote =>
      'These settings are local to this device and are stored in Hive.';

  @override
  String get connected => 'Connected';

  @override
  String get tapToConnect => 'Tap to Connect';

  @override
  String get resolvingIp => 'Resolving IP…';

  @override
  String get millisecondsUnit => ' ms';

  @override
  String get refreshLatency => 'Refresh latency';

  @override
  String get checkingLatency => 'Checking latency';

  @override
  String get checkingLatencyShort => 'Checking…';

  @override
  String get openTrafficDashboard => 'Open traffic dashboard';

  @override
  String get refreshActiveSubscription => 'Refresh current subscription';

  @override
  String get refreshActiveSubscriptionUnavailable =>
      'Manual imports cannot be refreshed';

  @override
  String activeSubscriptionRefreshComplete(String name) {
    return '$name updated';
  }

  @override
  String get trafficDashboardTitle => 'Traffic dashboard';

  @override
  String get trafficDashboardSubtitle =>
      'Live speed, session totals, and connection info';

  @override
  String get trafficDashboardDownload => 'Download';

  @override
  String get trafficDashboardUpload => 'Upload';

  @override
  String get trafficDashboardSessionTraffic => 'Session traffic';

  @override
  String get trafficDashboardConnectedFor => 'Connected for';

  @override
  String get trafficDashboardGraphTitle => 'Live traffic';

  @override
  String trafficDashboardGraphMax(String speed) {
    return 'Peak $speed';
  }

  @override
  String get trafficDashboardNoSamples => 'Waiting for traffic data';

  @override
  String get trafficDashboardConnectionState => 'Connection';

  @override
  String get trafficDashboardCurrentProfile => 'Profile';

  @override
  String get trafficDashboardActiveProxy => 'Proxy';

  @override
  String get trafficDashboardServerIp => 'Server IP';

  @override
  String get trafficDashboardDownloadTotal => 'Downloaded';

  @override
  String get trafficDashboardUploadTotal => 'Uploaded';

  @override
  String get trafficDashboardStateConnected => 'Connected';

  @override
  String get trafficDashboardStateConnecting => 'Connecting';

  @override
  String get trafficDashboardStateDisconnected => 'Disconnected';

  @override
  String trafficDashboardUptimeHours(int hours, int minutes) {
    return '$hours h $minutes min';
  }

  @override
  String trafficDashboardUptimeMinutes(int minutes, int seconds) {
    return '$minutes min $seconds s';
  }

  @override
  String trafficDashboardUptimeSeconds(int seconds) {
    return '$seconds s';
  }

  @override
  String get notAvailableShort => 'N/A';

  @override
  String daysLeft(int days) {
    return '$days days left';
  }

  @override
  String get daysLeftUnlimited => '∞ days left';

  @override
  String get unlimitedTraffic => 'Unlimited';

  @override
  String get unlimitedSymbol => '∞';

  @override
  String get welcomeGreeting => 'Hi';

  @override
  String get welcomeTitlePrefix => 'Welcome to';

  @override
  String get welcomeSubtitle => 'Fast Android VPN client';

  @override
  String get welcomeTapHint => 'tap anywhere to continue';

  @override
  String get hapticTitle => 'Vibration';

  @override
  String get hapticSubtitle => 'Light vibration for important actions';

  @override
  String get hideServerIpTitle => 'Hide server IP';

  @override
  String get hideServerIpSubtitle => 'Masks last two octets of the IP address';

  @override
  String get performanceModeTitle => 'Performance mode';

  @override
  String get performanceModeCool => 'Cool';

  @override
  String get performanceModeStandard => 'Standard';

  @override
  String get performanceModeEconomy => 'Economy';

  @override
  String get performanceModeBalanced => 'Balanced';

  @override
  String get performanceModePerformance => 'Performance';

  @override
  String get performanceModeCoolSubtitle =>
      'Lowest heat and background load for daily Android use.';

  @override
  String get performanceModeStandardSubtitle =>
      'Stable daily mode: automatic ping every 5 minutes, moderate concurrency, and less background load.';

  @override
  String get performanceModeEconomySubtitle =>
      'Minimum extra background work: automatic ping every 5 minutes, fewer parallel checks, and no automatic server geolocation.';

  @override
  String get performanceModeBalancedSubtitle =>
      'Moderate checks and battery use.';

  @override
  String get performanceModePerformanceSubtitle =>
      'Faster checks with more CPU, traffic, and heat.';

  @override
  String get performanceModeRecommendation =>
      'Recommended: keep Standard. Use Economy when battery life matters more than fast background checks.';

  @override
  String get memoryLimitTitle => 'Memory limit';

  @override
  String get memoryLimitEnabledSubtitle =>
      'Recommended. Lets sing-box stop before memory pressure can destabilize the app. Changes take effect after app restart.';

  @override
  String get memoryLimitDisabledSubtitle =>
      'Disabled. Can help with false memory-limit errors, but may increase RAM use and crash risk. Takes effect after app restart.';

  @override
  String get memoryLimitDisableWarningTitle => 'Disable memory limit?';

  @override
  String get memoryLimitDisableWarningMessage =>
      'Use this only if VPN start fails with a memory-limit error. Disabling the limit can increase RAM usage, heat, and the chance Android kills the app. The change takes effect after restarting Etonify.';

  @override
  String get memoryLimitDisableConfirm => 'Disable';

  @override
  String get enableInboundTitle => 'Enabled';

  @override
  String get vpnInDescription =>
      'VPN TUN is the Android system VPN path for phone traffic. Apps see an Android VPN, while routing decides what goes through proxy or direct.';

  @override
  String get vpnInboundEnabledSubtitle =>
      'Creates a VPN TUN inbound and routes traffic through it';

  @override
  String get inboundNoneEnabled =>
      'Enable VPN TUN or Proxy In before starting.';

  @override
  String get mtuTitle => 'MTU';

  @override
  String get mtuSubtitle => 'TUN interface packet size';

  @override
  String get strictRouteTitle => 'Prevent VPN bypass';

  @override
  String get strictRouteSubtitle =>
      'Forces traffic through VPN and reduces the chance of traffic escaping the tunnel';

  @override
  String get tunImplementationTitle => 'TUN implementation';

  @override
  String get tunImplementationSubtitle =>
      'How the client handles the TUN stack';

  @override
  String get tunImplementationMixed => 'Mixed';

  @override
  String get tunImplementationMixedSubtitle =>
      'Automatic mode. Uses the safer stack for the current device and config.';

  @override
  String get tunImplementationSystem => 'System';

  @override
  String get tunImplementationSystemSubtitle =>
      'Android system stack. Usually lighter, but may depend on device firmware.';

  @override
  String get tunImplementationGvisor => 'gVisor';

  @override
  String get tunImplementationGvisorSubtitle =>
      'Userspace network stack. Can be more compatible, but may cost more CPU.';

  @override
  String get proxyInDescription =>
      'Proxy In / mixed is a local HTTP/SOCKS entry for apps or other devices that you configure manually. It is not the Android system VPN.';

  @override
  String get proxyInboundEnabledSubtitle =>
      'Starts a local mixed inbound for apps and devices';

  @override
  String get allowLanConnectionsTitle => 'Allow LAN connections';

  @override
  String get allowLanConnectionsSubtitle =>
      'If enabled, listen on 0.0.0.0, otherwise on 127.0.0.1';

  @override
  String get portTitle => 'Port';

  @override
  String get proxyPortSubtitle => 'Local mixed inbound port';

  @override
  String get dnsUsePresetTitle => 'Use preset';

  @override
  String get dnsResolverTitle => 'Resolver';

  @override
  String get dnsDirectPresetSubtitle => 'Recommended: udp://1.1.1.1';

  @override
  String get dnsDirectResolverSubtitle =>
      'DNS for direct requests without proxy';

  @override
  String get dnsRussiaDirectTitle => 'DNS for Russia routes';

  @override
  String get dnsRussiaDirectSubtitle =>
      'Used only when Russia routes are enabled. Russian domains resolve directly through this DNS so sites and apps reach direct routing faster.';

  @override
  String get dnsRussiaDirectResolverSubtitle =>
      'Default: udp://77.88.8.8. Keep a fast Russian DNS when using “all except RU through VPN”.';

  @override
  String get dnsProxyPresetSubtitle =>
      'Recommended: https://dns.cloudflare.com/dns-query';

  @override
  String get dnsProxyResolverSubtitle => 'DNS for requests through proxy';

  @override
  String get dnsResolverTypeTitle => 'Resolver type';

  @override
  String get dnsPresetDevice => 'Device network';

  @override
  String get dnsPresetCustom => 'Custom';

  @override
  String get dnsPresetDeviceSubtitle =>
      'Use DNS from the current Android network.';

  @override
  String get dnsPresetCustomSubtitle =>
      'Enter your own resolver: udp://, tcp://, tls://, or https://.';

  @override
  String get dnsPresetUdpSubtitle => 'Plain UDP DNS. Fast, but not encrypted.';

  @override
  String get dnsPresetTcpSubtitle =>
      'Plain TCP DNS. More stable on some networks, but not encrypted.';

  @override
  String get dnsPresetTlsSubtitle => 'DNS over TLS. Encrypted DNS on port 853.';

  @override
  String get dnsPresetHttpsSubtitle =>
      'DNS over HTTPS. Encrypted DNS over HTTPS, often best through proxy.';

  @override
  String get dnsPreferIpv6Title => 'Prefer IPv6';

  @override
  String get dnsPreferIpv6Subtitle =>
      'Prefer IPv6 when both address versions are available';

  @override
  String get urlTestUrlTitle => 'Test URL';

  @override
  String get urlTestUrlSubtitle =>
      'If the subscription already defines a value, that value is used';

  @override
  String get urlTestIntervalTitle => 'Interval, sec.';

  @override
  String get urlTestIntervalSubtitle =>
      'How often proxies are checked for lowest';

  @override
  String get urlTestTimeoutTitle => 'Timeout, sec.';

  @override
  String get urlTestTimeoutSubtitle =>
      'How long to wait for one proxy test before failing it';

  @override
  String get urlTestConcurrencyTitle => 'Test concurrency';

  @override
  String get urlTestConcurrencySubtitle =>
      'How many proxies URLTest checks at the same time';

  @override
  String get urlTestSingleRetestTitle => 'Quick retry delay, sec.';

  @override
  String get urlTestSingleRetestSubtitle =>
      'How long to wait before one quick recheck after a proxy fails';

  @override
  String get locationLookupTitle => 'Locations';

  @override
  String get locationLookupSubtitle =>
      'IP and country through the proxies themselves';

  @override
  String get locationLookupLimitTitle => 'Check best proxies';

  @override
  String get locationLookupLimitSubtitle =>
      'After URLTest, the app resolves external IP and country for this many fastest outbounds';

  @override
  String get locationLookupTimeoutTitle => 'Request timeout';

  @override
  String get locationLookupTimeoutSubtitle =>
      'How long to wait for external IP and country for one server';

  @override
  String get locationLookupConcurrencyTitle => 'Parallel requests';

  @override
  String get locationLookupConcurrencySubtitle =>
      'How many location requests may run at the same time';

  @override
  String settingsSecondsShort(int seconds) {
    return '${seconds}s';
  }

  @override
  String get serverRequestTitle => 'Server request';

  @override
  String get sendHwidTitle => 'Send HWID';

  @override
  String get sendHwidSubtitle =>
      'Adds the device HWID to the subscription request';

  @override
  String get useCustomHwidTitle => 'Use custom HWID';

  @override
  String get useCustomHwidSubtitle =>
      'Override the device HWID with your own value';

  @override
  String get customUserAgentTitle => 'Custom User-Agent';

  @override
  String get customUserAgentSubtitle =>
      'Overrides the default Etonify user agent for this subscription';

  @override
  String get customHwidTitle => 'Custom HWID';

  @override
  String get customHwidSubtitle => 'Used only when custom HWID is enabled';

  @override
  String get customRequestHeadersTitle => 'Custom headers';

  @override
  String get customRequestHeadersSubtitle =>
      'One header per line in Header: value format';

  @override
  String get hwidTitle => 'HWID';

  @override
  String get hwidSubtitle =>
      'Your device identifier used by some subscription providers';

  @override
  String get hwidValueTitle => 'Your HWID';

  @override
  String get coreStartFailedTitle => 'Failed to start core';

  @override
  String coreStartFailedMessage(String message) {
    return 'sing-box failed to start.\n\n$message';
  }

  @override
  String get vpnStopFailed =>
      'VPN did not stop completely. Open logs and try again.';

  @override
  String get clearLogsTitle => 'Clear logs';

  @override
  String get logsFilterTitle => 'Filter';

  @override
  String get logsFilterAll => 'All';

  @override
  String get singBoxLogLevelTitle => 'sing-box log level';

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
  String get noLogsTitle => 'No logs yet';

  @override
  String get continueLabel => 'Get started';

  @override
  String get subscriptionsTab => 'Subscriptions';

  @override
  String get subscriptionsTitle => 'Subscriptions';

  @override
  String get settingsProfilesChecksTitle => 'Profiles and checks';

  @override
  String get settingsProfilesChecksSubtitle =>
      'Server checks · HWID · profile options';

  @override
  String get addSubscription => 'Add subscription';

  @override
  String get addSubscriptionQuickTitle => 'Add profile';

  @override
  String get addSubscriptionQuickSubtitle =>
      'Choose how to import a subscription.';

  @override
  String get addSubscriptionFromClipboard => 'Clipboard';

  @override
  String get addSubscriptionManual => 'Manual';

  @override
  String get addSubscriptionReadingClipboard => 'Reading clipboard…';

  @override
  String get addSubscriptionReadingFile => 'Reading file…';

  @override
  String get addSubscriptionImporting => 'Importing subscription…';

  @override
  String get addSubscriptionSaving => 'Saving profile…';

  @override
  String get addSubscriptionDone => 'Subscription added';

  @override
  String get clipboardEmpty => 'Clipboard is empty';

  @override
  String get scanQrCode => 'Scan QR';

  @override
  String get showQrCode => 'Show QR';

  @override
  String get subscriptionQrTitle => 'Subscription QR';

  @override
  String get subscriptionQrHint =>
      'Scan this code on another device to import the subscription.';

  @override
  String get subscriptionQrUnsupported =>
      'This subscription cannot be shared as QR yet.';

  @override
  String get invalidQrSubscription =>
      'The QR code does not contain a supported subscription link.';

  @override
  String get subscriptionUrl => 'Subscription URL';

  @override
  String get subscriptionUrlOrContent => 'URL or content';

  @override
  String get subscriptionUrlOrContentHint =>
      'Paste a URL, vless:// link, link list, or config';

  @override
  String get importFromFile => 'From file';

  @override
  String get invalidSubscriptionFile => 'Failed to read the subscription file';

  @override
  String get subscriptionName => 'Name (optional)';

  @override
  String get add => 'Add';

  @override
  String get cancel => 'Cancel';

  @override
  String get delete => 'Delete';

  @override
  String get refresh => 'Refresh';

  @override
  String get reparseProxies => 'Reparse proxies';

  @override
  String get subscriptionLocalImportBadge => 'Local import';

  @override
  String get refreshAll => 'Refresh all';

  @override
  String subscriptionsRefreshAllComplete(int updated, int failed) {
    return 'Updated $updated subscriptions, $failed failed';
  }

  @override
  String get deleteSubscription => 'Delete subscription?';

  @override
  String get deleteSubscriptionConfirm =>
      'This will remove all proxies from this subscription.';

  @override
  String get subscriptionDetailsTitle => 'Subscription';

  @override
  String get subscriptionMovedTitle => 'Subscription moved';

  @override
  String get ignoreAction => 'Ignore';

  @override
  String get updateUrlAction => 'Update URL';

  @override
  String get autoUpdateTitle => 'Auto update';

  @override
  String get disableAutoUpdateTitle => 'Disable auto update';

  @override
  String get disabledLabel => 'Disabled';

  @override
  String refreshesEvery(String interval) {
    return 'Refreshes every: $interval';
  }

  @override
  String get usageTitle => 'Usage';

  @override
  String spentTraffic(String usage) {
    return 'Spent $usage';
  }

  @override
  String untilDate(String date) {
    return 'Until $date';
  }

  @override
  String get infoTitle => 'Information';

  @override
  String get supportUrlLabel => 'Support';

  @override
  String get websiteLabel => 'Website';

  @override
  String get newUrlTitle => 'NewURL';

  @override
  String get movedSubscriptionMessage =>
      'The server reported that this subscription moved to a new URL.';

  @override
  String get movedSubscriptionPrompt =>
      'The server reports a new subscription URL. Update it now or keep the current one?';

  @override
  String get noSubscriptions => 'No subscriptions yet';

  @override
  String get noProxies => 'No proxies';

  @override
  String get noSubscriptionsHint => 'Tap + to add a subscription URL';

  @override
  String outboundsCount(int count) {
    return '$count proxies';
  }

  @override
  String subscriptionServersCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count servers',
      one: '$count server',
    );
    return '$_temp0';
  }

  @override
  String get subscriptionReparseRecommended => 'Reparse needed';

  @override
  String get subscriptionProxyTypeLabel => 'Proxies';

  @override
  String moreProxies(int count) {
    return '…$count more proxies';
  }

  @override
  String lastUpdated(String time) {
    return 'Updated $time';
  }

  @override
  String trafficUsage(String used, String total) {
    return '$used / $total';
  }

  @override
  String get expired => 'Expired';

  @override
  String get loading => 'Loading…';

  @override
  String get error => 'Error';

  @override
  String get invalidUrl => 'Please enter a valid URL';

  @override
  String get fetchFailed => 'Failed to fetch subscription';

  @override
  String get subscriptionSavedWithFetchWarning =>
      'The subscription was saved, but the server did not respond. You can change HWID or headers and refresh it later.';

  @override
  String get sourceLabel => 'Source';

  @override
  String importedFromFileLabel(String name) {
    return 'Imported from file: $name';
  }

  @override
  String get deepLinkImportTitle => 'Import subscription';

  @override
  String get deepLinkImportMessage =>
      'Do you really want to import this subscription?';

  @override
  String get deepLinkImportNameLabel => 'Name';

  @override
  String get deepLinkImportAction => 'Import';

  @override
  String get deepLinkImportSourceLabel => 'Source link';

  @override
  String get deepLinkImportResolvedUrlLabel => 'Resolved subscription URL';

  @override
  String get deepLinkImportHappBadge => 'Happ subscription';

  @override
  String get deepLinkImportHappNotice =>
      'This subscription is intended for the Happ app and may require your device HWID. Etonify will send the HWID and Happ User-Agent only if you confirm this import.';

  @override
  String get deepLinkImportHappSendHwidAction => 'Send HWID and import';

  @override
  String get deepLinkImportHappWithoutHwidAction => 'Import without HWID';

  @override
  String get deepLinkImportHappCancelAction => 'Do not import';

  @override
  String get deepLinkImportUserAgentLabel => 'User-Agent';

  @override
  String get deepLinkImportHwidLabel => 'HWID';

  @override
  String get deepLinkImportHwidValue => 'Will be sent only after confirmation';

  @override
  String deepLinkImportSuccess(String name) {
    return 'Subscription \"$name\" imported';
  }

  @override
  String get happCryptoLinkImportedLabel => 'Imported via Happ Crypto Link';

  @override
  String get happCryptoLinkTitle => 'Happ Crypto Link';

  @override
  String get happCryptUnsupportedTitle => 'Happ crypt5';

  @override
  String get happCryptUnsupportedMessage =>
      'This Happ Crypto Link version is not supported yet.';

  @override
  String get happImportTitle => 'Happ subscription';

  @override
  String get happImportMessage =>
      'This subscription is intended for the Happ app and may require your device HWID. You can send HWID now, import without HWID, or cancel. If the provider requires HWID, importing without it may show placeholder nodes about an unsupported device.';

  @override
  String get subscriptionOperationSlowWarning =>
      'The subscription server is taking longer than usual. Check the link or network if this keeps happening.';

  @override
  String get subscriptionOperationTimeout =>
      'The subscription server did not respond in time. Check the link or network and try again.';

  @override
  String get continueAction => 'Continue';

  @override
  String get routingTitle => 'Routing';

  @override
  String get routingSubtitle => 'Traffic routing rules';

  @override
  String get bypassLocalNetworkTitle => 'Bypass local network';

  @override
  String get bypassLocalNetworkSubtitle =>
      'Route private and LAN addresses directly';

  @override
  String get russiaRoutesTitle => 'Russia routes';

  @override
  String get russiaRoutesRunetFreedomBadge => 'runetfreedom';

  @override
  String get russiaRoutesDomainListBadge => 'domain-list-community';

  @override
  String get russiaRoutesSubtitle =>
      'The client downloads the live runetfreedom sing-box.zip, verifies required rule-set files, and uses the bundled fallback if it fails.';

  @override
  String get russiaRoutesInstallAction => 'Prepare';

  @override
  String get russiaRoutesReinstallAction => 'Update';

  @override
  String get russiaRoutesUpdateAction => 'Update';

  @override
  String get russiaRoutesEnableTitle => 'Use Russia routes';

  @override
  String get russiaRoutesEnabledSubtitle =>
      'Required routes will be applied automatically: reachable Russian services go direct, everything else stays on VPN.';

  @override
  String get russiaRoutesMissingSubtitle =>
      'Prepare the route package first in order to use it.';

  @override
  String get russiaRoutesPreparingStatus => 'Preparing local route files...';

  @override
  String get russiaRoutesMissingStatus => 'Local routes are not prepared yet';

  @override
  String get russiaRoutesMissingHint =>
      'The client will download runetfreedom sing-box.zip, verify required `.srs`, and use the bundled fallback if needed.';

  @override
  String russiaRoutesReadyStatus(String versionTag) {
    return 'Routes are ready, version: $versionTag';
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
    return 'Source: $source · verified: $verifiedAt · files: $fileCount';
  }

  @override
  String russiaRoutesMeta(
    String installedAt,
    String domainListUpdatedAt,
    int categoryCount,
    int domainCount,
  ) {
    return 'runetfreedom: $installedAt · domain-list-community: $domainListUpdatedAt · categories: $categoryCount · domains: $domainCount';
  }

  @override
  String get adBlockTitle => 'Ad blocking';

  @override
  String get adBlockSubtitle =>
      'The client downloads a local rule-set itself and wires it into routing.';

  @override
  String get adBlockDownloadAction => 'Download';

  @override
  String get adBlockUpdateAction => 'Update';

  @override
  String get adBlockEnableTitle => 'Enable local blocking';

  @override
  String get adBlockEnabledSubtitle =>
      'Use the downloaded local rule-set for DNS and route reject.';

  @override
  String get adBlockMissingSubtitle =>
      'Download the filter package first in order to use it.';

  @override
  String get adBlockDownloadingStatus =>
      'Downloading and building the local filter...';

  @override
  String get adBlockMissingStatus => 'Filter is not downloaded yet';

  @override
  String get adBlockMissingHint =>
      'We download the list from AdGuard and keep it locally for sing-box.';

  @override
  String adBlockReadyStatus(int blockedCount) {
    return 'Filter is ready, domains: $blockedCount';
  }

  @override
  String adBlockMeta(String updatedAt, int allowedCount) {
    return 'Updated: $updatedAt · exceptions: $allowedCount';
  }

  @override
  String get splitRoutingTitle => 'Split routing';

  @override
  String get splitRoutingSubtitle =>
      'Route selected Android apps through VPN TUN or fully outside the VPN.';

  @override
  String get splitRoutingUnavailableTitle => 'Temporarily unavailable';

  @override
  String get splitRoutingUnavailableMessage =>
      'Split tunneling does not work correctly right now. We are working on a fix. Follow updates.';

  @override
  String get splitRoutingTunOnly =>
      'Per-app split tunneling works only when VPN TUN is enabled. Local Proxy In cannot see Android app package names.';

  @override
  String get splitRoutingModeTitle => 'Mode';

  @override
  String get splitRoutingModeDisabled => 'Off';

  @override
  String get splitRoutingModeDisabledSubtitle =>
      'Use the normal routing flow for all apps';

  @override
  String get splitRoutingModeProxySelected => 'Through VPN';

  @override
  String get splitRoutingModeProxySelectedSubtitle =>
      'Only selected apps enter VPN TUN and use the selected server';

  @override
  String get splitRoutingModeBypassSelected => 'Outside VPN';

  @override
  String get splitRoutingModeBypassSelectedSubtitle =>
      'Selected apps do not enter VPN TUN and go direct';

  @override
  String get splitRoutingAppsTitle => 'Applications';

  @override
  String get splitRoutingPackagesTitle => 'Package names';

  @override
  String get splitRoutingPackagesHint => 'com.termux\norg.mozilla.firefox';

  @override
  String get splitRoutingPackagesHelper =>
      'Package names only, for example org.telegram.messenger. App display names are ignored';

  @override
  String get splitRoutingPickAppsAction => 'Choose apps';

  @override
  String get splitRoutingPickAppsTitle => 'Choose apps';

  @override
  String get splitRoutingSearchHint => 'Search by app or package name';

  @override
  String get splitRoutingAndroidOnly =>
      'App picker is available on Android only';

  @override
  String get splitRoutingLoadAppsFailed => 'Failed to load installed apps';

  @override
  String splitRoutingSelectedCount(int count) {
    return '$count selected';
  }

  @override
  String get splitRoutingNoAppsTitle => 'No apps selected yet';

  @override
  String get splitRoutingNoAppsSubtitle =>
      'Pick Android apps to apply split routing to them';

  @override
  String get splitRoutingManualEditorTitle => 'Manual package list';

  @override
  String get splitRoutingManualEditorSubtitle =>
      'Use this if you want to edit package names directly';

  @override
  String refreshIntervalDaysShort(int count) {
    return '$count d';
  }

  @override
  String refreshIntervalHoursShort(int count) {
    return '$count h';
  }

  @override
  String refreshIntervalMinutesShort(int count) {
    return '$count min';
  }

  @override
  String get happCrypt5Supported => 'Supported';

  @override
  String get happCrypt5Unsupported => 'Not supported';

  @override
  String get happCrypt5Checking => 'Checking happ://crypt5/... decrypt support';

  @override
  String get happCrypt5SupportedDescription =>
      'Your device can decrypt Happ crypt5 crypto links directly in the app.';

  @override
  String get happCrypt5UnsupportedDescription =>
      'Happ crypt5 decrypt is currently unavailable on this device.';

  @override
  String get subscriptionLikelyRequiresHwidTitle => 'HWID may be required';

  @override
  String get subscriptionLikelyRequiresHwidWarning =>
      'This subscription probably requires HWID. The server returned only one outbound with app/HWID in its name. Open the subscription settings and enable HWID sending.';

  @override
  String get subscriptionLikelyRequiresHwidMessage =>
      'The server returned only one outbound, and its name looks like a placeholder related to app or HWID.\n\nThis usually means the subscription expects the device HWID in the request.\n\nEnable HWID sending now and update the subscription again?';

  @override
  String get subscriptionLikelyRequiresHwidAction => 'Enable HWID';

  @override
  String get subscriptionHwidEnabledAndUpdated =>
      'HWID sending enabled. The subscription was updated.';

  @override
  String get noValidOutboundsTitle => 'No working nodes';

  @override
  String get noValidOutboundsWarning =>
      'There are no working outbounds left in this subscription. They were filtered out during validation. Check the subscription or update it.';

  @override
  String get noValidOutboundsMessage =>
      'This subscription does not have any working outbounds left.\n\nAll nodes were filtered out during validation before startup, so the client will not try to launch sing-box with an empty proxy set.\n\nCheck the subscription, refresh it, or import a valid one.';

  @override
  String get noValidOutboundsAfterDropInvalidWarning =>
      'There are no working outbounds left in the selected subscription after invalid nodes were dropped. Check the subscription, something looks wrong with it.';

  @override
  String get noValidOutboundsAfterDropInvalidMessage =>
      'All remaining nodes in the selected subscription were dropped as invalid during startup.\n\nThe client stopped before handing a broken config to sing-box.\n\nCheck the subscription content and update or replace it.';

  @override
  String get experimentalTcpFastOpenTitle => 'TCP Fast Open';

  @override
  String get experimentalTcpFastOpenSubtitle =>
      'May reduce TCP handshake time, but support depends on the network and server.';

  @override
  String get experimentalTcpMultiPathTitle => 'TCP Multipath';

  @override
  String get experimentalTcpMultiPathSubtitle =>
      'Tries multiple network paths. Can help handoff, but may heat the phone or behave unstably.';

  @override
  String get experimentalInterruptConnectionsTitle =>
      'Interrupt active connections on node change';

  @override
  String get experimentalInterruptConnectionsSubtitle =>
      'Applies proxy changes faster, but old app connections can be dropped.';

  @override
  String get experimentalUrlTestStrictToleranceTitle =>
      'URLTest 1 ms tolerance';

  @override
  String get experimentalUrlTestStrictToleranceSubtitle =>
      'Selects the lowest-latency proxy more strictly, but may switch servers more often.';

  @override
  String get tlsFragmentationTitle => 'TLS fragmentation';

  @override
  String get tlsFragmentationSubtitle =>
      'Fragments TLS handshakes for proxy outbounds. It can help with DPI, but may slow connection setup.';

  @override
  String get tlsFragmentationModeDisabled => 'Disabled';

  @override
  String get tlsFragmentationModeDisabledSubtitle =>
      'Does not change server TLS settings.';

  @override
  String get tlsFragmentationModeRecord => 'TLS record fragment';

  @override
  String get tlsFragmentationModeRecordSubtitle =>
      'Softer mode. Try this first.';

  @override
  String get tlsFragmentationModeFragment => 'TLS fragment';

  @override
  String get tlsFragmentationModeFragmentSubtitle =>
      'More aggressive mode with a 300 ms fallback delay.';

  @override
  String get blockLeaksTitle => 'Fix some leaks';

  @override
  String get blockLeaksSubtitle =>
      'Blocks only STUN/WebRTC traffic that may bypass the proxy';

  @override
  String get addSubscriptionCaption => 'Add a subscription from a link or file';

  @override
  String get pasteSubscriptionLink => 'Paste subscription link';

  @override
  String get orManually => 'Or manually';

  @override
  String get pasteAction => 'Paste';

  @override
  String get cancelAction => 'Cancel';

  @override
  String get backupTitle => 'Data & backup';

  @override
  String get backupSubtitle => 'Export settings or move subscriptions safely';

  @override
  String get backupExportSettings => 'Export settings';

  @override
  String get backupExportSettingsSubtitle =>
      'Saves only safe client settings, without subscriptions or keys';

  @override
  String get backupExportProfileEncrypted =>
      'Export subscriptions with password';

  @override
  String get backupExportProfileEncryptedSubtitle =>
      'Recommended. Stores subscriptions, selected nodes and raw profile data encrypted with AES-256-GCM';

  @override
  String get backupExportProfilePlain =>
      'Export subscriptions without encryption';

  @override
  String get backupExportProfilePlainSubtitle =>
      'Only use this for trusted local transfer. The file contains VPN keys';

  @override
  String get backupImportFile => 'Import Etonify file';

  @override
  String get backupImportFileSubtitle =>
      'Supports .etonify-settings.json and .etonify-profile from Etonify 0.2.0+';

  @override
  String get backupPlainWarningTitle => 'The file will contain VPN keys';

  @override
  String get backupPlainWarningMessage =>
      'Plain export is readable by anyone who gets the file. Use encrypted export unless you fully trust the storage and transfer path.';

  @override
  String get backupPlainImportTitle => 'Plain profile file';

  @override
  String get backupPlainImportMessage =>
      'This file contains subscriptions and VPN keys without encryption. Import it only if you trust the source.';

  @override
  String get backupPasswordCreateTitle => 'Create export password';

  @override
  String get backupPasswordEnterTitle => 'Enter profile password';

  @override
  String get backupPasswordHint => 'Password';

  @override
  String get backupSaved => 'Backup file saved';

  @override
  String get backupImported => 'Import completed';

  @override
  String get backupUnsupportedVersion =>
      'This backup format is not supported by this client version.';

  @override
  String get backupNewerVersionTitle => 'Backup from a newer client';

  @override
  String backupNewerVersionMessage(String version) {
    return 'This file was created by Etonify $version. Some settings may not apply correctly. Continue?';
  }

  @override
  String get splitRoutingEmptyWhitelist =>
      'Choose at least one app or disable split tunneling before starting VPN.';

  @override
  String get connectionStagePreparing => 'Preparing VPN';

  @override
  String get connectionStageConfiguring => 'Building config';

  @override
  String get connectionStageStarting => 'Starting core';

  @override
  String get connectionStageStopping => 'Stopping VPN';

  @override
  String get connectionStageRecovering => 'Recovering';

  @override
  String get connectionStageSelectingProxy => 'Selecting server';

  @override
  String get vpnStartTimedOut =>
      'VPN did not start within 15 seconds. Startup was stopped.';

  @override
  String get vpnStartFailed => 'Failed to start VPN.';
}

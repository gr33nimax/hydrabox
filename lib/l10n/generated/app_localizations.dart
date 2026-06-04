import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_ru.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('ru'),
  ];

  /// No description provided for @profiles.
  ///
  /// In en, this message translates to:
  /// **'Profiles'**
  String get profiles;

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// No description provided for @homeTab.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get homeTab;

  /// No description provided for @proxiesTab.
  ///
  /// In en, this message translates to:
  /// **'Proxies'**
  String get proxiesTab;

  /// No description provided for @proxiesTitle.
  ///
  /// In en, this message translates to:
  /// **'Proxies'**
  String get proxiesTitle;

  /// No description provided for @proxySwitching.
  ///
  /// In en, this message translates to:
  /// **'Switching'**
  String get proxySwitching;

  /// No description provided for @proxySelectorTitle.
  ///
  /// In en, this message translates to:
  /// **'Selector'**
  String get proxySelectorTitle;

  /// No description provided for @shareProxyTitle.
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get shareProxyTitle;

  /// No description provided for @shareProxyLinkLabel.
  ///
  /// In en, this message translates to:
  /// **'Share link'**
  String get shareProxyLinkLabel;

  /// No description provided for @shareSingboxOutboundLabel.
  ///
  /// In en, this message translates to:
  /// **'sing-box outbound'**
  String get shareSingboxOutboundLabel;

  /// No description provided for @copiedToClipboard.
  ///
  /// In en, this message translates to:
  /// **'{label} copied'**
  String copiedToClipboard(String label);

  /// No description provided for @unavailableForThisType.
  ///
  /// In en, this message translates to:
  /// **'Unavailable for this type'**
  String get unavailableForThisType;

  /// No description provided for @sortByDefault.
  ///
  /// In en, this message translates to:
  /// **'Source order'**
  String get sortByDefault;

  /// No description provided for @sortByLatency.
  ///
  /// In en, this message translates to:
  /// **'By latency'**
  String get sortByLatency;

  /// No description provided for @sortByName.
  ///
  /// In en, this message translates to:
  /// **'By name'**
  String get sortByName;

  /// No description provided for @sortByCountry.
  ///
  /// In en, this message translates to:
  /// **'By country'**
  String get sortByCountry;

  /// No description provided for @settingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// No description provided for @generalSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'General'**
  String get generalSectionTitle;

  /// No description provided for @inboundTitle.
  ///
  /// In en, this message translates to:
  /// **'Inbound'**
  String get inboundTitle;

  /// No description provided for @dnsTitle.
  ///
  /// In en, this message translates to:
  /// **'DNS'**
  String get dnsTitle;

  /// No description provided for @whitelistTitle.
  ///
  /// In en, this message translates to:
  /// **'Whitelist'**
  String get whitelistTitle;

  /// No description provided for @whitelistSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Optional Snowtun module'**
  String get whitelistSubtitle;

  /// No description provided for @experimentalTitle.
  ///
  /// In en, this message translates to:
  /// **'Experimental'**
  String get experimentalTitle;

  /// No description provided for @experimentalSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Multipath, Fast Open, and connection switching behavior'**
  String get experimentalSubtitle;

  /// No description provided for @logsTitle.
  ///
  /// In en, this message translates to:
  /// **'Logs'**
  String get logsTitle;

  /// No description provided for @logsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Generated sing-box config and app events'**
  String get logsSubtitle;

  /// No description provided for @urlTestTitle.
  ///
  /// In en, this message translates to:
  /// **'URLTest'**
  String get urlTestTitle;

  /// No description provided for @urlTestSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Latency check and lowest selection'**
  String get urlTestSubtitle;

  /// No description provided for @vpnInTitle.
  ///
  /// In en, this message translates to:
  /// **'VPN In'**
  String get vpnInTitle;

  /// No description provided for @proxyInTitle.
  ///
  /// In en, this message translates to:
  /// **'Proxy In'**
  String get proxyInTitle;

  /// No description provided for @dnsDirectTitle.
  ///
  /// In en, this message translates to:
  /// **'Direct'**
  String get dnsDirectTitle;

  /// No description provided for @dnsProxyTitle.
  ///
  /// In en, this message translates to:
  /// **'Via proxy'**
  String get dnsProxyTitle;

  /// No description provided for @dnsIpPreferenceTitle.
  ///
  /// In en, this message translates to:
  /// **'IP version'**
  String get dnsIpPreferenceTitle;

  /// No description provided for @aboutSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'About client'**
  String get aboutSectionTitle;

  /// No description provided for @aboutSectionSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Client version, core, team, and service information.'**
  String get aboutSectionSubtitle;

  /// No description provided for @aboutHeroSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Android VPN client focused on speed, stability, and a clean daily experience.'**
  String get aboutHeroSubtitle;

  /// No description provided for @aboutDevelopedBy.
  ///
  /// In en, this message translates to:
  /// **'Developed by MeowTeam.'**
  String get aboutDevelopedBy;

  /// No description provided for @aboutCoreSourceLabel.
  ///
  /// In en, this message translates to:
  /// **'core source code'**
  String get aboutCoreSourceLabel;

  /// No description provided for @coreVersionLabel.
  ///
  /// In en, this message translates to:
  /// **'Core version'**
  String get coreVersionLabel;

  /// No description provided for @debugMenuTitle.
  ///
  /// In en, this message translates to:
  /// **'Debug'**
  String get debugMenuTitle;

  /// No description provided for @debugMenuSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Hidden area for debugging and service actions.'**
  String get debugMenuSubtitle;

  /// No description provided for @debugNetworkHeartbeatTitle.
  ///
  /// In en, this message translates to:
  /// **'Network heartbeat'**
  String get debugNetworkHeartbeatTitle;

  /// No description provided for @debugNetworkHeartbeatSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Re-asserts the default network if Android misses callbacks. Current interval: {seconds}s. Applies on next VPN start.'**
  String debugNetworkHeartbeatSubtitle(int seconds);

  /// No description provided for @debugWakeLockTitle.
  ///
  /// In en, this message translates to:
  /// **'Partial wake lock'**
  String get debugWakeLockTitle;

  /// No description provided for @debugWakeLockSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Keeps CPU awake while VPN runs. Off by default because it can heat the phone on aggressive firmware.'**
  String get debugWakeLockSubtitle;

  /// No description provided for @debugRecordSnapshot.
  ///
  /// In en, this message translates to:
  /// **'Record performance snapshot'**
  String get debugRecordSnapshot;

  /// No description provided for @debugSnapshotDone.
  ///
  /// In en, this message translates to:
  /// **'Performance snapshot added to logs'**
  String get debugSnapshotDone;

  /// No description provided for @teamPageTitle.
  ///
  /// In en, this message translates to:
  /// **'MeowTeam'**
  String get teamPageTitle;

  /// No description provided for @teamIntroTitle.
  ///
  /// In en, this message translates to:
  /// **'The team behind Etonify'**
  String get teamIntroTitle;

  /// No description provided for @teamIntroBody.
  ///
  /// In en, this message translates to:
  /// **'We are a small team building our own VPN client and improving it step by step.'**
  String get teamIntroBody;

  /// No description provided for @teamTimelineForkTitle.
  ///
  /// In en, this message translates to:
  /// **'Started as a Hiddify fork'**
  String get teamTimelineForkTitle;

  /// No description provided for @teamTimelineForkBody.
  ///
  /// In en, this message translates to:
  /// **'The early client inherited the UI and a large legacy codebase from Hiddify. A few test versions helped us understand what had to change.'**
  String get teamTimelineForkBody;

  /// No description provided for @teamTimelineRefactorTitle.
  ///
  /// In en, this message translates to:
  /// **'Large refactor'**
  String get teamTimelineRefactorTitle;

  /// No description provided for @teamTimelineRefactorBody.
  ///
  /// In en, this message translates to:
  /// **'The old backend carried too much technical debt, patches, dead code, and behavior that was hard to maintain. We moved the client through a deep refactor and rebuilt the runtime layer around a cleaner Android-first flow.'**
  String get teamTimelineRefactorBody;

  /// No description provided for @teamTimelineCoreTitle.
  ///
  /// In en, this message translates to:
  /// **'MeowSingBox core'**
  String get teamTimelineCoreTitle;

  /// No description provided for @teamTimelineCoreBody.
  ///
  /// In en, this message translates to:
  /// **'The app uses a modified sing-box core with extra work around URLTest, connection cleanup, and resource handling.'**
  String get teamTimelineCoreBody;

  /// No description provided for @teamTimelineNowTitle.
  ///
  /// In en, this message translates to:
  /// **'Etonify today'**
  String get teamTimelineNowTitle;

  /// No description provided for @teamTimelineNowBody.
  ///
  /// In en, this message translates to:
  /// **'Etonify is still evolving: we keep simplifying UX, improving Android stability, and cutting technical debt without losing the speed-focused VPN experience.'**
  String get teamTimelineNowBody;

  /// No description provided for @teamDeveloperDdosxdRole.
  ///
  /// In en, this message translates to:
  /// **'MeowTeam developer'**
  String get teamDeveloperDdosxdRole;

  /// No description provided for @teamDeveloperYamixdevRole.
  ///
  /// In en, this message translates to:
  /// **'MeowTeam developer'**
  String get teamDeveloperYamixdevRole;

  /// No description provided for @languageSettingTitle.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get languageSettingTitle;

  /// No description provided for @themeSettingTitle.
  ///
  /// In en, this message translates to:
  /// **'Theme'**
  String get themeSettingTitle;

  /// No description provided for @accentColorTitle.
  ///
  /// In en, this message translates to:
  /// **'Accent color'**
  String get accentColorTitle;

  /// No description provided for @appearanceTitle.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get appearanceTitle;

  /// No description provided for @languageSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get languageSystem;

  /// No description provided for @languageEnglish.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get languageEnglish;

  /// No description provided for @languageRussian.
  ///
  /// In en, this message translates to:
  /// **'Russian'**
  String get languageRussian;

  /// No description provided for @themeSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get themeSystem;

  /// No description provided for @themeLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get themeLight;

  /// No description provided for @themeDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get themeDark;

  /// No description provided for @themeAmoled.
  ///
  /// In en, this message translates to:
  /// **'AMOLED'**
  String get themeAmoled;

  /// No description provided for @aboutResourcesTitle.
  ///
  /// In en, this message translates to:
  /// **'Resources'**
  String get aboutResourcesTitle;

  /// No description provided for @aboutResourcesSubtitle.
  ///
  /// In en, this message translates to:
  /// **'On-demand Android snapshot. It is not collected in the background.'**
  String get aboutResourcesSubtitle;

  /// No description provided for @aboutResourcePss.
  ///
  /// In en, this message translates to:
  /// **'Memory'**
  String get aboutResourcePss;

  /// No description provided for @aboutResourceNativeHeap.
  ///
  /// In en, this message translates to:
  /// **'Native heap'**
  String get aboutResourceNativeHeap;

  /// No description provided for @aboutResourceJavaHeap.
  ///
  /// In en, this message translates to:
  /// **'Java heap'**
  String get aboutResourceJavaHeap;

  /// No description provided for @aboutResourceSystemMemory.
  ///
  /// In en, this message translates to:
  /// **'Free system RAM'**
  String get aboutResourceSystemMemory;

  /// No description provided for @aboutResourceBatteryTemp.
  ///
  /// In en, this message translates to:
  /// **'Battery temperature'**
  String get aboutResourceBatteryTemp;

  /// No description provided for @appVersionLabel.
  ///
  /// In en, this message translates to:
  /// **'Client version'**
  String get appVersionLabel;

  /// No description provided for @currentProfileLabel.
  ///
  /// In en, this message translates to:
  /// **'Current profile'**
  String get currentProfileLabel;

  /// No description provided for @selectedProxyLabel.
  ///
  /// In en, this message translates to:
  /// **'Selected proxy'**
  String get selectedProxyLabel;

  /// No description provided for @onboardingStatusLabel.
  ///
  /// In en, this message translates to:
  /// **'Intro'**
  String get onboardingStatusLabel;

  /// No description provided for @onboardingSeen.
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get onboardingSeen;

  /// No description provided for @showOnboardingAgain.
  ///
  /// In en, this message translates to:
  /// **'Show intro again'**
  String get showOnboardingAgain;

  /// No description provided for @settingsFootnote.
  ///
  /// In en, this message translates to:
  /// **'These settings are local to this device and are stored in Hive.'**
  String get settingsFootnote;

  /// No description provided for @connected.
  ///
  /// In en, this message translates to:
  /// **'Connected'**
  String get connected;

  /// No description provided for @tapToConnect.
  ///
  /// In en, this message translates to:
  /// **'Tap to Connect'**
  String get tapToConnect;

  /// No description provided for @resolvingIp.
  ///
  /// In en, this message translates to:
  /// **'Resolving IP…'**
  String get resolvingIp;

  /// No description provided for @millisecondsUnit.
  ///
  /// In en, this message translates to:
  /// **' ms'**
  String get millisecondsUnit;

  /// No description provided for @refreshLatency.
  ///
  /// In en, this message translates to:
  /// **'Refresh latency'**
  String get refreshLatency;

  /// No description provided for @checkingLatency.
  ///
  /// In en, this message translates to:
  /// **'Checking latency'**
  String get checkingLatency;

  /// No description provided for @checkingLatencyShort.
  ///
  /// In en, this message translates to:
  /// **'Checking…'**
  String get checkingLatencyShort;

  /// No description provided for @openTrafficDashboard.
  ///
  /// In en, this message translates to:
  /// **'Open traffic dashboard'**
  String get openTrafficDashboard;

  /// No description provided for @refreshActiveSubscription.
  ///
  /// In en, this message translates to:
  /// **'Refresh current subscription'**
  String get refreshActiveSubscription;

  /// No description provided for @refreshActiveSubscriptionUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Manual imports cannot be refreshed'**
  String get refreshActiveSubscriptionUnavailable;

  /// No description provided for @activeSubscriptionRefreshComplete.
  ///
  /// In en, this message translates to:
  /// **'{name} updated'**
  String activeSubscriptionRefreshComplete(String name);

  /// No description provided for @trafficDashboardTitle.
  ///
  /// In en, this message translates to:
  /// **'Traffic dashboard'**
  String get trafficDashboardTitle;

  /// No description provided for @trafficDashboardSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Live speed, session totals, and connection info'**
  String get trafficDashboardSubtitle;

  /// No description provided for @trafficDashboardDownload.
  ///
  /// In en, this message translates to:
  /// **'Download'**
  String get trafficDashboardDownload;

  /// No description provided for @trafficDashboardUpload.
  ///
  /// In en, this message translates to:
  /// **'Upload'**
  String get trafficDashboardUpload;

  /// No description provided for @trafficDashboardSessionTraffic.
  ///
  /// In en, this message translates to:
  /// **'Session traffic'**
  String get trafficDashboardSessionTraffic;

  /// No description provided for @trafficDashboardConnectedFor.
  ///
  /// In en, this message translates to:
  /// **'Connected for'**
  String get trafficDashboardConnectedFor;

  /// No description provided for @trafficDashboardGraphTitle.
  ///
  /// In en, this message translates to:
  /// **'Live traffic'**
  String get trafficDashboardGraphTitle;

  /// No description provided for @trafficDashboardGraphMax.
  ///
  /// In en, this message translates to:
  /// **'Peak {speed}'**
  String trafficDashboardGraphMax(String speed);

  /// No description provided for @trafficDashboardNoSamples.
  ///
  /// In en, this message translates to:
  /// **'Waiting for traffic data'**
  String get trafficDashboardNoSamples;

  /// No description provided for @trafficDashboardConnectionState.
  ///
  /// In en, this message translates to:
  /// **'Connection'**
  String get trafficDashboardConnectionState;

  /// No description provided for @trafficDashboardCurrentProfile.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get trafficDashboardCurrentProfile;

  /// No description provided for @trafficDashboardActiveProxy.
  ///
  /// In en, this message translates to:
  /// **'Proxy'**
  String get trafficDashboardActiveProxy;

  /// No description provided for @trafficDashboardServerIp.
  ///
  /// In en, this message translates to:
  /// **'Server IP'**
  String get trafficDashboardServerIp;

  /// No description provided for @trafficDashboardDownloadTotal.
  ///
  /// In en, this message translates to:
  /// **'Downloaded'**
  String get trafficDashboardDownloadTotal;

  /// No description provided for @trafficDashboardUploadTotal.
  ///
  /// In en, this message translates to:
  /// **'Uploaded'**
  String get trafficDashboardUploadTotal;

  /// No description provided for @trafficDashboardStateConnected.
  ///
  /// In en, this message translates to:
  /// **'Connected'**
  String get trafficDashboardStateConnected;

  /// No description provided for @trafficDashboardStateConnecting.
  ///
  /// In en, this message translates to:
  /// **'Connecting'**
  String get trafficDashboardStateConnecting;

  /// No description provided for @trafficDashboardStateDisconnected.
  ///
  /// In en, this message translates to:
  /// **'Disconnected'**
  String get trafficDashboardStateDisconnected;

  /// No description provided for @trafficDashboardUptimeHours.
  ///
  /// In en, this message translates to:
  /// **'{hours} h {minutes} min'**
  String trafficDashboardUptimeHours(int hours, int minutes);

  /// No description provided for @trafficDashboardUptimeMinutes.
  ///
  /// In en, this message translates to:
  /// **'{minutes} min {seconds} s'**
  String trafficDashboardUptimeMinutes(int minutes, int seconds);

  /// No description provided for @trafficDashboardUptimeSeconds.
  ///
  /// In en, this message translates to:
  /// **'{seconds} s'**
  String trafficDashboardUptimeSeconds(int seconds);

  /// No description provided for @notAvailableShort.
  ///
  /// In en, this message translates to:
  /// **'N/A'**
  String get notAvailableShort;

  /// No description provided for @daysLeft.
  ///
  /// In en, this message translates to:
  /// **'{days} days left'**
  String daysLeft(int days);

  /// No description provided for @daysLeftUnlimited.
  ///
  /// In en, this message translates to:
  /// **'∞ days left'**
  String get daysLeftUnlimited;

  /// No description provided for @unlimitedTraffic.
  ///
  /// In en, this message translates to:
  /// **'Unlimited'**
  String get unlimitedTraffic;

  /// No description provided for @unlimitedSymbol.
  ///
  /// In en, this message translates to:
  /// **'∞'**
  String get unlimitedSymbol;

  /// No description provided for @welcomeGreeting.
  ///
  /// In en, this message translates to:
  /// **'Hi'**
  String get welcomeGreeting;

  /// No description provided for @welcomeTitlePrefix.
  ///
  /// In en, this message translates to:
  /// **'Welcome to'**
  String get welcomeTitlePrefix;

  /// No description provided for @welcomeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Fast Android VPN client'**
  String get welcomeSubtitle;

  /// No description provided for @welcomeTapHint.
  ///
  /// In en, this message translates to:
  /// **'tap anywhere to continue'**
  String get welcomeTapHint;

  /// No description provided for @hapticTitle.
  ///
  /// In en, this message translates to:
  /// **'Vibration'**
  String get hapticTitle;

  /// No description provided for @hapticSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Light vibration for important actions'**
  String get hapticSubtitle;

  /// No description provided for @hideServerIpTitle.
  ///
  /// In en, this message translates to:
  /// **'Hide server IP'**
  String get hideServerIpTitle;

  /// No description provided for @hideServerIpSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Masks last two octets of the IP address'**
  String get hideServerIpSubtitle;

  /// No description provided for @progressiveBlurTitle.
  ///
  /// In en, this message translates to:
  /// **'Progressive blur'**
  String get progressiveBlurTitle;

  /// No description provided for @progressiveBlurSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Blurs content under headers and navigation bars'**
  String get progressiveBlurSubtitle;

  /// No description provided for @enableInboundTitle.
  ///
  /// In en, this message translates to:
  /// **'Enabled'**
  String get enableInboundTitle;

  /// No description provided for @vpnInDescription.
  ///
  /// In en, this message translates to:
  /// **'VPN TUN is the Android system VPN path for phone traffic. Apps see an Android VPN, while routing decides what goes through proxy or direct.'**
  String get vpnInDescription;

  /// No description provided for @vpnInboundEnabledSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Creates a VPN TUN inbound and routes traffic through it'**
  String get vpnInboundEnabledSubtitle;

  /// No description provided for @mtuTitle.
  ///
  /// In en, this message translates to:
  /// **'MTU'**
  String get mtuTitle;

  /// No description provided for @mtuSubtitle.
  ///
  /// In en, this message translates to:
  /// **'TUN interface packet size'**
  String get mtuSubtitle;

  /// No description provided for @strictRouteTitle.
  ///
  /// In en, this message translates to:
  /// **'Prevent VPN bypass'**
  String get strictRouteTitle;

  /// No description provided for @strictRouteSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Forces traffic through VPN and reduces the chance of traffic escaping the tunnel'**
  String get strictRouteSubtitle;

  /// No description provided for @tunImplementationTitle.
  ///
  /// In en, this message translates to:
  /// **'TUN implementation'**
  String get tunImplementationTitle;

  /// No description provided for @tunImplementationSubtitle.
  ///
  /// In en, this message translates to:
  /// **'How the client handles the TUN stack'**
  String get tunImplementationSubtitle;

  /// No description provided for @tunImplementationMixed.
  ///
  /// In en, this message translates to:
  /// **'Mixed'**
  String get tunImplementationMixed;

  /// No description provided for @tunImplementationMixedSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Automatic mode. Uses the safer stack for the current device and config.'**
  String get tunImplementationMixedSubtitle;

  /// No description provided for @tunImplementationSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get tunImplementationSystem;

  /// No description provided for @tunImplementationSystemSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Android system stack. Usually lighter, but may depend on device firmware.'**
  String get tunImplementationSystemSubtitle;

  /// No description provided for @tunImplementationGvisor.
  ///
  /// In en, this message translates to:
  /// **'gVisor'**
  String get tunImplementationGvisor;

  /// No description provided for @tunImplementationGvisorSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Userspace network stack. Can be more compatible, but may cost more CPU.'**
  String get tunImplementationGvisorSubtitle;

  /// No description provided for @proxyInDescription.
  ///
  /// In en, this message translates to:
  /// **'Proxy In / mixed is a local HTTP/SOCKS entry for apps or other devices that you configure manually. It is not the Android system VPN.'**
  String get proxyInDescription;

  /// No description provided for @proxyInboundEnabledSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Starts a local mixed inbound for apps and devices'**
  String get proxyInboundEnabledSubtitle;

  /// No description provided for @allowLanConnectionsTitle.
  ///
  /// In en, this message translates to:
  /// **'Allow LAN connections'**
  String get allowLanConnectionsTitle;

  /// No description provided for @allowLanConnectionsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'If enabled, listen on 0.0.0.0, otherwise on 127.0.0.1'**
  String get allowLanConnectionsSubtitle;

  /// No description provided for @portTitle.
  ///
  /// In en, this message translates to:
  /// **'Port'**
  String get portTitle;

  /// No description provided for @proxyPortSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Local mixed inbound port'**
  String get proxyPortSubtitle;

  /// No description provided for @dnsUsePresetTitle.
  ///
  /// In en, this message translates to:
  /// **'Use preset'**
  String get dnsUsePresetTitle;

  /// No description provided for @dnsResolverTitle.
  ///
  /// In en, this message translates to:
  /// **'Resolver'**
  String get dnsResolverTitle;

  /// No description provided for @dnsDirectPresetSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Recommended: udp://1.1.1.1'**
  String get dnsDirectPresetSubtitle;

  /// No description provided for @dnsDirectResolverSubtitle.
  ///
  /// In en, this message translates to:
  /// **'DNS for direct requests without proxy'**
  String get dnsDirectResolverSubtitle;

  /// No description provided for @dnsProxyPresetSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Recommended: https://dns.cloudflare.com/dns-query'**
  String get dnsProxyPresetSubtitle;

  /// No description provided for @dnsProxyResolverSubtitle.
  ///
  /// In en, this message translates to:
  /// **'DNS for requests through proxy'**
  String get dnsProxyResolverSubtitle;

  /// No description provided for @dnsResolverTypeTitle.
  ///
  /// In en, this message translates to:
  /// **'Resolver type'**
  String get dnsResolverTypeTitle;

  /// No description provided for @dnsPresetDevice.
  ///
  /// In en, this message translates to:
  /// **'Device network'**
  String get dnsPresetDevice;

  /// No description provided for @dnsPresetCustom.
  ///
  /// In en, this message translates to:
  /// **'Custom'**
  String get dnsPresetCustom;

  /// No description provided for @dnsPresetDeviceSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Use DNS from the current Android network.'**
  String get dnsPresetDeviceSubtitle;

  /// No description provided for @dnsPresetCustomSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Enter your own resolver: udp://, tcp://, tls://, or https://.'**
  String get dnsPresetCustomSubtitle;

  /// No description provided for @dnsPresetUdpSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Plain UDP DNS. Fast, but not encrypted.'**
  String get dnsPresetUdpSubtitle;

  /// No description provided for @dnsPresetTcpSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Plain TCP DNS. More stable on some networks, but not encrypted.'**
  String get dnsPresetTcpSubtitle;

  /// No description provided for @dnsPresetTlsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'DNS over TLS. Encrypted DNS on port 853.'**
  String get dnsPresetTlsSubtitle;

  /// No description provided for @dnsPresetHttpsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'DNS over HTTPS. Encrypted DNS over HTTPS, often best through proxy.'**
  String get dnsPresetHttpsSubtitle;

  /// No description provided for @dnsPreferIpv6Title.
  ///
  /// In en, this message translates to:
  /// **'Prefer IPv6'**
  String get dnsPreferIpv6Title;

  /// No description provided for @dnsPreferIpv6Subtitle.
  ///
  /// In en, this message translates to:
  /// **'Prefer IPv6 when both address versions are available'**
  String get dnsPreferIpv6Subtitle;

  /// No description provided for @urlTestUrlTitle.
  ///
  /// In en, this message translates to:
  /// **'Test URL'**
  String get urlTestUrlTitle;

  /// No description provided for @urlTestUrlSubtitle.
  ///
  /// In en, this message translates to:
  /// **'If the subscription already defines a value, that value is used'**
  String get urlTestUrlSubtitle;

  /// No description provided for @urlTestIntervalTitle.
  ///
  /// In en, this message translates to:
  /// **'Interval, sec.'**
  String get urlTestIntervalTitle;

  /// No description provided for @urlTestIntervalSubtitle.
  ///
  /// In en, this message translates to:
  /// **'How often proxies are checked for lowest'**
  String get urlTestIntervalSubtitle;

  /// No description provided for @urlTestTimeoutTitle.
  ///
  /// In en, this message translates to:
  /// **'Timeout, sec.'**
  String get urlTestTimeoutTitle;

  /// No description provided for @urlTestTimeoutSubtitle.
  ///
  /// In en, this message translates to:
  /// **'How long to wait for one proxy test before failing it'**
  String get urlTestTimeoutSubtitle;

  /// No description provided for @urlTestConcurrencyTitle.
  ///
  /// In en, this message translates to:
  /// **'Test concurrency'**
  String get urlTestConcurrencyTitle;

  /// No description provided for @urlTestConcurrencySubtitle.
  ///
  /// In en, this message translates to:
  /// **'How many proxies URLTest checks at the same time'**
  String get urlTestConcurrencySubtitle;

  /// No description provided for @urlTestSingleRetestTitle.
  ///
  /// In en, this message translates to:
  /// **'Quick retry delay, sec.'**
  String get urlTestSingleRetestTitle;

  /// No description provided for @urlTestSingleRetestSubtitle.
  ///
  /// In en, this message translates to:
  /// **'How long to wait before one quick recheck after a proxy fails'**
  String get urlTestSingleRetestSubtitle;

  /// No description provided for @locationLookupTitle.
  ///
  /// In en, this message translates to:
  /// **'Locations'**
  String get locationLookupTitle;

  /// No description provided for @locationLookupSubtitle.
  ///
  /// In en, this message translates to:
  /// **'IP and country through the proxies themselves'**
  String get locationLookupSubtitle;

  /// No description provided for @locationLookupLimitTitle.
  ///
  /// In en, this message translates to:
  /// **'Check best proxies'**
  String get locationLookupLimitTitle;

  /// No description provided for @locationLookupLimitSubtitle.
  ///
  /// In en, this message translates to:
  /// **'After URLTest, the app resolves external IP and country for this many fastest outbounds'**
  String get locationLookupLimitSubtitle;

  /// No description provided for @serverRequestTitle.
  ///
  /// In en, this message translates to:
  /// **'Server request'**
  String get serverRequestTitle;

  /// No description provided for @sendHwidTitle.
  ///
  /// In en, this message translates to:
  /// **'Send HWID'**
  String get sendHwidTitle;

  /// No description provided for @sendHwidSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Adds the device HWID to the subscription request'**
  String get sendHwidSubtitle;

  /// No description provided for @useCustomHwidTitle.
  ///
  /// In en, this message translates to:
  /// **'Use custom HWID'**
  String get useCustomHwidTitle;

  /// No description provided for @useCustomHwidSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Override the device HWID with your own value'**
  String get useCustomHwidSubtitle;

  /// No description provided for @customUserAgentTitle.
  ///
  /// In en, this message translates to:
  /// **'Custom User-Agent'**
  String get customUserAgentTitle;

  /// No description provided for @customUserAgentSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Overrides the default Etonify user agent for this subscription'**
  String get customUserAgentSubtitle;

  /// No description provided for @customHwidTitle.
  ///
  /// In en, this message translates to:
  /// **'Custom HWID'**
  String get customHwidTitle;

  /// No description provided for @customHwidSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Used only when custom HWID is enabled'**
  String get customHwidSubtitle;

  /// No description provided for @customRequestHeadersTitle.
  ///
  /// In en, this message translates to:
  /// **'Custom headers'**
  String get customRequestHeadersTitle;

  /// No description provided for @customRequestHeadersSubtitle.
  ///
  /// In en, this message translates to:
  /// **'One header per line in Header: value format'**
  String get customRequestHeadersSubtitle;

  /// No description provided for @hwidTitle.
  ///
  /// In en, this message translates to:
  /// **'HWID'**
  String get hwidTitle;

  /// No description provided for @hwidSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Your device identifier used by some subscription providers'**
  String get hwidSubtitle;

  /// No description provided for @hwidValueTitle.
  ///
  /// In en, this message translates to:
  /// **'Your HWID'**
  String get hwidValueTitle;

  /// No description provided for @coreStartFailedTitle.
  ///
  /// In en, this message translates to:
  /// **'Failed to start core'**
  String get coreStartFailedTitle;

  /// No description provided for @coreStartFailedMessage.
  ///
  /// In en, this message translates to:
  /// **'sing-box failed to start.\n\n{message}'**
  String coreStartFailedMessage(String message);

  /// No description provided for @vpnStopFailed.
  ///
  /// In en, this message translates to:
  /// **'VPN did not stop completely. Open logs and try again.'**
  String get vpnStopFailed;

  /// No description provided for @clearLogsTitle.
  ///
  /// In en, this message translates to:
  /// **'Clear logs'**
  String get clearLogsTitle;

  /// No description provided for @logsFilterTitle.
  ///
  /// In en, this message translates to:
  /// **'Filter'**
  String get logsFilterTitle;

  /// No description provided for @logsFilterAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get logsFilterAll;

  /// No description provided for @singBoxLogLevelTitle.
  ///
  /// In en, this message translates to:
  /// **'sing-box log level'**
  String get singBoxLogLevelTitle;

  /// No description provided for @logLevelTrace.
  ///
  /// In en, this message translates to:
  /// **'Trace'**
  String get logLevelTrace;

  /// No description provided for @logLevelDebug.
  ///
  /// In en, this message translates to:
  /// **'Debug'**
  String get logLevelDebug;

  /// No description provided for @logLevelInfo.
  ///
  /// In en, this message translates to:
  /// **'Info'**
  String get logLevelInfo;

  /// No description provided for @logLevelWarning.
  ///
  /// In en, this message translates to:
  /// **'Warning'**
  String get logLevelWarning;

  /// No description provided for @logLevelError.
  ///
  /// In en, this message translates to:
  /// **'Error'**
  String get logLevelError;

  /// No description provided for @noLogsTitle.
  ///
  /// In en, this message translates to:
  /// **'No logs yet'**
  String get noLogsTitle;

  /// No description provided for @continueLabel.
  ///
  /// In en, this message translates to:
  /// **'Get started'**
  String get continueLabel;

  /// No description provided for @subscriptionsTab.
  ///
  /// In en, this message translates to:
  /// **'Subscriptions'**
  String get subscriptionsTab;

  /// No description provided for @subscriptionsTitle.
  ///
  /// In en, this message translates to:
  /// **'Subscriptions'**
  String get subscriptionsTitle;

  /// No description provided for @addSubscription.
  ///
  /// In en, this message translates to:
  /// **'Add subscription'**
  String get addSubscription;

  /// No description provided for @scanQrCode.
  ///
  /// In en, this message translates to:
  /// **'Scan QR'**
  String get scanQrCode;

  /// No description provided for @showQrCode.
  ///
  /// In en, this message translates to:
  /// **'Show QR'**
  String get showQrCode;

  /// No description provided for @subscriptionQrTitle.
  ///
  /// In en, this message translates to:
  /// **'Subscription QR'**
  String get subscriptionQrTitle;

  /// No description provided for @subscriptionQrHint.
  ///
  /// In en, this message translates to:
  /// **'Scan this code on another device to import the subscription.'**
  String get subscriptionQrHint;

  /// No description provided for @subscriptionQrUnsupported.
  ///
  /// In en, this message translates to:
  /// **'This subscription cannot be shared as QR yet.'**
  String get subscriptionQrUnsupported;

  /// No description provided for @invalidQrSubscription.
  ///
  /// In en, this message translates to:
  /// **'The QR code does not contain a supported subscription link.'**
  String get invalidQrSubscription;

  /// No description provided for @subscriptionUrl.
  ///
  /// In en, this message translates to:
  /// **'Subscription URL'**
  String get subscriptionUrl;

  /// No description provided for @subscriptionUrlOrContent.
  ///
  /// In en, this message translates to:
  /// **'URL or content'**
  String get subscriptionUrlOrContent;

  /// No description provided for @subscriptionUrlOrContentHint.
  ///
  /// In en, this message translates to:
  /// **'Paste a URL, vless:// link, link list, or config'**
  String get subscriptionUrlOrContentHint;

  /// No description provided for @importFromFile.
  ///
  /// In en, this message translates to:
  /// **'From file'**
  String get importFromFile;

  /// No description provided for @invalidSubscriptionFile.
  ///
  /// In en, this message translates to:
  /// **'Failed to read the subscription file'**
  String get invalidSubscriptionFile;

  /// No description provided for @subscriptionName.
  ///
  /// In en, this message translates to:
  /// **'Name (optional)'**
  String get subscriptionName;

  /// No description provided for @add.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get add;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @refresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get refresh;

  /// No description provided for @reparseProxies.
  ///
  /// In en, this message translates to:
  /// **'Reparse proxies'**
  String get reparseProxies;

  /// No description provided for @subscriptionLocalImportBadge.
  ///
  /// In en, this message translates to:
  /// **'Local import'**
  String get subscriptionLocalImportBadge;

  /// No description provided for @refreshAll.
  ///
  /// In en, this message translates to:
  /// **'Refresh all'**
  String get refreshAll;

  /// No description provided for @subscriptionsRefreshAllComplete.
  ///
  /// In en, this message translates to:
  /// **'Updated {updated} subscriptions, {failed} failed'**
  String subscriptionsRefreshAllComplete(int updated, int failed);

  /// No description provided for @deleteSubscription.
  ///
  /// In en, this message translates to:
  /// **'Delete subscription?'**
  String get deleteSubscription;

  /// No description provided for @deleteSubscriptionConfirm.
  ///
  /// In en, this message translates to:
  /// **'This will remove all proxies from this subscription.'**
  String get deleteSubscriptionConfirm;

  /// No description provided for @subscriptionDetailsTitle.
  ///
  /// In en, this message translates to:
  /// **'Subscription'**
  String get subscriptionDetailsTitle;

  /// No description provided for @subscriptionMovedTitle.
  ///
  /// In en, this message translates to:
  /// **'Subscription moved'**
  String get subscriptionMovedTitle;

  /// No description provided for @ignoreAction.
  ///
  /// In en, this message translates to:
  /// **'Ignore'**
  String get ignoreAction;

  /// No description provided for @updateUrlAction.
  ///
  /// In en, this message translates to:
  /// **'Update URL'**
  String get updateUrlAction;

  /// No description provided for @autoUpdateTitle.
  ///
  /// In en, this message translates to:
  /// **'Auto update'**
  String get autoUpdateTitle;

  /// No description provided for @disableAutoUpdateTitle.
  ///
  /// In en, this message translates to:
  /// **'Disable auto update'**
  String get disableAutoUpdateTitle;

  /// No description provided for @disabledLabel.
  ///
  /// In en, this message translates to:
  /// **'Disabled'**
  String get disabledLabel;

  /// No description provided for @refreshesEvery.
  ///
  /// In en, this message translates to:
  /// **'Refreshes every: {interval}'**
  String refreshesEvery(String interval);

  /// No description provided for @usageTitle.
  ///
  /// In en, this message translates to:
  /// **'Usage'**
  String get usageTitle;

  /// No description provided for @spentTraffic.
  ///
  /// In en, this message translates to:
  /// **'Spent {usage}'**
  String spentTraffic(String usage);

  /// No description provided for @untilDate.
  ///
  /// In en, this message translates to:
  /// **'Until {date}'**
  String untilDate(String date);

  /// No description provided for @infoTitle.
  ///
  /// In en, this message translates to:
  /// **'Information'**
  String get infoTitle;

  /// No description provided for @supportUrlLabel.
  ///
  /// In en, this message translates to:
  /// **'Support'**
  String get supportUrlLabel;

  /// No description provided for @websiteLabel.
  ///
  /// In en, this message translates to:
  /// **'Website'**
  String get websiteLabel;

  /// No description provided for @newUrlTitle.
  ///
  /// In en, this message translates to:
  /// **'NewURL'**
  String get newUrlTitle;

  /// No description provided for @movedSubscriptionMessage.
  ///
  /// In en, this message translates to:
  /// **'The server reported that this subscription moved to a new URL.'**
  String get movedSubscriptionMessage;

  /// No description provided for @movedSubscriptionPrompt.
  ///
  /// In en, this message translates to:
  /// **'The server reports a new subscription URL. Update it now or keep the current one?'**
  String get movedSubscriptionPrompt;

  /// No description provided for @noSubscriptions.
  ///
  /// In en, this message translates to:
  /// **'No subscriptions yet'**
  String get noSubscriptions;

  /// No description provided for @noProxies.
  ///
  /// In en, this message translates to:
  /// **'No proxies'**
  String get noProxies;

  /// No description provided for @noSubscriptionsHint.
  ///
  /// In en, this message translates to:
  /// **'Tap + to add a subscription URL'**
  String get noSubscriptionsHint;

  /// No description provided for @outboundsCount.
  ///
  /// In en, this message translates to:
  /// **'{count} proxies'**
  String outboundsCount(int count);

  /// No description provided for @subscriptionServersCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{{count} server} other{{count} servers}}'**
  String subscriptionServersCount(int count);

  /// No description provided for @subscriptionProxyTypeLabel.
  ///
  /// In en, this message translates to:
  /// **'Proxies'**
  String get subscriptionProxyTypeLabel;

  /// No description provided for @moreProxies.
  ///
  /// In en, this message translates to:
  /// **'…{count} more proxies'**
  String moreProxies(int count);

  /// No description provided for @lastUpdated.
  ///
  /// In en, this message translates to:
  /// **'Updated {time}'**
  String lastUpdated(String time);

  /// No description provided for @trafficUsage.
  ///
  /// In en, this message translates to:
  /// **'{used} / {total}'**
  String trafficUsage(String used, String total);

  /// No description provided for @expired.
  ///
  /// In en, this message translates to:
  /// **'Expired'**
  String get expired;

  /// No description provided for @loading.
  ///
  /// In en, this message translates to:
  /// **'Loading…'**
  String get loading;

  /// No description provided for @error.
  ///
  /// In en, this message translates to:
  /// **'Error'**
  String get error;

  /// No description provided for @invalidUrl.
  ///
  /// In en, this message translates to:
  /// **'Please enter a valid URL'**
  String get invalidUrl;

  /// No description provided for @fetchFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to fetch subscription'**
  String get fetchFailed;

  /// No description provided for @subscriptionSavedWithFetchWarning.
  ///
  /// In en, this message translates to:
  /// **'The subscription was saved, but the server did not respond. You can change HWID or headers and refresh it later.'**
  String get subscriptionSavedWithFetchWarning;

  /// No description provided for @sourceLabel.
  ///
  /// In en, this message translates to:
  /// **'Source'**
  String get sourceLabel;

  /// No description provided for @importedFromFileLabel.
  ///
  /// In en, this message translates to:
  /// **'Imported from file: {name}'**
  String importedFromFileLabel(String name);

  /// No description provided for @deepLinkImportTitle.
  ///
  /// In en, this message translates to:
  /// **'Import subscription'**
  String get deepLinkImportTitle;

  /// No description provided for @deepLinkImportMessage.
  ///
  /// In en, this message translates to:
  /// **'Do you really want to import this subscription?'**
  String get deepLinkImportMessage;

  /// No description provided for @deepLinkImportNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get deepLinkImportNameLabel;

  /// No description provided for @deepLinkImportAction.
  ///
  /// In en, this message translates to:
  /// **'Import'**
  String get deepLinkImportAction;

  /// No description provided for @deepLinkImportSourceLabel.
  ///
  /// In en, this message translates to:
  /// **'Source link'**
  String get deepLinkImportSourceLabel;

  /// No description provided for @deepLinkImportResolvedUrlLabel.
  ///
  /// In en, this message translates to:
  /// **'Resolved subscription URL'**
  String get deepLinkImportResolvedUrlLabel;

  /// No description provided for @deepLinkImportHappBadge.
  ///
  /// In en, this message translates to:
  /// **'Happ subscription'**
  String get deepLinkImportHappBadge;

  /// No description provided for @deepLinkImportHappNotice.
  ///
  /// In en, this message translates to:
  /// **'This subscription is intended for the Happ app and may require your device HWID. Etonify will send the HWID and Happ User-Agent only if you confirm this import.'**
  String get deepLinkImportHappNotice;

  /// No description provided for @deepLinkImportHappSendHwidAction.
  ///
  /// In en, this message translates to:
  /// **'Send HWID and import'**
  String get deepLinkImportHappSendHwidAction;

  /// No description provided for @deepLinkImportHappCancelAction.
  ///
  /// In en, this message translates to:
  /// **'Do not import'**
  String get deepLinkImportHappCancelAction;

  /// No description provided for @deepLinkImportUserAgentLabel.
  ///
  /// In en, this message translates to:
  /// **'User-Agent'**
  String get deepLinkImportUserAgentLabel;

  /// No description provided for @deepLinkImportHwidLabel.
  ///
  /// In en, this message translates to:
  /// **'HWID'**
  String get deepLinkImportHwidLabel;

  /// No description provided for @deepLinkImportHwidValue.
  ///
  /// In en, this message translates to:
  /// **'Will be sent only after confirmation'**
  String get deepLinkImportHwidValue;

  /// No description provided for @deepLinkImportSuccess.
  ///
  /// In en, this message translates to:
  /// **'Subscription \"{name}\" imported'**
  String deepLinkImportSuccess(String name);

  /// No description provided for @happCryptoLinkImportedLabel.
  ///
  /// In en, this message translates to:
  /// **'Imported via Happ Crypto Link'**
  String get happCryptoLinkImportedLabel;

  /// No description provided for @happCryptoLinkTitle.
  ///
  /// In en, this message translates to:
  /// **'Happ Crypto Link'**
  String get happCryptoLinkTitle;

  /// No description provided for @happCryptUnsupportedTitle.
  ///
  /// In en, this message translates to:
  /// **'Happ crypt5'**
  String get happCryptUnsupportedTitle;

  /// No description provided for @happCryptUnsupportedMessage.
  ///
  /// In en, this message translates to:
  /// **'This Happ Crypto Link version is not supported yet.'**
  String get happCryptUnsupportedMessage;

  /// No description provided for @happImportTitle.
  ///
  /// In en, this message translates to:
  /// **'Happ subscription'**
  String get happImportTitle;

  /// No description provided for @happImportMessage.
  ///
  /// In en, this message translates to:
  /// **'This subscription is intended for the Happ app and may require your device HWID. Continue only if you agree to send the HWID and Happ User-Agent to the subscription server.'**
  String get happImportMessage;

  /// No description provided for @subscriptionOperationSlowWarning.
  ///
  /// In en, this message translates to:
  /// **'The subscription server is taking longer than usual. Check the link or network if this keeps happening.'**
  String get subscriptionOperationSlowWarning;

  /// No description provided for @subscriptionOperationTimeout.
  ///
  /// In en, this message translates to:
  /// **'The subscription server did not respond in time. Check the link or network and try again.'**
  String get subscriptionOperationTimeout;

  /// No description provided for @continueAction.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get continueAction;

  /// No description provided for @routingTitle.
  ///
  /// In en, this message translates to:
  /// **'Routing'**
  String get routingTitle;

  /// No description provided for @routingSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Traffic routing rules'**
  String get routingSubtitle;

  /// No description provided for @bypassLocalNetworkTitle.
  ///
  /// In en, this message translates to:
  /// **'Bypass local network'**
  String get bypassLocalNetworkTitle;

  /// No description provided for @bypassLocalNetworkSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Route private and LAN addresses directly'**
  String get bypassLocalNetworkSubtitle;

  /// No description provided for @russiaRoutesTitle.
  ///
  /// In en, this message translates to:
  /// **'Russia routes'**
  String get russiaRoutesTitle;

  /// No description provided for @russiaRoutesRunetFreedomBadge.
  ///
  /// In en, this message translates to:
  /// **'runetfreedom'**
  String get russiaRoutesRunetFreedomBadge;

  /// No description provided for @russiaRoutesDomainListBadge.
  ///
  /// In en, this message translates to:
  /// **'domain-list-community'**
  String get russiaRoutesDomainListBadge;

  /// No description provided for @russiaRoutesSubtitle.
  ///
  /// In en, this message translates to:
  /// **'The client locally copies runetfreedom bundles and downloads the required domain-list-community categories, then builds local rule-set files.'**
  String get russiaRoutesSubtitle;

  /// No description provided for @russiaRoutesInstallAction.
  ///
  /// In en, this message translates to:
  /// **'Prepare'**
  String get russiaRoutesInstallAction;

  /// No description provided for @russiaRoutesReinstallAction.
  ///
  /// In en, this message translates to:
  /// **'Update'**
  String get russiaRoutesReinstallAction;

  /// No description provided for @russiaRoutesUpdateAction.
  ///
  /// In en, this message translates to:
  /// **'Update'**
  String get russiaRoutesUpdateAction;

  /// No description provided for @russiaRoutesEnableTitle.
  ///
  /// In en, this message translates to:
  /// **'Use Russia routes'**
  String get russiaRoutesEnableTitle;

  /// No description provided for @russiaRoutesEnabledSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Required routes will be applied automatically: some through the proxy, some directly.'**
  String get russiaRoutesEnabledSubtitle;

  /// No description provided for @russiaRoutesMissingSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Prepare the route package first in order to use it.'**
  String get russiaRoutesMissingSubtitle;

  /// No description provided for @russiaRoutesPreparingStatus.
  ///
  /// In en, this message translates to:
  /// **'Preparing local route files...'**
  String get russiaRoutesPreparingStatus;

  /// No description provided for @russiaRoutesMissingStatus.
  ///
  /// In en, this message translates to:
  /// **'Local routes are not prepared yet'**
  String get russiaRoutesMissingStatus;

  /// No description provided for @russiaRoutesMissingHint.
  ///
  /// In en, this message translates to:
  /// **'The client will copy bundled runetfreedom `.srs`, download domain-list-community categories, and build local route files for sing-box.'**
  String get russiaRoutesMissingHint;

  /// No description provided for @russiaRoutesReadyStatus.
  ///
  /// In en, this message translates to:
  /// **'Routes are ready, version: {versionTag}'**
  String russiaRoutesReadyStatus(String versionTag);

  /// No description provided for @russiaRoutesMeta.
  ///
  /// In en, this message translates to:
  /// **'runetfreedom: {installedAt} · domain-list-community: {domainListUpdatedAt} · categories: {categoryCount} · domains: {domainCount}'**
  String russiaRoutesMeta(
    String installedAt,
    String domainListUpdatedAt,
    int categoryCount,
    int domainCount,
  );

  /// No description provided for @adBlockTitle.
  ///
  /// In en, this message translates to:
  /// **'Ad blocking'**
  String get adBlockTitle;

  /// No description provided for @adBlockSubtitle.
  ///
  /// In en, this message translates to:
  /// **'The client downloads a local rule-set itself and wires it into routing.'**
  String get adBlockSubtitle;

  /// No description provided for @adBlockDownloadAction.
  ///
  /// In en, this message translates to:
  /// **'Download'**
  String get adBlockDownloadAction;

  /// No description provided for @adBlockUpdateAction.
  ///
  /// In en, this message translates to:
  /// **'Update'**
  String get adBlockUpdateAction;

  /// No description provided for @adBlockEnableTitle.
  ///
  /// In en, this message translates to:
  /// **'Enable local blocking'**
  String get adBlockEnableTitle;

  /// No description provided for @adBlockEnabledSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Use the downloaded local rule-set for DNS and route reject.'**
  String get adBlockEnabledSubtitle;

  /// No description provided for @adBlockMissingSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Download the filter package first in order to use it.'**
  String get adBlockMissingSubtitle;

  /// No description provided for @adBlockDownloadingStatus.
  ///
  /// In en, this message translates to:
  /// **'Downloading and building the local filter...'**
  String get adBlockDownloadingStatus;

  /// No description provided for @adBlockMissingStatus.
  ///
  /// In en, this message translates to:
  /// **'Filter is not downloaded yet'**
  String get adBlockMissingStatus;

  /// No description provided for @adBlockMissingHint.
  ///
  /// In en, this message translates to:
  /// **'We download the list from AdGuard and keep it locally for sing-box.'**
  String get adBlockMissingHint;

  /// No description provided for @adBlockReadyStatus.
  ///
  /// In en, this message translates to:
  /// **'Filter is ready, domains: {blockedCount}'**
  String adBlockReadyStatus(int blockedCount);

  /// No description provided for @adBlockMeta.
  ///
  /// In en, this message translates to:
  /// **'Updated: {updatedAt} · exceptions: {allowedCount}'**
  String adBlockMeta(String updatedAt, int allowedCount);

  /// No description provided for @splitRoutingTitle.
  ///
  /// In en, this message translates to:
  /// **'Split routing'**
  String get splitRoutingTitle;

  /// No description provided for @splitRoutingSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Route selected Android packages through the proxy or bypass it'**
  String get splitRoutingSubtitle;

  /// No description provided for @splitRoutingModeTitle.
  ///
  /// In en, this message translates to:
  /// **'Mode'**
  String get splitRoutingModeTitle;

  /// No description provided for @splitRoutingModeDisabled.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get splitRoutingModeDisabled;

  /// No description provided for @splitRoutingModeDisabledSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Use the normal routing flow for all apps'**
  String get splitRoutingModeDisabledSubtitle;

  /// No description provided for @splitRoutingModeProxySelected.
  ///
  /// In en, this message translates to:
  /// **'Proxy selected'**
  String get splitRoutingModeProxySelected;

  /// No description provided for @splitRoutingModeProxySelectedSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Only the selected apps go through the proxy'**
  String get splitRoutingModeProxySelectedSubtitle;

  /// No description provided for @splitRoutingModeBypassSelected.
  ///
  /// In en, this message translates to:
  /// **'Bypass selected'**
  String get splitRoutingModeBypassSelected;

  /// No description provided for @splitRoutingModeBypassSelectedSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Selected apps bypass the proxy and go direct'**
  String get splitRoutingModeBypassSelectedSubtitle;

  /// No description provided for @splitRoutingAppsTitle.
  ///
  /// In en, this message translates to:
  /// **'Applications'**
  String get splitRoutingAppsTitle;

  /// No description provided for @splitRoutingPackagesTitle.
  ///
  /// In en, this message translates to:
  /// **'Package names'**
  String get splitRoutingPackagesTitle;

  /// No description provided for @splitRoutingPackagesHint.
  ///
  /// In en, this message translates to:
  /// **'com.termux\norg.mozilla.firefox'**
  String get splitRoutingPackagesHint;

  /// No description provided for @splitRoutingPackagesHelper.
  ///
  /// In en, this message translates to:
  /// **'One Android package name per line'**
  String get splitRoutingPackagesHelper;

  /// No description provided for @splitRoutingPickAppsAction.
  ///
  /// In en, this message translates to:
  /// **'Choose apps'**
  String get splitRoutingPickAppsAction;

  /// No description provided for @splitRoutingPickAppsTitle.
  ///
  /// In en, this message translates to:
  /// **'Choose apps'**
  String get splitRoutingPickAppsTitle;

  /// No description provided for @splitRoutingSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search by app or package name'**
  String get splitRoutingSearchHint;

  /// No description provided for @splitRoutingAndroidOnly.
  ///
  /// In en, this message translates to:
  /// **'App picker is available on Android only'**
  String get splitRoutingAndroidOnly;

  /// No description provided for @splitRoutingLoadAppsFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to load installed apps'**
  String get splitRoutingLoadAppsFailed;

  /// No description provided for @splitRoutingSelectedCount.
  ///
  /// In en, this message translates to:
  /// **'{count} selected'**
  String splitRoutingSelectedCount(int count);

  /// No description provided for @splitRoutingNoAppsTitle.
  ///
  /// In en, this message translates to:
  /// **'No apps selected yet'**
  String get splitRoutingNoAppsTitle;

  /// No description provided for @splitRoutingNoAppsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Pick Android apps to apply split routing to them'**
  String get splitRoutingNoAppsSubtitle;

  /// No description provided for @splitRoutingManualEditorTitle.
  ///
  /// In en, this message translates to:
  /// **'Manual package list'**
  String get splitRoutingManualEditorTitle;

  /// No description provided for @splitRoutingManualEditorSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Use this if you want to edit package names directly'**
  String get splitRoutingManualEditorSubtitle;

  /// No description provided for @snowtunTitle.
  ///
  /// In en, this message translates to:
  /// **'Snowtun'**
  String get snowtunTitle;

  /// No description provided for @snowtunSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Optional module for special connections'**
  String get snowtunSubtitle;

  /// No description provided for @snowtunDescription.
  ///
  /// In en, this message translates to:
  /// **'Install Snowtun only if a subscription explicitly needs it. Normal VPN connections work without this module.'**
  String get snowtunDescription;

  /// No description provided for @snowtunManifestUrlTitle.
  ///
  /// In en, this message translates to:
  /// **'Manifest URL'**
  String get snowtunManifestUrlTitle;

  /// No description provided for @snowtunManifestUrlHint.
  ///
  /// In en, this message translates to:
  /// **'https://host.example/snowtun/manifest.json'**
  String get snowtunManifestUrlHint;

  /// No description provided for @snowtunUpdateAction.
  ///
  /// In en, this message translates to:
  /// **'Update from server'**
  String get snowtunUpdateAction;

  /// No description provided for @snowtunDeleteAction.
  ///
  /// In en, this message translates to:
  /// **'Delete local binary'**
  String get snowtunDeleteAction;

  /// No description provided for @snowtunStatusTitle.
  ///
  /// In en, this message translates to:
  /// **'Local status'**
  String get snowtunStatusTitle;

  /// No description provided for @snowtunInstalledLabel.
  ///
  /// In en, this message translates to:
  /// **'Installed'**
  String get snowtunInstalledLabel;

  /// No description provided for @snowtunInstalledYes.
  ///
  /// In en, this message translates to:
  /// **'Yes'**
  String get snowtunInstalledYes;

  /// No description provided for @snowtunInstalledNo.
  ///
  /// In en, this message translates to:
  /// **'No'**
  String get snowtunInstalledNo;

  /// No description provided for @snowtunVersionLabel.
  ///
  /// In en, this message translates to:
  /// **'Version'**
  String get snowtunVersionLabel;

  /// No description provided for @snowtunChecksumLabel.
  ///
  /// In en, this message translates to:
  /// **'SHA-256'**
  String get snowtunChecksumLabel;

  /// No description provided for @snowtunSizeLabel.
  ///
  /// In en, this message translates to:
  /// **'Size'**
  String get snowtunSizeLabel;

  /// No description provided for @snowtunChunkCountLabel.
  ///
  /// In en, this message translates to:
  /// **'Chunks'**
  String get snowtunChunkCountLabel;

  /// No description provided for @snowtunPathLabel.
  ///
  /// In en, this message translates to:
  /// **'Binary path'**
  String get snowtunPathLabel;

  /// No description provided for @snowtunInstalledAtLabel.
  ///
  /// In en, this message translates to:
  /// **'Installed at'**
  String get snowtunInstalledAtLabel;

  /// No description provided for @snowtunImportSourceLabel.
  ///
  /// In en, this message translates to:
  /// **'Import source'**
  String get snowtunImportSourceLabel;

  /// No description provided for @snowtunImportSourceValue.
  ///
  /// In en, this message translates to:
  /// **'sing-box outbound only'**
  String get snowtunImportSourceValue;

  /// No description provided for @snowtunIdleStatus.
  ///
  /// In en, this message translates to:
  /// **'Ready.'**
  String get snowtunIdleStatus;

  /// No description provided for @snowtunFetchingManifest.
  ///
  /// In en, this message translates to:
  /// **'Preparing download…'**
  String get snowtunFetchingManifest;

  /// No description provided for @snowtunDownloadingChunks.
  ///
  /// In en, this message translates to:
  /// **'Downloading…'**
  String snowtunDownloadingChunks(int current, int total);

  /// No description provided for @snowtunFinalizing.
  ///
  /// In en, this message translates to:
  /// **'Finishing…'**
  String get snowtunFinalizing;

  /// No description provided for @snowtunUpdated.
  ///
  /// In en, this message translates to:
  /// **'Download completed.'**
  String get snowtunUpdated;

  /// No description provided for @snowtunInstalledMessage.
  ///
  /// In en, this message translates to:
  /// **'The component is installed.'**
  String get snowtunInstalledMessage;

  /// No description provided for @snowtunRemovingStatus.
  ///
  /// In en, this message translates to:
  /// **'Removing module…'**
  String get snowtunRemovingStatus;

  /// No description provided for @snowtunReadyShort.
  ///
  /// In en, this message translates to:
  /// **'Ready.'**
  String get snowtunReadyShort;

  /// No description provided for @snowtunNotInstalledShort.
  ///
  /// In en, this message translates to:
  /// **'The module is not installed yet.'**
  String get snowtunNotInstalledShort;

  /// No description provided for @snowtunPreparingInstallStatus.
  ///
  /// In en, this message translates to:
  /// **'Preparing install…'**
  String get snowtunPreparingInstallStatus;

  /// No description provided for @snowtunDownloadingModuleStatus.
  ///
  /// In en, this message translates to:
  /// **'Downloading module…'**
  String get snowtunDownloadingModuleStatus;

  /// No description provided for @snowtunInstallingStatus.
  ///
  /// In en, this message translates to:
  /// **'Installing…'**
  String get snowtunInstallingStatus;

  /// No description provided for @snowtunStoragePrepareFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to prepare Snowtun storage. Update the app and try again.'**
  String get snowtunStoragePrepareFailed;

  /// No description provided for @snowtunIntegrityFailed.
  ///
  /// In en, this message translates to:
  /// **'The downloaded file failed the integrity check.'**
  String get snowtunIntegrityFailed;

  /// No description provided for @snowtunInstallPermissionRequired.
  ///
  /// In en, this message translates to:
  /// **'Allow Etonify to install additional modules, then try again.'**
  String get snowtunInstallPermissionRequired;

  /// No description provided for @snowtunInstallPermissionTitle.
  ///
  /// In en, this message translates to:
  /// **'Install permission'**
  String get snowtunInstallPermissionTitle;

  /// No description provided for @snowtunInstallPermissionMessage.
  ///
  /// In en, this message translates to:
  /// **'Snowtun is installed as an optional module. Android needs permission to install from this app; the base VPN still works without this module.'**
  String get snowtunInstallPermissionMessage;

  /// No description provided for @snowtunInstallPermissionSkip.
  ///
  /// In en, this message translates to:
  /// **'Not now'**
  String get snowtunInstallPermissionSkip;

  /// No description provided for @snowtunInstallPermissionAllow.
  ///
  /// In en, this message translates to:
  /// **'Allow'**
  String get snowtunInstallPermissionAllow;

  /// No description provided for @snowtunLaunchPrepareFailed.
  ///
  /// In en, this message translates to:
  /// **'The file was downloaded, but Android did not allow preparing it for launch.'**
  String get snowtunLaunchPrepareFailed;

  /// No description provided for @snowtunDownloadedFileMissing.
  ///
  /// In en, this message translates to:
  /// **'The downloaded file was not found.'**
  String get snowtunDownloadedFileMissing;

  /// No description provided for @snowtunDownloadModuleFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to download the module from the server.'**
  String get snowtunDownloadModuleFailed;

  /// No description provided for @snowtunNoCompatibleModule.
  ///
  /// In en, this message translates to:
  /// **'No compatible Snowtun module is available for this device.'**
  String get snowtunNoCompatibleModule;

  /// No description provided for @snowtunInstallOrRemoveFailedWithDetail.
  ///
  /// In en, this message translates to:
  /// **'Android failed to install or remove the module: {detail}'**
  String snowtunInstallOrRemoveFailedWithDetail(String detail);

  /// No description provided for @snowtunInstallOrRemoveFailed.
  ///
  /// In en, this message translates to:
  /// **'Android failed to install or remove the optional module.'**
  String get snowtunInstallOrRemoveFailed;

  /// No description provided for @snowtunWrongAppVersion.
  ///
  /// In en, this message translates to:
  /// **'This module was built for a different app version.'**
  String get snowtunWrongAppVersion;

  /// No description provided for @snowtunIncompatibleModulePackage.
  ///
  /// In en, this message translates to:
  /// **'The server returned an incompatible module package.'**
  String get snowtunIncompatibleModulePackage;

  /// No description provided for @snowtunGenericFailure.
  ///
  /// In en, this message translates to:
  /// **'Failed to download or install the component.'**
  String get snowtunGenericFailure;

  /// No description provided for @snowtunModuleDescription.
  ///
  /// In en, this message translates to:
  /// **'Snowtun is an optional Android module for specific outbound types. Leave it uninstalled unless your provider requires it.'**
  String get snowtunModuleDescription;

  /// No description provided for @snowtunInstalledSummary.
  ///
  /// In en, this message translates to:
  /// **'Already installed'**
  String get snowtunInstalledSummary;

  /// No description provided for @snowtunNotInstalledSummary.
  ///
  /// In en, this message translates to:
  /// **'Not installed yet'**
  String get snowtunNotInstalledSummary;

  /// No description provided for @snowtunInstallModuleAction.
  ///
  /// In en, this message translates to:
  /// **'Install module'**
  String get snowtunInstallModuleAction;

  /// No description provided for @snowtunRemoveModuleAction.
  ///
  /// In en, this message translates to:
  /// **'Remove module'**
  String get snowtunRemoveModuleAction;

  /// No description provided for @refreshIntervalDaysShort.
  ///
  /// In en, this message translates to:
  /// **'{count} d'**
  String refreshIntervalDaysShort(int count);

  /// No description provided for @refreshIntervalHoursShort.
  ///
  /// In en, this message translates to:
  /// **'{count} h'**
  String refreshIntervalHoursShort(int count);

  /// No description provided for @refreshIntervalMinutesShort.
  ///
  /// In en, this message translates to:
  /// **'{count} min'**
  String refreshIntervalMinutesShort(int count);

  /// No description provided for @happCrypt5Supported.
  ///
  /// In en, this message translates to:
  /// **'Supported'**
  String get happCrypt5Supported;

  /// No description provided for @happCrypt5Unsupported.
  ///
  /// In en, this message translates to:
  /// **'Not supported'**
  String get happCrypt5Unsupported;

  /// No description provided for @happCrypt5Checking.
  ///
  /// In en, this message translates to:
  /// **'Checking happ://crypt5/... decrypt support'**
  String get happCrypt5Checking;

  /// No description provided for @happCrypt5SupportedDescription.
  ///
  /// In en, this message translates to:
  /// **'Your device can decrypt Happ crypt5 crypto links directly in the app.'**
  String get happCrypt5SupportedDescription;

  /// No description provided for @happCrypt5UnsupportedDescription.
  ///
  /// In en, this message translates to:
  /// **'Happ crypt5 decrypt is currently unavailable on this device.'**
  String get happCrypt5UnsupportedDescription;

  /// No description provided for @subscriptionLikelyRequiresHwidTitle.
  ///
  /// In en, this message translates to:
  /// **'HWID may be required'**
  String get subscriptionLikelyRequiresHwidTitle;

  /// No description provided for @subscriptionLikelyRequiresHwidWarning.
  ///
  /// In en, this message translates to:
  /// **'This subscription probably requires HWID. The server returned only one outbound with app/HWID in its name. Open the subscription settings and enable HWID sending.'**
  String get subscriptionLikelyRequiresHwidWarning;

  /// No description provided for @subscriptionLikelyRequiresHwidMessage.
  ///
  /// In en, this message translates to:
  /// **'The server returned only one outbound, and its name looks like a placeholder related to app or HWID.\n\nThis usually means the subscription expects the device HWID in the request.\n\nEnable HWID sending now and update the subscription again?'**
  String get subscriptionLikelyRequiresHwidMessage;

  /// No description provided for @subscriptionLikelyRequiresHwidAction.
  ///
  /// In en, this message translates to:
  /// **'Enable HWID'**
  String get subscriptionLikelyRequiresHwidAction;

  /// No description provided for @subscriptionHwidEnabledAndUpdated.
  ///
  /// In en, this message translates to:
  /// **'HWID sending enabled. The subscription was updated.'**
  String get subscriptionHwidEnabledAndUpdated;

  /// No description provided for @noValidOutboundsTitle.
  ///
  /// In en, this message translates to:
  /// **'No working nodes'**
  String get noValidOutboundsTitle;

  /// No description provided for @noValidOutboundsWarning.
  ///
  /// In en, this message translates to:
  /// **'There are no working outbounds left in this subscription. They were filtered out during validation. Check the subscription or update it.'**
  String get noValidOutboundsWarning;

  /// No description provided for @noValidOutboundsMessage.
  ///
  /// In en, this message translates to:
  /// **'This subscription does not have any working outbounds left.\n\nAll nodes were filtered out during validation before startup, so the client will not try to launch sing-box with an empty proxy set.\n\nCheck the subscription, refresh it, or import a valid one.'**
  String get noValidOutboundsMessage;

  /// No description provided for @noValidOutboundsAfterDropInvalidWarning.
  ///
  /// In en, this message translates to:
  /// **'There are no working outbounds left in the selected subscription after invalid nodes were dropped. Check the subscription, something looks wrong with it.'**
  String get noValidOutboundsAfterDropInvalidWarning;

  /// No description provided for @noValidOutboundsAfterDropInvalidMessage.
  ///
  /// In en, this message translates to:
  /// **'All remaining nodes in the selected subscription were dropped as invalid during startup.\n\nThe client stopped before handing a broken config to sing-box.\n\nCheck the subscription content and update or replace it.'**
  String get noValidOutboundsAfterDropInvalidMessage;

  /// No description provided for @experimentalTcpFastOpenTitle.
  ///
  /// In en, this message translates to:
  /// **'TCP Fast Open'**
  String get experimentalTcpFastOpenTitle;

  /// No description provided for @experimentalTcpFastOpenSubtitle.
  ///
  /// In en, this message translates to:
  /// **'May reduce TCP handshake time, but support depends on the network and server.'**
  String get experimentalTcpFastOpenSubtitle;

  /// No description provided for @experimentalTcpMultiPathTitle.
  ///
  /// In en, this message translates to:
  /// **'TCP Multipath'**
  String get experimentalTcpMultiPathTitle;

  /// No description provided for @experimentalTcpMultiPathSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Tries multiple network paths. Can help handoff, but may heat the phone or behave unstably.'**
  String get experimentalTcpMultiPathSubtitle;

  /// No description provided for @experimentalInterruptConnectionsTitle.
  ///
  /// In en, this message translates to:
  /// **'Interrupt active connections on node change'**
  String get experimentalInterruptConnectionsTitle;

  /// No description provided for @experimentalInterruptConnectionsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Applies proxy changes faster, but old app connections can be dropped.'**
  String get experimentalInterruptConnectionsSubtitle;

  /// No description provided for @experimentalUrlTestStrictToleranceTitle.
  ///
  /// In en, this message translates to:
  /// **'URLTest 1 ms tolerance'**
  String get experimentalUrlTestStrictToleranceTitle;

  /// No description provided for @experimentalUrlTestStrictToleranceSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Selects the lowest-latency proxy more strictly, but may switch servers more often.'**
  String get experimentalUrlTestStrictToleranceSubtitle;

  /// No description provided for @blockLeaksTitle.
  ///
  /// In en, this message translates to:
  /// **'Fix some leaks'**
  String get blockLeaksTitle;

  /// No description provided for @blockLeaksSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Blocks only STUN/WebRTC traffic that may bypass the proxy'**
  String get blockLeaksSubtitle;

  /// No description provided for @addSubscriptionCaption.
  ///
  /// In en, this message translates to:
  /// **'Add a subscription from a link or file'**
  String get addSubscriptionCaption;

  /// No description provided for @pasteSubscriptionLink.
  ///
  /// In en, this message translates to:
  /// **'Paste subscription link'**
  String get pasteSubscriptionLink;

  /// No description provided for @orManually.
  ///
  /// In en, this message translates to:
  /// **'Or manually'**
  String get orManually;

  /// No description provided for @pasteAction.
  ///
  /// In en, this message translates to:
  /// **'Paste'**
  String get pasteAction;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'ru'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'ru':
      return AppLocalizationsRu();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}

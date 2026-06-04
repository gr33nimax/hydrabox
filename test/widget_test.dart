import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meow_client/app/app.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:meow_client/core/lowest_proxy_groups.dart';
import 'package:meow_client/data/local/app_settings_store.dart';
import 'package:meow_client/features/home/home_page.dart';
import 'package:meow_client/features/home/traffic_dashboard_page.dart';
import 'package:meow_client/features/proxies/proxies_page.dart';
import 'package:meow_client/features/proxies/proxy_panel_shell.dart';
import 'package:meow_client/features/settings/settings_about_page.dart';
import 'package:meow_client/l10n/generated/app_localizations.dart';
import 'package:meow_client/models/app_view_models.dart';
import 'package:meow_client/widgets/country_flag_badge.dart';

void main() {
  testWidgets('renders cloned mobile shell', (tester) async {
    await tester.pumpWidget(
      MeowClient(
        store: MemoryAppSettingsStore(
          const AppSettingsState(
            onboardingCompleted: true,
            activeProfileId: '',
            selectedProxyTag: '',
            localeCode: 'system',
            themePreference: AppThemePreference.system,
            accentColorHex: 'default',
            hapticEnabled: true,
            hideServerIp: false,
            progressiveBlurEnabled: true,
            vpnInboundEnabled: true,
            vpnMtu: 3400,
            vpnStrictRoute: true,
            vpnTunImplementation: TunImplementationPreference.mixed,
            proxyInboundEnabled: false,
            proxyAllowLan: false,
            proxyMixedListen: '127.0.0.1',
            proxyMixedPort: 1080,
            dnsDirectPreset: 'cloudflare',
            dnsDirectResolver: 'udp://1.1.1.1',
            dnsProxyPreset: 'cloudflare',
            dnsProxyResolver: 'https://dns.cloudflare.com/dns-query',
            dnsPreferIpv6: false,
            urlTestUrl: 'https://www.gstatic.com/generate_204',
            urlTestIntervalSeconds: 180,
            urlTestTimeoutSeconds: 15,
            urlTestConcurrency: 30,
            urlTestUnavailableCheckIntervalSeconds: 2,
            locationLookupLimit: 12,
            locationLookupTimeoutSeconds: 6,
            locationLookupConcurrency: 16,
            blockLeaks: false,
            adBlockEnabled: false,
            useRussiaRouteData: false,
            bypassLocalNetwork: true,
            splitRoutingMode: SplitRoutingMode.disabled,
            splitRoutingPackages: <String>[],
            singBoxLogLevel: 'info',
            experimentalTcpFastOpen: true,
            experimentalTcpMultiPath: true,
            experimentalInterruptExistingConnections: true,
            experimentalUrlTestStrictTolerance: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Etonify'), findsOneWidget);
    expect(find.text('MeowVPN'), findsNothing);
    expect(find.text('No subscriptions yet'), findsOneWidget);
    expect(find.byIcon(Icons.settings_rounded), findsOneWidget);
  });

  testWidgets('welcome uses Etonify before onboarding is completed', (
    tester,
  ) async {
    await tester.pumpWidget(
      MeowClient(
        store: MemoryAppSettingsStore(
          const AppSettingsState(
            onboardingCompleted: false,
            activeProfileId: '',
            selectedProxyTag: '',
            localeCode: 'system',
            themePreference: AppThemePreference.system,
            accentColorHex: 'default',
            hapticEnabled: true,
            hideServerIp: false,
            progressiveBlurEnabled: true,
            vpnInboundEnabled: true,
            vpnMtu: 3400,
            vpnStrictRoute: true,
            vpnTunImplementation: TunImplementationPreference.mixed,
            proxyInboundEnabled: false,
            proxyAllowLan: false,
            proxyMixedListen: '127.0.0.1',
            proxyMixedPort: 1080,
            dnsDirectPreset: 'cloudflare',
            dnsDirectResolver: 'udp://1.1.1.1',
            dnsProxyPreset: 'cloudflare',
            dnsProxyResolver: 'https://dns.cloudflare.com/dns-query',
            dnsPreferIpv6: false,
            urlTestUrl: 'https://www.gstatic.com/generate_204',
            urlTestIntervalSeconds: 180,
            urlTestTimeoutSeconds: 15,
            urlTestConcurrency: 30,
            urlTestUnavailableCheckIntervalSeconds: 2,
            locationLookupLimit: 12,
            locationLookupTimeoutSeconds: 6,
            locationLookupConcurrency: 16,
            blockLeaks: false,
            adBlockEnabled: false,
            useRussiaRouteData: false,
            bypassLocalNetwork: true,
            splitRoutingMode: SplitRoutingMode.disabled,
            splitRoutingPackages: <String>[],
            singBoxLogLevel: 'info',
            experimentalTcpFastOpen: true,
            experimentalTcpMultiPath: true,
            experimentalInterruptExistingConnections: true,
            experimentalUrlTestStrictTolerance: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Etonify'), findsOneWidget);
    expect(find.text('No subscriptions yet'), findsNothing);
    expect(find.byIcon(Icons.settings_rounded), findsNothing);
  });

  testWidgets('opens settings page from home header', (tester) async {
    await tester.pumpWidget(
      MeowClient(
        store: MemoryAppSettingsStore(
          const AppSettingsState(
            onboardingCompleted: true,
            activeProfileId: '',
            selectedProxyTag: '',
            localeCode: 'system',
            themePreference: AppThemePreference.system,
            accentColorHex: 'default',
            hapticEnabled: true,
            hideServerIp: false,
            progressiveBlurEnabled: true,
            vpnInboundEnabled: true,
            vpnMtu: 3400,
            vpnStrictRoute: true,
            vpnTunImplementation: TunImplementationPreference.mixed,
            proxyInboundEnabled: false,
            proxyAllowLan: false,
            proxyMixedListen: '127.0.0.1',
            proxyMixedPort: 1080,
            dnsDirectPreset: 'cloudflare',
            dnsDirectResolver: 'udp://1.1.1.1',
            dnsProxyPreset: 'cloudflare',
            dnsProxyResolver: 'https://dns.cloudflare.com/dns-query',
            dnsPreferIpv6: false,
            urlTestUrl: 'https://www.gstatic.com/generate_204',
            urlTestIntervalSeconds: 180,
            urlTestTimeoutSeconds: 15,
            urlTestConcurrency: 30,
            urlTestUnavailableCheckIntervalSeconds: 2,
            locationLookupLimit: 12,
            locationLookupTimeoutSeconds: 6,
            locationLookupConcurrency: 16,
            blockLeaks: false,
            adBlockEnabled: false,
            useRussiaRouteData: false,
            bypassLocalNetwork: true,
            splitRoutingMode: SplitRoutingMode.disabled,
            splitRoutingPackages: <String>[],
            singBoxLogLevel: 'info',
            experimentalTcpFastOpen: true,
            experimentalTcpMultiPath: true,
            experimentalInterruptExistingConnections: true,
            experimentalUrlTestStrictTolerance: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.settings_rounded));
    await tester.pumpAndSettle();

    expect(find.text('Settings'), findsOneWidget);
  });

  testWidgets('proxy panel shell opens and collapses with local state', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ProxyPanelShell(
          ready: true,
          onboardingCompleted: true,
          loading: const SizedBox.shrink(),
          welcome: const SizedBox.shrink(),
          visibleRows: 20,
          hasActiveProfile: true,
          homeBuilder: (context, metrics, gestures) {
            return ColoredBox(
              color: Colors.white,
              child: Align(
                alignment: Alignment.topCenter,
                child: Text('home:${metrics.progress.toStringAsFixed(2)}'),
              ),
            );
          },
          sheetBuilder:
              (
                context,
                metrics,
                metricsListenable,
                scrollController,
                gestures,
              ) {
                return Material(
                  child: ValueListenableBuilder<ProxyPanelMetrics>(
                    valueListenable: metricsListenable,
                    builder: (context, liveMetrics, _) {
                      return GestureDetector(
                        key: const ValueKey('proxy-panel-header'),
                        behavior: HitTestBehavior.opaque,
                        onTap: gestures.onHeaderTap,
                        onVerticalDragUpdate: gestures.onDragUpdate,
                        onVerticalDragEnd: gestures.onDragEnd,
                        child: ListView.builder(
                          controller: scrollController,
                          padding: EdgeInsets.zero,
                          itemCount: 24,
                          itemBuilder: (context, index) => SizedBox(
                            height: index == 0 ? proxyPanelMinHeight : 48,
                            child: Text(
                              index == 0
                                  ? 'panel:${liveMetrics.progress.toStringAsFixed(2)}'
                                  : 'proxy-$index',
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                );
              },
        ),
      ),
    );

    expect(find.text('panel:0.00'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('proxy-panel-header')));
    await tester.pumpAndSettle();

    expect(find.text('panel:1.00'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('proxy-panel-header')));
    await tester.pumpAndSettle();

    expect(find.text('panel:0.00'), findsOneWidget);
  });

  testWidgets('embedded proxy sheet hides synthetic lowest rows', (
    tester,
  ) async {
    final proxies = <AppProxySummary>[
      _proxy(lowestProxyTag, 'lowest'),
      _proxy(lowestOpenProxyTag, 'lowest open'),
      _proxy(lowestFreeProxyTag, 'lowest free'),
      for (var i = 0; i < 80; i++)
        _proxy('proxy-$i', 'proxy $i', latency: i + 1),
      _proxy('chain-test', 'chain · Germany', latency: 999),
    ];

    await tester.pumpWidget(
      MaterialApp(
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Scaffold(
          body: SizedBox(
            height: 720,
            child: ProxiesPage(
              proxies: proxies,
              totalTopLevelProxies: proxies.length,
              selectedTag: lowestProxyTag,
              connected: false,
              progressiveBlurEnabled: false,
              onSelected: (_) {},
              onUrlTest: () async {},
              onAddProxyChain: (_, _) async {},
              isProxyChainTag: (tag) => tag == 'chain-test',
              embedded: true,
              sheetAtMaxExtent: true,
              sheetExtent: 1,
              collapsedSheetExtent: 0,
              expandedHeaderExtent: 1,
            ),
          ),
        ),
      ),
    );

    expect(find.text('lowest'), findsNothing);
    expect(find.text('lowest open'), findsNothing);
    expect(find.text('lowest free'), findsNothing);
    expect(find.byIcon(FluentIcons.more_horizontal_24_regular), findsNothing);
    expect(find.text('chain · Germany'), findsOneWidget);
    expect(find.text('+ add proxy chain'), findsNothing);
  });

  testWidgets('embedded proxy list uses SVG flag badges when expanded', (
    tester,
  ) async {
    final proxies = <AppProxySummary>[
      _proxy('proxy-1', 'proxy 1', latency: 42),
      _proxy('proxy-2', 'proxy 2', latency: 84),
    ];

    await tester.pumpWidget(
      MaterialApp(
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Scaffold(
          body: SizedBox(
            height: 720,
            child: ProxiesPage(
              proxies: proxies,
              totalTopLevelProxies: proxies.length,
              selectedTag: 'proxy-1',
              connected: false,
              progressiveBlurEnabled: false,
              onSelected: (_) {},
              onUrlTest: () async {},
              embedded: true,
              sheetAtMaxExtent: true,
              sheetExtent: 1,
            ),
          ),
        ),
      ),
    );

    expect(find.byType(CountryFlagBadge), findsWidgets);
    expect(find.text('proxy 1'), findsOneWidget);
  });

  testWidgets('proxy sheet header never overlaps active proxy and title', (
    tester,
  ) async {
    final activeProxy = _proxy(
      'active-proxy',
      'Active Poland',
      latency: 96,
    ).copyWith(ip: '57.128.200.35');
    final proxies = <AppProxySummary>[
      _proxy('proxy-1', 'Austria', latency: 42),
      _proxy('proxy-2', 'Germany', latency: 84),
    ];

    Future<void> pumpAt(double extent) async {
      await tester.pumpWidget(
        MaterialApp(
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: Scaffold(
            body: SizedBox(
              height: 720,
              child: ProxiesPage(
                proxies: proxies,
                totalTopLevelProxies: proxies.length,
                selectedTag: 'proxy-1',
                activeProxy: activeProxy,
                connected: true,
                progressiveBlurEnabled: false,
                onSelected: (_) {},
                onUrlTest: () async {},
                embedded: true,
                sheetAtMaxExtent: extent >= 1,
                sheetExtent: extent,
                collapsedSheetExtent: 0,
                expandedHeaderExtent: 1,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    await pumpAt(.20);
    expect(find.text('Active Poland'), findsOneWidget);
    expect(find.text('Proxies'), findsNothing);

    await pumpAt(.42);
    expect(find.text('Active Poland'), findsNothing);
    expect(find.text('Proxies'), findsNothing);

    await pumpAt(.70);
    expect(find.text('Active Poland'), findsNothing);
    expect(find.text('Proxies'), findsOneWidget);
  });

  testWidgets('closed proxy panel does not build proxy rows', (tester) async {
    final proxies = <AppProxySummary>[
      _proxy('proxy-1', 'proxy 1', latency: 42),
      _proxy('proxy-2', 'proxy 2', latency: 84),
    ];

    await tester.pumpWidget(
      MaterialApp(
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Scaffold(
          body: SizedBox(
            height: 720,
            child: ProxiesPage(
              proxies: proxies,
              totalTopLevelProxies: proxies.length,
              selectedTag: 'proxy-1',
              activeProxy: proxies.first,
              connected: false,
              progressiveBlurEnabled: false,
              onSelected: (_) {},
              onUrlTest: () async {},
              embedded: true,
              sheetAtMaxExtent: false,
              sheetExtent: 0,
            ),
          ),
        ),
      ),
    );

    expect(find.text('proxy 1'), findsOneWidget);
    expect(find.text('proxy 2'), findsNothing);
  });

  testWidgets('embedded proxy row updates latency from runtime notifier', (
    tester,
  ) async {
    final proxies = <AppProxySummary>[
      _proxy('proxy-1', 'proxy 1', latency: 42),
    ];
    final runtimeStates = ProxyRuntimeVisualStore();
    addTearDown(runtimeStates.dispose);

    await tester.pumpWidget(
      MaterialApp(
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Scaffold(
          body: SizedBox(
            height: 720,
            child: ProxiesPage(
              proxies: proxies,
              totalTopLevelProxies: proxies.length,
              selectedTag: 'proxy-1',
              connected: false,
              progressiveBlurEnabled: false,
              onSelected: (_) {},
              onUrlTest: () async {},
              embedded: true,
              sheetAtMaxExtent: true,
              sheetExtent: 1,
              runtimeStates: runtimeStates,
            ),
          ),
        ),
      ),
    );

    expect(find.text('42 ms'), findsOneWidget);

    runtimeStates.replaceAll(const <String, ProxyRuntimeVisualState>{
      'proxy-1': ProxyRuntimeVisualState(latency: 7, latencyFresh: true),
    });
    await tester.pump();

    expect(find.text('7 ms'), findsOneWidget);
  });

  testWidgets(
    'embedded proxy row shows switching feedback from runtime notifier',
    (tester) async {
      final proxies = <AppProxySummary>[
        _proxy('proxy-1', 'proxy 1', latency: 42),
      ];
      final runtimeStates = ProxyRuntimeVisualStore();
      addTearDown(runtimeStates.dispose);

      await tester.pumpWidget(
        MaterialApp(
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: Scaffold(
            body: SizedBox(
              height: 720,
              child: ProxiesPage(
                proxies: proxies,
                totalTopLevelProxies: proxies.length,
                selectedTag: 'proxy-1',
                connected: true,
                progressiveBlurEnabled: false,
                onSelected: (_) {},
                onUrlTest: () async {},
                embedded: true,
                sheetAtMaxExtent: true,
                sheetExtent: 1,
                runtimeStates: runtimeStates,
              ),
            ),
          ),
        ),
      );

      runtimeStates.replaceAll(const <String, ProxyRuntimeVisualState>{
        'proxy-1': ProxyRuntimeVisualState(selecting: true),
      });
      await tester.pump();

      expect(find.text('Switching'), findsOneWidget);
    },
  );

  testWidgets('embedded proxy rows use larger flag hit visuals', (
    tester,
  ) async {
    final proxies = <AppProxySummary>[
      _proxy('proxy-1', 'proxy 1', latency: 42),
    ];

    await tester.pumpWidget(
      MaterialApp(
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Scaffold(
          body: SizedBox(
            height: 720,
            child: ProxiesPage(
              proxies: proxies,
              totalTopLevelProxies: proxies.length,
              selectedTag: 'proxy-1',
              connected: false,
              progressiveBlurEnabled: false,
              onSelected: (_) {},
              onUrlTest: () async {},
              embedded: true,
              sheetAtMaxExtent: true,
              sheetExtent: 1,
            ),
          ),
        ),
      ),
    );

    expect(tester.getSize(find.byType(CountryFlagBadge).first).height, 36);
  });

  testWidgets('shows no proxies empty state for an empty proxy list', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Scaffold(
          body: ProxiesPage(
            proxies: const [],
            totalTopLevelProxies: 0,
            selectedTag: '',
            connected: false,
            progressiveBlurEnabled: false,
            onSelected: (_) {},
            onUrlTest: () async {},
          ),
        ),
      ),
    );

    final l10n = await AppLocalizations.delegate.load(const Locale('en'));

    expect(find.text(l10n.noProxies), findsOneWidget);
    expect(find.text('No subscriptions yet'), findsNothing);
  });

  testWidgets('active proxy delay indicator keeps visual ping tap target', (
    tester,
  ) async {
    var refreshCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Scaffold(
          body: Center(
            child: ActiveProxyDelayIndicator(
              connected: true,
              proxy: _proxy('proxy-1', 'proxy 1', latency: 42),
              onRefresh: () => refreshCount++,
            ),
          ),
        ),
      ),
    );

    expect(find.byIcon(FluentIcons.wifi_1_24_regular), findsOneWidget);

    await tester.tap(find.byType(InkWell));
    await tester.pump();

    expect(refreshCount, 1);
  });

  testWidgets('active proxy delay indicator is inactive when disconnected', (
    tester,
  ) async {
    var refreshCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Scaffold(
          body: Center(
            child: ActiveProxyDelayIndicator(
              connected: false,
              proxy: _proxy('proxy-1', 'proxy 1', latency: 42),
              onRefresh: () => refreshCount++,
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byType(InkWell), warnIfMissed: false);
    await tester.pump();

    expect(refreshCount, 0);
  });

  testWidgets('active proxy footer hides IP and traffic when disconnected', (
    tester,
  ) async {
    final proxy = _proxy(
      'proxy-1',
      'Poland',
      latency: 42,
    ).copyWith(ip: '57.128.200.35');

    await tester.pumpWidget(
      MaterialApp(
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Scaffold(
          body: Center(
            child: ActiveProxyFooter(
              connected: false,
              proxy: proxy,
              hideIp: false,
              hapticEnabled: false,
              speedBytesPerSecond: 44 * 1024,
              trafficBytes: 96.2 * 1024 * 1024,
              unknownText: '?',
              onHideIpChanged: (_) {},
            ),
          ),
        ),
      ),
    );

    expect(find.text('Poland'), findsOneWidget);
    expect(find.text('57.128.200.35'), findsNothing);
    expect(find.text('—'), findsOneWidget);
    expect(find.text('0.00 B/s'), findsOneWidget);
    expect(find.text('0.00 B'), findsOneWidget);
  });

  testWidgets('active proxy delay indicator shows checking state once', (
    tester,
  ) async {
    var refreshCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Scaffold(
          body: Center(
            child: ActiveProxyDelayIndicator(
              connected: true,
              proxy: AppProxySummary(
                tag: 'proxy-1',
                displayName: 'proxy 1',
                countryCode: 'DE',
                type: 'vless',
                server: 'proxy-1.example.com',
                port: 443,
                detailText: 'VLESS',
                ip: '',
                latency: 42,
                latencyFresh: true,
                latencyChecking: true,
                latencyUnavailable: false,
                latencyError: null,
                protocolLabel: 'VLESS',
                endpointLabel: 'proxy-1.example.com',
              ),
              onRefresh: () => refreshCount++,
            ),
          ),
        ),
      ),
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Checking…'), findsOneWidget);

    await tester.tap(find.text('Checking…'));
    await tester.pump();

    expect(refreshCount, 0);
  });

  testWidgets('active profile refresh button calls current refresh callback', (
    tester,
  ) async {
    var refreshCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: HomePage(
          connected: false,
          connecting: false,
          resolvingProxy: false,
          activeProfile: const AppProfileSummary(
            id: 'sub-1',
            name: 'Main subscription',
            consumed: 0,
            total: 0,
            remainingDays: null,
            outboundsCount: 1,
            sourceLabel: '',
          ),
          activeProxy: null,
          hideServerIp: false,
          hapticEnabled: false,
          speedBytesPerSecond: 0,
          trafficBytes: 0,
          onToggleConnection: () {},
          onRefreshLatency: () {},
          onHideServerIpChanged: (_) {},
          onOpenSubscriptions: () {},
          onAddSubscription: () {},
          onOpenSettings: () {},
          brandName: 'Etonify',
          bottomInset: 0,
          showActiveProfileRefreshAction: true,
          onRefreshActiveSubscription: () async {
            refreshCount++;
          },
        ),
      ),
    );

    await tester.tap(find.byIcon(Icons.update_rounded));
    await tester.pump();

    expect(refreshCount, 1);
  });

  testWidgets('active profile refresh button shows loading state', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: HomePage(
          connected: false,
          connecting: false,
          resolvingProxy: false,
          activeProfile: const AppProfileSummary(
            id: 'sub-1',
            name: 'Main subscription',
            consumed: 0,
            total: 0,
            remainingDays: null,
            outboundsCount: 1,
            sourceLabel: '',
          ),
          activeProxy: null,
          hideServerIp: false,
          hapticEnabled: false,
          speedBytesPerSecond: 0,
          trafficBytes: 0,
          onToggleConnection: () {},
          onRefreshLatency: () {},
          onHideServerIpChanged: (_) {},
          onOpenSubscriptions: () {},
          onAddSubscription: () {},
          onOpenSettings: () {},
          brandName: 'Etonify',
          bottomInset: 0,
          showActiveProfileRefreshAction: true,
          activeProfileRefreshing: true,
          onRefreshActiveSubscription: () async {},
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('profile-refresh-progress')),
      findsOneWidget,
    );
  });

  testWidgets('traffic dashboard renders live metrics and graph', (
    tester,
  ) async {
    final notifier = ValueNotifier<TrafficDashboardSnapshot>(
      TrafficDashboardSnapshot(
        connected: true,
        connecting: false,
        trafficAvailable: true,
        hideServerIp: false,
        downlinkBps: 2048,
        uplinkBps: 1024,
        uplinkTotalBytes: 4096,
        downlinkTotalBytes: 8192,
        connectedSince: DateTime.now().subtract(const Duration(seconds: 90)),
        activeProfile: const AppProfileSummary(
          id: 'sub-1',
          name: 'Main subscription',
          consumed: 0,
          total: 0,
          remainingDays: null,
          outboundsCount: 1,
          sourceLabel: '',
        ),
        activeProxy: _proxy('proxy-1', 'proxy 1', latency: 42),
        samples: [
          TrafficSample(
            timestamp: DateTime.now().subtract(const Duration(seconds: 2)),
            downlinkBps: 1024,
            uplinkBps: 512,
            totalBytes: 1024,
          ),
          TrafficSample(
            timestamp: DateTime.now().subtract(const Duration(seconds: 1)),
            downlinkBps: 2048,
            uplinkBps: 1024,
            totalBytes: 2048,
          ),
        ],
      ),
    );
    addTearDown(notifier.dispose);

    await tester.pumpWidget(
      MaterialApp(
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: TrafficDashboardPage(snapshotListenable: notifier),
      ),
    );

    expect(find.text('Traffic dashboard'), findsOneWidget);
    expect(find.text('2.00 KB/s'), findsOneWidget);
    expect(find.text('1.00 KB/s'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('traffic-dashboard-graph')),
      findsOneWidget,
    );
  });

  testWidgets('about page opens MeowTeam timeline', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: SettingsAboutPage(
          versionLabel: '0.1.0',
          onShowOnboarding: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Etonify v0.1.0'), findsNothing);
    expect(find.text('Client version'), findsOneWidget);
    expect(find.text('0.1.0'), findsOneWidget);
    expect(find.text('MeowVPN'), findsNothing);
    expect(find.text('dudosxdev/sing-box'), findsOneWidget);

    final teamAction = find.ancestor(
      of: find.text('MeowTeam'),
      matching: find.byType(InkWell),
    );
    await tester.tap(teamAction.first);
    await tester.pumpAndSettle();

    expect(find.text('The team behind Etonify'), findsOneWidget);
    expect(find.text('Started as a Hiddify fork'), findsOneWidget);
    expect(find.text('MeowSingBox core'), findsOneWidget);

    await tester.scrollUntilVisible(find.text('ddosxd'), 500);
    expect(find.text('ddosxd'), findsOneWidget);
    expect(find.text('yamixdev'), findsOneWidget);
    expect(find.text('© 2026 MeowTeam™'), findsOneWidget);
  });

  testWidgets('unsupported system locale falls back to English', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('fr'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        localeResolutionCallback: (locale, supportedLocales) {
          if (locale?.languageCode.toLowerCase() == 'ru') {
            return const Locale('ru');
          }
          return const Locale('en');
        },
        home: Builder(
          builder: (context) {
            return Text(AppLocalizations.of(context).settingsTitle);
          },
        ),
      ),
    );

    expect(find.text('Settings'), findsOneWidget);
  });

  test('subscription server count labels are localized', () async {
    final en = await AppLocalizations.delegate.load(const Locale('en'));
    final ru = await AppLocalizations.delegate.load(const Locale('ru'));

    expect(en.subscriptionServersCount(13), '13 servers');
    expect(en.subscriptionProxyTypeLabel, 'Proxies');
    expect(ru.subscriptionServersCount(13), '13 серверов');
    expect(ru.subscriptionProxyTypeLabel, 'Прокси');
  });
}

AppProxySummary _proxy(String tag, String name, {int? latency}) {
  return AppProxySummary(
    tag: tag,
    displayName: name,
    countryCode: 'DE',
    type: 'vless',
    server: '$tag.example.com',
    port: 443,
    detailText: 'VLESS',
    ip: '',
    latency: latency,
    latencyFresh: latency != null,
    latencyChecking: false,
    latencyUnavailable: false,
    latencyError: null,
    protocolLabel: 'VLESS',
    endpointLabel: '$tag.example.com',
  );
}

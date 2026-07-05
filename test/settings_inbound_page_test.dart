import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meow_client/data/local/app_settings_store.dart';
import 'package:meow_client/features/settings/settings_inbound_page.dart';
import 'package:meow_client/l10n/generated/app_localizations.dart';

void main() {
  testWidgets('header status follows the selected connection mode', (
    tester,
  ) async {
    InboundConnectionMode? selectedMode;

    await tester.binding.setSurfaceSize(const Size(420, 860));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ru'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: SettingsInboundPage(
          currentVpnInboundEnabled: true,
          currentVpnMtu: 1500,
          currentVpnStrictRoute: true,
          currentVpnTunImplementation: TunImplementationPreference.mixed,
          currentProxyInboundEnabled: false,
          currentProxyAllowLan: false,
          currentProxyMixedListen: '127.0.0.1',
          currentProxyMixedPort: 1080,
          currentProxyPassword: '',
          onConnectionModeChanged: (mode) => selectedMode = mode,
          onVpnMtuChanged: (_) {},
          onVpnStrictRouteChanged: (_) {},
          onVpnTunImplementationChanged: (_) {},
          onProxyInboundEnabledChanged: (_) {},
          onProxyAllowLanChanged: (_) {},
          onProxyMixedPortChanged: (_) {},
          onProxyPasswordChanged: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Активно: VPN TUN'), findsOneWidget);

    await tester.tap(find.text('Прокси').first);
    await tester.pumpAndSettle();

    expect(selectedMode, InboundConnectionMode.proxy);
    expect(find.text('Активно: Прокси'), findsOneWidget);
    expect(find.text('Активно: VPN TUN'), findsNothing);
  });
}

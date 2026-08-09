import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hydrabox/data/local/app_settings_store.dart';
import 'package:hydrabox/features/settings/settings_general_page.dart';
import 'package:hydrabox/l10n/generated/app_localizations.dart';

Widget _generalSettingsApp({
  required bool statusNotificationEnabled,
  ValueChanged<NotificationTrafficDisplayMode>? onTrafficDisplayChanged,
}) {
  return MaterialApp(
    locale: const Locale('en'),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    home: SettingsGeneralPage(
      currentLocaleCode: 'en',
      currentThemePreference: AppThemePreference.system,
      currentAccentColorHex: 'default',
      currentHapticEnabled: true,
      currentStatusNotificationEnabled: statusNotificationEnabled,
      currentNotificationTrafficDisplayMode:
          NotificationTrafficDisplayMode.speed,
      currentHideServerIp: false,
      currentPerformanceMode: AppPerformanceMode.standard,
      currentMemoryLimitEnabled: true,
      currentMemoryLimitWarningDismissed: false,
      currentUpdateInstallMode: AppUpdateInstallMode.ask,
      onLocaleChanged: (_) {},
      onThemePreferenceChanged: (_) {},
      onAccentColorChanged: (_) {},
      onHapticChanged: (_) {},
      onStatusNotificationChanged: (_) {},
      onNotificationTrafficDisplayModeChanged:
          onTrafficDisplayChanged ?? (_) {},
      onHideServerIpChanged: (_) {},
      onPerformanceModeChanged: (_) {},
      onMemoryLimitChanged: (_, {warningDismissed = false}) {},
      onUpdateInstallModeChanged: (_) {},
    ),
  );
}

void main() {
  const trafficDisplaySetting = ValueKey(
    'notification-traffic-display-setting',
  );

  testWidgets(
    'notification display setting remains visible but disabled with status off',
    (tester) async {
      await tester.pumpWidget(
        _generalSettingsApp(statusNotificationEnabled: false),
      );

      final tile = tester.widget<ListTile>(find.byKey(trafficDisplaySetting));
      expect(tile.enabled, isFalse);
      expect(tile.onTap, isNull);
    },
  );

  testWidgets('notification display setting opens only with status enabled', (
    tester,
  ) async {
    NotificationTrafficDisplayMode? selected;
    await tester.pumpWidget(
      _generalSettingsApp(
        statusNotificationEnabled: true,
        onTrafficDisplayChanged: (value) => selected = value,
      ),
    );

    final tile = tester.widget<ListTile>(find.byKey(trafficDisplaySetting));
    expect(tile.enabled, isTrue);
    expect(tile.onTap, isNotNull);

    await tester.ensureVisible(find.byKey(trafficDisplaySetting));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(trafficDisplaySetting));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Total transferred'));
    await tester.pumpAndSettle();

    expect(selected, NotificationTrafficDisplayMode.total);
  });
}

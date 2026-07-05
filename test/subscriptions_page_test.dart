import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:meow_client/data/subscription/subscription_store.dart';
import 'package:meow_client/features/subscriptions/subscriptions_page.dart';
import 'package:meow_client/l10n/generated/app_localizations.dart';
import 'package:meow_client/models/subscription.dart';

void main() {
  late Directory tempDir;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    tempDir = await Directory.systemTemp.createTemp('subscriptions-page-');
    Hive.init(tempDir.path);
    await SubscriptionStore.init();
  });

  setUp(() async {
    await SubscriptionStore.clear();
  });

  tearDownAll(() async {
    await SubscriptionStore.clear();
    await Hive.close();
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  testWidgets('add profile morphs in one sheet and keeps its header pinned', (
    tester,
  ) async {
    await _openSheet(tester, openAddOnStart: true);

    expect(find.text('Add profile'), findsOneWidget);
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(
      find.byKey(const ValueKey('subscriptions_sheet_clip')),
      findsOneWidget,
    );
    final quickSheetTop = tester
        .getTopLeft(find.byKey(const ValueKey('subscriptions_sheet_clip')))
        .dy;

    await tester.drag(find.text('Manual'), const Offset(0, -320));
    await _pumpUi(tester, const Duration(milliseconds: 320));

    expect(
      tester
          .getTopLeft(find.byKey(const ValueKey('subscriptions_sheet_clip')))
          .dy,
      closeTo(quickSheetTop, .1),
    );

    await tester.tap(find.text('Manual'));
    await _pumpUi(tester, const Duration(milliseconds: 420));

    expect(find.text('URL or content'), findsOneWidget);
    expect(find.byType(BottomSheet), findsOneWidget);
    final manualHeader = find.text('Manual').hitTestable();
    final headerTop = tester.getTopLeft(manualHeader).dy;

    await tester.dragFrom(const Offset(210, 700), const Offset(0, -260));
    await _pumpUi(tester, const Duration(milliseconds: 80));

    expect(tester.getTopLeft(manualHeader).dy, headerTop);

    await tester.tap(find.byIcon(Icons.arrow_back_rounded));
    await _pumpUi(tester, const Duration(milliseconds: 420));
    expect(find.text('Add profile'), findsOneWidget);

    await tester.drag(find.text('Add profile'), const Offset(0, 420));
    await _pumpUi(tester, const Duration(milliseconds: 400));
    expect(find.text('Add profile'), findsNothing);
  });

  testWidgets(
    'subscriptions keep a pinned header and use an inline sort menu',
    (tester) async {
      await tester.runAsync(() async {
        for (var index = 0; index < 8; index++) {
          await SubscriptionStore.save(
            Subscription(
              id: 'sub-$index',
              name: index == 0 ? 'FurkVPN' : 'Profile $index',
              url: 'https://example.com/$index',
              lastUpdated: DateTime(
                2026,
                6,
                28,
                12,
                index,
              ).millisecondsSinceEpoch,
              outbounds: [
                Outbound(
                  tag: 'proxy-$index-a',
                  name: 'Proxy A',
                  config: const {'type': 'vless'},
                ),
                Outbound(
                  tag: 'proxy-$index-b',
                  name: 'Proxy B',
                  config: const {'type': 'vless'},
                ),
              ],
              cachedVisibleProxyCount: 2,
              hasRawPayload: true,
              rawContent: 'vless://payload-$index',
            ),
          );
        }
      });
      await _openSheet(tester, activeSubscriptionId: 'sub-0');

      expect(find.text('Current profile'), findsNothing);
      expect(find.textContaining('2 proxies'), findsWidgets);
      await tester.drag(find.text('Subscriptions'), const Offset(0, -520));
      await _pumpUi(tester, const Duration(milliseconds: 420));
      final headerTop = tester.getTopLeft(find.text('Subscriptions')).dy;

      await tester.drag(find.byType(CustomScrollView), const Offset(0, -360));
      await _pumpUi(tester, const Duration(milliseconds: 80));
      expect(tester.getTopLeft(find.text('Subscriptions')).dy, headerTop);
      await tester.tap(find.byIcon(Icons.sort_rounded));
      await tester.pump();
      expect(find.text('By name'), findsOneWidget);
      expect(find.byType(BottomSheet), findsOneWidget);
      await tester.tap(find.byIcon(Icons.sort_rounded));
      await _pumpUi(tester, const Duration(milliseconds: 250));
      await tester.tap(find.byIcon(Icons.add_rounded).hitTestable());
      await _pumpUi(tester, const Duration(milliseconds: 420));
      expect(find.text('Add profile'), findsOneWidget);
      expect(find.byType(BottomSheet), findsOneWidget);
    },
  );
}

Future<void> _openSheet(
  WidgetTester tester, {
  bool openAddOnStart = false,
  String? activeSubscriptionId,
}) async {
  await tester.binding.setSurfaceSize(const Size(420, 860));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: FilledButton(
              onPressed: () => showModalBottomSheet<Object?>(
                context: context,
                isScrollControlled: true,
                enableDrag: false,
                useSafeArea: true,
                backgroundColor: Colors.transparent,
                builder: (context) => SubscriptionsPage(
                  activeSubscriptionId: activeSubscriptionId,
                  openAddOnStart: openAddOnStart,
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await _pumpUi(tester, const Duration(milliseconds: 500));
}

Future<void> _pumpUi(
  WidgetTester tester, [
  Duration duration = const Duration(milliseconds: 400),
]) async {
  const frame = Duration(milliseconds: 50);
  final frameCount = (duration.inMilliseconds / frame.inMilliseconds).ceil();
  for (var index = 0; index < frameCount; index++) {
    await tester.pump(frame);
  }
}

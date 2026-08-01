import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meow_client/widgets/hydrabox_logo_badge.dart';

void main() {
  testWidgets('HydraBox badge uses the repository-native painted mark', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: Center(child: HydraBoxLogoBadge())),
      ),
    );

    expect(find.byType(HydraBoxLogoBadge), findsOneWidget);
    expect(find.byType(HydraBoxMark), findsOneWidget);
    expect(find.bySemanticsLabel('HydraBox logo'), findsOneWidget);
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:meow_client/data/routing/russia_route_data_service.dart';

void main() {
  test('Russia route status only needs daily update after 24 hours', () {
    final now = DateTime.now().millisecondsSinceEpoch;
    final fresh = RussiaRouteDataStatus(
      available: true,
      sourceName: RussiaRouteDataService.sourceName,
      versionTag: RussiaRouteDataService.bundledTag,
      lastUpdateCheckAtMillis: now,
    );
    final stale = RussiaRouteDataStatus(
      available: true,
      sourceName: RussiaRouteDataService.sourceName,
      versionTag: RussiaRouteDataService.bundledTag,
      lastUpdateCheckAtMillis: DateTime.now()
          .subtract(const Duration(hours: 25))
          .millisecondsSinceEpoch,
    );

    expect(fresh.needsDailyUpdate, isFalse);
    expect(stale.needsDailyUpdate, isTrue);
  });
}

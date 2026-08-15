import 'package:flutter_test/flutter_test.dart';
import 'package:hydrabox/features/settings/settings_subscriptions_page.dart';

void main() {
  test('profiles and checks accepts the persisted 30 minute interval', () {
    expect(normalizeUrlTestIntervalSecondsForSettings(1800), 1800);
  });

  test('profiles and checks clamps invalid persisted intervals', () {
    expect(
      normalizeUrlTestIntervalSecondsForSettings(5),
      urlTestIntervalSettingsMinSeconds,
    );
    expect(
      normalizeUrlTestIntervalSecondsForSettings(9999),
      urlTestIntervalSettingsMaxSeconds,
    );
  });
}

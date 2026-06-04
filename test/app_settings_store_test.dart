import 'package:flutter_test/flutter_test.dart';
import 'package:meow_client/data/local/app_settings_store.dart';

void main() {
  test('defaults to cool performance mode and cool runtime values', () {
    final state = _TestSettingsStore().mapState(const <String, dynamic>{});

    expect(state.performanceMode, AppPerformanceMode.cool);
    expect(state.urlTestIntervalSeconds, 900);
    expect(state.urlTestConcurrency, 4);
    expect(state.urlTestUnavailableCheckIntervalSeconds, 30);
    expect(state.locationLookupLimit, 0);
    expect(state.locationLookupConcurrency, 2);
  });

  test('persists performance mode', () {
    final store = _TestSettingsStore();
    final state = store.mapState(const <String, dynamic>{
      'performance_mode': 'performance',
    });
    final map = store.stateToMap(state);

    expect(state.performanceMode, AppPerformanceMode.performance);
    expect(map['performance_mode'], 'performance');
  });
}

final class _TestSettingsStore extends AppSettingsStore {
  @override
  Future<void> close() async {}

  @override
  Future<AppSettingsState> loadState() async => mapState(const {});

  @override
  Future<void> saveState(AppSettingsState state) async {}
}

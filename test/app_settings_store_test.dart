import 'package:flutter_test/flutter_test.dart';
import 'package:meow_client/data/local/app_settings_store.dart';

void main() {
  test('defaults to standard performance mode and cold runtime values', () {
    final state = _TestSettingsStore().mapState(const <String, dynamic>{});

    expect(state.performanceMode, AppPerformanceMode.standard);
    expect(state.urlTestIntervalSeconds, 300);
    expect(state.urlTestTimeoutSeconds, 4);
    expect(state.urlTestConcurrency, 6);
    expect(state.urlTestUnavailableCheckIntervalSeconds, 300);
    expect(state.locationLookupLimit, 2);
    expect(state.locationLookupTimeoutSeconds, 5);
    expect(state.locationLookupConcurrency, 2);
    expect(state.russiaDnsDirectResolver, defaultRussiaDnsDirectResolver);
    expect(state.memoryLimitEnabled, isTrue);
    expect(state.memoryLimitWarningDismissed, isFalse);
  });

  test('migrates legacy aggressive performance mode to standard', () {
    final store = _TestSettingsStore();
    final state = store.mapState(const <String, dynamic>{
      'performance_mode': 'performance',
    });
    final map = store.stateToMap(state);

    expect(state.performanceMode, AppPerformanceMode.standard);
    expect(map['performance_mode'], 'standard');
  });

  test('migrates legacy cool performance mode to standard', () {
    final store = _TestSettingsStore();
    final state = store.mapState(const <String, dynamic>{
      'performance_mode': 'cool',
    });

    expect(state.performanceMode, AppPerformanceMode.standard);
  });

  test('economy performance mode uses colder runtime values', () {
    final state = _TestSettingsStore().mapState(const <String, dynamic>{
      'performance_mode': 'economy',
    });

    expect(state.performanceMode, AppPerformanceMode.economy);
    expect(state.urlTestIntervalSeconds, 300);
    expect(state.urlTestTimeoutSeconds, 4);
    expect(state.urlTestConcurrency, 3);
    expect(state.urlTestUnavailableCheckIntervalSeconds, 300);
    expect(state.locationLookupLimit, 0);
    expect(state.locationLookupTimeoutSeconds, 5);
    expect(state.locationLookupConcurrency, 1);
  });

  test('migrates old standard and economy URLTest defaults', () {
    final store = _TestSettingsStore();

    final standard = store.mapState(const <String, dynamic>{
      'performance_mode': 'standard',
      'url_test_interval_seconds': '900',
      'url_test_timeout_seconds': '10',
      'url_test_concurrency': '4',
      'urltest_unavailable_check_interval_seconds': '60',
      'location_lookup_concurrency': '1',
    });
    expect(standard.urlTestIntervalSeconds, 300);
    expect(standard.urlTestTimeoutSeconds, 4);
    expect(standard.urlTestConcurrency, 6);
    expect(standard.urlTestUnavailableCheckIntervalSeconds, 300);
    expect(standard.locationLookupConcurrency, 2);

    final previousStandard = store.mapState(const <String, dynamic>{
      'performance_mode': 'standard',
      'urltest_interval_seconds': '120',
      'urltest_concurrency': '8',
      'urltest_unavailable_check_interval_seconds': '120',
    });
    expect(previousStandard.urlTestIntervalSeconds, 300);
    expect(previousStandard.urlTestConcurrency, 6);
    expect(previousStandard.urlTestUnavailableCheckIntervalSeconds, 300);

    final economy = store.mapState(const <String, dynamic>{
      'performance_mode': 'economy',
      'url_test_interval_seconds': '1800',
      'url_test_timeout_seconds': '10',
      'url_test_concurrency': '2',
      'urltest_unavailable_check_interval_seconds': '120',
    });
    expect(economy.urlTestIntervalSeconds, 300);
    expect(economy.urlTestTimeoutSeconds, 4);
    expect(economy.urlTestConcurrency, 3);
    expect(economy.urlTestUnavailableCheckIntervalSeconds, 300);
  });

  test('normalizes Russia route DNS resolver', () {
    final store = _TestSettingsStore();

    expect(
      store.mapState(const {
        'russia_dns_direct_resolver': 'udp://77.88.8.1',
      }).russiaDnsDirectResolver,
      'udp://77.88.8.1',
    );
    expect(
      store.mapState(const {
        'russia_dns_direct_resolver': 'bad resolver',
      }).russiaDnsDirectResolver,
      defaultRussiaDnsDirectResolver,
    );
  });

  test(
    'normalizes split routing packages to a bounded Android package list',
    () {
      final packages = normalizeSplitRoutingPackages([
        'Telegram',
        'com.example.app',
        'com.example.app',
        'com.etonify.meow_client',
        'bad package',
        '',
        ...List.generate(140, (index) => 'com.example.app$index'),
      ]);

      expect(packages.first, 'com.example.app');
      expect(packages, isNot(contains('com.etonify.meow_client')));
      expect(packages.length, maxSplitRoutingPackageCount);
    },
  );

  test('persists accepted legal document metadata', () {
    final store = _TestSettingsStore();
    final state = store.mapState(const <String, dynamic>{
      'accepted_legal_version': '0.2.0',
      'accepted_legal_at_millis': '1780000000000',
    });
    final map = store.stateToMap(state);

    expect(state.acceptedLegalVersion, '0.2.0');
    expect(state.acceptedLegalAtMillis, 1780000000000);
    expect(map['accepted_legal_version'], '0.2.0');
    expect(map['accepted_legal_at_millis'], '1780000000000');
  });

  test('persists memory limit runtime setting and warning state', () {
    final store = _TestSettingsStore();
    final state = store.mapState(const <String, dynamic>{
      'memory_limit_enabled': '0',
      'memory_limit_warning_dismissed': '1',
    });
    final map = store.stateToMap(state);

    expect(state.memoryLimitEnabled, isFalse);
    expect(state.memoryLimitWarningDismissed, isTrue);
    expect(map['memory_limit_enabled'], '0');
    expect(map['memory_limit_warning_dismissed'], '1');
  });

  test('persists TLS fragmentation mode', () {
    final store = _TestSettingsStore();
    final state = store.mapState(const <String, dynamic>{
      'tls_fragmentation_mode': 'record',
    });
    final map = store.stateToMap(state);

    expect(state.tlsFragmentationMode, TlsFragmentationMode.record);
    expect(map['tls_fragmentation_mode'], 'record');
    expect(
      store.mapState(const <String, dynamic>{
        'tls_fragmentation_mode': 'fragment',
      }).tlsFragmentationMode,
      TlsFragmentationMode.fragment,
    );
    expect(
      store.mapState(const <String, dynamic>{
        'tls_fragmentation_mode': 'unknown',
      }).tlsFragmentationMode,
      TlsFragmentationMode.disabled,
    );
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

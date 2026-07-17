import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:meow_client/data/local/app_settings_store.dart';
import 'package:meow_client/singbox/core_config_migration.dart';
import 'package:meow_client/singbox/libbox_capabilities.dart';

void main() {
  final store = _TestSettingsStore();

  test('0.2.1 settings stay untouched while the legacy core is bundled', () {
    final original = _loadVersion021Fixture(store);
    final result = CoreConfigMigration.plan(
      state: original,
      capabilities: LibboxCapabilities.bundledLegacy,
    );

    expect(result.status, CoreConfigMigrationStatus.notRequired);
    expect(result.state, same(original));
    expect(result.state.coreConfigSchemaVersion, 0);
  });

  test('0.2.1 settings become a validation candidate for the new core', () {
    final original = _loadVersion021Fixture(store);
    final result = CoreConfigMigration.plan(
      state: original,
      capabilities: _versionedCapabilities(
        tunStacks: const <String>{'system', 'gvisor', 'mixed'},
      ),
    );

    expect(result.status, CoreConfigMigrationStatus.readyForValidation);
    expect(
      result.state.coreConfigSchemaVersion,
      currentCoreConfigSchemaVersion,
    );
    expect(result.changes, isEmpty);
    expect(result.state.activeProfileId, original.activeProfileId);
    expect(result.state.selectedProxyTag, original.selectedProxyTag);
    expect(result.state.proxySort, original.proxySort);
    expect(result.state.vpnTunImplementation, original.vpnTunImplementation);
    expect(result.state.vpnMtu, original.vpnMtu);
    expect(result.state.dnsDirectResolver, original.dnsDirectResolver);
    expect(result.state.dnsProxyResolver, original.dnsProxyResolver);
    expect(result.state.urlTestUrl, original.urlTestUrl);
    expect(result.state.urlTestTimeoutSeconds, original.urlTestTimeoutSeconds);
    expect(result.state.splitRoutingMode, original.splitRoutingMode);
    expect(result.state.splitRoutingPackages, original.splitRoutingPackages);
  });

  test('unsupported legacy TUN choice gets a deterministic candidate', () {
    final original = _loadVersion021Fixture(store);
    final result = CoreConfigMigration.plan(
      state: original,
      capabilities: _versionedCapabilities(
        tunStacks: const <String>{'system', 'gvisor'},
      ),
    );

    expect(result.status, CoreConfigMigrationStatus.readyForValidation);
    expect(
      result.state.vpnTunImplementation,
      TunImplementationPreference.gvisor,
    );
    expect(result.changes, <String>['vpn_tun_implementation:mixed->gvisor']);
  });

  test('schema marker is local-only and survives storage round trips', () {
    final original = _loadVersion021Fixture(
      store,
    ).copyWith(coreConfigSchemaVersion: currentCoreConfigSchemaVersion);
    final persisted = store.stateToMap(original);
    final restored = store.mapState(persisted);

    expect(restored.coreConfigSchemaVersion, currentCoreConfigSchemaVersion);
    expect(
      store.stateToSafeExportMap(restored),
      isNot(contains('core_config_schema_version')),
    );
  });
}

AppSettingsState _loadVersion021Fixture(_TestSettingsStore store) {
  final content = File('test/fixtures/settings_0_2_1.json').readAsStringSync();
  return store.mapState((jsonDecode(content) as Map<String, dynamic>));
}

LibboxCapabilities _versionedCapabilities({required Set<String> tunStacks}) {
  return LibboxCapabilities(
    apiVersion: 1,
    coreVersion: '1.13.14-etonify',
    supportsTargetedUrlTest: false,
    supportsGroupUrlTestSessions: false,
    supportsStructuredProbeErrors: false,
    supportsOutboundExternalInfo: false,
    supportsUrlTestTimeout: false,
    supportsUrlTestConcurrency: false,
    supportsUrlTestDeadline: false,
    supportsUrlTestForce: false,
    supportsUrlTestUnavailableCheckInterval: false,
    supportsUrlTestMethod: false,
    supportsUrlTestInterruptDelayThreshold: false,
    urlTestCompletionModel: UrlTestCompletionModel.groupEvents,
    supportsConfigCheck: true,
    supportsCloseConnections: true,
    tunStacks: tunStacks,
  );
}

final class _TestSettingsStore extends AppSettingsStore {
  @override
  Future<void> close() async {}

  @override
  Future<AppSettingsState> loadState() async => mapState(const {});

  @override
  Future<void> saveState(AppSettingsState state) async {}
}

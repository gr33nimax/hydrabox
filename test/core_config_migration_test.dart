import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hydrabox/data/local/app_settings_store.dart';
import 'package:hydrabox/core/lowest_proxy_groups.dart';
import 'package:hydrabox/singbox/core_config_migration.dart';
import 'package:hydrabox/singbox/hydracore_capabilities.dart';

void main() {
  final store = _TestSettingsStore();

  test('existing settings become a validation candidate for HydraCore v2', () {
    final original = _loadVersion021Fixture(store);
    final result = CoreConfigMigration.plan(
      state: original,
      capabilities: HydraCoreCapabilities.requiredV2,
    );

    expect(result.status, CoreConfigMigrationStatus.readyForValidation);
    expect(
      result.state.coreConfigSchemaVersion,
      currentCoreConfigSchemaVersion,
    );
  });

  test('migration preserves compatible settings', () {
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

  test('unsupported TUN choice gets a deterministic candidate', () {
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

  for (final oldTag in const <String>[
    mixedProxyTag,
    lowestOpenProxyTag,
    lowestFreeProxyTag,
  ]) {
    test('$oldTag selection migrates to lowest', () {
      final original = _loadVersion021Fixture(
        store,
      ).copyWith(selectedProxyTag: oldTag);
      final result = CoreConfigMigration.plan(
        state: original,
        capabilities: _versionedCapabilities(
          tunStacks: const <String>{'system', 'gvisor', 'mixed'},
        ),
      );

      expect(result.status, CoreConfigMigrationStatus.readyForValidation);
      expect(result.state.selectedProxyTag, lowestProxyTag);
      expect(result.changes, contains('selected_proxy_tag:$oldTag->lowest'));
    });
  }

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

HydraCoreCapabilities _versionedCapabilities({required Set<String> tunStacks}) {
  return HydraCoreCapabilities(
    apiVersion: 2,
    coreVersion: 'v1.13.16-extended-hydracore.1',
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

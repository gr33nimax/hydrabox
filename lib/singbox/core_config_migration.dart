import 'package:hydrabox/data/local/app_settings_store.dart';
import 'package:hydrabox/core/lowest_proxy_groups.dart';
import 'package:hydrabox/singbox/hydracore_capabilities.dart';

const currentCoreConfigSchemaVersion = 1;

enum CoreConfigMigrationStatus { notRequired, readyForValidation, blocked }

/// A non-destructive migration candidate.
///
/// The caller must validate a generated sing-box config before persisting
/// [state]. Planning alone never marks an upgrade as completed.
class CoreConfigMigrationResult {
  const CoreConfigMigrationResult({
    required this.status,
    required this.state,
    this.changes = const <String>[],
    this.blockReason = '',
  });

  final CoreConfigMigrationStatus status;
  final AppSettingsState state;
  final List<String> changes;
  final String blockReason;

  bool get requiresValidation =>
      status == CoreConfigMigrationStatus.readyForValidation;
}

class CoreConfigMigration {
  const CoreConfigMigration._();

  static CoreConfigMigrationResult plan({
    required AppSettingsState state,
    required HydraCoreCapabilities capabilities,
  }) {
    if (!capabilities.hasVersionedContract) {
      return CoreConfigMigrationResult(
        status: CoreConfigMigrationStatus.notRequired,
        state: state,
      );
    }
    if (state.coreConfigSchemaVersion > currentCoreConfigSchemaVersion) {
      return CoreConfigMigrationResult(
        status: CoreConfigMigrationStatus.blocked,
        state: state,
        blockReason: 'settings_from_newer_client',
      );
    }
    if (state.coreConfigSchemaVersion == currentCoreConfigSchemaVersion) {
      return CoreConfigMigrationResult(
        status: CoreConfigMigrationStatus.notRequired,
        state: state,
      );
    }
    if (capabilities.tunStacks.isEmpty) {
      return CoreConfigMigrationResult(
        status: CoreConfigMigrationStatus.blocked,
        state: state,
        blockReason: 'core_tun_capabilities_missing',
      );
    }

    var tunImplementation = state.vpnTunImplementation;
    var selectedProxyTag = state.selectedProxyTag;
    final changes = <String>[];
    if (!capabilities.supportsTunStack(tunImplementation.name)) {
      final fallback = _firstSupportedTunStack(capabilities);
      if (fallback == null) {
        return CoreConfigMigrationResult(
          status: CoreConfigMigrationStatus.blocked,
          state: state,
          blockReason: 'no_compatible_tun_stack',
        );
      }
      changes.add(
        'vpn_tun_implementation:${tunImplementation.name}->${fallback.name}',
      );
      tunImplementation = fallback;
    }
    final normalizedSelectedProxyTag = normalizeProxySelectionTag(
      selectedProxyTag,
    );
    if (normalizedSelectedProxyTag != selectedProxyTag) {
      changes.add(
        'selected_proxy_tag:$selectedProxyTag->$normalizedSelectedProxyTag',
      );
      selectedProxyTag = normalizedSelectedProxyTag;
    }

    return CoreConfigMigrationResult(
      status: CoreConfigMigrationStatus.readyForValidation,
      state: state.copyWith(
        coreConfigSchemaVersion: currentCoreConfigSchemaVersion,
        vpnTunImplementation: tunImplementation,
        selectedProxyTag: selectedProxyTag,
      ),
      changes: List<String>.unmodifiable(changes),
    );
  }

  static TunImplementationPreference? _firstSupportedTunStack(
    HydraCoreCapabilities capabilities,
  ) {
    for (final candidate in const <TunImplementationPreference>[
      TunImplementationPreference.gvisor,
      TunImplementationPreference.system,
      TunImplementationPreference.mixed,
    ]) {
      if (capabilities.supportsTunStack(candidate.name)) {
        return candidate;
      }
    }
    return null;
  }
}

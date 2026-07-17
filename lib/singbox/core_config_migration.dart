import 'package:meow_client/data/local/app_settings_store.dart';
import 'package:meow_client/singbox/libbox_capabilities.dart';

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
    required LibboxCapabilities capabilities,
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

    return CoreConfigMigrationResult(
      status: CoreConfigMigrationStatus.readyForValidation,
      state: state.copyWith(
        coreConfigSchemaVersion: currentCoreConfigSchemaVersion,
        vpnTunImplementation: tunImplementation,
      ),
      changes: List<String>.unmodifiable(changes),
    );
  }

  static TunImplementationPreference? _firstSupportedTunStack(
    LibboxCapabilities capabilities,
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

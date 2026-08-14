import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hydrabox/singbox/singbox_api.g.dart' as bridge;

enum CoreManagerOperation { check, download, probe, activate, rollback }

class CoreSlotInfo {
  const CoreSlotInfo({
    required this.releaseSequence,
    required this.version,
    required this.abi,
    required this.sha256,
  });

  final int releaseSequence;
  final String version;
  final String abi;
  final String sha256;
}

class CheckedCoreReleaseInfo {
  const CheckedCoreReleaseInfo({
    required this.releaseSequence,
    required this.version,
    required this.publishedAt,
    required this.coreApiMajor,
    required this.coreApiMinor,
    required this.artifactSizeBytes,
  });

  final int releaseSequence;
  final String version;
  final DateTime? publishedAt;
  final int coreApiMajor;
  final int coreApiMinor;
  final int artifactSizeBytes;
}

class CoreCandidateProbeInfo {
  const CoreCandidateProbeInfo({
    required this.healthy,
    required this.validatedFixtureCount,
    this.errorCode,
  });

  final bool healthy;
  final int validatedFixtureCount;
  final String? errorCode;
}

class CoreManagerFailure {
  const CoreManagerFailure(this.code, this.safeMessage);

  final String code;
  final String safeMessage;
}

class CoreManagerViewState {
  const CoreManagerViewState({
    required this.supported,
    required this.embeddedVersion,
    required this.trustedKeyRingAvailable,
    required this.usingEmbeddedFallback,
    required this.runtimeDisconnected,
    required this.recoveryRollbackAllowed,
    this.active,
    this.previous,
    this.candidate,
    this.checkedRelease,
    this.probe,
    this.busy,
    this.failure,
  });

  const CoreManagerViewState.unsupported()
    : supported = false,
      embeddedVersion = '',
      trustedKeyRingAvailable = false,
      usingEmbeddedFallback = true,
      runtimeDisconnected = true,
      recoveryRollbackAllowed = false,
      active = null,
      previous = null,
      candidate = null,
      checkedRelease = null,
      probe = null,
      busy = null,
      failure = null;

  final bool supported;
  final String embeddedVersion;
  final CoreSlotInfo? active;
  final CoreSlotInfo? previous;
  final CoreSlotInfo? candidate;
  final bool trustedKeyRingAvailable;
  final bool usingEmbeddedFallback;
  final bool runtimeDisconnected;
  final bool recoveryRollbackAllowed;
  final CheckedCoreReleaseInfo? checkedRelease;
  final CoreCandidateProbeInfo? probe;
  final CoreManagerOperation? busy;
  final CoreManagerFailure? failure;

  CoreManagerViewState copyWith({
    String? embeddedVersion,
    CoreSlotInfo? active,
    bool clearActive = false,
    CoreSlotInfo? previous,
    bool clearPrevious = false,
    CoreSlotInfo? candidate,
    bool clearCandidate = false,
    bool? trustedKeyRingAvailable,
    bool? usingEmbeddedFallback,
    bool? runtimeDisconnected,
    bool? recoveryRollbackAllowed,
    CheckedCoreReleaseInfo? checkedRelease,
    CoreCandidateProbeInfo? probe,
    bool clearProbe = false,
    CoreManagerOperation? busy,
    bool clearBusy = false,
    CoreManagerFailure? failure,
    bool clearFailure = false,
  }) => CoreManagerViewState(
    supported: supported,
    embeddedVersion: embeddedVersion ?? this.embeddedVersion,
    active: clearActive ? null : active ?? this.active,
    previous: clearPrevious ? null : previous ?? this.previous,
    candidate: clearCandidate ? null : candidate ?? this.candidate,
    trustedKeyRingAvailable:
        trustedKeyRingAvailable ?? this.trustedKeyRingAvailable,
    usingEmbeddedFallback: usingEmbeddedFallback ?? this.usingEmbeddedFallback,
    runtimeDisconnected: runtimeDisconnected ?? this.runtimeDisconnected,
    recoveryRollbackAllowed:
        recoveryRollbackAllowed ?? this.recoveryRollbackAllowed,
    checkedRelease: checkedRelease ?? this.checkedRelease,
    probe: clearProbe ? null : probe ?? this.probe,
    busy: clearBusy ? null : busy ?? this.busy,
    failure: clearFailure ? null : failure ?? this.failure,
  );
}

final coreManagerControllerProvider =
    AsyncNotifierProvider<CoreManagerController, CoreManagerViewState>(
      CoreManagerController.new,
    );

class CoreManagerController extends AsyncNotifier<CoreManagerViewState> {
  final bridge.CoreManagerHostApi _api = bridge.CoreManagerHostApi();

  @override
  Future<CoreManagerViewState> build() async {
    if (!Platform.isAndroid) return const CoreManagerViewState.unsupported();
    return _stateFromMessage(await _api.getState());
  }

  Future<void> refresh() async {
    if (!Platform.isAndroid) return;
    final current = state.valueOrNull;
    try {
      final refreshed = _stateFromMessage(await _api.getState());
      state = AsyncData(
        refreshed.copyWith(
          checkedRelease: current?.checkedRelease,
          probe: current?.probe,
        ),
      );
    } on Object catch (error) {
      if (current != null) {
        state = AsyncData(current.copyWith(failure: _failure(error)));
      }
    }
  }

  Future<void> checkLatest() => _run(
    CoreManagerOperation.check,
    (current) async => current.copyWith(
      checkedRelease: _checkedFromMessage(await _api.checkLatest()),
      clearFailure: true,
    ),
  );

  Future<void> downloadChecked() => _run(
    CoreManagerOperation.download,
    (current) async => current.copyWith(
      candidate: _slotFromMessage(await _api.downloadChecked()),
      clearProbe: true,
      clearFailure: true,
    ),
  );

  Future<void> probeCandidate() => _run(
    CoreManagerOperation.probe,
    (current) async {
      final report = await _api.probeCandidate();
      return current.copyWith(
        candidate: _slotFromMessage(report.candidate),
        probe: CoreCandidateProbeInfo(
          healthy: report.healthy,
          validatedFixtureCount: report.validatedFixtureCount,
          errorCode: report.errorCode,
        ),
        clearFailure: true,
      );
    },
  );

  Future<void> activateCandidate() => _run(
    CoreManagerOperation.activate,
    (current) async => _stateFromMessage(
      await _api.activateCandidate(),
      checkedRelease: current.checkedRelease,
    ),
  );

  Future<void> rollback() => _run(
    CoreManagerOperation.rollback,
    (current) async => _stateFromMessage(
      await _api.rollback(),
      checkedRelease: current.checkedRelease,
    ),
  );

  Future<void> _run(
    CoreManagerOperation operation,
    Future<CoreManagerViewState> Function(CoreManagerViewState current) action,
  ) async {
    final current = state.valueOrNull;
    if (current == null || current.busy != null || !current.supported) return;
    state = AsyncData(current.copyWith(busy: operation, clearFailure: true));
    try {
      final updated = await action(current);
      state = AsyncData(updated.copyWith(clearBusy: true, clearFailure: true));
    } on Object catch (error) {
      state = AsyncData(
        current.copyWith(
          clearBusy: true,
          failure: _failure(error),
        ),
      );
    }
  }

  CoreManagerFailure _failure(Object error) {
    if (error is PlatformException) {
      return CoreManagerFailure(
        error.code,
        error.message ?? 'HydraCore operation failed.',
      );
    }
    return const CoreManagerFailure(
      'core.ui.unknown',
      'HydraCore operation failed.',
    );
  }
}

CoreManagerViewState _stateFromMessage(
  bridge.CoreManagerStateMessage message, {
  CheckedCoreReleaseInfo? checkedRelease,
}) => CoreManagerViewState(
  supported: true,
  embeddedVersion: message.embeddedVersion,
  active: _nullableSlotFromMessage(message.active),
  previous: _nullableSlotFromMessage(message.previous),
  candidate: _nullableSlotFromMessage(message.candidate),
  trustedKeyRingAvailable: message.trustedKeyRingAvailable,
  usingEmbeddedFallback: message.usingEmbeddedFallback,
  runtimeDisconnected: message.runtimeDisconnected,
  recoveryRollbackAllowed: message.recoveryRollbackAllowed,
  checkedRelease: checkedRelease,
);

CoreSlotInfo? _nullableSlotFromMessage(bridge.CoreBundleSlotMessage? message) =>
    message == null ? null : _slotFromMessage(message);

CoreSlotInfo _slotFromMessage(bridge.CoreBundleSlotMessage message) =>
    CoreSlotInfo(
      releaseSequence: message.releaseSequence,
      version: message.version,
      abi: message.abi,
      sha256: message.sha256,
    );

CheckedCoreReleaseInfo _checkedFromMessage(
  bridge.CheckedCoreReleaseMessage message,
) => CheckedCoreReleaseInfo(
  releaseSequence: message.releaseSequence,
  version: message.version,
  publishedAt: DateTime.tryParse(message.publishedAt),
  coreApiMajor: message.coreApiMajor,
  coreApiMinor: message.coreApiMinor,
  artifactSizeBytes: message.artifactSizeBytes,
);

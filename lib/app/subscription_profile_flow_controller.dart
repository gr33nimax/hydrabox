class SubscriptionProfilePageSession {
  const SubscriptionProfilePageSession({
    required this.activeProfileId,
    required this.selectedProxyTag,
    required this.metadataFingerprint,
    required this.activeRuntimeFingerprint,
  });

  final String activeProfileId;
  final String selectedProxyTag;
  final String metadataFingerprint;
  final String? activeRuntimeFingerprint;
}

enum SubscriptionProfileFlowKind {
  unchanged,
  reloadCurrentProfile,
  selectProfile,
}

class SubscriptionReloadPlan {
  const SubscriptionReloadPlan({
    required this.preferredSubscriptionId,
    required this.preferredProxyTag,
    required this.applyRuntime,
    required this.resetRuntimeState,
    required this.restartRuntimeOnApply,
    required this.urlTestAfterApply,
  });

  final String preferredSubscriptionId;
  final String preferredProxyTag;
  final bool applyRuntime;
  final bool resetRuntimeState;
  final bool restartRuntimeOnApply;
  final bool urlTestAfterApply;
}

class SubscriptionProfileFlowDecision {
  const SubscriptionProfileFlowDecision._({
    required this.kind,
    this.reloadPlan,
    this.shouldStopRuntime = false,
  });

  const SubscriptionProfileFlowDecision.unchanged()
    : this._(kind: SubscriptionProfileFlowKind.unchanged);

  final SubscriptionProfileFlowKind kind;
  final SubscriptionReloadPlan? reloadPlan;
  final bool shouldStopRuntime;

  bool get shouldReload => reloadPlan != null;
  bool get isProfileSwitch => kind == SubscriptionProfileFlowKind.selectProfile;
}

/// Decides how to apply the result returned by the subscriptions sheet.
///
/// This class owns no Flutter state and performs no I/O. The caller keeps
/// ownership of stopping the runtime and applying the reload plan.
class SubscriptionProfileFlowController {
  const SubscriptionProfileFlowController();

  SubscriptionProfileFlowDecision decide({
    required SubscriptionProfilePageSession session,
    required String? selectedProfileId,
    required String afterMetadataFingerprint,
    required String? afterActiveRuntimeFingerprint,
    required bool runtimeActiveOrRequested,
    required bool connected,
  }) {
    final selectedId = selectedProfileId?.trim() ?? '';
    if (selectedId.isEmpty) {
      final subscriptionsChanged =
          session.metadataFingerprint != afterMetadataFingerprint;
      final activeRuntimeChanged =
          session.activeRuntimeFingerprint != afterActiveRuntimeFingerprint;
      if (!subscriptionsChanged && !activeRuntimeChanged) {
        return const SubscriptionProfileFlowDecision.unchanged();
      }
      return SubscriptionProfileFlowDecision._(
        kind: SubscriptionProfileFlowKind.reloadCurrentProfile,
        reloadPlan: SubscriptionReloadPlan(
          preferredSubscriptionId: session.activeProfileId,
          preferredProxyTag: session.selectedProxyTag,
          applyRuntime: activeRuntimeChanged,
          resetRuntimeState: activeRuntimeChanged,
          restartRuntimeOnApply: connected && activeRuntimeChanged,
          urlTestAfterApply: connected && activeRuntimeChanged,
        ),
      );
    }

    final switchingProfile = selectedId != session.activeProfileId;
    return SubscriptionProfileFlowDecision._(
      kind: SubscriptionProfileFlowKind.selectProfile,
      shouldStopRuntime: switchingProfile && runtimeActiveOrRequested,
      reloadPlan: SubscriptionReloadPlan(
        preferredSubscriptionId: selectedId,
        preferredProxyTag: '',
        applyRuntime: false,
        resetRuntimeState: false,
        restartRuntimeOnApply: false,
        urlTestAfterApply: false,
      ),
    );
  }
}

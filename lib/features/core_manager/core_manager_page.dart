import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:hydrabox/features/core_manager/core_manager_controller.dart';
import 'package:hydrabox/features/settings/settings_ui.dart';
import 'package:hydrabox/l10n/generated/app_localizations.dart';
import 'package:hydrabox/widgets/progressive_blur_scaffold.dart';

class CoreManagerPage extends ConsumerWidget {
  const CoreManagerPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final asyncState = ref.watch(coreManagerControllerProvider);
    return ProgressiveBlurScaffold(
      appBar: AppBar(
        title: Text(l10n.coreManagerTitle),
        actions: [
          IconButton(
            tooltip: l10n.refresh,
            onPressed: asyncState.isLoading
                ? null
                : () => ref
                      .read(coreManagerControllerProvider.notifier)
                      .refresh(),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: asyncState.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => Center(
          child: FilledButton.tonalIcon(
            onPressed: () => ref.invalidate(coreManagerControllerProvider),
            icon: const Icon(Icons.refresh_rounded),
            label: Text(l10n.refresh),
          ),
        ),
        data: (state) => _CoreManagerBody(state: state),
      ),
    );
  }
}

class _CoreManagerBody extends ConsumerWidget {
  const _CoreManagerBody({required this.state});

  final CoreManagerViewState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final controller = ref.read(coreManagerControllerProvider.notifier);
    final busy = state.busy != null;
    final checked = state.checkedRelease;
    final probe = state.probe;
    return ListView(
      padding: EdgeInsets.fromLTRB(
        settingsScreenPadding.left,
        progressiveHeaderTopPadding(context, 20),
        settingsScreenPadding.right,
        appBottomSafePadding(context, 24),
      ),
      children: [
        Text(
          l10n.coreManagerChannelTitle,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const Gap(8),
        SegmentedButton<CoreReleaseChannel>(
          segments: <ButtonSegment<CoreReleaseChannel>>[
            ButtonSegment<CoreReleaseChannel>(
              value: CoreReleaseChannel.stable,
              label: Text(l10n.coreManagerChannelStable),
            ),
            ButtonSegment<CoreReleaseChannel>(
              value: CoreReleaseChannel.debug,
              label: Text(l10n.coreManagerChannelDebug),
            ),
          ],
          selected: <CoreReleaseChannel>{state.releaseChannel},
          onSelectionChanged: busy
              ? null
              : (selection) => controller.selectReleaseChannel(
                  selection.single,
                ),
        ),
        const Gap(16),
        _CoreVersionsCard(state: state),
        if (state.usingEmbeddedFallback) ...[
          const Gap(10),
          _InfoBanner(
            icon: Icons.inventory_2_outlined,
            message: l10n.coreManagerUsingEmbedded,
          ),
        ],
        if (!state.trustedKeyRingAvailable) ...[
          const Gap(10),
          _InfoBanner(
            icon: Icons.gpp_bad_outlined,
            message: l10n.coreManagerNoTrustedKeys,
            error: true,
          ),
        ],
        if (!state.runtimeDisconnected) ...[
          const Gap(10),
          _InfoBanner(
            icon: Icons.link_off_rounded,
            message: l10n.coreManagerDisconnectRequired,
          ),
        ],
        if (state.failure != null) ...[
          const Gap(10),
          _InfoBanner(
            icon: Icons.error_outline_rounded,
            message: l10n.coreManagerOperationFailed(state.failure!.code),
            error: true,
          ),
        ],
        if (checked != null) ...[
          const Gap(10),
          _InfoBanner(
            icon: Icons.new_releases_outlined,
            message: l10n.coreManagerCheckedRelease(
              checked.version,
              _formatBytes(checked.artifactSizeBytes),
            ),
          ),
        ],
        if (probe != null && state.candidate != null) ...[
          const Gap(10),
          _InfoBanner(
            icon: probe.healthy
                ? Icons.verified_outlined
                : Icons.warning_amber_rounded,
            message: probe.healthy
                ? l10n.coreManagerProbePassed(probe.validatedFixtureCount)
                : l10n.coreManagerProbeFailed,
            error: !probe.healthy && probe.validatedFixtureCount > 0,
          ),
        ],
        const Gap(14),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            FilledButton.tonalIcon(
              onPressed: busy || !state.trustedKeyRingAvailable
                  ? null
                  : controller.checkLatest,
              icon: _operationIcon(state, CoreManagerOperation.check),
              label: Text(l10n.coreManagerCheck),
            ),
            FilledButton.tonalIcon(
              onPressed: busy || checked == null
                  ? null
                  : controller.downloadChecked,
              icon: _operationIcon(state, CoreManagerOperation.download),
              label: Text(l10n.coreManagerDownload),
            ),
            FilledButton.tonalIcon(
              onPressed: busy || state.candidate == null
                  ? null
                  : controller.probeCandidate,
              icon: _operationIcon(state, CoreManagerOperation.probe),
              label: Text(l10n.coreManagerProbe),
            ),
            FilledButton.icon(
              onPressed:
                  busy ||
                      state.candidate == null ||
                      probe?.healthy != true ||
                      !state.runtimeDisconnected
                  ? null
                  : controller.activateCandidate,
              icon: _operationIcon(state, CoreManagerOperation.activate),
              label: Text(l10n.coreManagerActivate),
            ),
            OutlinedButton.icon(
              onPressed:
                  busy || state.active == null || !state.recoveryRollbackAllowed
                  ? null
                  : controller.rollback,
              icon: _operationIcon(state, CoreManagerOperation.rollback),
              label: Text(l10n.coreManagerRollback),
            ),
          ],
        ),
      ],
    );
  }

  Widget _operationIcon(
    CoreManagerViewState state,
    CoreManagerOperation operation,
  ) {
    if (state.busy == operation) {
      return const SizedBox.square(
        dimension: 18,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    return Icon(switch (operation) {
      CoreManagerOperation.check => Icons.search_rounded,
      CoreManagerOperation.download => Icons.download_rounded,
      CoreManagerOperation.probe => Icons.fact_check_outlined,
      CoreManagerOperation.activate => Icons.power_settings_new_rounded,
      CoreManagerOperation.rollback => Icons.settings_backup_restore_rounded,
    });
  }
}

class _CoreVersionsCard extends StatelessWidget {
  const _CoreVersionsCard({required this.state});

  final CoreManagerViewState state;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          children: [
            _VersionRow(
              label: l10n.coreManagerEmbeddedVersion,
              value: state.embeddedVersion,
            ),
            const Divider(height: 22),
            _VersionRow(
              label: l10n.coreManagerActiveVersion,
              value: _slotLabel(state.active),
            ),
            const Divider(height: 22),
            _VersionRow(
              label: l10n.coreManagerPreviousVersion,
              value: _slotLabel(state.previous),
            ),
            const Divider(height: 22),
            _VersionRow(
              label: l10n.coreManagerCandidateVersion,
              value: _slotLabel(state.candidate),
            ),
          ],
        ),
      ),
    );
  }

  String _slotLabel(CoreSlotInfo? slot) {
    if (slot == null) return '—';
    final digest = slot.sha256.length > 12
        ? slot.sha256.substring(0, 12)
        : slot.sha256;
    return '${slot.version} · ${slot.abi} · $digest';
  }
}

class _VersionRow extends StatelessWidget {
  const _VersionRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(child: Text(label)),
      const Gap(12),
      Flexible(
        child: Text(
          value,
          textAlign: TextAlign.end,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
    ],
  );
}

class _InfoBanner extends StatelessWidget {
  const _InfoBanner({
    required this.icon,
    required this.message,
    this.error = false,
  });

  final IconData icon;
  final String message;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final foreground = error
        ? colors.onErrorContainer
        : colors.onTertiaryContainer;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: error ? colors.errorContainer : colors.tertiaryContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: foreground),
            const Gap(10),
            Expanded(
              child: Text(
                message,
                style: TextStyle(color: foreground, height: 1.35),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _formatBytes(int bytes) {
  final mib = bytes / (1024 * 1024);
  return '${mib.toStringAsFixed(mib >= 100 ? 0 : 1)} MiB';
}

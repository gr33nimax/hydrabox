import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gap/gap.dart';
import 'package:meow_client/features/legal/legal_consent_page.dart';
import 'package:meow_client/features/settings/settings_update_page.dart';
import 'package:meow_client/features/settings/settings_ui.dart';
import 'package:meow_client/l10n/generated/app_localizations.dart';
import 'package:meow_client/logging/app_log_store.dart';
import 'package:meow_client/singbox/singbox_runtime.dart';
import 'package:meow_client/widgets/app_visual_effects.dart';
import 'package:meow_client/widgets/progressive_blur_scaffold.dart';
import 'package:url_launcher/url_launcher.dart';

class SettingsAboutPage extends StatefulWidget {
  const SettingsAboutPage({
    super.key,
    required this.versionLabel,
    required this.onShowOnboarding,
  });

  static final Uri _coreSourceUri = Uri.parse(
    'https://github.com/dudosxdev/sing-box',
  );
  static final Uri _telegramUri = Uri.parse('https://t.me/etonify');
  static final Uri _contactUri = Uri.parse('https://t.me/etonify?direct');

  final String versionLabel;
  final VoidCallback onShowOnboarding;

  @override
  State<SettingsAboutPage> createState() => _SettingsAboutPageState();
}

class _SettingsAboutPageState extends State<SettingsAboutPage> {
  bool _debugVisible = false;
  String? _coreVersion;
  Map<String, dynamic>? _performanceSnapshot;
  bool _performanceBusy = false;

  @override
  void initState() {
    super.initState();
    _loadCoreVersion();
  }

  Future<void> _loadCoreVersion() async {
    final version = await SingboxRuntime.instance.getCoreVersion();
    if (!mounted) return;
    setState(() => _coreVersion = version);
  }

  void _toggleDebugVisible() {
    if (AppVisualEffects.of(context).hapticEnabled) {
      HapticFeedback.selectionClick();
    }
    setState(() => _debugVisible = !_debugVisible);
  }

  Future<void> _openUri(Uri uri) async {
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(uri.toString())));
    }
  }

  void _openTeamPage() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (context) => const _MeowTeamPage()),
    );
  }

  void _openUpdatePage() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) =>
            SettingsUpdatePage(currentVersion: widget.versionLabel),
      ),
    );
  }

  void _openLegalDocument({required bool privacy}) {
    final l10n = AppLocalizations.of(context);
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (context) => LegalDocumentPage(
          title: privacy ? l10n.legalPrivacyTitle : l10n.legalTermsTitle,
          body: privacy ? l10n.legalPrivacyBody : l10n.legalTermsBody,
        ),
      ),
    );
  }

  Future<void> _refreshPerformanceSnapshot() async {
    if (_performanceBusy) return;
    setState(() => _performanceBusy = true);
    try {
      final snapshot = await SingboxRuntime.instance.getPerformanceSnapshot();
      if (!mounted) return;
      setState(() => _performanceSnapshot = snapshot);
    } finally {
      if (mounted) {
        setState(() => _performanceBusy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return ProgressiveBlurScaffold(
      appBar: AppBar(title: Text(l10n.aboutSectionTitle)),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          0,
          progressiveHeaderTopPadding(context, 20),
          0,
          appBottomSafePadding(context, 24),
        ),
        children: [
          Padding(
            padding: settingsScreenPadding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _AboutInfoCard(
                  versionLabel: widget.versionLabel,
                  coreVersion: _coreVersion,
                  onOpenCoreSource: () =>
                      _openUri(SettingsAboutPage._coreSourceUri),
                  onOpenTelegram: () =>
                      _openUri(SettingsAboutPage._telegramUri),
                  onOpenContact: () => _openUri(SettingsAboutPage._contactUri),
                  onOpenTerms: () => _openLegalDocument(privacy: false),
                  onOpenPrivacy: () => _openLegalDocument(privacy: true),
                  onOpenTeam: _openTeamPage,
                ),
                const Gap(12),
                _AboutResourcesCard(
                  snapshot: _performanceSnapshot,
                  busy: _performanceBusy,
                  onRefresh: _refreshPerformanceSnapshot,
                  onDebugToggle: _toggleDebugVisible,
                ),
                const Gap(12),
                _AboutUpdatesCard(onOpenUpdates: _openUpdatePage),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeOutCubic,
                  child: _debugVisible
                      ? Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: _AboutDebugCard(
                            onShowOnboarding: () {
                              Navigator.of(context).pop();
                              widget.onShowOnboarding();
                            },
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AboutInfoCard extends StatelessWidget {
  const _AboutInfoCard({
    required this.versionLabel,
    required this.coreVersion,
    required this.onOpenCoreSource,
    required this.onOpenTelegram,
    required this.onOpenContact,
    required this.onOpenTerms,
    required this.onOpenPrivacy,
    required this.onOpenTeam,
  });

  final String versionLabel;
  final String? coreVersion;
  final VoidCallback onOpenCoreSource;
  final VoidCallback onOpenTelegram;
  final VoidCallback onOpenContact;
  final VoidCallback onOpenTerms;
  final VoidCallback onOpenPrivacy;
  final VoidCallback onOpenTeam;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final cs = theme.colorScheme;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Etonify',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: 0,
              ),
            ),
            const Gap(14),
            _AboutInfoRow(label: l10n.appVersionLabel, value: versionLabel),
            const Gap(8),
            _AboutInfoRow(
              label: l10n.coreVersionLabel,
              value: coreVersion ?? l10n.loading,
            ),
            const Gap(16),
            Text(
              l10n.aboutDevelopedBy,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: cs.onSurfaceVariant,
                height: 1.4,
              ),
            ),
            const Gap(10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _AboutActionChip(
                  icon: Icons.groups_rounded,
                  label: 'MeowTeam',
                  onTap: onOpenTeam,
                ),
                _AboutActionChip(
                  icon: Icons.code_rounded,
                  label: 'dudosxdev/sing-box',
                  onTap: onOpenCoreSource,
                ),
                _AboutActionChip(
                  icon: Icons.send_rounded,
                  label: l10n.telegramChannelLabel,
                  onTap: onOpenTelegram,
                ),
                _AboutActionChip(
                  icon: Icons.forum_rounded,
                  label: l10n.aboutContactLabel,
                  onTap: onOpenContact,
                ),
                _AboutActionChip(
                  icon: Icons.description_rounded,
                  label: l10n.legalTermsTitle,
                  onTap: onOpenTerms,
                ),
                _AboutActionChip(
                  icon: Icons.privacy_tip_rounded,
                  label: l10n.legalPrivacyTitle,
                  onTap: onOpenPrivacy,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AboutUpdatesCard extends StatelessWidget {
  const _AboutUpdatesCard({required this.onOpenUpdates});

  final VoidCallback onOpenUpdates;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final cs = theme.colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        onTap: onOpenUpdates,
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        leading: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: cs.primaryContainer,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(
            Icons.system_update_rounded,
            color: cs.onPrimaryContainer,
          ),
        ),
        title: Text(
          l10n.updatesTitle,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(l10n.updatesSubtitle),
        ),
        trailing: const Icon(Icons.chevron_right_rounded),
      ),
    );
  }
}

class _AboutResourcesCard extends StatelessWidget {
  const _AboutResourcesCard({
    required this.snapshot,
    required this.busy,
    required this.onRefresh,
    required this.onDebugToggle,
  });

  final Map<String, dynamic>? snapshot;
  final bool busy;
  final VoidCallback onRefresh;
  final VoidCallback onDebugToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final cs = theme.colorScheme;
    final data = snapshot;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.aboutResourcesTitle,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                GestureDetector(
                  onDoubleTap: onDebugToggle,
                  child: IconButton(
                    tooltip: l10n.refresh,
                    onPressed: busy ? null : onRefresh,
                    icon: busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh_rounded),
                  ),
                ),
              ],
            ),
            const Gap(8),
            Text(
              l10n.aboutResourcesSubtitle,
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
                height: 1.35,
              ),
            ),
            const Gap(12),
            _AboutInfoRow(
              label: l10n.aboutResourcePss,
              value: _formatKb(data?['totalPssKb']),
            ),
            const Gap(8),
            _AboutInfoRow(
              label: l10n.aboutResourceNativeHeap,
              value: _formatKb(data?['nativeHeapAllocatedKb']),
            ),
            const Gap(8),
            _AboutInfoRow(
              label: l10n.aboutResourceJavaHeap,
              value: _formatKb(data?['javaHeapUsedKb']),
            ),
            const Gap(8),
            _AboutInfoRow(
              label: l10n.aboutResourceSystemMemory,
              value: _formatKb(data?['systemAvailMemKb']),
            ),
            const Gap(8),
            _AboutInfoRow(
              label: l10n.aboutResourceBatteryTemp,
              value: _formatTemperature(data?['batteryTemperatureC']),
            ),
          ],
        ),
      ),
    );
  }

  static String _formatKb(Object? value) {
    final kb = _numValue(value);
    if (kb == null || kb <= 0) return '—';
    final mb = kb / 1024;
    return '${mb.toStringAsFixed(mb >= 100 ? 0 : 1)} MB';
  }

  static String _formatTemperature(Object? value) {
    final c = _numValue(value);
    if (c == null) return '—';
    return '${c.toStringAsFixed(1)} °C';
  }

  static num? _numValue(Object? value) {
    if (value is num) return value;
    return num.tryParse(value?.toString() ?? '');
  }
}

class _AboutInfoRow extends StatelessWidget {
  const _AboutInfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
        ),
        const Gap(12),
        Flexible(
          flex: 2,
          child: Align(
            alignment: Alignment.centerRight,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Text(
                value,
                maxLines: 1,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _AboutActionChip extends StatelessWidget {
  const _AboutActionChip({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Material(
      color: cs.primaryContainer.withValues(alpha: .62),
      borderRadius: BorderRadius.circular(999),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: cs.onPrimaryContainer),
              const Gap(6),
              Text(
                label,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: cs.onPrimaryContainer,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MeowTeamPage extends StatelessWidget {
  const _MeowTeamPage();

  static final Uri _dudosxdevUri = Uri.parse('https://t.me/dddosxd');
  static final Uri _yamixdevUri = Uri.parse('https://t.me/Ilushadev');
  static final Uri _telegramUri = Uri.parse('https://t.me/etonify');
  static final Uri _coreUri = Uri.parse(
    'https://github.com/dudosxdev/sing-box',
  );

  Future<void> _open(BuildContext context, Uri uri) async {
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(uri.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

    return ProgressiveBlurScaffold(
      appBar: AppBar(title: Text(l10n.teamPageTitle)),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          16,
          progressiveHeaderTopPadding(context, 20),
          16,
          appBottomSafePadding(context, 24),
        ),
        children: [
          Text(
            l10n.teamIntroTitle,
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w900,
            ),
          ),
          const Gap(8),
          Text(
            l10n.teamIntroBody,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.4,
            ),
          ),
          const Gap(18),
          _TimelineItem(
            icon: Icons.fork_right_rounded,
            title: l10n.teamTimelineForkTitle,
            body: l10n.teamTimelineForkBody,
          ),
          _TimelineItem(
            icon: Icons.cleaning_services_rounded,
            title: l10n.teamTimelineRefactorTitle,
            body: l10n.teamTimelineRefactorBody,
          ),
          _TimelineItem(
            icon: Icons.memory_rounded,
            title: l10n.teamTimelineCoreTitle,
            body: l10n.teamTimelineCoreBody,
            actionLabel: 'dudosxdev/sing-box',
            onAction: () => _open(context, _coreUri),
          ),
          _TimelineItem(
            icon: Icons.auto_awesome_rounded,
            title: l10n.teamTimelineNowTitle,
            body: l10n.teamTimelineNowBody,
          ),
          const Gap(14),
          _DeveloperCard(
            name: 'dudosxdev',
            role: l10n.teamDeveloperDdosxdRole,
            avatarAsset: 'assets/images/team/ddosxd.jpg',
            onTap: () => _open(context, _dudosxdevUri),
          ),
          const Gap(10),
          _DeveloperCard(
            name: 'yamixdev',
            role: l10n.teamDeveloperYamixdevRole,
            avatarAsset: 'assets/images/team/yamixdev.jpg',
            onTap: () => _open(context, _yamixdevUri),
          ),
          const Gap(10),
          _DeveloperCard(
            name: l10n.telegramChannelLabel,
            role: l10n.teamTelegramRole,
            avatarAsset: 'assets/images/team/telegram.png',
            onTap: () => _open(context, _telegramUri),
          ),
          const Gap(28),
          Center(
            child: Text(
              '© 2026 MeowTeam™',
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TimelineItem extends StatelessWidget {
  const _TimelineItem({
    required this.icon,
    required this.title,
    required this.body,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String body;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: cs.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, size: 20, color: cs.onPrimaryContainer),
            ),
            const Gap(12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const Gap(5),
                  Text(
                    body,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: cs.onSurfaceVariant,
                      height: 1.35,
                    ),
                  ),
                  if (actionLabel != null && onAction != null) ...[
                    const Gap(8),
                    _AboutActionChip(
                      icon: Icons.open_in_new_rounded,
                      label: actionLabel!,
                      onTap: onAction!,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DeveloperCard extends StatelessWidget {
  const _DeveloperCard({
    required this.name,
    required this.role,
    required this.avatarAsset,
    required this.onTap,
  });

  final String name;
  final String role;
  final String avatarAsset;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(
          radius: 22,
          backgroundImage: AssetImage(avatarAsset),
          backgroundColor: theme.colorScheme.surfaceContainerHighest,
        ),
        title: Text(name),
        subtitle: Text(role),
        trailing: const Icon(Icons.open_in_new_rounded),
        titleTextStyle: theme.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _AboutDebugCard extends StatelessWidget {
  const _AboutDebugCard({required this.onShowOnboarding});

  final VoidCallback onShowOnboarding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.debugMenuTitle,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const Gap(8),
            Text(
              l10n.debugMenuSubtitle,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.4,
              ),
            ),
            const Gap(14),
            FilledButton.tonalIcon(
              onPressed: onShowOnboarding,
              icon: const Icon(Icons.rocket_launch_rounded),
              label: Text(l10n.showOnboardingAgain),
            ),
            const Gap(14),
            const _RuntimeFlagsToggles(),
          ],
        ),
      ),
    );
  }
}

class _RuntimeFlagsToggles extends StatefulWidget {
  const _RuntimeFlagsToggles();

  @override
  State<_RuntimeFlagsToggles> createState() => _RuntimeFlagsTogglesState();
}

class _RuntimeFlagsTogglesState extends State<_RuntimeFlagsToggles> {
  RuntimeFlags? _flags;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final flags = await SingboxRuntime.instance.getRuntimeFlags();
    if (!mounted) return;
    setState(() => _flags = flags);
  }

  Future<void> _setWakeLock(bool value) async {
    if (_busy || _flags == null) return;
    setState(() {
      _busy = true;
      _flags = RuntimeFlags(
        wakeLockEnabled: value,
        networkHeartbeatEnabled: _flags!.networkHeartbeatEnabled,
        networkHeartbeatIntervalSeconds:
            _flags!.networkHeartbeatIntervalSeconds,
        performanceMode: _flags!.performanceMode,
      );
    });
    await SingboxRuntime.instance.setRuntimeFlags(wakeLockEnabled: value);
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _setHeartbeat(bool value) async {
    if (_busy || _flags == null) return;
    setState(() {
      _busy = true;
      _flags = RuntimeFlags(
        wakeLockEnabled: _flags!.wakeLockEnabled,
        networkHeartbeatEnabled: value,
        networkHeartbeatIntervalSeconds:
            _flags!.networkHeartbeatIntervalSeconds,
        performanceMode: _flags!.performanceMode,
      );
    });
    await SingboxRuntime.instance.setRuntimeFlags(
      networkHeartbeatEnabled: value,
    );
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _recordPerformanceSnapshot() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final snapshot = await SingboxRuntime.instance.getPerformanceSnapshot();
      AppLogStore.info('performance snapshot', snapshot.toString());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).debugSnapshotDone)),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final flags = _flags;
    if (flags == null) {
      return const SizedBox(
        height: 48,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(l10n.debugNetworkHeartbeatTitle),
          subtitle: Text(
            l10n.debugNetworkHeartbeatSubtitle(
              flags.networkHeartbeatIntervalSeconds,
            ),
          ),
          value: flags.networkHeartbeatEnabled,
          onChanged: _busy ? null : _setHeartbeat,
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(l10n.debugWakeLockTitle),
          subtitle: Text(l10n.debugWakeLockSubtitle),
          value: flags.wakeLockEnabled,
          onChanged: _busy ? null : _setWakeLock,
        ),
        OutlinedButton.icon(
          onPressed: _busy ? null : _recordPerformanceSnapshot,
          icon: const Icon(Icons.memory_rounded),
          label: Text(l10n.debugRecordSnapshot),
        ),
      ],
    );
  }
}

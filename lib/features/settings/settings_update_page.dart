import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:hydrabox/core/widgets/app_notice.dart';
import 'package:hydrabox/data/local/app_settings_store.dart';
import 'package:hydrabox/data/update/app_update_service.dart';
import 'package:hydrabox/features/settings/settings_ui.dart';
import 'package:hydrabox/l10n/generated/app_localizations.dart';
import 'package:hydrabox/singbox/singbox_runtime.dart';
import 'package:hydrabox/widgets/progressive_blur_scaffold.dart';
import 'package:hydrabox/widgets/release_notes_card.dart';
import 'package:url_launcher/url_launcher.dart';

class SettingsUpdatePage extends StatefulWidget {
  const SettingsUpdatePage({
    super.key,
    required this.currentVersion,
    this.installMode = AppUpdateInstallMode.ask,
    this.onInstallModeChanged,
  });

  final String currentVersion;
  final AppUpdateInstallMode installMode;
  final ValueChanged<AppUpdateInstallMode>? onInstallModeChanged;

  @override
  State<SettingsUpdatePage> createState() => _SettingsUpdatePageState();
}

class _SettingsUpdatePageState extends State<SettingsUpdatePage>
    with WidgetsBindingObserver {
  AppUpdateCheckResult? _result;
  AppUpdateDownloadProgress? _downloadProgress;
  bool _checking = false;
  static const bool _downloading = false;
  bool _installing = false;
  bool _clearingUpdateCache = false;
  AppUpdateVerificationResult? _verification;
  String? _downloadedFilePath;
  late String _currentVersion = widget.currentVersion;
  int _currentVersionCode = 0;
  late AppUpdateInstallMode _installMode = widget.installMode;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_bootstrap());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_refreshInstalledVersion());
    }
  }

  Future<void> _bootstrap() async {
    await _refreshInstalledVersion();
    await _check(manual: false);
  }

  Future<void> _refreshInstalledVersion() async {
    final info = await SingboxRuntime.instance.getAppVersionInfo();
    if (!mounted) return;
    final next = info.displayVersion;
    final nextBuildNumber = info.updateBuildNumber;
    if (next != _currentVersion || nextBuildNumber != _currentVersionCode) {
      setState(() {
        _currentVersion = next;
        _currentVersionCode = nextBuildNumber;
      });
    }
  }

  Future<void> _check({required bool manual}) async {
    if (_checking || _downloading || _clearingUpdateCache) return;
    await _refreshInstalledVersion();
    if (!mounted || _checking || _downloading || _clearingUpdateCache) return;
    setState(() {
      _checking = true;
      if (manual) {
        _downloadProgress = null;
      }
    });
    final result = await AppUpdateService.instance.checkForUpdates(
      currentVersion: _currentVersion,
      currentBuildNumber: _currentVersionCode,
      manual: manual,
    );
    if (!mounted) return;
    setState(() {
      _result = result;
      _checking = false;
      _downloadedFilePath = result.downloadedFilePath;
    });
    await _refreshDownloadedVerification();
  }

  Future<void> _startUpdateFlow(AppUpdateInfo info) async {
    if (_downloading || _checking || _clearingUpdateCache) return;
    var mode = _installMode;
    if (mode == AppUpdateInstallMode.ask) {
      final decision = await _showInstallModeSheet();
      if (decision == null || !mounted) return;
      mode = decision.mode;
      if (decision.remember) {
        setState(() => _installMode = mode);
        widget.onInstallModeChanged?.call(mode);
      }
    }

    await _openRelease(info);
  }

  Future<_InstallModeDecision?> _showInstallModeSheet() {
    final l10n = AppLocalizations.of(context);
    var selected = AppUpdateInstallMode.manual;
    var remember = false;
    return showModalBottomSheet<_InstallModeDecision>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        final theme = Theme.of(context);
        return StatefulBuilder(
          builder: (context, setSheetState) {
            Widget option({
              required AppUpdateInstallMode value,
              required IconData icon,
              required String title,
              required String subtitle,
            }) {
              return RadioListTile<AppUpdateInstallMode>(
                value: value,
                secondary: Icon(icon),
                title: Text(title),
                subtitle: Text(subtitle),
              );
            }

            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      l10n.updatesInstallMethodTitle,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const Gap(8),
                    RadioGroup<AppUpdateInstallMode>(
                      groupValue: selected,
                      onChanged: (next) {
                        if (next == null) return;
                        setSheetState(() => selected = next);
                      },
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          option(
                            value: AppUpdateInstallMode.manual,
                            icon: Icons.download_done_rounded,
                            title: l10n.updatesInstallMethodManualTitle,
                            subtitle: l10n.updatesInstallMethodManualSubtitle,
                          ),
                        ],
                      ),
                    ),
                    CheckboxListTile(
                      value: remember,
                      onChanged: (value) {
                        setSheetState(() => remember = value ?? false);
                      },
                      controlAffinity: ListTileControlAffinity.leading,
                      title: Text(l10n.updatesInstallMethodRemember),
                    ),
                    const Gap(8),
                    FilledButton(
                      onPressed: () => Navigator.of(context).pop(
                        _InstallModeDecision(
                          mode: selected,
                          remember: remember,
                        ),
                      ),
                      child: Text(l10n.continueAction),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _openRelease(AppUpdateInfo info) async {
    if (_installing || _checking || _clearingUpdateCache) return;
    final uri = Uri.tryParse(info.htmlUrl);
    if (uri == null || uri.scheme != 'https' || uri.host != 'github.com') {
      setState(() {
        _result = AppUpdateCheckResult(
          status: AppUpdateStatus.error,
          checkedAt: DateTime.now(),
          info: info,
          error: AppLocalizations.of(context).updatesReleaseOpenFailed,
        );
      });
      return;
    }
    setState(() => _installing = true);
    try {
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened) throw StateError('release page was not opened');
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _result = AppUpdateCheckResult(
          status: AppUpdateStatus.error,
          checkedAt: DateTime.now(),
          info: info,
          error: AppLocalizations.of(context).updatesReleaseOpenFailed,
        );
      });
    } finally {
      if (mounted) setState(() => _installing = false);
    }
  }

  Future<void> _installDownloaded() async {
    final info = _result?.info;
    if (info != null) await _openRelease(info);
  }

  Future<void> _refreshDownloadedVerification() async {
    final info = _result?.info;
    final path = _cachedInstallerPath;
    if (info == null || path == null) {
      if (mounted) setState(() => _verification = null);
      return;
    }
    final verification = await AppUpdateService.instance.verifyDownloadedApk(
      info,
      path,
    );
    if (!mounted) return;
    setState(() => _verification = verification);
  }

  String? get _cachedInstallerPath {
    final savedPath = _downloadedFilePath?.trim();
    if (savedPath != null && savedPath.isNotEmpty) return savedPath;
    final progressPath = _downloadProgress?.filePath?.trim();
    if (progressPath != null && progressPath.isNotEmpty) return progressPath;
    return null;
  }

  Future<void> _deleteCachedInstaller() async {
    if (_checking || _downloading || _installing || _clearingUpdateCache) {
      return;
    }
    final l10n = AppLocalizations.of(context);
    final version = _result?.info?.displayVersion.trim().isNotEmpty == true
        ? 'v${_result!.info!.displayVersion}'
        : _currentVersion;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.updatesDeleteCachedApkTitle),
        content: Text(l10n.updatesDeleteCachedApkMessage(version)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.cancel),
          ),
          FilledButton.tonalIcon(
            onPressed: () => Navigator.of(context).pop(true),
            icon: const Icon(Icons.delete_sweep_rounded),
            label: Text(l10n.delete),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _clearingUpdateCache = true);
    final deleted = await AppUpdateService.instance.deleteCachedInstallers(
      currentVersion: _currentVersion,
      currentBuildNumber: _currentVersionCode,
    );
    final metadata = await AppUpdateService.instance.loadMetadata();
    if (!mounted) return;
    setState(() {
      _clearingUpdateCache = false;
      _downloadedFilePath = null;
      _downloadProgress = null;
      _verification = null;
      _result = AppUpdateCheckResult(
        status: metadata.lastStatus,
        checkedAt: metadata.lastCheckAt ?? DateTime.now(),
        info: metadata.latestInfo,
        error: metadata.lastError,
      );
    });
    AppNotice.show(
      context,
      l10n.updatesDeleteCachedApkDone(deleted),
      tone: AppNoticeTone.success,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final result = _result;
    final info = result?.info;
    final cachedInstallerPath = _cachedInstallerPath;

    return ProgressiveBlurScaffold(
      appBar: AppBar(
        title: Text(l10n.updatesTitle),
        actions: [
          IconButton(
            tooltip: l10n.updatesCheckAction,
            onPressed:
                !AppUpdateService.updatesConfigured ||
                    _checking ||
                    _downloading ||
                    _installing
                ? null
                : () => _check(manual: true),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          settingsScreenPadding.left,
          progressiveHeaderTopPadding(context, 24),
          settingsScreenPadding.right,
          appBottomSafePadding(context, 112),
        ),
        children: [
          _UpdateHero(
            checking: _checking,
            title: _titleFor(context, result),
            subtitle: _subtitleFor(context, result),
          ),
          const Gap(18),
          _UpdateInfoCard(
            currentVersion: _currentVersion,
            info: info,
            checkedAt: result?.checkedAt,
            action: _UpdateActionButton(
              result: result,
              checking: _checking,
              downloading: _downloading,
              installing: _installing,
              onCheck: () => _check(manual: true),
              onDownload: info == null ? null : () => _startUpdateFlow(info),
              onInstall: cachedInstallerPath == null
                  ? null
                  : _installDownloaded,
            ),
            verification: _verification,
            cacheAction: cachedInstallerPath == null
                ? null
                : _CachedInstallerButton(
                    clearing: _clearingUpdateCache,
                    onDelete: _deleteCachedInstaller,
                  ),
          ),
          if (_downloading || _downloadProgress != null) ...[
            const Gap(12),
            _DownloadProgressCard(progress: _downloadProgress),
          ],
          if (info != null) ...[
            const Gap(12),
            ReleaseNotesCard(body: info.body),
          ],
          if (result?.status == AppUpdateStatus.error) ...[
            const Gap(12),
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  result?.error?.trim().isNotEmpty == true
                      ? result!.error!
                      : l10n.updatesErrorSubtitle,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
      resizeToAvoidBottomInset: false,
      backgroundColor: theme.colorScheme.surface,
    );
  }

  String _titleFor(BuildContext context, AppUpdateCheckResult? result) {
    final l10n = AppLocalizations.of(context);
    if (_checking) return 'HydraBox';
    if (_downloading) return l10n.updatesDownloadingTitle;
    return switch (result?.status) {
      AppUpdateStatus.disabled => l10n.updatesDisabledTitle,
      AppUpdateStatus.updateAvailable => l10n.updatesAvailableTitle,
      AppUpdateStatus.unsupportedAndroid => l10n.updatesUnsupportedAndroidTitle,
      AppUpdateStatus.downloaded => l10n.updatesDownloadedTitle,
      AppUpdateStatus.upToDate => l10n.updatesUpToDateTitle,
      AppUpdateStatus.error => l10n.updatesErrorTitle,
      _ => l10n.updatesTitle,
    };
  }

  String _subtitleFor(BuildContext context, AppUpdateCheckResult? result) {
    final l10n = AppLocalizations.of(context);
    if (_checking) return l10n.updatesChecking;
    if (_downloading) return l10n.updatesDownloadWarning;
    final info = result?.info;
    return switch (result?.status) {
      AppUpdateStatus.disabled => l10n.updatesDisabledSubtitle,
      AppUpdateStatus.updateAvailable when info != null =>
        l10n.updatesAvailableSubtitle(
          info.displayVersion,
          _formatBytes(info.asset.sizeBytes, l10n),
        ),
      AppUpdateStatus.unsupportedAndroid when info != null =>
        l10n.updatesUnsupportedAndroidSubtitle(
          info.displayVersion,
          info.minimumAndroidSdk ?? 0,
        ),
      AppUpdateStatus.downloaded => l10n.updatesDownloadedSubtitle(
        (_downloadedFilePath ?? _downloadProgress?.filePath) == null
            ? ''
            : File(
                (_downloadedFilePath ?? _downloadProgress!.filePath)!,
              ).uri.pathSegments.last,
      ),
      AppUpdateStatus.upToDate => l10n.updatesUpToDateSubtitle(_currentVersion),
      AppUpdateStatus.error => l10n.updatesErrorSubtitle,
      _ => l10n.updatesSubtitle,
    };
  }
}

class _InstallModeDecision {
  const _InstallModeDecision({required this.mode, required this.remember});

  final AppUpdateInstallMode mode;
  final bool remember;
}

class _UpdateActionButton extends StatelessWidget {
  const _UpdateActionButton({
    required this.result,
    required this.checking,
    required this.downloading,
    required this.installing,
    required this.onCheck,
    required this.onDownload,
    required this.onInstall,
  });

  final AppUpdateCheckResult? result;
  final bool checking;
  final bool downloading;
  final bool installing;
  final VoidCallback onCheck;
  final VoidCallback? onDownload;
  final VoidCallback? onInstall;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (result?.status == AppUpdateStatus.disabled) {
      return const SizedBox.shrink();
    }
    if (downloading || installing) {
      return Text(
        installing ? l10n.updatesOpeningRelease : l10n.updatesDownloadWarning,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      );
    }
    if (result?.status == AppUpdateStatus.downloaded) {
      return FilledButton.icon(
        onPressed: checking ? null : onInstall,
        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
        icon: const Icon(Icons.open_in_new_rounded),
        label: Text(
          l10n.updatesOpenAction,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      );
    }
    if (result?.status == AppUpdateStatus.updateAvailable) {
      return FilledButton(
        onPressed: checking ? null : onDownload,
        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
        child: Text(
          l10n.updatesOpenAction,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      );
    }
    if (result?.status == AppUpdateStatus.error) {
      return FilledButton.tonal(
        onPressed: checking ? null : onCheck,
        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
        child: Text(
          l10n.updatesRetryAction,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      );
    }
    if (result?.status == AppUpdateStatus.unsupportedAndroid) {
      return OutlinedButton(
        onPressed: checking ? null : onCheck,
        style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
        child: Text(l10n.updatesCheckAction),
      );
    }
    return OutlinedButton(
      onPressed: checking ? null : onCheck,
      style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
      child: Text(
        l10n.updatesCheckAction,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

class _CachedInstallerButton extends StatelessWidget {
  const _CachedInstallerButton({
    required this.clearing,
    required this.onDelete,
  });

  final bool clearing;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return OutlinedButton.icon(
      onPressed: clearing ? null : onDelete,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(48),
        foregroundColor: Theme.of(context).colorScheme.error,
      ),
      icon: clearing
          ? const SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 3),
            )
          : const Icon(Icons.delete_sweep_rounded),
      label: Text(
        l10n.updatesDeleteCachedApkAction,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

class _UpdateHero extends StatelessWidget {
  const _UpdateHero({
    required this.checking,
    required this.title,
    required this.subtitle,
  });

  final bool checking;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final compact = MediaQuery.sizeOf(context).height < 720;
    return Padding(
      padding: EdgeInsets.fromLTRB(6, compact ? 18 : 44, 6, compact ? 18 : 34),
      child: Column(
        children: [
          Text(
            'HydraBox',
            style: theme.textTheme.displaySmall?.copyWith(
              color: cs.onSurface,
              fontWeight: FontWeight.w900,
              letterSpacing: 0,
            ),
          ),
          Gap(compact ? 10 : 16),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            child: checking
                ? SizedBox(
                    key: const ValueKey('checking'),
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(
                      strokeWidth: 4,
                      color: cs.primary,
                    ),
                  )
                : Text(
                    key: ValueKey(title),
                    title,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
          ),
          Gap(compact ? 8 : 14),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: cs.onSurfaceVariant,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

class _UpdateInfoCard extends StatelessWidget {
  const _UpdateInfoCard({
    required this.currentVersion,
    required this.info,
    required this.checkedAt,
    required this.action,
    required this.verification,
    required this.cacheAction,
  });

  final String currentVersion;
  final AppUpdateInfo? info;
  final DateTime? checkedAt;
  final Widget action;
  final AppUpdateVerificationResult? verification;
  final Widget? cacheAction;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _InfoRow(label: l10n.updatesCurrentVersion, value: currentVersion),
            const Gap(8),
            _InfoRow(
              label: l10n.updatesLatestVersion,
              value: info?.displayVersion ?? '—',
            ),
            const Gap(14),
            action,
            if (cacheAction != null) ...[const Gap(8), cacheAction!],
            if (verification != null) ...[
              const Gap(10),
              _InfoRow(
                label: l10n.updatesApkVerificationTitle,
                value: verification!.checksumAvailable
                    ? verification!.ok
                          ? l10n.updatesApkVerificationVerified
                          : l10n.updatesApkVerificationFailed
                    : l10n.updatesApkVerificationUnavailable,
                valueMaxLines: 2,
              ),
            ],
            const Gap(8),
            _InfoRow(
              label: l10n.updatesAsset,
              value: info?.asset.name ?? '—',
              valueMaxLines: 2,
              vertical: true,
            ),
            if (checkedAt != null) ...[
              const Gap(8),
              Text(
                l10n.updatesLastChecked(_formatTime(checkedAt!)),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _DownloadProgressCard extends StatelessWidget {
  const _DownloadProgressCard({required this.progress});

  final AppUpdateDownloadProgress? progress;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final value = progress?.fraction;
    final downloaded = _formatBytes(progress?.downloadedBytes ?? 0, l10n);
    final total = progress?.totalBytes != null && progress!.totalBytes > 0
        ? _formatBytes(progress!.totalBytes, l10n)
        : l10n.updatesUnknownSize;
    final eta = _formatEta(context, progress?.etaSeconds);
    final stage = progress?.stage ?? AppUpdateDownloadStage.downloading;
    final title = switch (stage) {
      AppUpdateDownloadStage.cleaning => l10n.updatesStageCleaning,
      AppUpdateDownloadStage.downloading => l10n.updatesDownloadingTitle,
      AppUpdateDownloadStage.verifying => l10n.updatesStageVerifying,
      AppUpdateDownloadStage.ready => l10n.updatesDownloadedTitle,
    };
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const Gap(12),
            LinearProgressIndicator(value: value, minHeight: 4),
            const Gap(10),
            if (stage == AppUpdateDownloadStage.downloading)
              Text(l10n.updatesProgressBytes(downloaded, total)),
            if (stage == AppUpdateDownloadStage.downloading &&
                progress != null &&
                progress!.bytesPerSecond > 0) ...[
              const Gap(4),
              Text(
                l10n.updatesProgressSpeedEta(
                  _formatBytes(progress!.bytesPerSecond.round(), l10n),
                  eta,
                ),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.label,
    required this.value,
    this.valueMaxLines = 1,
    this.vertical = false,
  });

  final String label;
  final String value;
  final int valueMaxLines;
  final bool vertical;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final labelStyle = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final valueStyle = theme.textTheme.bodyMedium?.copyWith(
      fontWeight: FontWeight.w700,
    );
    if (vertical) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: labelStyle),
          const Gap(4),
          Text(
            value,
            maxLines: valueMaxLines,
            overflow: TextOverflow.ellipsis,
            style: valueStyle,
          ),
        ],
      );
    }
    return Row(
      children: [
        Expanded(child: Text(label, style: labelStyle)),
        const Gap(12),
        Flexible(
          child: Text(
            value,
            maxLines: valueMaxLines,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.right,
            style: valueStyle,
          ),
        ),
      ],
    );
  }
}

String _formatBytes(int bytes, AppLocalizations l10n) {
  if (bytes <= 0) return l10n.updatesUnknownSize;
  const units = ['B', 'KB', 'MB', 'GB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  final digits = value >= 100 || unit == 0 ? 0 : 1;
  return '${value.toStringAsFixed(digits)} ${units[unit]}';
}

String _formatEta(BuildContext context, int? seconds) {
  final l10n = AppLocalizations.of(context);
  if (seconds == null || seconds < 0) return '—';
  if (seconds < 60) return l10n.updatesEtaSeconds(seconds);
  return l10n.updatesEtaMinutes(seconds ~/ 60, seconds % 60);
}

String _formatTime(DateTime time) {
  final local = time.toLocal();
  String two(int value) => value.toString().padLeft(2, '0');
  return '${two(local.day)}.${two(local.month)}.${local.year} '
      '${two(local.hour)}:${two(local.minute)}';
}

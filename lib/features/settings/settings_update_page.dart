import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:meow_client/data/update/app_update_service.dart';
import 'package:meow_client/features/settings/settings_ui.dart';
import 'package:meow_client/l10n/generated/app_localizations.dart';
import 'package:meow_client/singbox/singbox_runtime.dart';
import 'package:meow_client/widgets/progressive_blur_scaffold.dart';

class SettingsUpdatePage extends StatefulWidget {
  const SettingsUpdatePage({super.key, required this.currentVersion});

  final String currentVersion;

  @override
  State<SettingsUpdatePage> createState() => _SettingsUpdatePageState();
}

class _SettingsUpdatePageState extends State<SettingsUpdatePage> {
  AppUpdateCheckResult? _result;
  AppUpdateDownloadProgress? _downloadProgress;
  bool _checking = false;
  bool _downloading = false;
  bool _installing = false;
  bool _clearingUpdateCache = false;
  String? _downloadedFilePath;

  @override
  void initState() {
    super.initState();
    unawaited(_check(manual: false));
  }

  Future<void> _check({required bool manual}) async {
    if (_checking || _downloading || _clearingUpdateCache) return;
    setState(() {
      _checking = true;
      if (manual) {
        _downloadProgress = null;
      }
    });
    final result = await AppUpdateService.instance.checkForUpdates(
      currentVersion: widget.currentVersion,
      manual: manual,
    );
    if (!mounted) return;
    setState(() {
      _result = result;
      _checking = false;
      _downloadedFilePath = result.downloadedFilePath;
    });
  }

  Future<void> _download(AppUpdateInfo info) async {
    if (_downloading || _checking || _clearingUpdateCache) return;
    setState(() {
      _downloading = true;
      _downloadProgress = const AppUpdateDownloadProgress(
        downloadedBytes: 0,
        totalBytes: 0,
        bytesPerSecond: 0,
        done: false,
      );
    });
    try {
      await AppUpdateService.instance.downloadUpdate(
        info,
        onProgress: (progress) {
          if (!mounted) return;
          setState(() => _downloadProgress = progress);
        },
      );
      if (!mounted) return;
      final filePath = _downloadProgress?.filePath;
      setState(() {
        _downloading = false;
        _downloadedFilePath = filePath;
        _result = AppUpdateCheckResult(
          status: AppUpdateStatus.downloaded,
          checkedAt: DateTime.now(),
          info: info,
          downloadedFilePath: filePath,
        );
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _downloading = false;
        _result = AppUpdateCheckResult(
          status: AppUpdateStatus.error,
          checkedAt: DateTime.now(),
          info: info,
          error: error.toString(),
        );
      });
    }
  }

  Future<void> _installDownloaded() async {
    if (_checking || _downloading || _installing || _clearingUpdateCache) {
      return;
    }
    final path = _cachedInstallerPath ?? '';
    if (path.isEmpty) {
      setState(() {
        _result = AppUpdateCheckResult(
          status: AppUpdateStatus.error,
          checkedAt: DateTime.now(),
          info: _result?.info,
          error: AppLocalizations.of(context).updatesDownloadedFileMissing,
        );
      });
      return;
    }
    setState(() => _installing = true);
    try {
      final canInstall = await SingboxRuntime.instance.canInstallApks();
      if (!canInstall) {
        await SingboxRuntime.instance.openApkInstallSettings();
        if (!mounted) return;
        setState(() => _installing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context).updatesInstallPermissionHint,
            ),
          ),
        );
        return;
      }
      await SingboxRuntime.instance.installDownloadedApk(path);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _result = AppUpdateCheckResult(
          status: AppUpdateStatus.error,
          checkedAt: DateTime.now(),
          info: _result?.info,
          error: error.toString(),
          downloadedFilePath: path,
        );
      });
    } finally {
      if (mounted) {
        setState(() => _installing = false);
      }
    }
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
    final version = _result?.info?.version.trim().isNotEmpty == true
        ? 'v${_result!.info!.version}'
        : widget.currentVersion;
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
      currentVersion: widget.currentVersion,
    );
    final metadata = await AppUpdateService.instance.loadMetadata();
    if (!mounted) return;
    setState(() {
      _clearingUpdateCache = false;
      _downloadedFilePath = null;
      _downloadProgress = null;
      _result = AppUpdateCheckResult(
        status: metadata.lastStatus,
        checkedAt: metadata.lastCheckAt ?? DateTime.now(),
        info: metadata.latestInfo,
        error: metadata.lastError,
      );
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.updatesDeleteCachedApkDone(deleted))),
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
            onPressed: _checking || _downloading || _installing
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
            currentVersion: widget.currentVersion,
            info: info,
            checkedAt: result?.checkedAt,
            action: _UpdateActionButton(
              result: result,
              checking: _checking,
              downloading: _downloading,
              installing: _installing,
              onCheck: () => _check(manual: true),
              onDownload: info == null ? null : () => _download(info),
              onInstall: cachedInstallerPath == null
                  ? null
                  : _installDownloaded,
            ),
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
            _ReleaseNotesCard(body: info.body),
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
    if (_checking) return 'Etonify';
    if (_downloading) return l10n.updatesDownloadingTitle;
    return switch (result?.status) {
      AppUpdateStatus.updateAvailable => l10n.updatesAvailableTitle,
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
      AppUpdateStatus.updateAvailable when info != null =>
        l10n.updatesAvailableSubtitle(
          'v${info.version}',
          _formatBytes(info.asset.sizeBytes, l10n),
        ),
      AppUpdateStatus.downloaded => l10n.updatesDownloadedSubtitle(
        (_downloadedFilePath ?? _downloadProgress?.filePath) == null
            ? ''
            : File(
                (_downloadedFilePath ?? _downloadProgress!.filePath)!,
              ).uri.pathSegments.last,
      ),
      AppUpdateStatus.upToDate => l10n.updatesUpToDateSubtitle(
        widget.currentVersion,
      ),
      AppUpdateStatus.error => l10n.updatesErrorSubtitle,
      _ => l10n.updatesSubtitle,
    };
  }
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
    if (downloading || installing) {
      return Text(
        installing ? l10n.updatesOpeningInstaller : l10n.updatesDownloadWarning,
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
        icon: const Icon(Icons.install_mobile_rounded),
        label: Text(
          l10n.updatesInstallAction,
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
          l10n.updatesDownloadAction,
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
            'Etonify',
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
    required this.cacheAction,
  });

  final String currentVersion;
  final AppUpdateInfo? info;
  final DateTime? checkedAt;
  final Widget action;
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
              value: info == null ? '—' : 'v${info!.version}',
            ),
            const Gap(14),
            action,
            if (cacheAction != null) ...[const Gap(8), cacheAction!],
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
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.updatesDownloadingTitle,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const Gap(12),
            LinearProgressIndicator(value: value, minHeight: 4),
            const Gap(10),
            Text(l10n.updatesProgressBytes(downloaded, total)),
            if (progress != null && progress!.bytesPerSecond > 0) ...[
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

class _ReleaseNotesCard extends StatelessWidget {
  const _ReleaseNotesCard({required this.body});

  final String body;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final lines = _releaseNoteLines(body);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.updatesReleaseNotesTitle,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const Gap(12),
            if (lines.isEmpty)
              Text(
                l10n.updatesNoReleaseNotes,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              )
            else
              ...lines.map((line) => _ReleaseNoteLine(line: line)),
          ],
        ),
      ),
    );
  }
}

class _ReleaseNoteLine extends StatelessWidget {
  const _ReleaseNoteLine({required this.line});

  final _ReleaseLine line;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final textStyle = switch (line.kind) {
      _ReleaseLineKind.heading => theme.textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.w900,
      ),
      _ReleaseLineKind.bullet => theme.textTheme.bodyMedium?.copyWith(
        color: cs.onSurfaceVariant,
        height: 1.35,
      ),
      _ReleaseLineKind.paragraph => theme.textTheme.bodyMedium?.copyWith(
        color: cs.onSurfaceVariant,
        height: 1.35,
      ),
    };
    if (line.kind == _ReleaseLineKind.bullet) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Container(
                width: 5,
                height: 5,
                decoration: BoxDecoration(
                  color: cs.primary,
                  shape: BoxShape.circle,
                ),
              ),
            ),
            const Gap(10),
            Expanded(child: Text(line.text, style: textStyle)),
          ],
        ),
      );
    }
    return Padding(
      padding: EdgeInsets.only(
        top: line.kind == _ReleaseLineKind.heading ? 8 : 0,
        bottom: line.kind == _ReleaseLineKind.heading ? 8 : 10,
      ),
      child: Text(line.text, style: textStyle),
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

enum _ReleaseLineKind { heading, bullet, paragraph }

class _ReleaseLine {
  const _ReleaseLine(this.kind, this.text);

  final _ReleaseLineKind kind;
  final String text;
}

List<_ReleaseLine> _releaseNoteLines(String body) {
  final trimmedBody = body.trim();
  if (trimmedBody.isEmpty) return const <_ReleaseLine>[];
  final limited = trimmedBody.length > 6000
      ? '${trimmedBody.substring(0, 6000)}…'
      : trimmedBody;
  final lines = <_ReleaseLine>[];
  for (final raw in limited.split(RegExp(r'\r?\n'))) {
    final line = raw.trim();
    if (line.isEmpty) continue;
    if (line.startsWith('#')) {
      lines.add(
        _ReleaseLine(
          _ReleaseLineKind.heading,
          line.replaceFirst(RegExp(r'^#+\s*'), ''),
        ),
      );
    } else if (line.startsWith('- ') ||
        line.startsWith('* ') ||
        RegExp(r'^\d+\.\s+').hasMatch(line)) {
      lines.add(
        _ReleaseLine(
          _ReleaseLineKind.bullet,
          line
              .replaceFirst(RegExp(r'^[-*]\s+'), '')
              .replaceFirst(RegExp(r'^\d+\.\s+'), ''),
        ),
      );
    } else {
      lines.add(_ReleaseLine(_ReleaseLineKind.paragraph, line));
    }
    if (lines.length >= 48) break;
  }
  return lines;
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

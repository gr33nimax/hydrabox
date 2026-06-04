import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gap/gap.dart';
import 'package:meow_client/data/snowtun/snowtun_binary_service.dart';
import 'package:meow_client/features/settings/settings_ui.dart';
import 'package:meow_client/l10n/generated/app_localizations.dart';
import 'package:meow_client/widgets/progressive_blur_scaffold.dart';
import 'package:meow_client/singbox/singbox_runtime.dart';

enum _SnowtunAction { install, remove }

class SettingsWhitelistPage extends StatefulWidget {
  const SettingsWhitelistPage({
    super.key,
    required this.currentSnowtunStatus,
    required this.onUpdateSnowtunBinary,
    required this.onDeleteSnowtunBinary,
  });

  final SnowtunBinaryStatus currentSnowtunStatus;
  final Future<SnowtunBinaryStatus> Function({
    required void Function(SnowtunDownloadProgress progress) onProgress,
  })
  onUpdateSnowtunBinary;
  final Future<SnowtunBinaryStatus> Function() onDeleteSnowtunBinary;

  @override
  State<SettingsWhitelistPage> createState() => _SettingsWhitelistPageState();
}

class _SettingsWhitelistPageState extends State<SettingsWhitelistPage> {
  late SnowtunBinaryStatus _status;
  SnowtunDownloadProgress? _progress;
  bool _busy = false;
  _SnowtunAction? _activeAction;

  @override
  void initState() {
    super.initState();
    _status = widget.currentSnowtunStatus;
  }

  Future<void> _updateSnowtun() async {
    if (_busy) {
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _progress = null;
      _activeAction = _SnowtunAction.install;
    });
    try {
      final status = await widget.onUpdateSnowtunBinary(
        onProgress: (progress) {
          if (!mounted) {
            return;
          }
          setState(() {
            _progress = progress;
          });
        },
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _status = status;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).snowtunInstalledMessage),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      if (error is PlatformException &&
          error.code == 'install_permission_required') {
        await _handleInstallPermissionRequired();
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_friendlyErrorText(error))));
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _progress = null;
          _activeAction = null;
        });
      }
    }
  }

  Future<void> _deleteSnowtun() async {
    if (_busy) {
      return;
    }
    setState(() {
      _busy = true;
      _activeAction = _SnowtunAction.remove;
    });
    try {
      final status = await widget.onDeleteSnowtunBinary();
      if (!mounted) {
        return;
      }
      setState(() {
        _status = status;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_friendlyErrorText(error))));
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _activeAction = null;
        });
      }
    }
  }

  String _progressLabel() {
    final progress = _progress;
    final l10n = AppLocalizations.of(context);
    if (progress == null) {
      if (_busy && _activeAction == _SnowtunAction.remove) {
        return l10n.snowtunRemovingStatus;
      }
      return _status.available
          ? l10n.snowtunReadyShort
          : l10n.snowtunNotInstalledShort;
    }
    switch (progress.phase) {
      case SnowtunDownloadPhase.fetchingManifest:
        return l10n.snowtunPreparingInstallStatus;
      case SnowtunDownloadPhase.downloadingChunks:
        return l10n.snowtunDownloadingModuleStatus;
      case SnowtunDownloadPhase.finalizing:
        return l10n.snowtunInstallingStatus;
    }
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) {
      return '0 B';
    }
    const suffixes = ['B', 'KB', 'MB', 'GB'];
    var value = bytes.toDouble();
    var unitIndex = 0;
    while (value >= 1024 && unitIndex < suffixes.length - 1) {
      value /= 1024;
      unitIndex++;
    }
    final fractionDigits = value >= 100 || unitIndex == 0 ? 0 : 1;
    return '${value.toStringAsFixed(fractionDigits)} ${suffixes[unitIndex]}';
  }

  String _friendlyErrorText(Object error) {
    final l10n = AppLocalizations.of(context);
    final raw = error.toString();
    final lower = raw.toLowerCase();
    if (error is PlatformException &&
        (raw.contains('io/flutter/util/PathUtils') ||
            lower.contains('pathutils') ||
            lower.contains('classnotfoundexception'))) {
      return l10n.snowtunStoragePrepareFailed;
    }
    if (lower.contains('checksum mismatch')) {
      return l10n.snowtunIntegrityFailed;
    }
    if (error is PlatformException &&
        error.code == 'install_permission_required') {
      return l10n.snowtunInstallPermissionRequired;
    }
    if (error is PlatformException && error.code == 'chmod_failed') {
      return l10n.snowtunLaunchPrepareFailed;
    }
    if (error is PlatformException && error.code == 'missing_file') {
      return l10n.snowtunDownloadedFileMissing;
    }
    if (lower.contains('failed to download snowtun artifact')) {
      return l10n.snowtunDownloadModuleFailed;
    }
    if (lower.contains('compatible artifact')) {
      return l10n.snowtunNoCompatibleModule;
    }
    if (error is PlatformException &&
        (error.code == 'install_split_failed' ||
            error.code == 'remove_split_failed')) {
      final detail = error.message?.trim();
      if (detail != null && detail.isNotEmpty) {
        return l10n.snowtunInstallOrRemoveFailedWithDetail(detail);
      }
      return l10n.snowtunInstallOrRemoveFailed;
    }
    if (lower.contains('snowtun module package mismatch') ||
        lower.contains('snowtun module version mismatch')) {
      return l10n.snowtunWrongAppVersion;
    }
    if (error is PlatformException &&
        (error.code == 'package_mismatch' ||
            error.code == 'version_mismatch' ||
            error.code == 'invalid_apk')) {
      return l10n.snowtunIncompatibleModulePackage;
    }
    return l10n.snowtunGenericFailure;
  }

  Future<void> _handleInstallPermissionRequired() async {
    if (!mounted) {
      return;
    }
    final openSettings = await showDialog<bool>(
      context: context,
      builder: (context) {
        final theme = Theme.of(context);
        return AlertDialog(
          title: Text(
            AppLocalizations.of(context).snowtunInstallPermissionTitle,
          ),
          content: Text(
            AppLocalizations.of(context).snowtunInstallPermissionMessage,
            style: theme.textTheme.bodyMedium,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(
                AppLocalizations.of(context).snowtunInstallPermissionSkip,
              ),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(
                AppLocalizations.of(context).snowtunInstallPermissionAllow,
              ),
            ),
          ],
        );
      },
    );
    if (openSettings != true || !mounted) {
      return;
    }
    try {
      await SingboxRuntime.instance.requestInstallPackagesPermission();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context);
    final progress = _progress;
    final progressValue = progress?.progress;

    return ProgressiveBlurScaffold(
      appBar: AppBar(title: Text(l10n.whitelistTitle)),
      body: Theme(
        data: settingsTileTheme(context),
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            settingsScreenPadding.left,
            progressiveHeaderTopPadding(context, settingsScreenPadding.top),
            settingsScreenPadding.right,
            appBottomSafePadding(context, settingsScreenPadding.bottom),
          ),
          children: [
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        SettingsLeadingIcon(
                          icon: Icons.ac_unit_rounded,
                          color: theme.colorScheme.primary,
                        ),
                        const Gap(12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                l10n.snowtunTitle,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const Gap(16),
                    Text(l10n.snowtunModuleDescription),
                    const Gap(16),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: colorScheme.outlineVariant.withValues(
                            alpha: .18,
                          ),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                _status.available
                                    ? Icons.verified_rounded
                                    : Icons.download_for_offline_rounded,
                                size: 18,
                                color: colorScheme.primary,
                              ),
                              const Gap(8),
                              Expanded(
                                child: Text(
                                  _status.available
                                      ? l10n.snowtunInstalledSummary
                                      : l10n.snowtunNotInstalledSummary,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const Gap(6),
                          Text(
                            _progressLabel(),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Gap(16),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final button = _status.available
                            ? OutlinedButton.icon(
                                onPressed: _busy ? null : _deleteSnowtun,
                                style: OutlinedButton.styleFrom(
                                  minimumSize: const Size.fromHeight(54),
                                ),
                                icon: _busy
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Icons.delete_outline_rounded),
                                label: Text(l10n.snowtunRemoveModuleAction),
                              )
                            : FilledButton.tonalIcon(
                                onPressed: _busy ? null : _updateSnowtun,
                                style: FilledButton.styleFrom(
                                  minimumSize: const Size.fromHeight(54),
                                ),
                                icon: _busy
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Icons.download_rounded),
                                label: Text(l10n.snowtunInstallModuleAction),
                              );
                        if (constraints.maxWidth < 420) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [button],
                          );
                        }
                        return SizedBox(width: double.infinity, child: button);
                      },
                    ),
                    AnimatedSize(
                      duration: const Duration(milliseconds: 280),
                      curve: Curves.easeOutCubic,
                      alignment: Alignment.topCenter,
                      child: _busy || progress != null
                          ? Padding(
                              padding: const EdgeInsets.only(top: 16),
                              child: Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: colorScheme.surfaceContainerLow,
                                  borderRadius: BorderRadius.circular(18),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    AnimatedSwitcher(
                                      duration: const Duration(
                                        milliseconds: 220,
                                      ),
                                      switchInCurve: Curves.easeOutCubic,
                                      switchOutCurve: Curves.easeOutCubic,
                                      child: Text(
                                        _progressLabel(),
                                        key: ValueKey(_progressLabel()),
                                        style: theme.textTheme.bodyMedium
                                            ?.copyWith(
                                              color:
                                                  colorScheme.onSurfaceVariant,
                                              fontWeight: FontWeight.w600,
                                            ),
                                      ),
                                    ),
                                    const Gap(10),
                                    _AnimatedProgressBar(value: progressValue),
                                    if (progress != null) ...[
                                      const Gap(8),
                                      AnimatedSwitcher(
                                        duration: const Duration(
                                          milliseconds: 220,
                                        ),
                                        child: Text(
                                          '${_formatBytes(progress.downloadedBytes)} / ${_formatBytes(progress.totalBytes)}',
                                          key: ValueKey(
                                            '${progress.downloadedBytes}/${progress.totalBytes}',
                                          ),
                                          style: theme.textTheme.bodySmall
                                              ?.copyWith(
                                                color: colorScheme
                                                    .onSurfaceVariant,
                                              ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            )
                          : Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: Text(
                                _progressLabel(),
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AnimatedProgressBar extends StatelessWidget {
  const _AnimatedProgressBar({required this.value});

  final double? value;

  @override
  Widget build(BuildContext context) {
    if (value == null) {
      return const LinearProgressIndicator();
    }
    final normalized = value!.clamp(0.0, 1.0);
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: normalized),
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      builder: (context, animatedValue, child) {
        return LinearProgressIndicator(value: animatedValue);
      },
    );
  }
}

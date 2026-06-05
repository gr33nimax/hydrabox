import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:meow_client/data/adblock/ad_block_rule_set_service.dart';
import 'package:meow_client/data/local/app_settings_store.dart';
import 'package:meow_client/data/routing/russia_route_data_service.dart';
import 'package:meow_client/features/settings/settings_ui.dart';
import 'package:meow_client/l10n/generated/app_localizations.dart';
import 'package:meow_client/widgets/progressive_blur_scaffold.dart';

class SettingsRoutingPage extends StatefulWidget {
  const SettingsRoutingPage({
    super.key,
    required this.currentBlockLeaks,
    required this.currentAdBlockEnabled,
    required this.currentAdBlockStatus,
    required this.currentRussiaRouteDataEnabled,
    required this.currentRussiaRouteDataStatus,
    required this.currentBypassLocalNetwork,
    required this.currentSplitRoutingMode,
    required this.currentSplitRoutingPackages,
    required this.initialInstalledApps,
    required this.preloadInstalledApps,
    required this.onBlockLeaksChanged,
    required this.onAdBlockEnabledChanged,
    required this.onDownloadAdBlockRuleSet,
    required this.onDeleteAdBlockRuleSet,
    required this.onRussiaRouteDataEnabledChanged,
    required this.onInstallRussiaRouteData,
    required this.onDeleteRussiaRouteData,
    required this.onBypassLocalNetworkChanged,
    required this.onSplitRoutingModeChanged,
    required this.onSplitRoutingPackagesChanged,
  });

  final bool currentBlockLeaks;
  final bool currentAdBlockEnabled;
  final AdBlockRuleSetStatus currentAdBlockStatus;
  final bool currentRussiaRouteDataEnabled;
  final RussiaRouteDataStatus currentRussiaRouteDataStatus;
  final bool currentBypassLocalNetwork;
  final SplitRoutingMode currentSplitRoutingMode;
  final List<String> currentSplitRoutingPackages;
  final List<Map<String, dynamic>> initialInstalledApps;
  final Future<List<Map<String, dynamic>>> Function() preloadInstalledApps;
  final ValueChanged<bool> onBlockLeaksChanged;
  final ValueChanged<bool> onAdBlockEnabledChanged;
  final Future<AdBlockRuleSetStatus> Function() onDownloadAdBlockRuleSet;
  final Future<AdBlockRuleSetStatus> Function() onDeleteAdBlockRuleSet;
  final ValueChanged<bool> onRussiaRouteDataEnabledChanged;
  final Future<RussiaRouteDataStatus> Function() onInstallRussiaRouteData;
  final Future<RussiaRouteDataStatus> Function() onDeleteRussiaRouteData;
  final ValueChanged<bool> onBypassLocalNetworkChanged;
  final ValueChanged<SplitRoutingMode> onSplitRoutingModeChanged;
  final ValueChanged<List<String>> onSplitRoutingPackagesChanged;

  @override
  State<SettingsRoutingPage> createState() => _SettingsRoutingPageState();
}

class _SettingsRoutingPageState extends State<SettingsRoutingPage> {
  late bool _blockLeaks;
  late bool _adBlockEnabled;
  late AdBlockRuleSetStatus _adBlockStatus;
  late bool _russiaRouteDataEnabled;
  late RussiaRouteDataStatus _russiaRouteDataStatus;
  late bool _bypassLocalNetwork;
  late SplitRoutingMode _splitRoutingMode;
  late final TextEditingController _packagesController;
  bool _adBlockBusy = false;
  bool _russiaRouteDataBusy = false;
  bool _loadingInstalledApps = false;
  String? _installedAppsError;
  bool _manualEditorExpanded = false;
  List<_InstalledApp> _installedApps = const <_InstalledApp>[];

  @override
  void initState() {
    super.initState();
    _blockLeaks = widget.currentBlockLeaks;
    _adBlockEnabled = widget.currentAdBlockEnabled;
    _adBlockStatus = widget.currentAdBlockStatus;
    _russiaRouteDataEnabled = widget.currentRussiaRouteDataEnabled;
    _russiaRouteDataStatus = widget.currentRussiaRouteDataStatus;
    _bypassLocalNetwork = widget.currentBypassLocalNetwork;
    _splitRoutingMode = widget.currentSplitRoutingMode;
    _packagesController = TextEditingController(
      text: widget.currentSplitRoutingPackages.join('\n'),
    );
    _installedApps = widget.initialInstalledApps
        .map((item) => _InstalledApp.fromMap(item))
        .where((item) => item.packageName.isNotEmpty)
        .toList(growable: false);
    _loadInstalledApps();
  }

  @override
  void dispose() {
    _commitPackages();
    _packagesController.dispose();
    super.dispose();
  }

  Future<void> _loadInstalledApps() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return;
    }
    if (_installedApps.isEmpty) {
      setState(() {
        _loadingInstalledApps = true;
        _installedAppsError = null;
      });
    }
    try {
      final items = await widget.preloadInstalledApps();
      if (!mounted) {
        return;
      }
      setState(() {
        _installedApps = items
            .map((item) => _InstalledApp.fromMap(item))
            .where((item) => item.packageName.isNotEmpty)
            .toList(growable: false);
        _loadingInstalledApps = false;
        _installedAppsError = null;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loadingInstalledApps = false;
        _installedAppsError = error.toString();
      });
    }
  }

  List<String> _selectedPackages() {
    return normalizeSplitRoutingPackages(
      _packagesController.text.split(RegExp(r'[\n,;]')),
    );
  }

  void _commitPackages() {
    final packages = _selectedPackages();
    widget.onSplitRoutingPackagesChanged(packages);
    final normalizedText = packages.join('\n');
    if (_packagesController.text.trim() != normalizedText) {
      _packagesController.text = normalizedText;
    }
  }

  void _showOperationError(Object error) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(error.toString())));
  }

  Future<void> _setAdBlock(bool value) async {
    if (!value) {
      setState(() {
        _adBlockEnabled = false;
      });
      widget.onAdBlockEnabledChanged(false);
      return;
    }
    if (_adBlockStatus.available) {
      setState(() {
        _adBlockEnabled = true;
      });
      widget.onAdBlockEnabledChanged(true);
      return;
    }
    await _downloadAdBlock(enableAfterDownload: true);
  }

  Future<void> _downloadAdBlock({bool enableAfterDownload = false}) async {
    if (_adBlockBusy) {
      return;
    }
    setState(() {
      _adBlockBusy = true;
    });
    try {
      final status = await widget.onDownloadAdBlockRuleSet();
      if (!mounted) {
        return;
      }
      setState(() {
        _adBlockStatus = status;
        if (enableAfterDownload && status.available) {
          _adBlockEnabled = true;
        }
      });
      if (enableAfterDownload && status.available) {
        widget.onAdBlockEnabledChanged(true);
      }
    } catch (error) {
      if (mounted) {
        _showOperationError(error);
      }
    } finally {
      if (mounted) {
        setState(() {
          _adBlockBusy = false;
        });
      }
    }
  }

  Future<void> _deleteAdBlock() async {
    if (_adBlockBusy) {
      return;
    }
    setState(() {
      _adBlockBusy = true;
    });
    try {
      final status = await widget.onDeleteAdBlockRuleSet();
      if (!mounted) {
        return;
      }
      setState(() {
        _adBlockStatus = status;
        _adBlockEnabled = false;
      });
    } catch (error) {
      if (mounted) {
        _showOperationError(error);
      }
    } finally {
      if (mounted) {
        setState(() {
          _adBlockBusy = false;
        });
      }
    }
  }

  Future<void> _setRussiaRouteData(bool value) async {
    if (!value) {
      setState(() {
        _russiaRouteDataEnabled = false;
      });
      widget.onRussiaRouteDataEnabledChanged(false);
      return;
    }
    if (_russiaRouteDataStatus.available) {
      setState(() {
        _russiaRouteDataEnabled = true;
      });
      widget.onRussiaRouteDataEnabledChanged(true);
      return;
    }
    await _installRussiaRouteData(enableAfterInstall: true);
  }

  Future<void> _installRussiaRouteData({
    bool enableAfterInstall = false,
  }) async {
    if (_russiaRouteDataBusy) {
      return;
    }
    setState(() {
      _russiaRouteDataBusy = true;
    });
    try {
      final status = await widget.onInstallRussiaRouteData();
      if (!mounted) {
        return;
      }
      setState(() {
        _russiaRouteDataStatus = status;
        if (enableAfterInstall && status.available) {
          _russiaRouteDataEnabled = true;
        }
      });
      if (enableAfterInstall && status.available) {
        widget.onRussiaRouteDataEnabledChanged(true);
      }
    } catch (error) {
      if (mounted) {
        _showOperationError(error);
      }
    } finally {
      if (mounted) {
        setState(() {
          _russiaRouteDataBusy = false;
        });
      }
    }
  }

  Future<void> _deleteRussiaRouteData() async {
    if (_russiaRouteDataBusy) {
      return;
    }
    setState(() {
      _russiaRouteDataBusy = true;
    });
    try {
      final status = await widget.onDeleteRussiaRouteData();
      if (!mounted) {
        return;
      }
      setState(() {
        _russiaRouteDataStatus = status;
        _russiaRouteDataEnabled = false;
      });
    } catch (error) {
      if (mounted) {
        _showOperationError(error);
      }
    } finally {
      if (mounted) {
        setState(() {
          _russiaRouteDataBusy = false;
        });
      }
    }
  }

  Future<void> _openAppPicker() async {
    FocusScope.of(context).unfocus();
    _commitPackages();
    final result = await showModalBottomSheet<Set<String>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => _AppPickerSheet(
        apps: _installedApps,
        initialSelected: _selectedPackages().toSet(),
      ),
    );
    if (result == null) {
      return;
    }
    final packages = result.toList()..sort();
    _packagesController.text = packages.join('\n');
    _commitPackages();
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isAndroid =
        !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
    final selectedPackages = _selectedPackages();
    final installedAppByPackage = <String, _InstalledApp>{
      for (final app in _installedApps) app.packageName: app,
    };
    final selectedApps = selectedPackages
        .map(
          (packageName) =>
              installedAppByPackage[packageName] ??
              _InstalledApp(
                packageName: packageName,
                label: packageName,
                system: false,
                launchable: false,
              ),
        )
        .toList(growable: false);

    return ProgressiveBlurScaffold(
      appBar: AppBar(title: Text(l10n.routingTitle)),
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SwitchListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 4,
                    ),
                    secondary: SettingsLeadingIcon(
                      icon: Icons.shield_outlined,
                      color: theme.colorScheme.primary,
                    ),
                    title: Text(l10n.blockLeaksTitle),
                    subtitle: Text(l10n.blockLeaksSubtitle),
                    value: _blockLeaks,
                    onChanged: (value) {
                      setState(() {
                        _blockLeaks = value;
                      });
                      widget.onBlockLeaksChanged(value);
                    },
                  ),
                  SwitchListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 4,
                    ),
                    secondary: SettingsLeadingIcon(
                      icon: Icons.lan_rounded,
                      color: theme.colorScheme.primary,
                    ),
                    title: Text(l10n.bypassLocalNetworkTitle),
                    subtitle: Text(l10n.bypassLocalNetworkSubtitle),
                    value: _bypassLocalNetwork,
                    onChanged: (value) {
                      setState(() {
                        _bypassLocalNetwork = value;
                      });
                      widget.onBypassLocalNetworkChanged(value);
                    },
                  ),
                ],
              ),
            ),
            const Gap(settingsIslandGap),
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SettingsLeadingIcon(
                          icon: Icons.travel_explore_rounded,
                          color: cs.primary,
                        ),
                        const Gap(12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                l10n.russiaRoutesTitle,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const Gap(4),
                              Text(
                                l10n.russiaRoutesSubtitle,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const Gap(16),
                    _RussiaRouteDataStatusPanel(
                      status: _russiaRouteDataStatus,
                      busy: _russiaRouteDataBusy,
                      l10n: l10n,
                    ),
                    const Gap(12),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.tonalIcon(
                            onPressed: _russiaRouteDataBusy
                                ? null
                                : () => _installRussiaRouteData(),
                            icon: _russiaRouteDataBusy
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : Icon(
                                    _russiaRouteDataStatus.available
                                        ? Icons.refresh_rounded
                                        : Icons.download_rounded,
                                  ),
                            label: Text(
                              _russiaRouteDataStatus.available
                                  ? l10n.russiaRoutesUpdateAction
                                  : l10n.russiaRoutesInstallAction,
                            ),
                          ),
                        ),
                        if (_russiaRouteDataStatus.available) ...[
                          const Gap(10),
                          OutlinedButton(
                            onPressed: _russiaRouteDataBusy
                                ? null
                                : _deleteRussiaRouteData,
                            child: Text(l10n.delete),
                          ),
                        ],
                      ],
                    ),
                    const Gap(12),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      secondary: SettingsLeadingIcon(
                        icon: Icons.route_rounded,
                        color: cs.primary,
                      ),
                      title: Text(l10n.russiaRoutesEnableTitle),
                      subtitle: Text(
                        _russiaRouteDataStatus.available
                            ? l10n.russiaRoutesEnabledSubtitle
                            : l10n.russiaRoutesMissingSubtitle,
                      ),
                      value: _russiaRouteDataEnabled,
                      onChanged: _russiaRouteDataBusy
                          ? null
                          : _setRussiaRouteData,
                    ),
                  ],
                ),
              ),
            ),
            const Gap(settingsIslandGap),
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SettingsLeadingIcon(
                          icon: Icons.block_rounded,
                          color: cs.primary,
                        ),
                        const Gap(12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                l10n.adBlockTitle,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const Gap(4),
                              Text(
                                l10n.adBlockSubtitle,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const Gap(16),
                    _AdBlockStatusPanel(
                      status: _adBlockStatus,
                      busy: _adBlockBusy,
                      l10n: l10n,
                    ),
                    const Gap(12),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.tonalIcon(
                            onPressed: _adBlockBusy
                                ? null
                                : () => _downloadAdBlock(),
                            icon: _adBlockBusy
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : Icon(
                                    _adBlockStatus.available
                                        ? Icons.refresh_rounded
                                        : Icons.download_rounded,
                                  ),
                            label: Text(
                              _adBlockStatus.available
                                  ? l10n.adBlockUpdateAction
                                  : l10n.adBlockDownloadAction,
                            ),
                          ),
                        ),
                        if (_adBlockStatus.available) ...[
                          const Gap(10),
                          OutlinedButton(
                            onPressed: _adBlockBusy ? null : _deleteAdBlock,
                            child: Text(l10n.delete),
                          ),
                        ],
                      ],
                    ),
                    const Gap(12),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      secondary: SettingsLeadingIcon(
                        icon: Icons.shield_moon_rounded,
                        color: cs.primary,
                      ),
                      title: Text(l10n.adBlockEnableTitle),
                      subtitle: Text(
                        _adBlockStatus.available
                            ? l10n.adBlockEnabledSubtitle
                            : l10n.adBlockMissingSubtitle,
                      ),
                      value: _adBlockEnabled,
                      onChanged: _adBlockBusy ? null : _setAdBlock,
                    ),
                  ],
                ),
              ),
            ),
            const Gap(settingsIslandGap),
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SettingsLeadingIcon(
                          icon: Icons.alt_route_rounded,
                          color: cs.primary,
                        ),
                        const Gap(12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                l10n.splitRoutingTitle,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const Gap(4),
                              Text(
                                l10n.splitRoutingSubtitle,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const Gap(18),
                    Text(
                      l10n.splitRoutingModeTitle,
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Gap(10),
                    _RoutingModeCard(
                      icon: Icons.block_rounded,
                      title: l10n.splitRoutingModeDisabled,
                      subtitle: l10n.splitRoutingModeDisabledSubtitle,
                      selected: _splitRoutingMode == SplitRoutingMode.disabled,
                      onTap: () {
                        setState(() {
                          _splitRoutingMode = SplitRoutingMode.disabled;
                        });
                        widget.onSplitRoutingModeChanged(
                          SplitRoutingMode.disabled,
                        );
                      },
                    ),
                    const Gap(10),
                    _RoutingModeCard(
                      icon: Icons.north_east_rounded,
                      title: l10n.splitRoutingModeProxySelected,
                      subtitle: l10n.splitRoutingModeProxySelectedSubtitle,
                      selected:
                          _splitRoutingMode == SplitRoutingMode.proxySelected,
                      onTap: () {
                        setState(() {
                          _splitRoutingMode = SplitRoutingMode.proxySelected;
                        });
                        widget.onSplitRoutingModeChanged(
                          SplitRoutingMode.proxySelected,
                        );
                      },
                    ),
                    const Gap(10),
                    _RoutingModeCard(
                      icon: Icons.south_east_rounded,
                      title: l10n.splitRoutingModeBypassSelected,
                      subtitle: l10n.splitRoutingModeBypassSelectedSubtitle,
                      selected:
                          _splitRoutingMode == SplitRoutingMode.bypassSelected,
                      onTap: () {
                        setState(() {
                          _splitRoutingMode = SplitRoutingMode.bypassSelected;
                        });
                        widget.onSplitRoutingModeChanged(
                          SplitRoutingMode.bypassSelected,
                        );
                      },
                    ),
                    if (_splitRoutingMode != SplitRoutingMode.disabled) ...[
                      const Gap(18),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              l10n.splitRoutingAppsTitle,
                              style: theme.textTheme.labelLarge?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: cs.primary.withValues(alpha: .10),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              l10n.splitRoutingSelectedCount(
                                selectedPackages.length,
                              ),
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: cs.primary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const Gap(10),
                      if (isAndroid)
                        FilledButton.tonalIcon(
                          onPressed:
                              !_loadingInstalledApps &&
                                  _installedApps.isNotEmpty
                              ? _openAppPicker
                              : null,
                          icon: _loadingInstalledApps
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.apps_rounded),
                          label: Text(l10n.splitRoutingPickAppsAction),
                        ),
                      if (!isAndroid) ...[
                        const Gap(8),
                        Text(
                          l10n.splitRoutingAndroidOnly,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ] else if (_installedAppsError != null) ...[
                        const Gap(8),
                        Text(
                          l10n.splitRoutingLoadAppsFailed,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: cs.error,
                          ),
                        ),
                      ],
                      const Gap(12),
                      _SelectedAppsPanel(
                        apps: selectedApps,
                        emptyTitle: l10n.splitRoutingNoAppsTitle,
                        emptySubtitle: l10n.splitRoutingNoAppsSubtitle,
                      ),
                      const Gap(12),
                      Theme(
                        data: theme.copyWith(dividerColor: Colors.transparent),
                        child: ExpansionTile(
                          tilePadding: EdgeInsets.zero,
                          childrenPadding: EdgeInsets.zero,
                          initiallyExpanded: _manualEditorExpanded,
                          onExpansionChanged: (expanded) {
                            setState(() {
                              _manualEditorExpanded = expanded;
                            });
                          },
                          title: Text(
                            l10n.splitRoutingManualEditorTitle,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          subtitle: Text(
                            l10n.splitRoutingManualEditorSubtitle,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                          children: [
                            const Gap(8),
                            TextField(
                              controller: _packagesController,
                              minLines: 4,
                              maxLines: 8,
                              onTapOutside: (_) {
                                FocusScope.of(context).unfocus();
                                _commitPackages();
                              },
                              onEditingComplete: () {
                                FocusScope.of(context).unfocus();
                                _commitPackages();
                              },
                              decoration: InputDecoration(
                                labelText: l10n.splitRoutingPackagesTitle,
                                hintText: l10n.splitRoutingPackagesHint,
                                helperText: l10n.splitRoutingPackagesHelper,
                                alignLabelWithHint: true,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
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

class _InstalledApp {
  const _InstalledApp({
    required this.packageName,
    required this.label,
    required this.system,
    required this.launchable,
  });

  final String packageName;
  final String label;
  final bool system;
  final bool launchable;

  factory _InstalledApp.fromMap(Map<String, dynamic> map) {
    return _InstalledApp(
      packageName: map['packageName']?.toString() ?? '',
      label: map['label']?.toString() ?? '',
      system: map['system'] == true,
      launchable: map['launchable'] == true,
    );
  }
}

class _ScoredInstalledApp {
  const _ScoredInstalledApp(this.app, this.score, this.index);

  final _InstalledApp app;
  final int score;
  final int index;
}

String _normalizeAppSearchText(String value) {
  return value
      .toLowerCase()
      .replaceAll(RegExp(r'[._\-]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

String _compactAppSearchText(String value) {
  return value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9а-яё]+'), '');
}

int _installedAppSearchScore(_InstalledApp app, String rawQuery) {
  final query = _normalizeAppSearchText(rawQuery);
  if (query.isEmpty) {
    return 0;
  }
  final queryCompact = _compactAppSearchText(rawQuery);
  final label = _normalizeAppSearchText(app.label);
  final packageName = _normalizeAppSearchText(app.packageName);
  final labelCompact = _compactAppSearchText(app.label);
  final packageCompact = _compactAppSearchText(app.packageName);
  final tokens = query
      .split(' ')
      .where((token) => token.isNotEmpty)
      .toList(growable: false);
  final words = <String>[
    ...label.split(' '),
    ...packageName.split(' '),
  ].where((word) => word.isNotEmpty).toList(growable: false);

  if (label == query || packageName == query) return 0;
  if (label.startsWith(query)) return 4;
  if (packageName.startsWith(query)) return 6;
  if (label.contains(query)) return 10;
  if (packageName.contains(query)) return 12;
  if (queryCompact.isNotEmpty &&
      (labelCompact.contains(queryCompact) ||
          packageCompact.contains(queryCompact))) {
    return 14;
  }
  if (tokens.isNotEmpty &&
      tokens.every((token) => words.any((word) => word.startsWith(token)))) {
    return 18;
  }
  if (tokens.isNotEmpty &&
      tokens.every(
        (token) => label.contains(token) || packageName.contains(token),
      )) {
    return 24;
  }
  if (queryCompact.length >= 3 &&
      words.any((word) => _isCloseAppSearchMatch(queryCompact, word))) {
    return 34;
  }
  return -1;
}

@visibleForTesting
int installedAppSearchScoreForTest({
  required String label,
  required String packageName,
  required String query,
}) {
  return _installedAppSearchScore(
    _InstalledApp(
      packageName: packageName,
      label: label,
      system: false,
      launchable: true,
    ),
    query,
  );
}

bool _isCloseAppSearchMatch(String query, String word) {
  final compactWord = _compactAppSearchText(word);
  if (compactWord.length < 3) {
    return false;
  }
  if (compactWord.startsWith(query) || compactWord.contains(query)) {
    return true;
  }
  final lengthDelta = (compactWord.length - query.length).abs();
  if (lengthDelta > 2) {
    return false;
  }
  return _boundedEditDistance(query, compactWord, 2) <= 2;
}

int _boundedEditDistance(String a, String b, int maxDistance) {
  if ((a.length - b.length).abs() > maxDistance) {
    return maxDistance + 1;
  }
  var previous = List<int>.generate(b.length + 1, (index) => index);
  for (var i = 1; i <= a.length; i++) {
    final current = List<int>.filled(b.length + 1, i);
    var rowMin = current[0];
    for (var j = 1; j <= b.length; j++) {
      final substitutionCost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1)
          ? 0
          : 1;
      final value = [
        previous[j] + 1,
        current[j - 1] + 1,
        previous[j - 1] + substitutionCost,
      ].reduce((left, right) => left < right ? left : right);
      current[j] = value;
      if (value < rowMin) {
        rowMin = value;
      }
    }
    if (rowMin > maxDistance) {
      return maxDistance + 1;
    }
    previous = current;
  }
  return previous[b.length];
}

class _RoutingModeCard extends StatelessWidget {
  const _RoutingModeCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOut,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: selected
                ? cs.primary.withValues(alpha: .10)
                : cs.surfaceContainerLow,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected ? cs.primary : cs.outlineVariant,
            ),
          ),
          child: Row(
            children: [
              SettingsLeadingIcon(
                icon: icon,
                color: selected ? cs.primary : cs.onSurfaceVariant,
              ),
              const Gap(12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Gap(4),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const Gap(12),
              Icon(
                selected
                    ? Icons.check_circle_rounded
                    : Icons.radio_button_unchecked_rounded,
                color: selected ? cs.primary : cs.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SelectedAppsPanel extends StatelessWidget {
  const _SelectedAppsPanel({
    required this.apps,
    required this.emptyTitle,
    required this.emptySubtitle,
  });

  final List<_InstalledApp> apps;
  final String emptyTitle;
  final String emptySubtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    if (apps.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: cs.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: cs.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              emptyTitle,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const Gap(4),
            Text(
              emptySubtitle,
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    final visibleApps = apps.take(6).toList(growable: false);
    final remaining = apps.length - visibleApps.length;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        children: [
          for (final app in visibleApps)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: SettingsLeadingIcon(
                icon: app.system ? Icons.memory_rounded : Icons.android_rounded,
                color: cs.primary,
                size: 38,
                iconSize: 18,
              ),
              title: Text(
                app.label.isNotEmpty ? app.label : app.packageName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                app.packageName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          if (remaining > 0)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '+$remaining',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _AppPickerSheet extends StatefulWidget {
  const _AppPickerSheet({required this.apps, required this.initialSelected});

  final List<_InstalledApp> apps;
  final Set<String> initialSelected;

  @override
  State<_AppPickerSheet> createState() => _AppPickerSheetState();
}

class _AppPickerSheetState extends State<_AppPickerSheet> {
  late final TextEditingController _searchController;
  late final Set<String> _selected;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _selected = Set<String>.from(widget.initialSelected);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<_InstalledApp> _visibleApps() {
    if (_query.isEmpty) {
      return widget.apps;
    }
    final scoredApps = widget.apps
        .asMap()
        .entries
        .map((entry) {
          return _ScoredInstalledApp(
            entry.value,
            _installedAppSearchScore(entry.value, _query),
            entry.key,
          );
        })
        .where((entry) => entry.score >= 0)
        .toList(growable: false);
    scoredApps.sort((a, b) {
      final scoreCompare = a.score.compareTo(b.score);
      if (scoreCompare != 0) {
        return scoreCompare;
      }
      return a.index.compareTo(b.index);
    });
    return scoredApps.map((entry) => entry.app).toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final visibleApps = _visibleApps();

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        bottom: 24 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.splitRoutingPickAppsTitle,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(_selected),
                child: Text(l10n.continueAction),
              ),
            ],
          ),
          const Gap(12),
          TextField(
            controller: _searchController,
            onChanged: (value) {
              setState(() {
                _query = value.trim();
              });
            },
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search_rounded),
              hintText: l10n.splitRoutingSearchHint,
            ),
          ),
          const Gap(12),
          Expanded(
            child: ListView.builder(
              itemCount: visibleApps.length,
              itemBuilder: (context, index) {
                final app = visibleApps[index];
                final selected = _selected.contains(app.packageName);
                return CheckboxListTile(
                  value: selected,
                  contentPadding: EdgeInsets.zero,
                  secondary: SettingsLeadingIcon(
                    icon: app.system
                        ? Icons.memory_rounded
                        : Icons.android_rounded,
                    color: Theme.of(context).colorScheme.primary,
                    size: 38,
                    iconSize: 18,
                  ),
                  title: Text(
                    app.label.isNotEmpty ? app.label : app.packageName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    app.packageName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onChanged: (value) {
                    setState(() {
                      if (value == true) {
                        _selected.add(app.packageName);
                      } else {
                        _selected.remove(app.packageName);
                      }
                    });
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _AdBlockStatusPanel extends StatelessWidget {
  const _AdBlockStatusPanel({
    required this.status,
    required this.busy,
    required this.l10n,
  });

  final AdBlockRuleSetStatus status;
  final bool busy;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final updatedAt = status.downloadedAt;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: cs.primary.withValues(alpha: .10),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              status.providerName,
              style: theme.textTheme.labelMedium?.copyWith(
                color: cs.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const Gap(10),
          Text(
            busy
                ? l10n.adBlockDownloadingStatus
                : status.available
                ? l10n.adBlockReadyStatus(status.blockedDomainCount)
                : l10n.adBlockMissingStatus,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const Gap(4),
          Text(
            status.available
                ? l10n.adBlockMeta(
                    updatedAt == null ? '—' : _formatDateTime(updatedAt),
                    status.allowedDomainCount,
                  )
                : l10n.adBlockMissingHint,
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
              height: 1.3,
            ),
          ),
          if (busy) ...[
            const Gap(12),
            const LinearProgressIndicator(minHeight: 4),
          ],
        ],
      ),
    );
  }

  static String _formatDateTime(DateTime value) {
    final local = value.toLocal();
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$day.$month.${local.year} $hour:$minute';
  }
}

class _RussiaRouteDataStatusPanel extends StatelessWidget {
  const _RussiaRouteDataStatusPanel({
    required this.status,
    required this.busy,
    required this.l10n,
  });

  final RussiaRouteDataStatus status;
  final bool busy;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final installedAt = status.installedAt;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: cs.primary.withValues(alpha: .10),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              l10n.russiaRoutesRunetFreedomBadge,
              style: theme.textTheme.labelMedium?.copyWith(
                color: cs.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const Gap(8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: cs.secondary.withValues(alpha: .10),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              l10n.russiaRoutesDomainListBadge,
              style: theme.textTheme.labelMedium?.copyWith(
                color: cs.secondary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const Gap(10),
          Text(
            busy
                ? l10n.russiaRoutesPreparingStatus
                : status.available
                ? l10n.russiaRoutesReadyStatus(status.versionTag)
                : l10n.russiaRoutesMissingStatus,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const Gap(4),
          Text(
            status.available
                ? l10n.russiaRoutesMeta(
                    installedAt == null
                        ? '—'
                        : _AdBlockStatusPanel._formatDateTime(installedAt),
                    status.domainListCommunityUpdatedAt == null
                        ? '—'
                        : _AdBlockStatusPanel._formatDateTime(
                            status.domainListCommunityUpdatedAt!,
                          ),
                    status.domainListCommunityCategoryCount,
                    status.domainListCommunityDomainCount,
                  )
                : l10n.russiaRoutesMissingHint,
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
              height: 1.3,
            ),
          ),
          if (busy) ...[
            const Gap(12),
            const LinearProgressIndicator(minHeight: 4),
          ],
        ],
      ),
    );
  }
}

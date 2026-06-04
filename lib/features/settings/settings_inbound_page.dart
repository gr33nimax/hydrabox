import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gap/gap.dart';
import 'package:meow_client/data/local/app_settings_store.dart';
import 'package:meow_client/features/settings/settings_ui.dart';
import 'package:meow_client/l10n/generated/app_localizations.dart';
import 'package:meow_client/widgets/progressive_blur_scaffold.dart';

class SettingsInboundPage extends StatefulWidget {
  const SettingsInboundPage({
    super.key,
    required this.currentVpnInboundEnabled,
    required this.currentVpnMtu,
    required this.currentVpnStrictRoute,
    required this.currentVpnTunImplementation,
    required this.currentProxyInboundEnabled,
    required this.currentProxyAllowLan,
    required this.currentProxyMixedListen,
    required this.currentProxyMixedPort,
    required this.onVpnInboundEnabledChanged,
    required this.onVpnMtuChanged,
    required this.onVpnStrictRouteChanged,
    required this.onVpnTunImplementationChanged,
    required this.onProxyInboundEnabledChanged,
    required this.onProxyAllowLanChanged,
    required this.onProxyMixedPortChanged,
  });

  final bool currentVpnInboundEnabled;
  final int currentVpnMtu;
  final bool currentVpnStrictRoute;
  final TunImplementationPreference currentVpnTunImplementation;
  final bool currentProxyInboundEnabled;
  final bool currentProxyAllowLan;
  final String currentProxyMixedListen;
  final int currentProxyMixedPort;
  final ValueChanged<bool> onVpnInboundEnabledChanged;
  final ValueChanged<int> onVpnMtuChanged;
  final ValueChanged<bool> onVpnStrictRouteChanged;
  final ValueChanged<TunImplementationPreference> onVpnTunImplementationChanged;
  final ValueChanged<bool> onProxyInboundEnabledChanged;
  final ValueChanged<bool> onProxyAllowLanChanged;
  final ValueChanged<int> onProxyMixedPortChanged;

  @override
  State<SettingsInboundPage> createState() => _SettingsInboundPageState();
}

class _SettingsInboundPageState extends State<SettingsInboundPage> {
  static const _mtuOptions = <int>[1280, 1400, 1450, 1500, 3400, 9000];
  late final TextEditingController _portController;

  @override
  void initState() {
    super.initState();
    _portController = TextEditingController(
      text: widget.currentProxyMixedPort.toString(),
    );
  }

  @override
  void dispose() {
    _portController.dispose();
    super.dispose();
  }

  String _tunImplementationLabel(
    AppLocalizations l10n,
    TunImplementationPreference value,
  ) {
    return switch (value) {
      TunImplementationPreference.mixed => l10n.tunImplementationMixed,
      TunImplementationPreference.system => l10n.tunImplementationSystem,
      TunImplementationPreference.gvisor => l10n.tunImplementationGvisor,
    };
  }

  String _tunImplementationDescription(
    AppLocalizations l10n,
    TunImplementationPreference value,
  ) {
    return switch (value) {
      TunImplementationPreference.mixed => l10n.tunImplementationMixedSubtitle,
      TunImplementationPreference.system =>
        l10n.tunImplementationSystemSubtitle,
      TunImplementationPreference.gvisor =>
        l10n.tunImplementationGvisorSubtitle,
    };
  }

  Future<void> _showMtuPicker(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final result = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => _RadioSheet<int>(
        title: l10n.mtuTitle,
        current: widget.currentVpnMtu,
        items: _mtuOptions
            .map((value) => _RadioItem(value: value, label: value.toString()))
            .toList(growable: false),
      ),
    );
    if (result != null) {
      widget.onVpnMtuChanged(result);
    }
  }

  Future<void> _showTunImplementationPicker(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final result = await showModalBottomSheet<TunImplementationPreference>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => _RadioSheet<TunImplementationPreference>(
        title: l10n.tunImplementationTitle,
        current: widget.currentVpnTunImplementation,
        items: [
          _RadioItem(
            value: TunImplementationPreference.mixed,
            label: l10n.tunImplementationMixed,
            subtitle: l10n.tunImplementationMixedSubtitle,
          ),
          _RadioItem(
            value: TunImplementationPreference.system,
            label: l10n.tunImplementationSystem,
            subtitle: l10n.tunImplementationSystemSubtitle,
          ),
          _RadioItem(
            value: TunImplementationPreference.gvisor,
            label: l10n.tunImplementationGvisor,
            subtitle: l10n.tunImplementationGvisorSubtitle,
          ),
        ],
      ),
    );
    if (result != null) {
      widget.onVpnTunImplementationChanged(result);
    }
  }

  void _commitPort() {
    final value = int.tryParse(_portController.text.trim());
    if (value == null || value <= 0 || value > 65535) {
      _portController.text = widget.currentProxyMixedPort.toString();
      return;
    }
    if (value == widget.currentProxyMixedPort) {
      return;
    }
    widget.onProxyMixedPortChanged(value);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return ProgressiveBlurScaffold(
      appBar: AppBar(title: Text(l10n.inboundTitle)),
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
            _SectionLabel(label: l10n.vpnInTitle),
            const Gap(settingsSectionLabelGap),
            _SectionDescription(label: l10n.vpnInDescription),
            const Gap(settingsSectionLabelGap),
            Card(
              margin: EdgeInsets.zero,
              child: Column(
                children: [
                  SwitchListTile(
                    secondary: SettingsLeadingIcon(
                      icon: Icons.vpn_lock_rounded,
                      color: cs.primary,
                    ),
                    title: Text(l10n.enableInboundTitle),
                    subtitle: Text(l10n.vpnInboundEnabledSubtitle),
                    value: widget.currentVpnInboundEnabled,
                    onChanged: widget.onVpnInboundEnabledChanged,
                  ),
                  ListTile(
                    enabled: widget.currentVpnInboundEnabled,
                    leading: SettingsLeadingIcon(
                      icon: Icons.swap_vert_rounded,
                      color: cs.primary,
                    ),
                    title: Text(l10n.mtuTitle),
                    subtitle: Text(
                      '${widget.currentVpnMtu} • ${l10n.mtuSubtitle}',
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: widget.currentVpnInboundEnabled
                        ? () => _showMtuPicker(context)
                        : null,
                  ),
                  SwitchListTile(
                    secondary: SettingsLeadingIcon(
                      icon: Icons.route_rounded,
                      color: cs.primary,
                    ),
                    title: Text(l10n.strictRouteTitle),
                    subtitle: Text(l10n.strictRouteSubtitle),
                    value: widget.currentVpnStrictRoute,
                    onChanged: widget.currentVpnInboundEnabled
                        ? widget.onVpnStrictRouteChanged
                        : null,
                  ),
                  ListTile(
                    enabled: widget.currentVpnInboundEnabled,
                    leading: SettingsLeadingIcon(
                      icon: Icons.tune_rounded,
                      color: cs.primary,
                    ),
                    title: Text(l10n.tunImplementationTitle),
                    subtitle: Text(
                      '${_tunImplementationLabel(l10n, widget.currentVpnTunImplementation)} • ${_tunImplementationDescription(l10n, widget.currentVpnTunImplementation)}',
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: widget.currentVpnInboundEnabled
                        ? () => _showTunImplementationPicker(context)
                        : null,
                  ),
                ],
              ),
            ),
            const Gap(settingsSectionGap),
            _SectionLabel(label: l10n.proxyInTitle),
            const Gap(settingsSectionLabelGap),
            _SectionDescription(label: l10n.proxyInDescription),
            const Gap(settingsSectionLabelGap),
            Card(
              margin: EdgeInsets.zero,
              child: Column(
                children: [
                  SwitchListTile(
                    secondary: SettingsLeadingIcon(
                      icon: Icons.lan_rounded,
                      color: cs.primary,
                    ),
                    title: Text(l10n.enableInboundTitle),
                    subtitle: Text(l10n.proxyInboundEnabledSubtitle),
                    value: widget.currentProxyInboundEnabled,
                    onChanged: widget.onProxyInboundEnabledChanged,
                  ),
                  SwitchListTile(
                    secondary: SettingsLeadingIcon(
                      icon: Icons.wifi_tethering_rounded,
                      color: cs.primary,
                    ),
                    title: Text(l10n.allowLanConnectionsTitle),
                    subtitle: Text(l10n.allowLanConnectionsSubtitle),
                    value: widget.currentProxyAllowLan,
                    onChanged: widget.currentProxyInboundEnabled
                        ? widget.onProxyAllowLanChanged
                        : null,
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                    child: TextField(
                      controller: _portController,
                      enabled: widget.currentProxyInboundEnabled,
                      onTapOutside: (_) {
                        FocusScope.of(context).unfocus();
                        _commitPort();
                      },
                      onSubmitted: (_) => _commitPort(),
                      onEditingComplete: () {
                        FocusScope.of(context).unfocus();
                        _commitPort();
                      },
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.deny(RegExp(r'[\r\n]')),
                        FilteringTextInputFormatter.digitsOnly,
                      ],
                      decoration: InputDecoration(
                        labelText: l10n.portTitle,
                        hintText: '1080',
                        helperText: l10n.proxyPortSubtitle,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Text(
        label,
        style: theme.textTheme.titleSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _SectionDescription extends StatelessWidget {
  const _SectionDescription({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Text(
        label,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _RadioItem<T> {
  const _RadioItem({required this.value, required this.label, this.subtitle});

  final T value;
  final String label;
  final String? subtitle;
}

class _RadioSheet<T> extends StatelessWidget {
  const _RadioSheet({
    required this.title,
    required this.current,
    required this.items,
  });

  final String title;
  final T current;
  final List<_RadioItem<T>> items;

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: mediaQuery.size.height * 0.75),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              const Gap(12),
              Flexible(
                child: RadioGroup<T>(
                  groupValue: current,
                  onChanged: (value) {
                    if (value != null) {
                      Navigator.of(context).pop(value);
                    }
                  },
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final item in items)
                        RadioListTile<T>(
                          value: item.value,
                          title: Text(item.label),
                          subtitle: item.subtitle == null
                              ? null
                              : Text(item.subtitle!),
                          contentPadding: EdgeInsets.zero,
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

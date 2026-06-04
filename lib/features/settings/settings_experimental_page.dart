import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:meow_client/features/settings/settings_ui.dart';
import 'package:meow_client/l10n/generated/app_localizations.dart';
import 'package:meow_client/widgets/progressive_blur_scaffold.dart';

class SettingsExperimentalPage extends StatelessWidget {
  const SettingsExperimentalPage({
    super.key,
    required this.currentTcpFastOpen,
    required this.currentTcpMultiPath,
    required this.currentInterruptExistingConnections,
    required this.currentUrlTestStrictTolerance,
    required this.onTcpFastOpenChanged,
    required this.onTcpMultiPathChanged,
    required this.onInterruptExistingConnectionsChanged,
    required this.onUrlTestStrictToleranceChanged,
  });

  final bool currentTcpFastOpen;
  final bool currentTcpMultiPath;
  final bool currentInterruptExistingConnections;
  final bool currentUrlTestStrictTolerance;
  final ValueChanged<bool> onTcpFastOpenChanged;
  final ValueChanged<bool> onTcpMultiPathChanged;
  final ValueChanged<bool> onInterruptExistingConnectionsChanged;
  final ValueChanged<bool> onUrlTestStrictToleranceChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return ProgressiveBlurScaffold(
      appBar: AppBar(title: Text(l10n.experimentalTitle)),
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
                children: [
                  SwitchListTile(
                    secondary: SettingsLeadingIcon(
                      icon: Icons.bolt_rounded,
                      color: cs.primary,
                    ),
                    title: Text(l10n.experimentalTcpFastOpenTitle),
                    subtitle: Text(l10n.experimentalTcpFastOpenSubtitle),
                    value: currentTcpFastOpen,
                    onChanged: onTcpFastOpenChanged,
                  ),
                  SwitchListTile(
                    secondary: SettingsLeadingIcon(
                      icon: Icons.merge_type_rounded,
                      color: cs.primary,
                    ),
                    title: Text(l10n.experimentalTcpMultiPathTitle),
                    subtitle: Text(l10n.experimentalTcpMultiPathSubtitle),
                    value: currentTcpMultiPath,
                    onChanged: onTcpMultiPathChanged,
                  ),
                ],
              ),
            ),
            const Gap(settingsIslandGap),
            Card(
              margin: EdgeInsets.zero,
              child: Column(
                children: [
                  SwitchListTile(
                    secondary: SettingsLeadingIcon(
                      icon: Icons.sync_problem_rounded,
                      color: cs.primary,
                    ),
                    title: Text(l10n.experimentalInterruptConnectionsTitle),
                    subtitle: Text(
                      l10n.experimentalInterruptConnectionsSubtitle,
                    ),
                    value: currentInterruptExistingConnections,
                    onChanged: onInterruptExistingConnectionsChanged,
                  ),
                  SwitchListTile(
                    secondary: SettingsLeadingIcon(
                      icon: Icons.speed_rounded,
                      color: cs.primary,
                    ),
                    title: Text(l10n.experimentalUrlTestStrictToleranceTitle),
                    subtitle: Text(
                      l10n.experimentalUrlTestStrictToleranceSubtitle,
                    ),
                    value: currentUrlTestStrictTolerance,
                    onChanged: onUrlTestStrictToleranceChanged,
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

import 'package:flutter/material.dart';
import 'package:meow_client/l10n/generated/app_localizations.dart';
import 'package:meow_client/features/settings/settings_ui.dart';
import 'package:meow_client/widgets/progressive_blur_scaffold.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({
    super.key,
    required this.currentLocaleLabel,
    required this.currentThemeLabel,
    required this.onOpenGeneral,
    required this.onOpenDns,
    required this.onOpenSubscriptions,
    required this.onOpenInbound,
    required this.onOpenRouting,
    required this.onOpenBackup,
    required this.onOpenExperimental,
    required this.onOpenLogs,
    required this.onOpenAbout,
  });

  final String currentLocaleLabel;
  final String currentThemeLabel;
  final VoidCallback onOpenGeneral;
  final VoidCallback onOpenDns;
  final VoidCallback onOpenSubscriptions;
  final VoidCallback onOpenInbound;
  final VoidCallback onOpenRouting;
  final VoidCallback onOpenBackup;
  final VoidCallback onOpenExperimental;
  final VoidCallback onOpenLogs;
  final VoidCallback onOpenAbout;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return ProgressiveBlurScaffold(
      appBar: AppBar(
        title: Text(l10n.settingsTitle),
        actions: [
          PopupMenuButton<String>(
            tooltip: l10n.backupTitle,
            onSelected: (value) {
              if (value == 'backup') {
                onOpenBackup();
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'backup',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.backup_rounded),
                  title: Text(l10n.backupTitle),
                  subtitle: Text(l10n.backupSubtitle),
                ),
              ),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          settingsScreenPadding.left,
          progressiveHeaderTopPadding(context, settingsScreenPadding.top),
          settingsScreenPadding.right,
          appBottomSafePadding(context, settingsScreenPadding.bottom),
        ),
        children: [
          _SettingsEntryTile(
            icon: Icons.tune_rounded,
            title: l10n.generalSectionTitle,
            subtitle:
                '${l10n.languageSettingTitle}: $currentLocaleLabel · ${l10n.themeSettingTitle}: $currentThemeLabel',
            onTap: onOpenGeneral,
          ),
          const SizedBox(height: settingsIslandGap),
          _SettingsEntryTile(
            icon: Icons.settings_ethernet_rounded,
            title: l10n.inboundTitle,
            subtitle: '${l10n.vpnInTitle} · ${l10n.proxyInTitle}',
            onTap: onOpenInbound,
          ),
          const SizedBox(height: settingsIslandGap),
          _SettingsEntryTile(
            icon: Icons.alt_route_rounded,
            title: l10n.routingTitle,
            subtitle: l10n.routingSubtitle,
            onTap: onOpenRouting,
          ),
          const SizedBox(height: settingsIslandGap),
          _SettingsEntryTile(
            icon: Icons.dns_rounded,
            title: l10n.dnsTitle,
            subtitle: '${l10n.dnsDirectTitle} · ${l10n.dnsProxyTitle}',
            onTap: onOpenDns,
          ),
          const SizedBox(height: settingsIslandGap),
          _SettingsEntryTile(
            icon: Icons.science_rounded,
            title: l10n.experimentalTitle,
            subtitle: l10n.experimentalSubtitle,
            onTap: onOpenExperimental,
          ),
          const SizedBox(height: settingsIslandGap),
          _SettingsEntryTile(
            icon: Icons.speed_rounded,
            title: l10n.settingsProfilesChecksTitle,
            subtitle: l10n.settingsProfilesChecksSubtitle,
            onTap: onOpenSubscriptions,
          ),
          const SizedBox(height: settingsIslandGap),
          _SettingsEntryTile(
            icon: Icons.article_rounded,
            title: l10n.logsTitle,
            subtitle: l10n.logsSubtitle,
            onTap: onOpenLogs,
          ),
          const SizedBox(height: settingsIslandGap),
          _SettingsEntryTile(
            icon: Icons.info_outline_rounded,
            title: l10n.aboutSectionTitle,
            subtitle: l10n.aboutSectionSubtitle,
            onTap: onOpenAbout,
          ),
        ],
      ),
    );
  }
}

class _SettingsEntryTile extends StatelessWidget {
  const _SettingsEntryTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        leading: SettingsLeadingIcon(
          icon: icon,
          color: theme.colorScheme.primary,
        ),
        title: Text(
          title,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(subtitle),
        ),
        trailing: const Icon(Icons.chevron_right_rounded),
      ),
    );
  }
}

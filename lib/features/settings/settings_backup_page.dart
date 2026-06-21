import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:meow_client/data/backup/etonify_backup_service.dart';
import 'package:meow_client/data/local/app_settings_store.dart';
import 'package:meow_client/features/settings/settings_ui.dart';
import 'package:meow_client/l10n/generated/app_localizations.dart';
import 'package:meow_client/models/subscription.dart';
import 'package:meow_client/widgets/progressive_blur_scaffold.dart';

class SettingsBackupPage extends StatefulWidget {
  const SettingsBackupPage({
    super.key,
    required this.store,
    required this.settingsState,
    required this.clientVersion,
    required this.loadSubscriptions,
    required this.onImportSettings,
    required this.onImportSubscriptions,
  });

  final AppSettingsStore store;
  final AppSettingsState settingsState;
  final String clientVersion;
  final List<Subscription> Function() loadSubscriptions;
  final Future<void> Function(AppSettingsState state) onImportSettings;
  final Future<void> Function(List<Subscription> subscriptions)
  onImportSubscriptions;

  @override
  State<SettingsBackupPage> createState() => _SettingsBackupPageState();
}

class _SettingsBackupPageState extends State<SettingsBackupPage> {
  static const _service = EtonifyBackupService();
  _BackupAction? _busyAction;

  Future<void> _run(
    _BackupAction action,
    Future<void> Function() operation,
  ) async {
    if (_busyAction != null) return;
    setState(() => _busyAction = action);
    try {
      await operation();
    } on EtonifyBackupException catch (error) {
      _showSnack(error.message);
    } catch (error) {
      _showSnack(error.toString());
    } finally {
      if (mounted) {
        setState(() => _busyAction = null);
      }
    }
  }

  Future<void> _exportSettings() async {
    final l10n = AppLocalizations.of(context);
    final content = _service.buildSettingsExport(
      store: widget.store,
      state: widget.settingsState,
      clientVersion: widget.clientVersion,
    );
    final path = await FilePicker.saveFile(
      dialogTitle: l10n.backupExportSettings,
      fileName: 'etonify.etonify-settings.json',
      type: FileType.custom,
      allowedExtensions: const ['json'],
      bytes: Uint8List.fromList(utf8.encode(content)),
    );
    if (path == null) return;
    _showSnack(l10n.backupSaved);
  }

  Future<void> _exportEncryptedProfile() async {
    final l10n = AppLocalizations.of(context);
    final password = await _askPassword(exportMode: true);
    if (password == null) return;
    final content = _service.buildProfileExport(
      subscriptions: widget.loadSubscriptions(),
      clientVersion: widget.clientVersion,
      encryption: EtonifyProfileEncryption.encrypted,
      password: password,
    );
    final path = await FilePicker.saveFile(
      dialogTitle: l10n.backupExportProfileEncrypted,
      fileName: 'etonify-profile.etonify-profile',
      type: FileType.custom,
      allowedExtensions: const ['etonify-profile'],
      bytes: Uint8List.fromList(utf8.encode(content)),
    );
    if (path == null) return;
    _showSnack(l10n.backupSaved);
  }

  Future<void> _exportPlainProfile() async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppLocalizations.of(context).backupPlainWarningTitle),
        content: Text(AppLocalizations.of(context).backupPlainWarningMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(AppLocalizations.of(context).continueAction),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final content = _service.buildProfileExport(
      subscriptions: widget.loadSubscriptions(),
      clientVersion: widget.clientVersion,
      encryption: EtonifyProfileEncryption.plain,
    );
    final path = await FilePicker.saveFile(
      dialogTitle: l10n.backupExportProfilePlain,
      fileName: 'etonify-profile-plain.etonify-profile',
      type: FileType.custom,
      allowedExtensions: const ['etonify-profile'],
      bytes: Uint8List.fromList(utf8.encode(content)),
    );
    if (path == null) return;
    _showSnack(l10n.backupSaved);
  }

  Future<void> _importFile() async {
    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['json', 'etonify-profile'],
      withData: true,
    );
    if (picked == null || picked.files.isEmpty) return;
    final file = picked.files.first;
    final path = file.path;
    final bytes =
        file.bytes ?? (path == null ? null : await File(path).readAsBytes());
    if (bytes == null) {
      throw const EtonifyBackupException('Could not read selected file.');
    }
    final decodedHead = utf8.decode(
      bytes.take(256).toList(growable: false),
      allowMalformed: true,
    );
    if (decodedHead.contains(EtonifyBackupService.settingsMagic)) {
      await _importSettings(bytes);
      return;
    }
    if (decodedHead.contains(EtonifyBackupService.profileMagic)) {
      await _importProfile(bytes);
      return;
    }
    throw const EtonifyBackupException('This is not an Etonify backup file.');
  }

  Future<void> _importSettings(List<int> bytes) async {
    final l10n = AppLocalizations.of(context);
    final parsed = _service.parseSettingsExport(
      bytes: bytes,
      currentClientVersion: widget.clientVersion,
    );
    if (!await _confirmCompatibility(parsed.warning)) return;
    final state = widget.store.mergeSafeImportMap(
      widget.settingsState,
      parsed.settings,
    );
    await widget.onImportSettings(state);
    if (!mounted) return;
    _showSnack(l10n.backupImported);
  }

  Future<void> _importProfile(List<int> bytes) async {
    final l10n = AppLocalizations.of(context);
    EtonifyProfileImportResult parsed;
    try {
      parsed = _service.parseProfileExport(
        bytes: bytes,
        currentClientVersion: widget.clientVersion,
      );
    } on EtonifyBackupException catch (error) {
      if (!error.message.toLowerCase().contains('password')) {
        rethrow;
      }
      final password = await _askPassword(exportMode: false);
      if (password == null) return;
      parsed = _service.parseProfileExport(
        bytes: bytes,
        currentClientVersion: widget.clientVersion,
        password: password,
      );
    }
    if (parsed.encryption == EtonifyProfileEncryption.plain) {
      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(AppLocalizations.of(context).backupPlainImportTitle),
          content: Text(AppLocalizations.of(context).backupPlainImportMessage),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(AppLocalizations.of(context).continueAction),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    if (!await _confirmCompatibility(parsed.warning)) return;
    await widget.onImportSubscriptions(parsed.subscriptions);
    if (!mounted) return;
    _showSnack(l10n.backupImported);
  }

  Future<bool> _confirmCompatibility(EtonifyImportWarning warning) async {
    if (warning.compatibility == ExportCompatibilityStatus.compatible) {
      return true;
    }
    if (warning.compatibility == ExportCompatibilityStatus.unsupported) {
      _showSnack(AppLocalizations.of(context).backupUnsupportedVersion);
      return false;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppLocalizations.of(context).backupNewerVersionTitle),
        content: Text(
          AppLocalizations.of(
            context,
          ).backupNewerVersionMessage(warning.createdByVersion),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(AppLocalizations.of(context).continueAction),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  Future<String?> _askPassword({required bool exportMode}) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          exportMode
              ? AppLocalizations.of(context).backupPasswordCreateTitle
              : AppLocalizations.of(context).backupPasswordEnterTitle,
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          obscureText: true,
          decoration: InputDecoration(
            hintText: AppLocalizations.of(context).backupPasswordHint,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: Text(AppLocalizations.of(context).continueAction),
          ),
        ],
      ),
    );
    controller.dispose();
    final trimmed = result?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ProgressiveBlurScaffold(
      appBar: AppBar(title: Text(l10n.backupTitle)),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          settingsScreenPadding.left,
          progressiveHeaderTopPadding(context, settingsScreenPadding.top),
          settingsScreenPadding.right,
          appBottomSafePadding(context, settingsScreenPadding.bottom),
        ),
        children: [
          _ActionCard(
            icon: Icons.settings_backup_restore_rounded,
            title: l10n.backupExportSettings,
            busy: _busyAction == _BackupAction.exportSettings,
            disabled: _busyAction != null,
            onTap: () => _run(_BackupAction.exportSettings, _exportSettings),
          ),
          const SizedBox(height: settingsIslandGap),
          _ActionCard(
            icon: Icons.lock_rounded,
            title: l10n.backupExportProfileEncrypted,
            busy: _busyAction == _BackupAction.exportEncryptedProfile,
            disabled: _busyAction != null,
            onTap: () => _run(
              _BackupAction.exportEncryptedProfile,
              _exportEncryptedProfile,
            ),
          ),
          const SizedBox(height: settingsIslandGap),
          _ActionCard(
            icon: Icons.no_encryption_rounded,
            title: l10n.backupExportProfilePlain,
            busy: _busyAction == _BackupAction.exportPlainProfile,
            disabled: _busyAction != null,
            onTap: () =>
                _run(_BackupAction.exportPlainProfile, _exportPlainProfile),
          ),
          const SizedBox(height: settingsIslandGap),
          _ActionCard(
            icon: Icons.file_open_rounded,
            title: l10n.backupImportFile,
            busy: _busyAction == _BackupAction.importFile,
            disabled: _busyAction != null,
            onTap: () => _run(_BackupAction.importFile, _importFile),
          ),
        ],
      ),
    );
  }
}

enum _BackupAction {
  exportSettings,
  exportEncryptedProfile,
  exportPlainProfile,
  importFile,
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.icon,
    required this.title,
    required this.busy,
    required this.disabled,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final bool busy;
  final bool disabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        enabled: !disabled,
        onTap: disabled ? null : onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: SettingsLeadingIcon(
          icon: icon,
          color: theme.colorScheme.primary,
        ),
        title: Text(
          title,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        trailing: busy
            ? const SizedBox.square(
                dimension: 22,
                child: CircularProgressIndicator(strokeWidth: 3),
              )
            : const Icon(Icons.chevron_right_rounded),
      ),
    );
  }
}

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:meow_client/core/widgets/app_notice.dart';
import 'package:meow_client/data/backup/etonify_backup_service.dart';
import 'package:meow_client/data/local/app_settings_store.dart';
import 'package:meow_client/l10n/generated/app_localizations.dart';
import 'package:meow_client/models/subscription.dart';

enum SettingsBackupAction {
  importFile,
  exportSettings,
  exportEncryptedProfile,
  exportPlainProfile,
}

/// Runs settings and profile backup operations without opening another page.
class SettingsBackupActions {
  const SettingsBackupActions({
    required this.store,
    required this.settingsState,
    required this.clientVersion,
    required this.loadSubscriptions,
    required this.onImportSettings,
    required this.onImportSubscriptions,
  });

  static const _service = EtonifyBackupService();

  final AppSettingsStore store;
  final AppSettingsState settingsState;
  final String clientVersion;
  final List<Subscription> Function() loadSubscriptions;
  final Future<void> Function(AppSettingsState state) onImportSettings;
  final Future<void> Function(List<Subscription> subscriptions)
  onImportSubscriptions;

  Future<void> run(BuildContext context, SettingsBackupAction action) async {
    try {
      switch (action) {
        case SettingsBackupAction.importFile:
          await _importFile(context);
          return;
        case SettingsBackupAction.exportSettings:
          await _exportSettings(context);
          return;
        case SettingsBackupAction.exportEncryptedProfile:
          await _exportEncryptedProfile(context);
          return;
        case SettingsBackupAction.exportPlainProfile:
          await _exportPlainProfile(context);
          return;
      }
    } on EtonifyBackupException catch (error) {
      if (!context.mounted) return;
      _showNotice(context, error.message);
    } catch (error) {
      if (!context.mounted) return;
      _showNotice(context, error.toString());
    }
  }

  Future<void> _exportSettings(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final content = _service.buildSettingsExport(
      store: store,
      state: settingsState,
      clientVersion: clientVersion,
    );
    final path = await FilePicker.saveFile(
      dialogTitle: l10n.backupExportSettings,
      fileName: 'etonify.etonify-settings.json',
      type: FileType.custom,
      allowedExtensions: const ['json'],
      bytes: Uint8List.fromList(utf8.encode(content)),
    );
    if (path == null || !context.mounted) return;
    _showNotice(context, l10n.backupSaved, tone: AppNoticeTone.success);
  }

  Future<void> _exportEncryptedProfile(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final password = await _askPassword(context, exportMode: true);
    if (password == null || !context.mounted) return;
    final content = _service.buildProfileExport(
      subscriptions: loadSubscriptions(),
      clientVersion: clientVersion,
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
    if (path == null || !context.mounted) return;
    _showNotice(context, l10n.backupSaved, tone: AppNoticeTone.success);
  }

  Future<void> _exportPlainProfile(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(AppLocalizations.of(dialogContext).backupPlainWarningTitle),
        content: Text(
          AppLocalizations.of(dialogContext).backupPlainWarningMessage,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(
              MaterialLocalizations.of(dialogContext).cancelButtonLabel,
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(AppLocalizations.of(dialogContext).continueAction),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final l10n = AppLocalizations.of(context);
    final content = _service.buildProfileExport(
      subscriptions: loadSubscriptions(),
      clientVersion: clientVersion,
      encryption: EtonifyProfileEncryption.plain,
    );
    final path = await FilePicker.saveFile(
      dialogTitle: l10n.backupExportProfilePlain,
      fileName: 'etonify-profile-plain.etonify-profile',
      type: FileType.custom,
      allowedExtensions: const ['etonify-profile'],
      bytes: Uint8List.fromList(utf8.encode(content)),
    );
    if (path == null || !context.mounted) return;
    _showNotice(context, l10n.backupSaved, tone: AppNoticeTone.success);
  }

  Future<void> _importFile(BuildContext context) async {
    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['json', 'etonify-profile'],
      withData: true,
    );
    if (picked == null || picked.files.isEmpty || !context.mounted) return;
    final file = picked.files.first;
    final path = file.path;
    final bytes =
        file.bytes ?? (path == null ? null : await File(path).readAsBytes());
    if (!context.mounted) return;
    if (bytes == null) {
      throw const EtonifyBackupException('Could not read selected file.');
    }
    final decodedHead = utf8.decode(
      bytes.take(256).toList(growable: false),
      allowMalformed: true,
    );
    if (decodedHead.contains(EtonifyBackupService.settingsMagic)) {
      await _importSettings(context, bytes);
      return;
    }
    if (decodedHead.contains(EtonifyBackupService.profileMagic)) {
      await _importProfile(context, bytes);
      return;
    }
    throw const EtonifyBackupException('This is not an Etonify backup file.');
  }

  Future<void> _importSettings(BuildContext context, List<int> bytes) async {
    final parsed = _service.parseSettingsExport(
      bytes: bytes,
      currentClientVersion: clientVersion,
    );
    if (!await _confirmCompatibility(context, parsed.warning) ||
        !context.mounted) {
      return;
    }
    final state = store.mergeSafeImportMap(settingsState, parsed.settings);
    await onImportSettings(state);
    if (!context.mounted) return;
    _showNotice(
      context,
      AppLocalizations.of(context).backupImported,
      tone: AppNoticeTone.success,
    );
  }

  Future<void> _importProfile(BuildContext context, List<int> bytes) async {
    EtonifyProfileImportResult parsed;
    try {
      parsed = _service.parseProfileExport(
        bytes: bytes,
        currentClientVersion: clientVersion,
      );
    } on EtonifyBackupException catch (error) {
      if (!error.message.toLowerCase().contains('password')) {
        rethrow;
      }
      final password = await _askPassword(context, exportMode: false);
      if (password == null) return;
      parsed = _service.parseProfileExport(
        bytes: bytes,
        currentClientVersion: clientVersion,
        password: password,
      );
    }
    if (!context.mounted) return;
    if (parsed.encryption == EtonifyProfileEncryption.plain) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(
            AppLocalizations.of(dialogContext).backupPlainImportTitle,
          ),
          content: Text(
            AppLocalizations.of(dialogContext).backupPlainImportMessage,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(
                MaterialLocalizations.of(dialogContext).cancelButtonLabel,
              ),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(AppLocalizations.of(dialogContext).continueAction),
            ),
          ],
        ),
      );
      if (confirmed != true || !context.mounted) return;
    }
    if (!await _confirmCompatibility(context, parsed.warning) ||
        !context.mounted) {
      return;
    }
    await onImportSubscriptions(parsed.subscriptions);
    if (!context.mounted) return;
    _showNotice(
      context,
      AppLocalizations.of(context).backupImported,
      tone: AppNoticeTone.success,
    );
  }

  Future<bool> _confirmCompatibility(
    BuildContext context,
    EtonifyImportWarning warning,
  ) async {
    if (warning.compatibility == ExportCompatibilityStatus.compatible) {
      return true;
    }
    if (warning.compatibility == ExportCompatibilityStatus.unsupported) {
      _showNotice(
        context,
        AppLocalizations.of(context).backupUnsupportedVersion,
      );
      return false;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(AppLocalizations.of(dialogContext).backupNewerVersionTitle),
        content: Text(
          AppLocalizations.of(
            dialogContext,
          ).backupNewerVersionMessage(warning.createdByVersion),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(
              MaterialLocalizations.of(dialogContext).cancelButtonLabel,
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(AppLocalizations.of(dialogContext).continueAction),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  Future<String?> _askPassword(
    BuildContext context, {
    required bool exportMode,
  }) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          exportMode
              ? AppLocalizations.of(dialogContext).backupPasswordCreateTitle
              : AppLocalizations.of(dialogContext).backupPasswordEnterTitle,
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          obscureText: true,
          decoration: InputDecoration(
            hintText: AppLocalizations.of(dialogContext).backupPasswordHint,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(
              MaterialLocalizations.of(dialogContext).cancelButtonLabel,
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: Text(AppLocalizations.of(dialogContext).continueAction),
          ),
        ],
      ),
    );
    controller.dispose();
    final trimmed = result?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  void _showNotice(
    BuildContext context,
    String message, {
    AppNoticeTone tone = AppNoticeTone.error,
  }) {
    if (!context.mounted) return;
    AppNotice.show(context, message, tone: tone);
  }
}

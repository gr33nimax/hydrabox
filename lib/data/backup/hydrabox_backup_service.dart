import 'dart:convert';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:hydrabox/data/local/app_settings_store.dart';
import 'package:hydrabox/models/subscription.dart';
import 'package:pointycastle/export.dart';

enum HydraBoxProfileEncryption { encrypted, plain }

enum ExportCompatibilityStatus { compatible, newerClient, unsupported }

class HydraBoxBackupException implements Exception {
  const HydraBoxBackupException(this.message);

  final String message;

  @override
  String toString() => message;
}

class HydraBoxImportWarning {
  const HydraBoxImportWarning({
    required this.compatibility,
    required this.createdByVersion,
    required this.minClientVersion,
  });

  final ExportCompatibilityStatus compatibility;
  final String createdByVersion;
  final String minClientVersion;

  bool get requiresConfirmation =>
      compatibility == ExportCompatibilityStatus.newerClient;
}

class HydraBoxProfileImportResult {
  const HydraBoxProfileImportResult({
    required this.warning,
    required this.subscriptions,
    required this.encryption,
  });

  final HydraBoxImportWarning warning;
  final List<Subscription> subscriptions;
  final HydraBoxProfileEncryption encryption;
}

class HydraBoxSettingsImportResult {
  const HydraBoxSettingsImportResult({
    required this.warning,
    required this.settings,
  });

  final HydraBoxImportWarning warning;
  final Map<String, dynamic> settings;
}

class HydraBoxBackupService {
  const HydraBoxBackupService();

  static const settingsMagic = 'HYDRABOX_SETTINGS';
  static const profileMagic = 'HYDRABOX_PROFILE';
  static const formatVersion = 1;
  static const minClientVersion = AppSettingsStore.exportMinClientVersion;
  // Large multi-profile exports can legitimately exceed 8 MiB. Keep a hard
  // ceiling to avoid decoding arbitrary files into several times their size.
  static const maxImportBytes = 32 * 1024 * 1024;
  static const _kdfIterations = 180000;
  static const _saltBytes = 16;
  static const _nonceBytes = 12;
  static const _keyBytes = 32;
  static const _tagBits = 128;

  String buildSettingsExport({
    required AppSettingsStore store,
    required AppSettingsState state,
    required String clientVersion,
  }) {
    final envelope = <String, dynamic>{
      'magic': settingsMagic,
      'formatVersion': formatVersion,
      'minClientVersion': minClientVersion,
      'createdByVersion': _normalizeVersion(clientVersion),
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'settings': store.stateToSafeExportMap(state),
    };
    return _encodeRestorableExport(envelope);
  }

  HydraBoxSettingsImportResult parseSettingsExport({
    required List<int> bytes,
    required String currentClientVersion,
  }) {
    final envelope = _decodeEnvelope(bytes, expectedMagic: settingsMagic);
    final settings = envelope['settings'];
    if (settings is! Map) {
      throw const HydraBoxBackupException('Settings section is missing.');
    }
    return HydraBoxSettingsImportResult(
      warning: _compatibility(envelope, currentClientVersion),
      settings: Map<String, dynamic>.from(settings),
    );
  }

  String buildProfileExport({
    required List<Subscription> subscriptions,
    required String clientVersion,
    required HydraBoxProfileEncryption encryption,
    String? password,
  }) {
    final profile = <String, dynamic>{
      'subscriptions': subscriptions
          .map((subscription) {
            final exported = subscription.toMap();
            // payload_ref is an internal encrypted-Hive pointer. It is neither
            // portable nor safe to let an untrusted backup choose it.
            exported.remove('payload_ref');
            return exported;
          })
          .toList(growable: false),
    };
    final envelope = <String, dynamic>{
      'magic': profileMagic,
      'formatVersion': formatVersion,
      'minClientVersion': minClientVersion,
      'createdByVersion': _normalizeVersion(clientVersion),
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'encryption': encryption.name,
    };
    if (encryption == HydraBoxProfileEncryption.encrypted) {
      final normalizedPassword = password?.trim() ?? '';
      if (normalizedPassword.length < 8) {
        throw const HydraBoxBackupException(
          'Password must contain at least 8 characters.',
        );
      }
      final salt = _randomBytes(_saltBytes);
      final nonce = _randomBytes(_nonceBytes);
      final key = _deriveKey(normalizedPassword, salt);
      final plaintext = utf8.encode(jsonEncode(profile));
      final ciphertext = _aesGcmEncrypt(
        key: key,
        nonce: nonce,
        plaintext: Uint8List.fromList(plaintext),
      );
      envelope
        ..['kdf'] = {
          'name': 'PBKDF2-HMAC-SHA256',
          'iterations': _kdfIterations,
          'salt': base64Encode(salt),
        }
        ..['cipher'] = {
          'name': 'AES-256-GCM',
          'nonce': base64Encode(nonce),
          'tagBits': _tagBits,
        }
        ..['payload'] = base64Encode(ciphertext);
    } else {
      envelope['profile'] = profile;
    }
    return _encodeRestorableExport(envelope);
  }

  String _encodeRestorableExport(Map<String, dynamic> envelope) {
    final output = const JsonEncoder.withIndent('  ').convert(envelope);
    if (utf8.encode(output).length > maxImportBytes) {
      throw const HydraBoxBackupException(
        'Export is too large to import. Reduce the exported data or split '
        'subscriptions and try again.',
      );
    }
    return output;
  }

  /// Serializes and encrypts large profile exports away from the UI isolate.
  Future<String> buildProfileExportInBackground({
    required List<Subscription> subscriptions,
    required String clientVersion,
    required HydraBoxProfileEncryption encryption,
    String? password,
  }) {
    return Isolate.run(
      () => const HydraBoxBackupService().buildProfileExport(
        subscriptions: subscriptions,
        clientVersion: clientVersion,
        encryption: encryption,
        password: password,
      ),
      debugName: 'hydrabox-profile-export',
    );
  }

  HydraBoxProfileImportResult parseProfileExport({
    required List<int> bytes,
    required String currentClientVersion,
    String? password,
  }) {
    final envelope = _decodeEnvelope(bytes, expectedMagic: profileMagic);
    final encryption = switch (envelope['encryption']?.toString()) {
      'encrypted' => HydraBoxProfileEncryption.encrypted,
      'plain' => HydraBoxProfileEncryption.plain,
      _ => throw const HydraBoxBackupException(
        'Unknown profile encryption mode.',
      ),
    };
    final profile = encryption == HydraBoxProfileEncryption.encrypted
        ? _decryptProfile(envelope, password)
        : envelope['profile'];
    if (profile is! Map) {
      throw const HydraBoxBackupException('Profile section is missing.');
    }
    final rawSubscriptions = profile['subscriptions'];
    if (rawSubscriptions is! List) {
      throw const HydraBoxBackupException('Subscriptions section is missing.');
    }
    final subscriptions = rawSubscriptions
        .map((entry) {
          if (entry is! Map) {
            throw const HydraBoxBackupException('Invalid subscription entry.');
          }
          return Subscription.fromMap(Map<String, dynamic>.from(entry));
        })
        .where((subscription) {
          return subscription.id.trim().isNotEmpty ||
              subscription.url.trim().isNotEmpty;
        })
        .toList(growable: false);
    return HydraBoxProfileImportResult(
      warning: _compatibility(envelope, currentClientVersion),
      subscriptions: subscriptions,
      encryption: encryption,
    );
  }

  /// Decodes, decrypts and reconstructs profiles away from the UI isolate.
  Future<HydraBoxProfileImportResult> parseProfileExportInBackground({
    required List<int> bytes,
    required String currentClientVersion,
    String? password,
  }) {
    final transferable = TransferableTypedData.fromList([
      bytes is Uint8List ? bytes : Uint8List.fromList(bytes),
    ]);
    return Isolate.run(
      () => const HydraBoxBackupService().parseProfileExport(
        bytes: transferable.materialize().asUint8List(),
        currentClientVersion: currentClientVersion,
        password: password,
      ),
      debugName: 'hydrabox-profile-import',
    );
  }

  Map<String, dynamic> _decodeEnvelope(
    List<int> bytes, {
    required String expectedMagic,
  }) {
    if (bytes.isEmpty) {
      throw const HydraBoxBackupException('File is empty.');
    }
    if (bytes.length > maxImportBytes) {
      throw const HydraBoxBackupException('File is too large.');
    }
    final head = utf8.decode(bytes.take(128).toList(), allowMalformed: true);
    if (head.trimLeft().startsWith('<')) {
      throw const HydraBoxBackupException(
        'HTML is not a valid HydraBox backup file.',
      );
    }
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map) {
      throw const HydraBoxBackupException('Invalid HydraBox backup file.');
    }
    final envelope = Map<String, dynamic>.from(decoded);
    final allowed = expectedMagic == settingsMagic
        ? const {
            'magic',
            'formatVersion',
            'minClientVersion',
            'createdByVersion',
            'createdAt',
            'settings',
          }
        : const {
            'magic',
            'formatVersion',
            'minClientVersion',
            'createdByVersion',
            'createdAt',
            'encryption',
            'kdf',
            'cipher',
            'payload',
            'profile',
          };
    final unknown = envelope.keys.where((key) => !allowed.contains(key));
    if (unknown.isNotEmpty) {
      throw HydraBoxBackupException(
        'Unknown top-level section: ${unknown.first}.',
      );
    }
    if (envelope['magic'] != expectedMagic) {
      throw const HydraBoxBackupException(
        'This is not a compatible HydraBox backup file.',
      );
    }
    if (envelope['formatVersion'] != formatVersion) {
      throw const HydraBoxBackupException(
        'Unsupported HydraBox backup format version.',
      );
    }
    return envelope;
  }

  HydraBoxImportWarning _compatibility(
    Map<String, dynamic> envelope,
    String currentClientVersion,
  ) {
    final createdBy = envelope['createdByVersion']?.toString() ?? '';
    final minVersion = envelope['minClientVersion']?.toString() ?? '';
    if (minVersion.isEmpty ||
        _compareVersions(minVersion, minClientVersion) < 0 ||
        _compareVersions(currentClientVersion, minVersion) < 0) {
      return HydraBoxImportWarning(
        compatibility: ExportCompatibilityStatus.unsupported,
        createdByVersion: createdBy,
        minClientVersion: minVersion,
      );
    }
    return HydraBoxImportWarning(
      compatibility: _compareVersions(createdBy, currentClientVersion) > 0
          ? ExportCompatibilityStatus.newerClient
          : ExportCompatibilityStatus.compatible,
      createdByVersion: createdBy,
      minClientVersion: minVersion,
    );
  }

  Map<String, dynamic> _decryptProfile(
    Map<String, dynamic> envelope,
    String? password,
  ) {
    final normalizedPassword = password?.trim() ?? '';
    if (normalizedPassword.isEmpty) {
      throw const HydraBoxBackupException('Password is required.');
    }
    final kdf = envelope['kdf'];
    final cipher = envelope['cipher'];
    if (kdf is! Map || cipher is! Map) {
      throw const HydraBoxBackupException('Encryption metadata is missing.');
    }
    try {
      final salt = base64Decode(kdf['salt']?.toString() ?? '');
      final nonce = base64Decode(cipher['nonce']?.toString() ?? '');
      final payload = base64Decode(envelope['payload']?.toString() ?? '');
      final key = _deriveKey(normalizedPassword, Uint8List.fromList(salt));
      final plaintext = _aesGcmDecrypt(
        key: key,
        nonce: Uint8List.fromList(nonce),
        ciphertext: Uint8List.fromList(payload),
      );
      final decoded = jsonDecode(utf8.decode(plaintext));
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
    } catch (_) {
      throw const HydraBoxBackupException('Wrong password or damaged file.');
    }
    throw const HydraBoxBackupException('Invalid encrypted profile.');
  }

  Uint8List _deriveKey(String password, Uint8List salt) {
    final derivator = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))
      ..init(Pbkdf2Parameters(salt, _kdfIterations, _keyBytes));
    return derivator.process(Uint8List.fromList(utf8.encode(password)));
  }

  Uint8List _aesGcmEncrypt({
    required Uint8List key,
    required Uint8List nonce,
    required Uint8List plaintext,
  }) {
    final cipher = GCMBlockCipher(AESEngine())
      ..init(
        true,
        AEADParameters(KeyParameter(key), _tagBits, nonce, Uint8List(0)),
      );
    return cipher.process(plaintext);
  }

  Uint8List _aesGcmDecrypt({
    required Uint8List key,
    required Uint8List nonce,
    required Uint8List ciphertext,
  }) {
    final cipher = GCMBlockCipher(AESEngine())
      ..init(
        false,
        AEADParameters(KeyParameter(key), _tagBits, nonce, Uint8List(0)),
      );
    return cipher.process(ciphertext);
  }

  Uint8List _randomBytes(int length) {
    final random = Random.secure();
    return Uint8List.fromList(
      List<int>.generate(length, (_) => random.nextInt(256)),
    );
  }
}

String _normalizeVersion(String value) {
  final normalized = value.trim().replaceFirst(RegExp(r'^v'), '');
  return normalized.split('+').first;
}

int _compareVersions(String left, String right) {
  final a = _normalizeVersion(left).split('.').map(int.tryParse).toList();
  final b = _normalizeVersion(right).split('.').map(int.tryParse).toList();
  for (var i = 0; i < 3; i++) {
    final av = i < a.length ? a[i] ?? 0 : 0;
    final bv = i < b.length ? b[i] ?? 0 : 0;
    if (av != bv) return av.compareTo(bv);
  }
  return 0;
}

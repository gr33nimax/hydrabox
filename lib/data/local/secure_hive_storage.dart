import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:hive_ce/hive.dart';
import 'package:pointycastle/export.dart';

/// AES-256-GCM encryption for Hive frames.
///
/// Hive's built-in cipher uses CBC and does not authenticate ciphertext. This
/// implementation stores a fresh 96-bit nonce followed by ciphertext and a
/// 128-bit authentication tag for every encrypted value.
class HiveAesGcmCipher implements HiveCipher {
  HiveAesGcmCipher(List<int> key)
    : _key = Uint8List.fromList(key),
      _keyCrc = _calculateKeyCrc(key) {
    if (key.length != 32 || key.any((byte) => byte < 0 || byte > 255)) {
      throw ArgumentError('The AES-256-GCM key must contain exactly 32 bytes.');
    }
  }

  static const _nonceBytes = 12;
  static const _tagBits = 128;
  static const _tagBytes = _tagBits ~/ 8;
  static final Random _random = Random.secure();

  final Uint8List _key;
  final int _keyCrc;

  static int _calculateKeyCrc(List<int> key) {
    final digest = sha256.convert(key).bytes;
    return ByteData.sublistView(Uint8List.fromList(digest)).getUint32(0);
  }

  @override
  int calculateKeyCrc() => _keyCrc;

  @override
  int maxEncryptedSize(Uint8List inp) => inp.length + _nonceBytes + _tagBytes;

  @override
  int encrypt(
    Uint8List inp,
    int inpOff,
    int inpLength,
    Uint8List out,
    int outOff,
  ) {
    final nonce = Uint8List.fromList(
      List<int>.generate(_nonceBytes, (_) => _random.nextInt(256)),
    );
    final plaintext = Uint8List.sublistView(inp, inpOff, inpOff + inpLength);
    final cipher = GCMBlockCipher(AESEngine())
      ..init(
        true,
        AEADParameters(KeyParameter(_key), _tagBits, nonce, Uint8List(0)),
      );
    final ciphertext = cipher.process(plaintext);
    out.setRange(outOff, outOff + _nonceBytes, nonce);
    out.setRange(
      outOff + _nonceBytes,
      outOff + _nonceBytes + ciphertext.length,
      ciphertext,
    );
    return _nonceBytes + ciphertext.length;
  }

  @override
  int decrypt(
    Uint8List inp,
    int inpOff,
    int inpLength,
    Uint8List out,
    int outOff,
  ) {
    if (inpLength < _nonceBytes + _tagBytes) {
      throw StateError('Encrypted Hive frame is too short.');
    }
    final nonce = Uint8List.sublistView(inp, inpOff, inpOff + _nonceBytes);
    final ciphertext = Uint8List.sublistView(
      inp,
      inpOff + _nonceBytes,
      inpOff + inpLength,
    );
    final cipher = GCMBlockCipher(AESEngine())
      ..init(
        false,
        AEADParameters(KeyParameter(_key), _tagBits, nonce, Uint8List(0)),
      );
    final plaintext = cipher.process(ciphertext);
    out.setRange(outOff, outOff + plaintext.length, plaintext);
    return plaintext.length;
  }
}

class SecureHiveStorage {
  SecureHiveStorage._();

  static const _channel = MethodChannel('io.hydrabox.client/secure_storage');
  static HiveCipher? _cipher;
  static bool _initialized = false;
  static Future<void>? _initialization;

  static HiveCipher? get cipher => _cipher;

  /// Loads the data key protected by Android Keystore.
  ///
  /// Android must never silently fall back to plaintext. Non-Android builds
  /// remain unencrypted because HydraBox's production target is Android.
  static Future<void> init() async {
    if (_initialized) return;
    final inFlight = _initialization;
    if (inFlight != null) {
      await inFlight;
      return;
    }
    final initialization = () async {
      if (Platform.isAndroid) {
        final encoded = await _channel.invokeMethod<String>(
          'getOrCreateHiveDataKey',
        );
        if (encoded == null) {
          throw StateError('Android Keystore returned no Hive data key.');
        }
        final key = base64Decode(encoded);
        _cipher = HiveAesGcmCipher(key);
      }
      _initialized = true;
    }();
    _initialization = initialization;
    try {
      await initialization;
    } finally {
      if (identical(_initialization, initialization)) {
        _initialization = null;
      }
    }
  }
}

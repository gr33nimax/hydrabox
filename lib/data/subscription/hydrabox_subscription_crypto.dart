import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

import 'strict_json.dart';

/// Shared-key HydraBox transport based on JWE JSON Serialization.
///
/// v1 intentionally supports one small, auditable suite:
///
/// * key management: `dir` (a 256-bit key supplied out of band);
/// * content encryption: `A256GCM`;
/// * compression: forbidden.
///
/// The key can be carried in an HTTPS URL fragment as `hbx-key`. URI fragments
/// are not part of an HTTP request and must be stripped before a native fetch.
class HydraBoxJweCodec {
  HydraBoxJweCodec._();

  static const mediaType = 'application/vnd.hydrabox.subscription+json';
  static const joseType = 'hbx+jwe';
  static const keyFragmentName = 'hbx-key';
  static const _maxPlaintextBytes = 12 * 1024 * 1024;
  static const _nonceBytes = 12;
  static const _tagBytes = 16;
  static const _tagBits = _tagBytes * 8;
  static final Random _random = Random.secure();

  static bool looksLike(String source) {
    final members = scanTopLevelJsonObjectForDetection(
      source,
      memberNames: const {'protected', 'iv', 'ciphertext', 'tag'},
    );
    final hasProtected = members.containsKey('protected');
    final encryptedMembers = [
      members.containsKey('iv'),
      members.containsKey('ciphertext'),
      members.containsKey('tag'),
    ].where((present) => present).length;
    // Treat partial containers as JWE too, so a truncated/tampered envelope
    // fails closed instead of falling through to a legacy config parser.
    return hasProtected || encryptedMembers >= 2;
  }

  /// Returns a base64url key from `#hbx-key=...`, without decoding it.
  static String? keyFromUri(Uri uri) {
    final values = _rawKeyFragmentValues(uri);
    if (values.length != 1) return null;
    try {
      final value = Uri.decodeQueryComponent(values.single);
      return value.isEmpty || value != value.trim() ? null : value;
    } on FormatException {
      return null;
    }
  }

  /// Whether the fragment declares an encryption policy, even if its key is
  /// empty, duplicated, or malformed. Callers use this to reject invalid key
  /// hints instead of silently treating them as an absent policy.
  static bool hasKeyFragment(Uri uri) => _rawKeyFragmentValues(uri).isNotEmpty;

  /// Rejects attempts to deliver the decryption key in the request query.
  ///
  /// Query parameters are sent to the origin and routinely recorded by
  /// servers, proxies, and CDNs. HydraBox therefore reserves `hbx-key`
  /// exclusively for the URI fragment, including percent-encoded spellings
  /// of the query parameter name.
  static bool hasKeyQueryParameter(Uri uri) {
    if (!uri.hasQuery) return false;
    for (final member in uri.query.split(RegExp(r'[&;]'))) {
      final separator = member.indexOf('=');
      final rawName = separator < 0 ? member : member.substring(0, separator);
      String name;
      try {
        name = Uri.decodeQueryComponent(rawName);
      } on FormatException {
        name = rawName;
      }
      if (name.toLowerCase() == keyFragmentName) return true;
    }
    return false;
  }

  static Uri uriWithoutSecretFragment(Uri uri) {
    if (!uri.hasFragment) return uri;
    // `Uri.replace(fragment: '')` preserves an explicit empty fragment and
    // serializes it as a trailing `#`. Reparse the already percent-encoded
    // prefix instead so the secret delimiter is removed as well.
    final serialized = uri.toString();
    return Uri.parse(serialized.substring(0, serialized.indexOf('#')));
  }

  static List<String> _rawKeyFragmentValues(Uri uri) {
    final fragment = uri.fragment;
    if (fragment.isEmpty) return const [];
    final values = <String>[];
    for (final member in fragment.split('&')) {
      final separator = member.indexOf('=');
      final rawName = separator < 0 ? member : member.substring(0, separator);
      String name;
      try {
        name = Uri.decodeQueryComponent(rawName);
      } on FormatException {
        // A plainly written key name still establishes the fail-closed policy
        // even when another escape in the member is malformed.
        name = rawName;
      }
      if (name != keyFragmentName) continue;
      values.add(separator < 0 ? '' : member.substring(separator + 1));
    }
    return values;
  }

  static Uint8List decodeKey(String encoded) {
    final key = _decodeBase64Url(encoded, field: keyFragmentName, maxBytes: 32);
    if (key.length != 32) {
      throw const FormatException(
        'HydraBox JWE key must contain exactly 32 bytes',
      );
    }
    return key;
  }

  static String decrypt(
    String source, {
    required String encodedKey,
    String? expectedKeyId,
  }) {
    final outer = decodeStrictJson(source);
    if (outer is! Map) {
      throw const FormatException('HydraBox JWE must be a JSON object');
    }
    final envelope = Map<String, dynamic>.from(outer);
    const allowedOuterKeys = {'protected', 'iv', 'ciphertext', 'tag'};
    final unsupported = envelope.keys
        .where((key) => !allowedOuterKeys.contains(key))
        .toList(growable: false);
    if (unsupported.isNotEmpty) {
      throw FormatException(
        'Unsupported HydraBox JWE member: ${unsupported.first}',
      );
    }

    final protectedValue = _requiredString(envelope, 'protected');
    final protectedBytes = _decodeBase64Url(
      protectedValue,
      field: 'protected',
      maxBytes: 4096,
    );
    final protectedJson = utf8.decode(protectedBytes, allowMalformed: false);
    final decodedHeader = decodeStrictJson(protectedJson);
    if (decodedHeader is! Map) {
      throw const FormatException('JWE protected header must be an object');
    }
    final header = Map<String, dynamic>.from(decodedHeader);
    _validateProtectedHeader(header, expectedKeyId: expectedKeyId);

    final iv = _decodeBase64Url(
      _requiredString(envelope, 'iv'),
      field: 'iv',
      maxBytes: _nonceBytes,
    );
    if (iv.length != _nonceBytes) {
      throw const FormatException('A256GCM IV must contain 12 bytes');
    }
    final ciphertext = _decodeBase64Url(
      _requiredString(envelope, 'ciphertext'),
      field: 'ciphertext',
      maxBytes: _maxPlaintextBytes,
    );
    final tag = _decodeBase64Url(
      _requiredString(envelope, 'tag'),
      field: 'tag',
      maxBytes: _tagBytes,
    );
    if (tag.length != _tagBytes) {
      throw const FormatException('A256GCM tag must contain 16 bytes');
    }

    final cipherInput = Uint8List(ciphertext.length + tag.length)
      ..setRange(0, ciphertext.length, ciphertext)
      ..setRange(ciphertext.length, ciphertext.length + tag.length, tag);
    final cipher = GCMBlockCipher(AESEngine())
      ..init(
        false,
        AEADParameters(
          KeyParameter(decodeKey(encodedKey)),
          _tagBits,
          iv,
          Uint8List.fromList(ascii.encode(protectedValue)),
        ),
      );
    try {
      final plaintext = cipher.process(cipherInput);
      if (plaintext.length > _maxPlaintextBytes) {
        throw const FormatException(
          'Decrypted HydraBox subscription is too large',
        );
      }
      return utf8.decode(plaintext, allowMalformed: false);
    } on InvalidCipherTextException {
      throw const FormatException(
        'HydraBox JWE authentication failed (wrong key or modified data)',
      );
    }
  }

  /// Creates a flattened JWE JSON object. This is primarily used by provider
  /// tooling and deterministic interoperability tests.
  static String encrypt(
    String plaintext, {
    required String encodedKey,
    String? keyId,
    Uint8List? nonce,
  }) {
    final plaintextBytes = Uint8List.fromList(utf8.encode(plaintext));
    if (plaintextBytes.length > _maxPlaintextBytes) {
      throw const FormatException('HydraBox subscription is too large');
    }
    final iv =
        nonce ??
        Uint8List.fromList(
          List<int>.generate(_nonceBytes, (_) => _random.nextInt(256)),
        );
    if (iv.length != _nonceBytes) {
      throw const FormatException('A256GCM IV must contain 12 bytes');
    }

    final normalizedKeyId = keyId;
    if (normalizedKeyId != null &&
        (normalizedKeyId.isEmpty ||
            normalizedKeyId != normalizedKeyId.trim() ||
            normalizedKeyId.length > 256 ||
            normalizedKeyId.contains(RegExp(r'[\x00-\x1F\x7F]')))) {
      throw const FormatException('HydraBox JWE kid is invalid');
    }
    final protectedHeader = <String, dynamic>{
      'alg': 'dir',
      'enc': 'A256GCM',
      'typ': joseType,
      'cty': mediaType,
      'kid': ?normalizedKeyId,
    };
    final protectedValue = _encodeBase64Url(
      utf8.encode(jsonEncode(protectedHeader)),
    );
    final cipher = GCMBlockCipher(AESEngine())
      ..init(
        true,
        AEADParameters(
          KeyParameter(decodeKey(encodedKey)),
          _tagBits,
          iv,
          Uint8List.fromList(ascii.encode(protectedValue)),
        ),
      );
    final encrypted = cipher.process(plaintextBytes);
    final ciphertext = Uint8List.sublistView(
      encrypted,
      0,
      encrypted.length - _tagBytes,
    );
    final tag = Uint8List.sublistView(encrypted, encrypted.length - _tagBytes);
    return jsonEncode({
      'protected': protectedValue,
      'iv': _encodeBase64Url(iv),
      'ciphertext': _encodeBase64Url(ciphertext),
      'tag': _encodeBase64Url(tag),
    });
  }

  static String? keyId(String source) {
    try {
      final outer = decodeStrictJson(source);
      if (outer is! Map || outer['protected'] is! String) return null;
      final headerBytes = _decodeBase64Url(
        outer['protected'] as String,
        field: 'protected',
        maxBytes: 4096,
      );
      final header = decodeStrictJson(
        utf8.decode(headerBytes, allowMalformed: false),
      );
      if (header is! Map) return null;
      final rawValue = header['kid'];
      final value = rawValue is String ? rawValue : null;
      return value == null ||
              value.isEmpty ||
              value != value.trim() ||
              value.length > 256 ||
              value.contains(RegExp(r'[\x00-\x1F\x7F]'))
          ? null
          : value;
    } on FormatException {
      return null;
    }
  }

  static void _validateProtectedHeader(
    Map<String, dynamic> header, {
    String? expectedKeyId,
  }) {
    const allowedHeaderKeys = {'alg', 'enc', 'typ', 'cty', 'kid'};
    final unsupported = header.keys
        .where((key) => !allowedHeaderKeys.contains(key))
        .toList(growable: false);
    if (unsupported.isNotEmpty) {
      throw FormatException(
        'Unsupported JWE protected header: ${unsupported.first}',
      );
    }
    if (header['alg'] != 'dir' ||
        header['enc'] != 'A256GCM' ||
        header['typ'] != joseType ||
        header['cty'] != mediaType) {
      throw const FormatException('Unsupported HydraBox JWE algorithm suite');
    }
    final rawKeyId = header['kid'];
    if (rawKeyId != null && rawKeyId is! String) {
      throw const FormatException('HydraBox JWE kid must be a string');
    }
    final keyId = rawKeyId as String?;
    if (rawKeyId != null &&
        (keyId == null ||
            keyId.isEmpty ||
            keyId != keyId.trim() ||
            keyId.length > 256 ||
            keyId.contains(RegExp(r'[\x00-\x1F\x7F]')))) {
      throw const FormatException('HydraBox JWE kid is invalid');
    }
    if (expectedKeyId != null &&
        expectedKeyId.isNotEmpty &&
        keyId != expectedKeyId) {
      throw const FormatException('HydraBox JWE key id does not match');
    }
  }

  static String _requiredString(Map<String, dynamic> map, String key) {
    final value = map[key];
    if (value is! String || value.isEmpty) {
      throw FormatException('HydraBox JWE member "$key" is required');
    }
    return value;
  }

  static Uint8List _decodeBase64Url(
    String value, {
    required String field,
    required int maxBytes,
  }) {
    if (value.isEmpty ||
        value.contains('=') ||
        !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(value)) {
      throw FormatException('$field must be unpadded base64url');
    }
    // Reject oversized input before allocating the decoded buffer.
    if (value.length > ((maxBytes + 2) ~/ 3) * 4) {
      throw FormatException('$field is too large');
    }
    final padded = switch (value.length % 4) {
      0 => value,
      2 => '$value==',
      3 => '$value=',
      _ => throw FormatException('$field has invalid base64url length'),
    };
    try {
      final decoded = Uint8List.fromList(base64Url.decode(padded));
      if (decoded.length > maxBytes) {
        throw FormatException('$field is too large');
      }
      return decoded;
    } on FormatException {
      rethrow;
    } catch (_) {
      throw FormatException('$field is not valid base64url');
    }
  }

  static String _encodeBase64Url(List<int> bytes) =>
      base64Url.encode(bytes).replaceAll('=', '');
}

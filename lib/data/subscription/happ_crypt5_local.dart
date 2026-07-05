import 'dart:convert';

import 'package:asn1lib/asn1lib.dart';
import 'package:flutter/services.dart';
import 'package:pointycastle/export.dart';

class HappCrypt5Support {
  const HappCrypt5Support({required this.supported, required this.detail});

  final bool supported;
  final String detail;
}

class HappCrypt5Local {
  HappCrypt5Local._();

  static Future<_Crypt5Data>? _dataFuture;
  static final _keyCache = <String, RSAPrivateKey>{};

  static Future<HappCrypt5Support> checkSupport({AssetBundle? bundle}) async {
    try {
      final data = bundle == null
          ? await _loadData()
          : await _Crypt5Data.load(bundle: bundle);
      if (!data.isStructurallyValid) {
        return const HappCrypt5Support(
          supported: false,
          detail: 'Happ crypt5 compatibility assets are incomplete.',
        );
      }
      return const HappCrypt5Support(
        supported: true,
        detail: 'Happ crypt5 compatibility assets are loaded.',
      );
    } catch (error) {
      return HappCrypt5Support(
        supported: false,
        detail: 'Happ crypt5 compatibility assets are unavailable: $error',
      );
    }
  }

  static Future<String> decrypt(String link) async {
    final payload = link.trim().startsWith('happ://crypt5/')
        ? link.trim().substring('happ://crypt5/'.length)
        : link.trim();
    if (payload.isEmpty) {
      throw const FormatException('Empty Happ crypt5 payload.');
    }

    final data = await _loadData();

    final legacyResult = _tryDecryptLegacyCrypt5(payload, data);
    if (legacyResult != null) return legacyResult;

    final selector = _deriveCrypt51Selector(payload);
    final rsaKeys = <String>[];
    _pushUnique(rsaKeys, data.crypt51Keys[selector]);
    try {
      _pushUnique(rsaKeys, data.expandedKey(selector));
    } catch (_) {
      // Some crypt5.1 selectors only exist in the APK-native fallback set.
    }
    _pushFamilyKeys(rsaKeys, selector, data.crypt51Keys);
    _pushFamilyKeys(rsaKeys, selector, data.expandedKeys);
    for (final key in data.nativeKeys.values) {
      _pushUnique(rsaKeys, key);
    }

    for (final candidate in _parsePayloadCandidates(payload)) {
      late Uint8List cipherBytes;
      late Uint8List ciphertext;
      try {
        cipherBytes = _base64Decode(
          _makeCipherB64(candidate.encStr, candidate.splitOnInnerEquals),
        );
        ciphertext = _base64UrlDecode(candidate.urlB64);
      } catch (_) {
        continue;
      }

      for (final rsaKeyB64 in rsaKeys) {
        String rsaPlain;
        try {
          rsaPlain = _rsaDecrypt(_parsePkcs8PrivateKey(rsaKeyB64), cipherBytes);
        } catch (_) {
          continue;
        }

        for (final keyB64 in [_swapPairs(rsaPlain), rsaPlain]) {
          try {
            final chachaKey = _base64UrlDecode(keyB64);
            final plaintext = _chacha20Poly1305Decrypt(
              key: chachaKey,
              nonce: Uint8List.fromList(utf8.encode(candidate.nonceStr)),
              ciphertext: ciphertext,
            );
            final intermediate = utf8.decode(plaintext);
            return utf8.decode(_base64UrlDecode(_swapPairs(intermediate)));
          } catch (_) {
            // Try the next RSA key / key-string shape.
          }
        }
      }
    }

    throw const FormatException('Unable to decrypt Happ crypt5 payload.');
  }

  static String? _tryDecryptLegacyCrypt5(String payload, _Crypt5Data data) {
    final shuffled = _legacyBlockPairSwap(payload);
    if (shuffled.length < 8) return null;

    final marker =
        shuffled.substring(0, 4) +
        shuffled.substring(shuffled.length - 4, shuffled.length);
    final rsaKeyB64 = data.expandedKeys[marker];
    if (rsaKeyB64 == null) return null;

    final body = shuffled.substring(4, shuffled.length - 4);
    if (body.length < 13) return null;

    final nonce = Uint8List.fromList(utf8.encode(body.substring(0, 12)));
    final rest = body.substring(12);
    final digitMatch = RegExp(r'^\d+').firstMatch(rest);
    if (digitMatch == null) return null;

    final segmentLength = int.tryParse(digitMatch.group(0)!);
    if (segmentLength == null) return null;

    final packed = rest.substring(digitMatch.end);
    if (packed.length < 1 + segmentLength) return null;

    final urlB64 = packed.substring(1, 1 + segmentLength);
    final encStr = packed.substring(1 + segmentLength);

    try {
      final rsaPlain = _rsaDecrypt(
        _parsePkcs8PrivateKey(rsaKeyB64),
        _base64UrlDecode(encStr),
      );
      final chachaKey = _base64UrlDecode(_swapPairs(rsaPlain));
      final plaintext = _chacha20Poly1305Decrypt(
        key: chachaKey,
        nonce: nonce,
        ciphertext: _base64UrlDecode(urlB64),
      );
      final intermediate = utf8.decode(plaintext);
      return utf8.decode(_base64UrlDecode(_swapPairs(intermediate)));
    } catch (_) {
      return null;
    }
  }

  static Future<_Crypt5Data> _loadData() {
    return _dataFuture ??= _Crypt5Data.load();
  }

  static String _deriveCrypt51Selector(String payload) {
    if (payload.length < 10) return '';
    return (payload.substring(2, 4) +
            payload.substring(0, 2) +
            payload.substring(payload.length - 6, payload.length - 4) +
            payload.substring(payload.length - 2))
        .toLowerCase();
  }

  static List<_Crypt5Candidate> _parsePayloadCandidates(String payload) {
    final nonceStr = _extractNonce(payload);
    final candidates = <_Crypt5Candidate>[];
    final seen = <String>{};

    void push(String urlB64, String encStr, bool splitOnInnerEquals) {
      if (urlB64.isEmpty || encStr.length < 684) return;
      final key = [
        urlB64.length,
        urlB64.substring(0, urlB64.length < 16 ? urlB64.length : 16),
        urlB64.substring(urlB64.length < 16 ? 0 : urlB64.length - 16),
        encStr.substring(0, encStr.length < 16 ? encStr.length : 16),
        encStr.substring(encStr.length < 16 ? 0 : encStr.length - 16),
      ].join(':');
      if (!seen.add(key)) return;
      candidates.add(
        _Crypt5Candidate(
          nonceStr: nonceStr,
          urlB64: urlB64,
          encStr: encStr,
          splitOnInnerEquals: splitOnInnerEquals,
        ),
      );
    }

    final n = int.tryParse(
      payload.substring(18, payload.length < 20 ? payload.length : 20),
    );
    if (n != null && n > 0 && payload.length >= 20 + n + 684) {
      push(_extractUrlB64(payload, n), _extractEncStr(payload, n), true);
    }

    for (var trailerLength = 4; trailerLength <= 8; trailerLength++) {
      final urlLength = payload.length - 20 - 684 - trailerLength;
      if (urlLength <= 0) continue;
      final urlRegion = payload.substring(20, 20 + urlLength);
      final encRegion = payload.substring(20 + urlLength, 20 + urlLength + 684);
      if (encRegion.length != 684) continue;
      final urlB64 = _blockPairSwap(urlRegion, urlLength);
      final encStr = _blockPairSwap(encRegion, 684);
      push(urlB64, encStr, false);
      if (urlB64.endsWith('=')) {
        push('${urlB64.substring(1)}=', encStr, false);
      }
    }

    return candidates;
  }

  static String _extractNonce(String payload) {
    final n = payload.substring(4, 16);
    return n[2] +
        n[3] +
        n[0] +
        n[1] +
        n[6] +
        n[7] +
        n[4] +
        n[5] +
        n[10] +
        n[11] +
        n[8] +
        n[9];
  }

  static String _extractUrlB64(String payload, int n) {
    return payload[17] + _blockPairSwap(payload.substring(20, 20 + n), n - 1);
  }

  static String _extractEncStr(String payload, int n) {
    final urlRegion = payload.substring(20, 20 + n);
    final encRegion = payload.substring(20 + n, 20 + n + 684);
    final skip = ((n - 1) ~/ 4) * 4 + 1;
    return urlRegion[skip] + _blockPairSwap(encRegion, 683);
  }

  static String _blockPairSwap(String region, int length) {
    final result = StringBuffer();
    for (var j = 1; j <= length; j++) {
      final k = (j - 1) ~/ 4;
      final p = (j - 1) % 4;
      final index = 4 * k + ((p + 2) % 4);
      if (index < region.length) {
        result.write(region[index]);
      }
    }
    return result.toString();
  }

  static String _legacyBlockPairSwap(String value) {
    final result = StringBuffer();
    final fullLength = value.length - (value.length % 4);
    for (var offset = 0; offset < fullLength; offset += 4) {
      result
        ..write(value.substring(offset + 2, offset + 4))
        ..write(value.substring(offset, offset + 2));
    }
    result.write(value.substring(fullLength));
    return result.toString();
  }

  static String _makeCipherB64(String encStr, bool splitOnInnerEquals) {
    final trailingStart = encStr.replaceFirst(RegExp(r'=+$'), '').length;
    final eqIdx = encStr.indexOf('=');
    final cipherB64 = splitOnInnerEquals && eqIdx >= 0 && eqIdx < trailingStart
        ? encStr.substring(eqIdx + 1)
        : encStr;
    final cb = cipherB64
        .replaceFirst(RegExp(r'^=+'), '')
        .replaceFirst(RegExp(r'=+$'), '');
    return cb + ('=' * ((4 - (cb.length % 4)) % 4));
  }

  static String _swapPairs(String value) {
    final out = StringBuffer();
    for (var i = 0; i < value.length; i += 2) {
      if (i + 1 < value.length) {
        out
          ..write(value[i + 1])
          ..write(value[i]);
      } else {
        out.write(value[i]);
      }
    }
    return out.toString();
  }

  static String _rsaDecrypt(RSAPrivateKey key, Uint8List cipherBytes) {
    final cipher = PKCS1Encoding(RSAEngine())
      ..init(false, PrivateKeyParameter<RSAPrivateKey>(key));
    return String.fromCharCodes(cipher.process(cipherBytes));
  }

  static Uint8List _chacha20Poly1305Decrypt({
    required Uint8List key,
    required Uint8List nonce,
    required Uint8List ciphertext,
  }) {
    final cipher = AEADCipher(
      'ChaCha20-Poly1305',
    )..init(false, AEADParameters(KeyParameter(key), 128, nonce, Uint8List(0)));
    final out = Uint8List(cipher.getOutputSize(ciphertext.length));
    var length = cipher.processBytes(ciphertext, 0, ciphertext.length, out, 0);
    length += cipher.doFinal(out, length);
    return Uint8List.view(out.buffer, 0, length);
  }

  static RSAPrivateKey _parsePkcs8PrivateKey(String keyB64) {
    final cached = _keyCache[keyB64];
    if (cached != null) return cached;

    final privateKeyInfo =
        ASN1Parser(_base64Decode(keyB64)).nextObject() as ASN1Sequence;
    final privateKeyOctets = privateKeyInfo.elements[2] as ASN1OctetString;
    final key = _parsePkcs1DerPrivateKey(privateKeyOctets.octets);
    _keyCache[keyB64] = key;
    return key;
  }

  static RSAPrivateKey _parsePkcs1DerPrivateKey(Uint8List derBytes) {
    final sequence = ASN1Parser(derBytes).nextObject() as ASN1Sequence;
    final elements = sequence.elements;
    if (elements.length < 9) {
      throw const FormatException('Invalid RSA key format.');
    }

    final modulus = (elements[1] as ASN1Integer).valueAsBigInteger;
    final privateExponent = (elements[3] as ASN1Integer).valueAsBigInteger;
    final p = (elements[4] as ASN1Integer).valueAsBigInteger;
    final q = (elements[5] as ASN1Integer).valueAsBigInteger;
    return RSAPrivateKey(modulus, privateExponent, p, q);
  }

  static Uint8List _base64Decode(String value) {
    final normalized = value.replaceAll(RegExp(r'\s'), '');
    final padded = normalized + ('=' * ((4 - (normalized.length % 4)) % 4));
    return Uint8List.fromList(base64.decode(padded));
  }

  static Uint8List _base64UrlDecode(String value) {
    final normalized = value
        .replaceAll('-', '+')
        .replaceAll('_', '/')
        .replaceAll(RegExp(r'\s'), '');
    final padded = normalized + ('=' * ((4 - (normalized.length % 4)) % 4));
    return Uint8List.fromList(base64.decode(padded));
  }

  static void _pushUnique(List<String> values, String? value) {
    if (value != null && value.isNotEmpty && !values.contains(value)) {
      values.add(value);
    }
  }

  static void _pushFamilyKeys(
    List<String> values,
    String selector,
    Map<String, String> keys,
  ) {
    if (selector.length < 4) return;
    final family = selector.substring(0, 4);
    for (final entry in keys.entries) {
      if (entry.key.startsWith(family)) {
        _pushUnique(values, entry.value);
      }
    }
  }
}

class _Crypt5Data {
  const _Crypt5Data({
    required this.selectors,
    required this.expandedKeys,
    required this.crypt51Keys,
    required this.nativeKeys,
  });

  final List<List<String>> selectors;
  final Map<String, String> expandedKeys;
  final Map<String, String> crypt51Keys;
  final Map<String, String> nativeKeys;

  static Future<_Crypt5Data> load({AssetBundle? bundle}) async {
    final assetBundle = bundle ?? rootBundle;
    final values = await Future.wait([
      assetBundle.loadString('assets/happ_crypto/selectors.json'),
      assetBundle.loadString('assets/happ_crypto/expanded_rsa_keys.json'),
      assetBundle.loadString('assets/happ_crypto/crypt51_rsa_keys.json'),
      assetBundle.loadString('assets/happ_crypto/native_rsa_keys.json'),
    ]);

    return _Crypt5Data(
      selectors: (jsonDecode(values[0]) as List<dynamic>)
          .map((row) => (row as List<dynamic>).cast<String>())
          .toList(),
      expandedKeys: (jsonDecode(values[1]) as Map<String, dynamic>)
          .cast<String, String>(),
      crypt51Keys: (jsonDecode(values[2]) as Map<String, dynamic>)
          .cast<String, String>(),
      nativeKeys: (jsonDecode(values[3]) as Map<String, dynamic>)
          .cast<String, String>(),
    );
  }

  bool get isStructurallyValid {
    if (selectors.isEmpty ||
        expandedKeys.isEmpty ||
        crypt51Keys.isEmpty ||
        nativeKeys.isEmpty) {
      return false;
    }
    if (selectors.any(
      (row) => row.length < 3 || row.take(3).any((value) => value.isEmpty),
    )) {
      return false;
    }
    return <Map<String, String>>[expandedKeys, crypt51Keys, nativeKeys].every(
      (keys) => keys.entries.every(
        (entry) => entry.key.trim().isNotEmpty && entry.value.trim().isNotEmpty,
      ),
    );
  }

  String expandedKey(String selector) {
    final exact = expandedKeys[selector];
    if (exact != null) return exact;

    for (final row in selectors) {
      final starts = row[0];
      final mid = row[1];
      final ends = row[2];
      if (selector.startsWith(starts) &&
          selector.length >= 6 &&
          selector.substring(2, 6) == mid &&
          selector.endsWith(ends)) {
        final key = expandedKeys[starts + mid + ends];
        if (key != null) return key;
      }
    }
    throw FormatException('No RSA key found for selector: $selector');
  }
}

class _Crypt5Candidate {
  const _Crypt5Candidate({
    required this.nonceStr,
    required this.urlB64,
    required this.encStr,
    required this.splitOnInnerEquals,
  });

  final String nonceStr;
  final String urlB64;
  final String encStr;
  final bool splitOnInnerEquals;
}

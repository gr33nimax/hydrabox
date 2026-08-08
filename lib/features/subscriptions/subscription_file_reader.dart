import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:hydrabox/data/subscription/parsers/hydra_subscription_parser.dart';

const _defaultReadTimeout = Duration(seconds: 20);
const _maxHydraFileBytes = 16 * 1024 * 1024;
const _maxSubscriptionFileBytes = 64 * 1024 * 1024;

class SubscriptionFileReadException implements Exception {
  const SubscriptionFileReadException(this.reason);

  final String reason;

  @override
  String toString() => 'Subscription file read failed: $reason';
}

Future<String> readSubscriptionFile(
  PlatformFile file, {
  Duration timeout = _defaultReadTimeout,
}) async {
  final declaredHydra = _isDeclaredHydraFile(file.name);
  final maxBytes = declaredHydra
      ? _maxHydraFileBytes
      : _maxSubscriptionFileBytes;
  if (file.size > maxBytes) {
    throw SubscriptionFileReadException(_tooLargeReason(declaredHydra));
  }

  final bytes = await _readFileBytes(file, maxBytes: maxBytes).timeout(timeout);
  if (bytes.isEmpty) {
    throw const SubscriptionFileReadException('file is empty');
  }

  final transferable = TransferableTypedData.fromList([bytes]);
  final content = await Isolate.run(
    () => _decodeTextFile(transferable.materialize().asUint8List()),
    debugName: 'hydrabox-read-subscription-file',
  ).timeout(timeout);
  if (content.isEmpty) {
    throw const SubscriptionFileReadException('decoded content is empty');
  }
  // Undeclared files can still contain a Hydra/JWE discriminator. Measure
  // the original file bytes here because the text decoder intentionally trims
  // surrounding whitespace for legacy import compatibility.
  if (!declaredHydra &&
      bytes.length > _maxHydraFileBytes &&
      HydraSubscriptionParser.looksLike(content)) {
    throw const SubscriptionFileReadException(
      'Hydra subscription file is larger than 16 MiB',
    );
  }
  return content;
}

Future<Uint8List> _readFileBytes(
  PlatformFile file, {
  required int maxBytes,
}) async {
  final inMemory = file.bytes;
  if (inMemory != null) {
    if (inMemory.length > maxBytes) {
      throw SubscriptionFileReadException(
        _tooLargeReason(maxBytes == _maxHydraFileBytes),
      );
    }
    return inMemory;
  }

  final stream = file.readStream;
  if (stream != null) {
    return _collectBytes(stream, maxBytes: maxBytes);
  }

  final path = file.path;
  if (path == null || path.isEmpty) {
    throw const SubscriptionFileReadException(
      'the document provider returned no readable data',
    );
  }
  return _collectBytes(File(path).openRead(), maxBytes: maxBytes);
}

Future<Uint8List> _collectBytes(
  Stream<List<int>> stream, {
  required int maxBytes,
}) async {
  final builder = BytesBuilder(copy: false);
  await for (final chunk in stream) {
    if (builder.length + chunk.length > maxBytes) {
      throw SubscriptionFileReadException(
        _tooLargeReason(maxBytes == _maxHydraFileBytes),
      );
    }
    builder.add(chunk);
  }
  return builder.takeBytes();
}

bool _isDeclaredHydraFile(String name) {
  final normalized = name.trim().toLowerCase();
  return normalized.endsWith('.hydra') ||
      normalized.endsWith('.hydra.json') ||
      normalized.endsWith('.hydra.jwe.json');
}

String _tooLargeReason(bool hydra) => hydra
    ? 'Hydra subscription file is larger than 16 MiB'
    : 'file is larger than 64 MiB';

String _decodeTextFile(Uint8List bytes) {
  if (bytes.length >= 3 &&
      bytes[0] == 0xef &&
      bytes[1] == 0xbb &&
      bytes[2] == 0xbf) {
    return _decodeUtf8(bytes.sublist(3));
  }
  if (bytes.length >= 2 && bytes[0] == 0xff && bytes[1] == 0xfe) {
    return _decodeLegacyUtf16(bytes, littleEndian: true);
  }
  if (bytes.length >= 2 && bytes[0] == 0xfe && bytes[1] == 0xff) {
    return _decodeLegacyUtf16(bytes, littleEndian: false);
  }
  return _decodeUtf8(bytes);
}

String _decodeUtf8(Uint8List bytes) {
  try {
    return utf8.decode(bytes, allowMalformed: false).trim();
  } on FormatException {
    throw const SubscriptionFileReadException('file is not valid UTF-8');
  }
}

String _decodeLegacyUtf16(Uint8List bytes, {required bool littleEndian}) {
  final content = _decodeUtf16(bytes, littleEndian: littleEndian).trim();
  // Hydra Subscription v2 is a strict UTF-8 wire format. Transcoding its JSON before
  // validation would erase the original byte representation and could make
  // different implementations authenticate or interpret different input.
  if (HydraSubscriptionParser.looksLike(content)) {
    throw const SubscriptionFileReadException(
      'Hydra subscription files must use UTF-8',
    );
  }
  return content;
}

String _decodeUtf16(Uint8List bytes, {required bool littleEndian}) {
  final codeUnits = <int>[];
  for (var index = 2; index + 1 < bytes.length; index += 2) {
    final first = bytes[index];
    final second = bytes[index + 1];
    codeUnits.add(littleEndian ? first | (second << 8) : (first << 8) | second);
  }
  return String.fromCharCodes(codeUnits);
}

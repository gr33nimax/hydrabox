import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hydrabox/features/subscriptions/subscription_file_reader.dart';

void main() {
  test('reads a picked txt file from its stream', () async {
    final source = utf8.encode(
      'vless://uuid@server.example:443?security=tls#Node',
    );
    final file = PlatformFile(
      name: 'nodes.txt',
      size: source.length,
      readStream: Stream<List<int>>.fromIterable([
        source.sublist(0, 12),
        source.sublist(12),
      ]),
    );

    expect(await readSubscriptionFile(file), utf8.decode(source));
  });

  test('removes an UTF-8 BOM from a picked json file', () async {
    const json = '{"outbounds":[{"type":"direct","tag":"direct"}]}';
    final bytes = Uint8List.fromList([0xef, 0xbb, 0xbf, ...utf8.encode(json)]);
    final file = PlatformFile(
      name: 'profile.json',
      size: bytes.length,
      bytes: bytes,
    );

    expect(await readSubscriptionFile(file), json);
  });

  test('rejects malformed UTF-8 inside a JSON string', () async {
    final bytes = Uint8List.fromList([
      ...ascii.encode('{"name":"broken '),
      0xc3,
      0x28,
      ...ascii.encode('"}'),
    ]);
    final file = PlatformFile(
      name: 'profile.json',
      size: bytes.length,
      bytes: bytes,
    );

    await expectLater(
      readSubscriptionFile(file),
      throwsA(
        isA<SubscriptionFileReadException>().having(
          (error) => error.reason,
          'reason',
          'file is not valid UTF-8',
        ),
      ),
    );
  });

  test('keeps BOM-marked UTF-16 support for legacy subscriptions', () async {
    const content = 'vless://uuid@server.example:443?security=tls#Legacy';
    final bytes = _utf16Bytes(content, littleEndian: true);
    final file = PlatformFile(
      name: 'legacy.txt',
      size: bytes.length,
      bytes: bytes,
    );

    expect(await readSubscriptionFile(file), content);
  });

  test('rejects a UTF-16 Hydra Subscription v2 plaintext document', () async {
    const content =
        '{"api_version":"hydra.io/subscription/v2",'
        '"kind":"Subscription"}';
    final bytes = _utf16Bytes(content, littleEndian: true);
    final file = PlatformFile(
      name: 'subscription.hydra',
      size: bytes.length,
      bytes: bytes,
    );

    await expectLater(
      readSubscriptionFile(file),
      throwsA(_isHydraUtf8OnlyError),
    );
  });

  test('rejects a UTF-16 flattened Hydra JWE document', () async {
    const content =
        '{"protected":"header","iv":"nonce",'
        '"ciphertext":"payload","tag":"auth"}';
    final bytes = _utf16Bytes(content, littleEndian: false);
    final file = PlatformFile(
      name: 'subscription.jwe',
      size: bytes.length,
      bytes: bytes,
    );

    await expectLater(
      readSubscriptionFile(file),
      throwsA(_isHydraUtf8OnlyError),
    );
  });

  test('applies the 16 MiB Hydra file limit to original bytes', () async {
    const maxHydraBytes = 16 * 1024 * 1024;
    const partialJwe = '{"protected":"header"}';
    final boundaryBytes = _rightAlignedAscii(maxHydraBytes, partialJwe);
    final boundaryFile = PlatformFile(
      name: 'subscription.hydra.jwe.json',
      size: boundaryBytes.length,
      bytes: boundaryBytes,
    );
    expect(await readSubscriptionFile(boundaryFile), partialJwe);

    final oversizedBytes = _rightAlignedAscii(maxHydraBytes + 1, partialJwe);
    final underreportedFile = PlatformFile(
      name: 'subscription.hydra.json',
      size: 1,
      bytes: oversizedBytes,
    );
    await expectLater(
      readSubscriptionFile(underreportedFile),
      throwsA(
        isA<SubscriptionFileReadException>().having(
          (error) => error.reason,
          'reason',
          'Hydra subscription file is larger than 16 MiB',
        ),
      ),
    );

    final contentDetectedFile = PlatformFile(
      name: 'subscription.json',
      size: oversizedBytes.length,
      bytes: oversizedBytes,
    );
    await expectLater(
      readSubscriptionFile(contentDetectedFile),
      throwsA(
        isA<SubscriptionFileReadException>().having(
          (error) => error.reason,
          'reason',
          'Hydra subscription file is larger than 16 MiB',
        ),
      ),
    );
  });

  test('keeps generic files above the Hydra limit compatible', () async {
    const legacy = 'vless://uuid@server.example:443?security=tls#Legacy';
    final bytes = _rightAlignedAscii(16 * 1024 * 1024 + 1, legacy);
    final file = PlatformFile(
      name: 'legacy.txt',
      size: bytes.length,
      bytes: bytes,
    );

    expect(await readSubscriptionFile(file), legacy);
  });

  test('reports a picked file without readable data', () async {
    final file = PlatformFile(name: 'nodes.txt', size: 12);

    await expectLater(
      readSubscriptionFile(file),
      throwsA(isA<SubscriptionFileReadException>()),
    );
  });
}

final Matcher _isHydraUtf8OnlyError = isA<SubscriptionFileReadException>()
    .having(
      (error) => error.reason,
      'reason',
      'Hydra subscription files must use UTF-8',
    );

Uint8List _utf16Bytes(String value, {required bool littleEndian}) {
  final endian = littleEndian ? Endian.little : Endian.big;
  final data = ByteData((value.codeUnits.length + 1) * 2)
    ..setUint16(0, 0xfeff, endian);
  for (var index = 0; index < value.codeUnits.length; index++) {
    data.setUint16((index + 1) * 2, value.codeUnits[index], endian);
  }
  return data.buffer.asUint8List();
}

Uint8List _rightAlignedAscii(int length, String value) {
  final encoded = ascii.encode(value);
  return Uint8List(length)
    ..fillRange(0, length - encoded.length, 0x20)
    ..setRange(length - encoded.length, length, encoded);
}

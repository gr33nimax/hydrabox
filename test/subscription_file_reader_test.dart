import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meow_client/features/subscriptions/subscription_file_reader.dart';

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

  test('reports a picked file without readable data', () async {
    final file = PlatformFile(name: 'nodes.txt', size: 12);

    await expectLater(
      readSubscriptionFile(file),
      throwsA(isA<SubscriptionFileReadException>()),
    );
  });
}

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:hydrabox/data/local/secure_hive_storage.dart';

void main() {
  test('AES-GCM Hive cipher authenticates and round-trips frames', () {
    final cipher = HiveAesGcmCipher(List<int>.generate(32, (index) => index));
    final input = Uint8List.fromList(<int>[
      99,
      ...'secret-value'.codeUnits,
      88,
    ]);
    final first = Uint8List(cipher.maxEncryptedSize(input));
    final second = Uint8List(cipher.maxEncryptedSize(input));

    final firstLength = cipher.encrypt(input, 1, input.length - 2, first, 0);
    final secondLength = cipher.encrypt(input, 1, input.length - 2, second, 0);
    expect(firstLength, secondLength);
    expect(
      first.sublist(0, firstLength),
      isNot(equals(second.sublist(0, secondLength))),
    );

    final output = Uint8List(input.length + 4);
    final plaintextLength = cipher.decrypt(first, 0, firstLength, output, 2);
    expect(
      output.sublist(2, 2 + plaintextLength),
      equals('secret-value'.codeUnits),
    );

    first[firstLength - 1] ^= 1;
    expect(
      () => cipher.decrypt(first, 0, firstLength, output, 0),
      throwsA(anything),
    );
  });

  test('encrypted Hive box does not persist a plaintext secret', () async {
    final directory = await Directory.systemTemp.createTemp('hydrabox-gcm-');
    addTearDown(() async {
      await Hive.close();
      if (directory.existsSync()) await directory.delete(recursive: true);
    });
    Hive.init(directory.path);
    final key = List<int>.generate(32, (index) => 255 - index);
    final box = await Hive.openBox<String>(
      'secrets',
      encryptionCipher: HiveAesGcmCipher(key),
    );
    await box.put('subscription', 'vless://private-credential@example.com');
    await box.flush();
    await box.close();

    final bytes = await File('${directory.path}/secrets.hive').readAsBytes();
    expect(String.fromCharCodes(bytes), isNot(contains('private-credential')));

    final reopened = await Hive.openBox<String>(
      'secrets',
      encryptionCipher: HiveAesGcmCipher(key),
    );
    expect(
      reopened.get('subscription'),
      'vless://private-credential@example.com',
    );
  });
}

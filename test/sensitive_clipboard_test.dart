import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hydrabox/core/security/sensitive_clipboard.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late String clipboard;

  setUp(() {
    clipboard = '';
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          switch (call.method) {
            case 'Clipboard.setData':
              clipboard = (call.arguments as Map)['text']?.toString() ?? '';
              return null;
            case 'Clipboard.getData':
              return <String, dynamic>{'text': clipboard};
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  test('clears a copied secret after its lifetime', () async {
    await SensitiveClipboard.copy(
      'subscription-token',
      clearAfter: const Duration(milliseconds: 10),
    );
    expect(clipboard, 'subscription-token');

    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(clipboard, isEmpty);
  });

  test('does not erase clipboard content copied by the user later', () async {
    await SensitiveClipboard.copy(
      'proxy-password',
      clearAfter: const Duration(milliseconds: 10),
    );
    clipboard = 'unrelated text';

    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(clipboard, 'unrelated text');
  });
}

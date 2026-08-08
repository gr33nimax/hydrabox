import 'package:flutter_test/flutter_test.dart';
import 'package:hydrabox/logging/app_log_store.dart';

void main() {
  group('AppLogStore', () {
    tearDown(AppLogStore.clear);

    test('logs sing-box config summary without secrets', () {
      AppLogStore.config('test', {
        'inbounds': [
          {'type': 'tun', 'tag': 'tun-in'},
        ],
        'outbounds': [
          {
            'type': 'vless',
            'tag': 'secret-tag',
            'server': 'secret.example',
            'uuid': '11111111-1111-1111-1111-111111111111',
            'password': 'super-secret',
            'tls': {
              'server_name': 'hidden.example',
              'reality': {'public_key': 'secret-public-key'},
            },
          },
        ],
        'route': {
          'rules': [
            {'outbound': 'secret-tag'},
          ],
        },
      });

      final dump = AppLogStore.dump();
      expect(dump, contains('config summary: 1 outbounds'));
      expect(dump, contains('vless=1'));
      expect(dump, isNot(contains('secret-tag')));
      expect(dump, isNot(contains('secret.example')));
      expect(dump, isNot(contains('11111111-1111-1111-1111-111111111111')));
      expect(dump, isNot(contains('super-secret')));
      expect(dump, isNot(contains('hidden.example')));
      expect(dump, isNot(contains('secret-public-key')));
    });

    test('redacts secrets before logs are stored and exported', () {
      AppLogStore.info(
        'subscription',
        'vless://11111111-1111-4111-8111-111111111111@example.com:443'
            '?token=super-secret&uuid=11111111-1111-4111-8111-111111111111 '
            'https://api.example/private/subscription/path?token=super-secret '
            '"password":"plain" Authorization: BearerToken X-HWID=device-id',
      );

      final dump = AppLogStore.dump();
      expect(dump, contains('vless://<redacted>'));
      expect(dump, contains('https://api.example/<redacted>'));
      expect(dump, contains('"password":"<redacted>"'));
      expect(dump, contains('Authorization=<redacted>'));
      expect(dump, isNot(contains('super-secret')));
      expect(dump, isNot(contains('BearerToken')));
      expect(dump, isNot(contains('device-id')));
      expect(dump, isNot(contains('private/subscription/path')));
      expect(dump, isNot(contains('11111111-1111-4111-8111-111111111111')));
    });
  });
}

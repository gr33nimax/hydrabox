import 'package:flutter_test/flutter_test.dart';
import 'package:meow_client/app/deep_link_import.dart';

void main() {
  group('DeepLinkImportRequest.fromPayload', () {
    test('keeps ordinary subscription urls unchanged', () {
      final request = DeepLinkImportRequest.fromPayload({
        'url': 'https://example.com/subscription',
        'name': 'Example',
        'scheme': 'meowvpn',
      });

      expect(request, isNotNull);
      expect(request!.url, 'https://example.com/subscription');
      expect(request.name, 'Example');
      expect(request.scheme, 'meowvpn');
      expect(request.sourceType, DeepLinkImportSource.etonifyImport);
    });

    test(
      'accepts the HydraBox import scheme without removing legacy aliases',
      () {
        final request = DeepLinkImportRequest.fromPayload({
          'url': 'https://example.com/hydrabox-subscription',
          'name': 'HydraBox example',
          'scheme': 'hydrabox',
        });

        expect(request, isNotNull);
        expect(request!.url, 'https://example.com/hydrabox-subscription');
        expect(request.name, 'HydraBox example');
        expect(request.scheme, 'hydrabox');
        expect(request.sourceType, DeepLinkImportSource.etonifyImport);
      },
    );

    test('normalizes happ add links without explicit scheme', () {
      final request = DeepLinkImportRequest.fromPayload({
        'url': 'happ://add/google.com',
        'scheme': 'happ',
      });

      expect(request, isNotNull);
      expect(request!.url, 'https://google.com');
      expect(request.sourceType, DeepLinkImportSource.happAdd);
      expect(request.isHapp, isTrue);
    });

    test('normalizes happ add links with embedded https url', () {
      final request = DeepLinkImportRequest.fromPayload({
        'url': 'happ://add/https://example.com/subscription',
        'scheme': 'happ',
      });

      expect(request, isNotNull);
      expect(request!.url, 'https://example.com/subscription');
      expect(request.sourceType, DeepLinkImportSource.happAdd);
    });

    test('normalizes happ add links with url query parameter', () {
      final request = DeepLinkImportRequest.fromPayload({
        'url': 'happ://add?url=https://example.com/subscription',
        'scheme': 'happ',
      });

      expect(request, isNotNull);
      expect(request!.url, 'https://example.com/subscription');
      expect(request.sourceType, DeepLinkImportSource.happAdd);
    });

    test('preserves non-add happ links for crypto import flow', () {
      final request = DeepLinkImportRequest.fromPayload({
        'url': 'happ://crypt5/encrypted-payload',
        'scheme': 'happ',
      });

      expect(request, isNotNull);
      expect(request!.url, 'happ://crypt5/encrypted-payload');
      expect(request.sourceType, DeepLinkImportSource.happCrypto);
      expect(request.isHapp, isTrue);
    });

    test('preserves happ crypt4 links for crypto import flow', () {
      final request = DeepLinkImportRequest.fromPayload({
        'url': 'happ://crypt4/encrypted-payload',
        'scheme': 'happ',
      });

      expect(request, isNotNull);
      expect(request!.url, 'happ://crypt4/encrypted-payload');
      expect(request.sourceType, DeepLinkImportSource.happCrypto);
    });

    test('normalizes sing-box remote profile import links', () {
      final request = DeepLinkImportRequest.fromPayload({
        'url':
            'sing-box://import-remote-profile/?url=https://example.com/sub.json',
        'scheme': 'sing-box',
      });

      expect(request, isNotNull);
      expect(request!.url, 'https://example.com/sub.json');
      expect(request.sourceType, DeepLinkImportSource.singBoxRemoteProfile);
    });

    test('keeps remaining query parameters on happ add links', () {
      final request = DeepLinkImportRequest.fromPayload({
        'url': 'happ://add/sub.example.com/list?token=abc&name=Demo',
        'name': 'Demo',
        'scheme': 'happ',
      });

      expect(request, isNotNull);
      expect(request!.url, 'https://sub.example.com/list?token=abc');
      expect(request.name, 'Demo');
    });
  });
}

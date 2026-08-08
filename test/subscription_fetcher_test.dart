import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hydrabox/data/subscription/hydra_subscription_uri.dart';
import 'package:hydrabox/data/subscription/subscription_fetcher.dart';

void main() {
  const key = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';

  group('Hydra Subscription URI policy', () {
    test('extracts one exact key and strips the complete fragment', () {
      final uri = Uri.parse(
        'https://provider.example/subscription#hydra-key=$key',
      );

      expect(HydraSubscriptionUri.hasKeyFragment(uri), isTrue);
      expect(HydraSubscriptionUri.keyFromUri(uri), key);
      expect(
        HydraSubscriptionUri.withoutSecretFragment(uri).toString(),
        'https://provider.example/subscription',
      );
    });

    test('invalid, missing, and duplicate key values fail closed', () {
      for (final value in <String>[
        'https://provider.example/subscription#hydra-key=',
        'https://provider.example/subscription#hydra-key=short',
        'https://provider.example/subscription#hydra-key=$key&hydra-key=$key',
        'https://provider.example/subscription#hydra-key=%20$key',
      ]) {
        final uri = Uri.parse(value);
        expect(HydraSubscriptionUri.hasKeyFragment(uri), isTrue);
        expect(HydraSubscriptionUri.keyFromUri(uri), isNull, reason: value);
      }
    });

    test('detects literal and encoded hydra-key query names', () {
      expect(
        HydraSubscriptionUri.hasKeyQueryParameter(
          Uri.parse('https://provider.example/subscription?hydra-key=$key'),
        ),
        isTrue,
      );
      expect(
        HydraSubscriptionUri.hasKeyQueryParameter(
          Uri.parse('https://provider.example/subscription?hydra%2Dkey=$key'),
        ),
        isTrue,
      );
    });

    test(
      'key-bearing fetch is rejected before non-HTTPS network access',
      () async {
        await expectLater(
          SubscriptionFetcher.fetch(
            'http://127.0.0.1/subscription#hydra-key=$key',
          ),
          throwsA(isA<HttpException>()),
        );
      },
    );

    test('key in query is rejected before network access', () async {
      await expectLater(
        SubscriptionFetcher.fetch(
          'https://provider.invalid/subscription?hydra-key=$key',
        ),
        throwsFormatException,
      );
    });
  });

  group('request security', () {
    test('remote plaintext subscriptions require HTTPS', () {
      expect(
        () => SubscriptionFetcher.validateRequestSecurityForTest(
          Uri.parse('http://provider.example/subscription'),
          const {},
        ),
        throwsA(isA<HttpException>()),
      );
      expect(
        () => SubscriptionFetcher.validateRequestSecurityForTest(
          Uri.parse('https://provider.example/subscription'),
          const {},
        ),
        returnsNormally,
      );
    });

    test('loopback HTTP refuses sensitive headers and query parameters', () {
      expect(
        () => SubscriptionFetcher.validateRequestSecurityForTest(
          Uri.parse('http://127.0.0.1/subscription'),
          const {'Authorization': 'Bearer secret'},
        ),
        throwsA(isA<HttpException>()),
      );
      expect(
        () => SubscriptionFetcher.validateRequestSecurityForTest(
          Uri.parse('http://127.0.0.1/subscription?token=secret'),
          const {},
        ),
        throwsA(isA<HttpException>()),
      );
    });

    test(
      'cross-origin redirects keep only non-sensitive negotiation headers',
      () {
        final redirected =
            SubscriptionFetcher.headersForCrossOriginRedirectForTest({
              'User-Agent': 'HydraBox/test',
              'Accept': 'application/vnd.hydra.subscription+json',
              'Authorization': 'Bearer secret',
              'Cookie': 'secret=1',
              'X-HWID': 'device',
            });

        expect(redirected, {
          'User-Agent': 'HydraBox/test',
          'Accept': 'application/vnd.hydra.subscription+json',
        });
      },
    );

    test('Unicode HTTPS hosts are normalized without leaking fragments', () {
      final uri = SubscriptionFetcher.parseRequestUriForTest(
        'https://пример.рф/subscription#hydra-key=$key',
      );
      final requestUri = HydraSubscriptionUri.withoutSecretFragment(uri);

      expect(requestUri.scheme, 'https');
      expect(requestUri.host, isNotEmpty);
      expect(requestUri.hasFragment, isFalse);
      expect(requestUri.toString(), isNot(contains(key)));
    });
  });
}

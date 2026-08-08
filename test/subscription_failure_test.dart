import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hydrabox/data/subscription/happ_crypto_link.dart';
import 'package:hydrabox/data/subscription/subscription_failure.dart';
import 'package:hydrabox/features/subscriptions/subscription_error_message.dart';
import 'package:hydrabox/l10n/generated/app_localizations_en.dart';
import 'package:hydrabox/l10n/generated/app_localizations_ru.dart';

void main() {
  group('classifySubscriptionFailure', () {
    test('keeps the HTTP status for a provider response', () {
      final failure = classifySubscriptionFailure(
        SubscriptionHttpStatusException(502),
      );

      expect(failure.kind, SubscriptionFailureKind.httpStatus);
      expect(failure.httpStatus, 502);
    });

    test('distinguishes common network failures', () {
      expect(
        classifySubscriptionFailure(
          const SocketException('Failed host lookup: provider.example'),
        ).kind,
        SubscriptionFailureKind.dns,
      );
      expect(
        classifySubscriptionFailure(
          const SocketException('Connection refused'),
        ).kind,
        SubscriptionFailureKind.connection,
      );
      expect(
        classifySubscriptionFailure(
          const HandshakeException('CERTIFICATE_VERIFY_FAILED'),
        ).kind,
        SubscriptionFailureKind.tls,
      );
      expect(
        classifySubscriptionFailure(
          TimeoutException('subscription import timed out'),
        ).kind,
        SubscriptionFailureKind.timeout,
      );
    });

    test('distinguishes content and Happ failures', () {
      expect(
        classifySubscriptionFailure(
          const SubscriptionContentException(
            SubscriptionContentFailureKind.emptyResponse,
          ),
        ).kind,
        SubscriptionFailureKind.emptyResponse,
      );
      expect(
        classifySubscriptionFailure(StateError('No usable proxies found')).kind,
        SubscriptionFailureKind.noUsableProxies,
      );
      expect(
        classifySubscriptionFailure(
          const UnsupportedHappCryptoLinkException('unsupported'),
        ).kind,
        SubscriptionFailureKind.happUnsupported,
      );
      expect(
        classifySubscriptionFailure(
          const HappCryptoLinkException('decrypt failed'),
        ).kind,
        SubscriptionFailureKind.happInvalid,
      );
    });

    test('recognizes legacy exception messages without exposing them', () {
      expect(
        classifySubscriptionFailure(
          const HttpException('Subscription server returned 403'),
        ).httpStatus,
        403,
      );
      expect(
        classifySubscriptionFailure(
          const HttpException(
            'Sensitive subscription credentials require HTTPS',
          ),
        ).kind,
        SubscriptionFailureKind.credentialsRequireHttps,
      );
    });

    test('keeps only safe HydraCore diagnostics', () {
      final error = HydraSubscriptionValidationException(
        operation: 'JWE validation',
        code: 'native_config_invalid',
        path: r'$.resources[2].document',
      );
      final failure = classifySubscriptionFailure(error);

      expect(failure.kind, SubscriptionFailureKind.invalidContent);
      expect(
        failure.diagnostic,
        r'JWE validation: native_config_invalid at $.resources[2].document',
      );

      final unsafe = HydraSubscriptionValidationException(
        operation: 'validation\nsecret',
        code: 'invalid\nsecret',
        path: r'$.resources[0].document["password"]',
      );
      expect(unsafe.diagnostic, r'validation: invalid at $');
    });
  });

  group('subscriptionErrorMessage', () {
    test('explains HTTP 502 in both supported languages', () {
      final error = SubscriptionHttpStatusException(502);

      expect(
        subscriptionErrorMessage(error, AppLocalizationsEn()),
        contains('HTTP 502'),
      );
      expect(
        subscriptionErrorMessage(error, AppLocalizationsRu()),
        allOf(contains('HTTP 502'), contains('провайдер')),
      );
    });

    test('saved placeholder warning includes the actual reason', () {
      final message = subscriptionSavedWarningMessage(
        const SubscriptionContentException(
          SubscriptionContentFailureKind.emptyResponse,
        ),
        AppLocalizationsRu(),
      );

      expect(message, contains('Подписка сохранена без серверов'));
      expect(message, contains('пустой ответ'));
    });

    test('unknown errors do not expose raw exception text', () {
      const secret = 'vless://uuid-secret@example.com';
      final message = subscriptionErrorMessage(
        Exception(secret),
        AppLocalizationsEn(),
      );

      expect(message, isNot(contains(secret)));
      expect(message, contains('Diagnostics'));
    });

    test('shows a safe HydraCore code and path', () {
      final message = subscriptionErrorMessage(
        HydraSubscriptionValidationException(
          operation: 'JWE validation',
          code: 'native_config_invalid',
          path: r'$.resources[1].document',
        ),
        AppLocalizationsRu(),
      );

      expect(message, contains('HydraCore'));
      expect(message, contains('native_config_invalid'));
      expect(message, contains(r'$.resources[1].document'));
    });
  });
}

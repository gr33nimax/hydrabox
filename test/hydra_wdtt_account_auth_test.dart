import 'package:flutter_test/flutter_test.dart';
import 'package:meow_client/models/subscription.dart';
import 'package:meow_client/singbox/hydra_wdtt_account_auth.dart';

void main() {
  const credentialRef =
      'hwdtt1_AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';

  Subscription subscription({String auth = 'auto'}) => Subscription(
    id: 'subscription',
    name: 'Hydra',
    url: 'https://hydra.example/sub',
    nativeConfig: {
      'endpoints': [
        {
          'type': 'wdtt',
          'tag': 'wdtt-main',
          'credential_ref': credentialRef,
          'vk_hashes': ['abcdefgh1234'],
          'vk_auth': auth,
        },
      ],
    },
    wdttCredentials: const [
      HydraBoxWdttCredential(
        credentialRef: credentialRef,
        deviceId: 'device',
        deviceGrant: 'grant',
      ),
    ],
  );

  test('selects an account challenge only from a bound WDTT endpoint', () {
    final challenge = findHydraWdttAccountChallenge(subscription());

    expect(challenge?.credentialRef, credentialRef);
    expect(challenge?.hash, 'abcdefgh1234');
    expect(
      findHydraWdttAccountChallenge(subscription(auth: 'anonymous')),
      isNull,
    );
  });

  test('selects the credential_ref named by HydraCore', () {
    final selected = findHydraWdttAccountChallenge(
      subscription(),
      error:
          '$hydraWdttAccountCredentialsRequiredMessage '
          'for credential_ref "$credentialRef"',
    );
    final unknown = findHydraWdttAccountChallenge(
      subscription(),
      error:
          '$hydraWdttAccountCredentialsRequiredMessage '
          'for credential_ref "wdtt:other"',
    );

    expect(selected?.credentialRef, credentialRef);
    expect(unknown, isNull);
  });

  test('recognizes stable HydraCore account and captcha errors', () {
    expect(
      isHydraWdttAccountCredentialError(
        'endpoint: $hydraWdttAccountCredentialsRequiredMessage',
      ),
      isTrue,
    );
    expect(
      isHydraWdttAccountCredentialError(hydraWdttCaptchaRequiredMessage),
      isTrue,
    );
    expect(isHydraWdttAccountCredentialError('network unreachable'), isFalse);
  });
}

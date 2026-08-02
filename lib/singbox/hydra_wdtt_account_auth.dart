import 'package:meow_client/models/subscription.dart';

const hydraWdttAccountCredentialsRequiredMessage =
    'HydraBox VK WebView credentials are required';
const hydraWdttCaptchaRequiredMessage =
    'VK anonymous call authentication requires captcha';

class HydraWdttAccountChallenge {
  const HydraWdttAccountChallenge({
    required this.credentialRef,
    required this.hash,
  });

  final String credentialRef;
  final String hash;
}

bool isHydraWdttAccountCredentialError(String? error) {
  final message = error ?? '';
  return message.contains(hydraWdttAccountCredentialsRequiredMessage) ||
      message.contains(hydraWdttCaptchaRequiredMessage);
}

HydraWdttAccountChallenge? findHydraWdttAccountChallenge(
  Subscription? subscription,
) {
  if (subscription == null || subscription.wdttCredentials.isEmpty) {
    return null;
  }
  final allowedRefs = subscription.wdttCredentials
      .map((credential) => credential.credentialRef)
      .toSet();
  final endpoints = subscription.nativeConfig?['endpoints'];
  if (endpoints is! List) return null;

  for (final rawEndpoint in endpoints) {
    if (rawEndpoint is! Map) continue;
    final endpoint = Map<String, dynamic>.from(rawEndpoint);
    if (endpoint['type']?.toString().trim().toLowerCase() != 'wdtt') {
      continue;
    }
    final auth = endpoint['vk_auth']?.toString().trim().toLowerCase() ?? '';
    if (auth != 'auto' && auth != 'account') continue;
    final credentialRef = endpoint['credential_ref']?.toString().trim() ?? '';
    if (!allowedRefs.contains(credentialRef)) continue;
    final hashes = endpoint['vk_hashes'];
    if (hashes is! List) continue;
    for (final rawHash in hashes) {
      final hash = rawHash?.toString().trim() ?? '';
      if (hash.isNotEmpty) {
        return HydraWdttAccountChallenge(
          credentialRef: credentialRef,
          hash: hash,
        );
      }
    }
  }
  return null;
}

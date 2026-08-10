import 'dart:convert';

import 'package:crypto/crypto.dart';

/// App-owned identity for one Hydra Subscription v2 profile/resource pair.
///
/// Native sing-box tags are scoped to a single resource document and may be
/// repeated by every resource (for example, every entrypoint may be `proxy`).
/// They therefore cannot be used as keys in HydraBox selection or latency
/// caches. The reserved prefix also guarantees that this projection cannot be
/// confused with a provider-authored native tag.
class HydraProfileIdentity {
  HydraProfileIdentity._();

  static const runtimeTagPrefix = '__hydra.profile.';

  static String runtimeTag({
    required String profileId,
    required String resourceId,
  }) {
    final profile = profileId.trim();
    final resource = resourceId.trim();
    if (profile.isEmpty || resource.isEmpty) {
      return '';
    }
    // JSON array framing is unambiguous even if a future provider allows
    // control characters inside an identifier.
    final digest = sha256.convert(
      utf8.encode(jsonEncode(<String>[resource, profile])),
    );
    // 128 bits keeps the runtime tag compact while making accidental
    // collisions across profile/resource pairs computationally negligible.
    return '$runtimeTagPrefix${digest.toString().substring(0, 32)}';
  }

  static bool isRuntimeTag(String value) =>
      value.trim().startsWith(runtimeTagPrefix);
}

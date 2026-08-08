/// URL handling for encrypted Hydra Subscription v2 sources.
///
/// Cryptography and JWE validation belong exclusively to HydraCore. The client
/// only extracts the out-of-band base64url key from `#hydra-key=...` and strips
/// the fragment before issuing an HTTP request.
class HydraSubscriptionUri {
  HydraSubscriptionUri._();

  static const plaintextMediaType = 'application/vnd.hydra.subscription+json';
  static const encryptedMediaType = 'application/jose+json';
  static const keyFragmentName = 'hydra-key';

  static String? keyFromUri(Uri uri) {
    final values = _rawKeyFragmentValues(uri);
    if (values.length != 1) return null;
    try {
      final value = Uri.decodeQueryComponent(values.single);
      if (value.isEmpty ||
          value != value.trim() ||
          !RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(value)) {
        return null;
      }
      return value;
    } on FormatException {
      return null;
    }
  }

  static bool hasKeyFragment(Uri uri) => _rawKeyFragmentValues(uri).isNotEmpty;

  static bool hasKeyQueryParameter(Uri uri) {
    if (!uri.hasQuery) return false;
    for (final member in uri.query.split(RegExp(r'[&;]'))) {
      final separator = member.indexOf('=');
      final rawName = separator < 0 ? member : member.substring(0, separator);
      String name;
      try {
        name = Uri.decodeQueryComponent(rawName);
      } on FormatException {
        name = rawName;
      }
      if (name.toLowerCase() == keyFragmentName) return true;
    }
    return false;
  }

  static Uri withoutSecretFragment(Uri uri) {
    if (!uri.hasFragment) return uri;
    final serialized = uri.toString();
    return Uri.parse(serialized.substring(0, serialized.indexOf('#')));
  }

  static List<String> _rawKeyFragmentValues(Uri uri) {
    final fragment = uri.fragment;
    if (fragment.isEmpty) return const [];
    final values = <String>[];
    for (final member in fragment.split('&')) {
      final separator = member.indexOf('=');
      final rawName = separator < 0 ? member : member.substring(0, separator);
      String name;
      try {
        name = Uri.decodeQueryComponent(rawName);
      } on FormatException {
        name = rawName;
      }
      if (name != keyFragmentName) continue;
      values.add(separator < 0 ? '' : member.substring(separator + 1));
    }
    return values;
  }
}

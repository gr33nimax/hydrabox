/// Runtime validity policy for Hydra Subscription v2 documents.
///
/// Import-time validation alone is insufficient: a valid stored subscription
/// may expire while the application is running. Activation paths must invoke
/// this policy again immediately before building the core configuration.
class HydraSubscriptionTimePolicy {
  const HydraSubscriptionTimePolicy._();

  static const allowedClockSkew = Duration(minutes: 5);

  static void validate(Map<String, dynamic> metadata, {DateTime? now}) {
    final currentTime = (now ?? DateTime.now()).toUtc();
    final issuedAt = _parseRequiredTimestamp(
      metadata['issued_at'],
      field: 'issued_at',
    );
    final notBefore =
        _parseOptionalTimestamp(metadata['not_before'], field: 'not_before') ??
        issuedAt;
    final expiresAt = _parseOptionalTimestamp(
      metadata['expires_at'],
      field: 'expires_at',
    );
    if (notBefore.isBefore(issuedAt.subtract(const Duration(minutes: 10)))) {
      throw const FormatException('not_before is earlier than issued_at');
    }
    if (expiresAt != null && !expiresAt.isAfter(notBefore)) {
      throw const FormatException('expires_at must be after not_before');
    }
    if (currentTime.isBefore(notBefore.subtract(allowedClockSkew))) {
      throw const FormatException('Hydra subscription is not valid yet');
    }
    if (expiresAt != null &&
        !currentTime.isBefore(expiresAt.add(allowedClockSkew))) {
      throw const FormatException('Hydra subscription has expired');
    }
  }

  static DateTime _parseRequiredTimestamp(
    dynamic value, {
    required String field,
  }) {
    final parsed = _parseOptionalTimestamp(value, field: field);
    if (parsed == null) {
      throw FormatException('Hydra $field timestamp is required');
    }
    return parsed;
  }

  static DateTime? _parseOptionalTimestamp(
    dynamic value, {
    required String field,
  }) {
    if (value == null) {
      return null;
    }
    final raw = value.toString();
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) {
      throw FormatException('Hydra $field timestamp is invalid');
    }
    return parsed.toUtc();
  }
}

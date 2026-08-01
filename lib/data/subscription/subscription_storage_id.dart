const subscriptionStorageSchemaVersionKey =
    '__etonify_storage_schema_version__';
const subscriptionPayloadGenerationSeparator = '::payload::';
const maxSubscriptionStorageIdLength = 128;

final RegExp _subscriptionStorageIdPattern = RegExp(
  r'^[A-Za-z0-9][A-Za-z0-9._-]*$',
);

/// Whether [value] is safe to use as a subscription metadata/payload key.
///
/// IDs are an internal storage namespace, not publisher-controlled labels.
/// Keeping it narrow prevents collisions with schema markers and immutable
/// payload-generation keys when importing untrusted backup data.
bool isSafeSubscriptionStorageId(String value) {
  return value.isNotEmpty &&
      value.length <= maxSubscriptionStorageIdLength &&
      value != subscriptionStorageSchemaVersionKey &&
      !value.contains(subscriptionPayloadGenerationSeparator) &&
      _subscriptionStorageIdPattern.hasMatch(value);
}

void validateSubscriptionStorageId(String value) {
  if (!isSafeSubscriptionStorageId(value)) {
    throw const FormatException('Invalid subscription storage ID');
  }
}

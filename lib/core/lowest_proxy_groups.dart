const String lowestProxyTag = 'lowest';
const String lowestOpenProxyTag = 'lowest-open';
const String lowestFreeProxyTag = 'lowest-free';
const String mixedProxyTag = 'mixed';

const List<String> lowestProxyTags = <String>[
  lowestProxyTag,
  lowestOpenProxyTag,
  lowestFreeProxyTag,
];

const List<String> baseLowestProxyTags = <String>[lowestProxyTag];

const List<String> pinnedProxyTags = <String>[
  lowestProxyTag,
  lowestOpenProxyTag,
  lowestFreeProxyTag,
  mixedProxyTag,
];

const Set<String> reservedProxyTags = <String>{
  'select',
  'direct',
  mixedProxyTag,
  lowestProxyTag,
  lowestOpenProxyTag,
  lowestFreeProxyTag,
};

const Set<String> _openExcludedCountryCodes = <String>{
  'RU',
  'IR',
  'IQ',
  'CN',
  'TM',
};

const Set<String> _cisCountryCodes = <String>{
  'AM',
  'AZ',
  'BY',
  'KZ',
  'KG',
  'MD',
  'TJ',
  'UZ',
};

bool isLowestProxyTag(String tag) => lowestProxyTags.contains(tag);

bool isMixedProxyTag(String tag) => tag == mixedProxyTag;

bool isSyntheticProxyTag(String tag) =>
    isLowestProxyTag(tag) || isMixedProxyTag(tag);

bool isPinnedProxyTag(String tag) => pinnedProxyTags.contains(tag);

bool isReservedProxyTag(String tag) => reservedProxyTags.contains(tag);

List<String> activeLowestProxyTags({required bool russiaRouteDataEnabled}) =>
    russiaRouteDataEnabled ? lowestProxyTags : baseLowestProxyTags;

int lowestProxyTagOrder(String tag) {
  final index = lowestProxyTags.indexOf(tag);
  return index < 0 ? 1 << 30 : index;
}

int pinnedProxyTagOrder(String tag) {
  final index = pinnedProxyTags.indexOf(tag);
  return index < 0 ? 1 << 30 : index;
}

String lowestProxyBaseLabel(String tag) {
  return switch (tag) {
    lowestOpenProxyTag => 'lowest · open',
    lowestFreeProxyTag => 'lowest · free',
    _ => 'lowest',
  };
}

String lowestProxyDisplayName(String tag, [String? selectedName]) {
  final label = lowestProxyBaseLabel(tag);
  final selected = selectedName?.trim() ?? '';
  return selected.isEmpty ? label : '$label · $selected';
}

String normalizeLowestCountryCode(String? countryCode) {
  final normalized = countryCode?.trim().toUpperCase() ?? '';
  return RegExp(r'^[A-Z]{2}$').hasMatch(normalized) ? normalized : '';
}

bool lowestProxyAllowsCountry(String tag, String? countryCode) {
  if (tag == lowestProxyTag) {
    return true;
  }
  final normalized = normalizeLowestCountryCode(countryCode);
  if (normalized.isEmpty) {
    return true;
  }
  if (_openExcludedCountryCodes.contains(normalized)) {
    return false;
  }
  if (tag == lowestFreeProxyTag && _cisCountryCodes.contains(normalized)) {
    return false;
  }
  return true;
}

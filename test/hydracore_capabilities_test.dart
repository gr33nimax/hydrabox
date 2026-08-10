import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hydrabox/singbox/hydracore_capabilities.dart';

void main() {
  test('strictly parses the pinned HydraCore API v2 capability shape', () {
    final capabilities = HydraCoreCapabilities.parseStrict(
      jsonEncode(_capabilities()),
    );

    expect(capabilities.apiVersion, 2);
    expect(capabilities.coreId, 'io.hydrabox.hydracore');
    expect(capabilities.coreVersion, 'v1.13.16-extended-hydracore.5');
    expect(capabilities.supportsCallVkMultiUser, isTrue);
    expect(capabilities.callModes, {'p2p', 'multi_user'});
    expect(capabilities.validationProfiles, {'local', 'remote_v2'});
    expect(capabilities.subscriptionContracts, {2});
    expect(capabilities.remoteSafeInboundTypes, {'call'});
    expect(capabilities.remoteSafeEndpointTypes, {'wireguard'});
    expect(capabilities.minimumEventIntervalMillis, 250);
    expect(capabilities.maximumEventIntervalMillis, 30000);
    expect(capabilities.retainedUrlTestSessions, 64);
    expect(capabilities.isCompatibleRelease, isTrue);
  });

  test('missing runtime and subscription features fail closed', () {
    for (final feature in <String>[
      'runtime_snapshot',
      'runtime_events',
      'managed_url_test_sessions',
      'subscription_jwe',
      'call',
      'call_vk_multi_user',
    ]) {
      final document = _capabilities();
      (document['features'] as Map<String, dynamic>)[feature] = false;
      expect(
        () => HydraCoreCapabilities.parseStrict(jsonEncode(document)),
        throwsFormatException,
        reason: feature,
      );
    }
  });

  test('legacy, malformed, or incomplete contracts fail closed', () {
    expect(() => HydraCoreCapabilities.parseStrict(''), throwsFormatException);
    expect(
      () => HydraCoreCapabilities.parseStrict('{not-json'),
      throwsFormatException,
    );

    final wrongApi = _capabilities()..['api_version'] = 1;
    expect(
      () => HydraCoreCapabilities.parseStrict(jsonEncode(wrongApi)),
      throwsFormatException,
    );

    final missingRuntime = _capabilities()..remove('runtime');
    expect(
      () => HydraCoreCapabilities.parseStrict(jsonEncode(missingRuntime)),
      throwsFormatException,
    );
  });
}

Map<String, dynamic> _capabilities() => {
  'api_version': 2,
  'identity': {
    'core_id': 'io.hydrabox.hydracore',
    'core_name': 'HydraCore',
    'core_version': 'v1.13.16-extended-hydracore.5',
  },
  'features': {
    'targeted_url_test': true,
    'preconnect_url_test': true,
    'group_url_test_sessions': true,
    'structured_probe_errors': true,
    'outbound_external_info': true,
    'outbound_external_info_fallback': true,
    'config_validation': true,
    'runtime_snapshot': true,
    'runtime_events': true,
    'managed_url_test_sessions': true,
    'subscription_jwe': true,
    'xhttp': true,
    'vless_encryption': true,
    'rmux': true,
    'call': true,
    'call_vk_multi_user': true,
    'amnezia_version': 3,
  },
  'protocols': {
    'inbounds': ['call'],
    'outbounds': [
      'socks',
      'http',
      'vmess',
      'trojan',
      'naive',
      'shadowtls',
      'vless',
      'mieru',
      'anytls',
      'trusttunnel',
      'hysteria',
      'hysteria2',
      'tuic',
      'sudoku',
      'snell',
      'call',
    ],
    'endpoints': ['wireguard'],
    'call_platforms': ['dion', 'telemost', 'vk', 'wbstream'],
    'call_modes': ['p2p', 'multi_user'],
  },
  'tun_stacks': ['system', 'gvisor', 'mixed'],
  'xhttp_modes': ['packet-up', 'stream-up', 'stream-one'],
  'vless_encryption_modes': [
    '1rtt',
    '0rtt',
    'native',
    'xorpub',
    'random',
    'x25519',
    'mlkem768',
  ],
  'validation_profiles': ['local', 'remote_v2'],
  'subscription_contracts': [2],
  'subscription_media_types': [
    'application/vnd.hydra.subscription+json',
    'application/jose+json',
  ],
  'remote_policy': {
    'version': 2,
    'safe_top_level_fields': [r'$schema', 'inbounds', 'outbounds', 'endpoints'],
    'safe_inbound_types': ['call'],
    'safe_outbound_types': [
      'socks',
      'http',
      'vmess',
      'trojan',
      'naive',
      'shadowtls',
      'vless',
      'mieru',
      'anytls',
      'trusttunnel',
      'hysteria',
      'hysteria2',
      'tuic',
      'sudoku',
      'snell',
      'call',
    ],
    'safe_endpoint_types': ['wireguard'],
    'safe_dns_server_types': <String>[],
    'safe_provider_types': <String>[],
    'reserved_tag_prefixes': ['__hydra.'],
  },
  'runtime': {
    'version': 1,
    'snapshot_schema_version': 1,
    'minimum_event_interval_millis': 250,
    'maximum_event_interval_millis': 30000,
    'retained_url_test_sessions': 64,
  },
};

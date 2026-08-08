import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hydrabox/data/subscription/parsers/hydra_subscription_parser.dart';
import 'package:hydrabox/data/subscription/subscription_parser.dart';

void main() {
  test('valid v2 subscription is accepted with automatic permissions', () {
    final parsed = SubscriptionParser.parse(jsonEncode(_document()));

    expect(parsed.format, SubscriptionFormat.hydraV2);
    expect(
      parsed.sourceMetadata['api_version'],
      HydraSubscriptionParser.apiVersion,
    );
    expect(parsed.sourceMetadata['permissions_automatic'], isTrue);
    expect(parsed.sourceMetadata['permissions'], {
      'resource-main': ['network.outbound'],
    });
    expect(parsed.defaultProfileId, 'profile-main');
    expect(parsed.profiles.single.resourceId, 'resource-main');
    expect(parsed.resourceConfigs.keys, {'resource-main'});
    expect(parsed.nativeConfig?['outbounds'], hasLength(1));
  });

  test('resources stay independent even when native tags are equal', () {
    final document = _document();
    (document['resources'] as List<dynamic>).add({
      'id': 'resource-backup',
      'format': 'sing-box-json',
      'requested_permissions': ['network.outbound'],
      'document': {
        'outbounds': [
          {
            'type': 'trojan',
            'tag': 'proxy',
            'server': 'backup.example',
            'server_port': 443,
            'password': 'backup-secret',
          },
        ],
      },
    });
    (document['profiles'] as List<dynamic>).add({
      'id': 'profile-backup',
      'resource': 'resource-backup',
      'name': 'Backup',
      'entrypoint': {'section': 'outbounds', 'tag': 'proxy'},
    });

    final parsed = SubscriptionParser.parse(jsonEncode(document));

    expect(parsed.resourceConfigs, hasLength(2));
    expect(parsed.outbounds, hasLength(2));
    expect(parsed.outbounds.map((entry) => entry['_source_scope']).toSet(), {
      'resource-main',
      'resource-backup',
    });
  });

  test('accepts the VK Calls outbound published by HYDRA ULTIMATE', () {
    final document = _document();
    final requirements = document['requirements'] as Map<String, dynamic>;
    (requirements['core'] as Map<String, dynamic>)['features'] = ['call'];
    final resource =
        (document['resources'] as List<dynamic>).single
            as Map<String, dynamic>;
    resource['document'] = {
      'outbounds': [
        {
          'type': 'call',
          'tag': 'call-vk-out',
          'platform': 'vk',
          'read_buffer': 65536,
          'join_link': 'https://calls.example/join/secret',
        },
      ],
    };
    final profile =
        (document['profiles'] as List<dynamic>).single as Map<String, dynamic>;
    profile['entrypoint'] = {
      'section': 'outbounds',
      'tag': 'call-vk-out',
    };

    final parsed = SubscriptionParser.parse(jsonEncode(document));

    expect(parsed.format, SubscriptionFormat.hydraV2);
    expect(parsed.outbounds.single['type'], 'call');
    expect(parsed.outbounds.single['platform'], 'vk');
    expect(parsed.nativeConfig?['outbounds'], hasLength(1));
  });

  test('missing, extra, duplicate, and unknown permissions fail closed', () {
    for (final permissions in <List<String>>[
      const [],
      const ['network.outbound', 'network.endpoint.wireguard'],
      const ['network.outbound', 'network.outbound'],
      const ['network.unknown'],
    ]) {
      final document = _document();
      final resource =
          (document['resources'] as List<dynamic>).single
              as Map<String, dynamic>;
      resource['requested_permissions'] = permissions;

      expect(
        () => SubscriptionParser.parse(jsonEncode(document)),
        throwsFormatException,
        reason: 'permissions=$permissions',
      );
    }
  });

  test('permissions are derived from all executable sections', () {
    final document = _document();
    final resource =
        (document['resources'] as List<dynamic>).single as Map<String, dynamic>;
    final native = resource['document'] as Map<String, dynamic>;
    native['inbounds'] = [
      {'type': 'call', 'tag': 'calls', 'platform': 'vk'},
    ];
    native['endpoints'] = [
      {
        'type': 'wireguard',
        'tag': 'wg',
        'address': ['10.0.0.2/32'],
        'private_key': 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=',
        'peers': const [],
      },
    ];
    resource['requested_permissions'] = [
      'network.inbound.call',
      'network.outbound',
      'network.endpoint.wireguard',
    ];

    final parsed = SubscriptionParser.parse(jsonEncode(document));
    expect(
      parsed.sourceMetadata['permissions']['resource-main'],
      containsAll(resource['requested_permissions'] as List<dynamic>),
    );
  });

  test('unsupported protocol and client feature fail closed', () {
    final unsupportedProtocol = _document();
    final resource =
        (unsupportedProtocol['resources'] as List<dynamic>).single
            as Map<String, dynamic>;
    final native = resource['document'] as Map<String, dynamic>;
    (native['outbounds'] as List<dynamic>).single['type'] = 'ssh';
    expect(
      () => SubscriptionParser.parse(jsonEncode(unsupportedProtocol)),
      throwsFormatException,
    );

    final unsupportedFeature = _document();
    final requirements =
        unsupportedFeature['requirements'] as Map<String, dynamic>;
    (requirements['client'] as Map<String, dynamic>)['features'] = [
      'interactive-permission-dialog',
    ];
    expect(
      () => SubscriptionParser.parse(jsonEncode(unsupportedFeature)),
      throwsFormatException,
    );
  });

  test('legacy HydraBox discriminator is rejected', () {
    final document = _document()
      ..['api_version'] = 'hydrabox.io/subscription/v1';
    expect(
      () => SubscriptionParser.parse(jsonEncode(document)),
      throwsFormatException,
    );
  });
}

Map<String, dynamic> _document() => {
  'api_version': HydraSubscriptionParser.apiVersion,
  'kind': 'Subscription',
  'identity': {
    'issuer': 'https://provider.example',
    'id': 'customer-main',
    'channel': 'stable',
    'sequence': 7,
  },
  'validity': {'issued_at': '2026-08-08T00:00:00Z'},
  'display': {'name': 'Hydra test'},
  'requirements': {
    'core': {
      'id': 'io.hydrabox.hydracore',
      'api_version': 2,
      'remote_policy': 2,
    },
    'client': {
      'subscription_contract': 2,
      'min_version': '0.4.0-beta.1',
      'features': ['automatic-permissions', 'multi-resource'],
    },
  },
  'resources': [
    {
      'id': 'resource-main',
      'format': 'sing-box-json',
      'requested_permissions': ['network.outbound'],
      'document': {
        'outbounds': [
          {
            'type': 'vless',
            'tag': 'proxy',
            'server': 'proxy.example',
            'server_port': 443,
            'uuid': '3a1a58e6-e167-4d9f-8b60-34fee9ee51e9',
            'tls': {'enabled': true, 'server_name': 'proxy.example'},
          },
        ],
      },
    },
  ],
  'profiles': [
    {
      'id': 'profile-main',
      'resource': 'resource-main',
      'name': {'default': 'Main'},
      'entrypoint': {'section': 'outbounds', 'tag': 'proxy'},
    },
  ],
  'default_profile': 'profile-main',
};

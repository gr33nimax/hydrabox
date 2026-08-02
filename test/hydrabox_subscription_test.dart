import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meow_client/data/subscription/hydrabox_subscription_crypto.dart';
import 'package:meow_client/data/subscription/parsers/hydrabox_subscription_parser.dart';
import 'package:meow_client/data/subscription/subscription_parser.dart';

void main() {
  String encodeKey(List<int> bytes) =>
      base64Url.encode(bytes).replaceAll('=', '');

  Map<String, dynamic> document() => {
    'api_version': 'hydrabox.io/subscription/v1',
    'kind': 'SubscriptionData',
    'issuer': 'https://provider.example',
    'subscription_id': 'customer-main',
    'channel': 'stable',
    'sequence': 42,
    'issued_at': '2026-07-30T18:00:00Z',
    'default_profile_id': 'trojan-shadowtls',
    'metadata': <String, dynamic>{
      'name': <String, dynamic>{'default': 'HydraBox test'},
    },
    'runtime': <String, dynamic>{
      'format': 'sing-box-json',
      'ownership': <String, dynamic>{
        'inbounds': 'client',
        'route_final': 'selected-profile',
        'dns': 'merge-safe',
        'route_rules': 'merge-safe',
        'log': 'client-overlay',
        'global': 'client-overlay',
      },
      'document': <String, dynamic>{
        'outbounds': [
          {
            'type': 'trojan',
            'tag': 'trojan-main',
            'server': 'proxy.example',
            'server_port': 443,
            'password': 'secret',
            'detour': 'shadowtls-transport',
            'future_protocol_field': {'kept': true},
          },
          {
            'type': 'shadowtls',
            'tag': 'shadowtls-transport',
            'server': 'transport.example',
            'server_port': 443,
            'version': 3,
            'password': 'secret',
          },
        ],
        'future_top_level': <String, dynamic>{'kept': true},
      },
    },
    'profiles': <dynamic>[
      <String, dynamic>{
        'id': 'trojan-shadowtls',
        'name': <String, dynamic>{'default': 'Trojan over ShadowTLS'},
        'entrypoint': <String, dynamic>{
          'section': 'outbounds',
          'tag': 'trojan-main',
        },
        'enabled': true,
      },
    ],
    'required_extensions': <dynamic>[],
    'extensions': <String, dynamic>{
      'example.provider/labels': <String, dynamic>{'tier': 'test'},
    },
  };

  Map<String, dynamic> wdttDocument() {
    const deviceId =
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
    const credentialRef = 'wdtt:user-1:device-1';
    return {
      'api_version': HydraBoxSubscriptionParser.apiVersionV2,
      'kind': 'SubscriptionData',
      'issuer': 'https://provider.example',
      'subscription_id': 'customer-main',
      'channel': 'stable',
      'sequence': 43,
      'issued_at': '2026-07-30T18:00:00Z',
      'default_profile_id': 'wdtt-primary',
      'metadata': {
        'name': {'default': 'HydraBox WDTT test'},
      },
      'runtime': {
        'format': 'sing-box-json',
        'document': {
          'endpoints': [
            {
              'type': 'wdtt',
              'tag': 'wdtt-primary',
              'server': 'wdtt.example',
              'server_port': 4433,
              'credential_ref': credentialRef,
              'vk_hashes': ['hash-1', 'hash-2', 'hash-3', 'hash-4'],
              'workers': 18,
              'obfs': 'audio',
              'vk_auth': 'auto',
              'vk_anon_path': 'vkcalls',
            },
          ],
        },
      },
      'profiles': [
        {
          'id': 'wdtt-primary',
          'name': {'default': 'WDTT primary'},
          'entrypoint': {'section': 'endpoints', 'tag': 'wdtt-primary'},
          'enabled': true,
        },
      ],
      'credentials': [
        {
          'kind': 'wdtt_device_grant',
          'credential_ref': credentialRef,
          'device_id': deviceId,
          'device_grant': 'hwdtt1_${List.filled(43, 'A').join()}',
        },
      ],
    };
  }

  test('explicit profiles are distinct from native runtime objects', () {
    final result = SubscriptionParser.parse(jsonEncode(document()));

    expect(result.format, SubscriptionFormat.hydraboxV1);
    expect(result.profiles, hasLength(1));
    expect(result.profiles.single.id, 'trojan-shadowtls');
    expect(result.profiles.single.entrypointTag, 'trojan-main');
    expect(result.nativeConfig?['future_top_level'], {'kept': true});
    expect(result.outbounds, hasLength(2));

    final entrypoint = result.outbounds.singleWhere(
      (outbound) => outbound['_etonify_original_tag'] == 'trojan-main',
    );
    final helper = result.outbounds.singleWhere(
      (outbound) => outbound['_etonify_original_tag'] == 'shadowtls-transport',
    );
    expect(entrypoint['_hydrabox_profile_id'], 'trojan-shadowtls');
    expect(entrypoint['_group_only'], isNot(true));
    expect(entrypoint['future_protocol_field'], {'kept': true});
    expect(helper['_group_only'], isTrue);
  });

  test('an explicit profile may target a native selector group', () {
    final source = document();
    final runtime = source['runtime'] as Map<String, dynamic>;
    final native = runtime['document'] as Map<String, dynamic>;
    final outbounds = native['outbounds'] as List<dynamic>;
    outbounds.add({
      'type': 'selector',
      'tag': 'provider-choice',
      'outbounds': ['trojan-main'],
      'default': 'trojan-main',
    });
    source['default_profile_id'] = 'provider-choice-profile';
    source['profiles'] = [
      {
        'id': 'provider-choice-profile',
        'name': {'default': 'Provider choice'},
        'entrypoint': {'section': 'outbounds', 'tag': 'provider-choice'},
      },
    ];

    final parsed = SubscriptionParser.parse(jsonEncode(source));
    final visible = parsed.outbounds.singleWhere(
      (entry) => entry['_hydrabox_profile_id'] == 'provider-choice-profile',
    );
    expect(visible['type'], 'selector');
    expect(visible['_group_only'], isNot(true));
    expect(
      parsed.outbounds
          .where((entry) => entry['_hydrabox_profile_id'] == null)
          .every((entry) => entry['_group_only'] == true),
      isTrue,
    );
  });

  test('an endpoint profile keeps the exact native endpoint tag', () {
    final source = document();
    final runtime = source['runtime'] as Map<String, dynamic>;
    final native = runtime['document'] as Map<String, dynamic>;
    native['endpoints'] = [
      {
        'type': 'wireguard',
        'tag': 'provider-wireguard',
        'address': ['10.0.0.2/32'],
        'private_key': 'opaque',
        'peers': <dynamic>[],
      },
    ];
    source['default_profile_id'] = 'wireguard-profile';
    source['profiles'] = [
      {
        'id': 'wireguard-profile',
        'name': {'default': 'Provider WireGuard'},
        'entrypoint': {'section': 'endpoints', 'tag': 'provider-wireguard'},
      },
    ];

    final parsed = SubscriptionParser.parse(jsonEncode(source));
    final visible = parsed.outbounds.singleWhere(
      (entry) => entry['_hydrabox_profile_id'] == 'wireguard-profile',
    );
    expect(visible['_etonify_source_index_section'], 'endpoints');
    expect(visible['_etonify_original_tag'], 'provider-wireguard');
    expect(visible['tag'], 'provider-wireguard');
  });

  test('all AmneziaWG fields are preserved by remote policy v1', () {
    final source = document();
    final runtime = source['runtime'] as Map<String, dynamic>;
    final native = runtime['document'] as Map<String, dynamic>;
    final amnezia = <String, dynamic>{
      'jc': 2,
      'jmin': 27,
      'jmax': 39,
      's1': 9,
      's2': 6,
      's3': 0,
      's4': 0,
      'h1': 1945982327,
      'h2': 1210256333,
      'h3': 125101821,
      'h4': 375691454,
      'i1': '<r 1>',
      'i2': '<r 2>',
      'i3': '<r 3>',
      'i4': '<r 4>',
      'i5': '<r 5>',
      'j1': '<r 6>',
      'j2': '<r 7>',
      'j3': '<r 8>',
      'itime': 50,
    };
    native['endpoints'] = [
      {
        'type': 'wireguard',
        'tag': 'provider-wireguard',
        'address': ['10.0.0.2/32'],
        'private_key': 'opaque',
        'amnezia': amnezia,
        'peers': <dynamic>[],
      },
    ];

    final parsed = SubscriptionParser.parse(jsonEncode(source));
    final endpoints = parsed.nativeConfig?['endpoints'] as List<dynamic>;
    final endpoint = endpoints.single as Map<String, dynamic>;

    expect(endpoint['amnezia'], amnezia);
  });

  test('unsupported HydraBox major never falls back to a legacy parser', () {
    final source = document()..['api_version'] = 'hydrabox.io/subscription/v3';

    expect(
      () => SubscriptionParser.parse(jsonEncode(source)),
      throwsFormatException,
    );
  });

  test('v2 JWE binds one WDTT endpoint to one device grant', () {
    final key = encodeKey(List<int>.generate(32, (index) => index + 1));
    final encrypted = HydraBoxJweCodec.encrypt(
      jsonEncode(wdttDocument()),
      encodedKey: key,
      nonce: Uint8List.fromList(List<int>.generate(12, (index) => index + 1)),
    );

    final parsed = SubscriptionParser.parse(
      encrypted,
      decryptionKey: key,
      expectedDeviceId:
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    );

    expect(parsed.format, SubscriptionFormat.hydraboxV2);
    expect(parsed.wdttCredentials, hasLength(1));
    expect(parsed.wdttCredentials.single.credentialRef, 'wdtt:user-1:device-1');
    expect(parsed.wdttCredentials.single.deviceGrant, startsWith('hwdtt1_'));
    final endpoint = (parsed.nativeConfig?['endpoints'] as List).single as Map;
    expect(endpoint['credential_ref'], 'wdtt:user-1:device-1');
    expect(endpoint, isNot(contains('device_grant')));
    expect(endpoint, isNot(contains('password')));
  });

  test('v2 WDTT credentials fail closed outside JWE or on device mismatch', () {
    final plaintext = jsonEncode(wdttDocument());
    expect(
      () => SubscriptionParser.parse(plaintext),
      throwsFormatException,
    );

    final key = encodeKey(List<int>.filled(32, 7));
    final encrypted = HydraBoxJweCodec.encrypt(
      plaintext,
      encodedKey: key,
      nonce: Uint8List.fromList(List<int>.generate(12, (index) => index + 2)),
    );
    expect(
      () => SubscriptionParser.parse(
        encrypted,
        decryptionKey: key,
        expectedDeviceId:
            'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
      ),
      throwsFormatException,
    );
  });

  test('v2 WDTT enforces worker groups and exact credential binding', () {
    final invalidWorkers = wdttDocument();
    final runtime = invalidWorkers['runtime'] as Map<String, dynamic>;
    final native = runtime['document'] as Map<String, dynamic>;
    final endpoint = (native['endpoints'] as List).single as Map<String, dynamic>;
    endpoint['workers'] = 8;
    final key = encodeKey(List<int>.filled(32, 8));
    final invalidWorkersJwe = HydraBoxJweCodec.encrypt(
      jsonEncode(invalidWorkers),
      encodedKey: key,
      nonce: Uint8List.fromList(List<int>.generate(12, (index) => index + 3)),
    );
    expect(
      () => SubscriptionParser.parse(invalidWorkersJwe, decryptionKey: key),
      throwsFormatException,
    );

    final missingCredential = wdttDocument()..remove('credentials');
    final missingCredentialJwe = HydraBoxJweCodec.encrypt(
      jsonEncode(missingCredential),
      encodedKey: key,
      nonce: Uint8List.fromList(List<int>.generate(12, (index) => index + 4)),
    );
    expect(
      () => SubscriptionParser.parse(missingCredentialJwe, decryptionKey: key),
      throwsFormatException,
    );
  });

  test('nested protocol members are not envelope discriminators', () {
    final nativeDocument = jsonEncode({
      'outbounds': [
        {
          'type': 'future-protocol',
          'tag': 'future-main',
          'protected': 'protocol-field',
          'iv': 'protocol-field',
          'ciphertext': 'protocol-field',
          'api_version': 'hydrabox.io/protocol/v1',
          'description': 'a string containing "protected": and "tag":',
        },
      ],
    });

    expect(HydraBoxJweCodec.looksLike(nativeDocument), isFalse);
    expect(HydraBoxSubscriptionParser.looksLike(nativeDocument), isFalse);
  });

  test('duplicate JSON keys are rejected before decoding', () {
    final source = jsonEncode(
      document(),
    ).replaceFirst('"sequence":42', '"sequence":41,"sequence":42');

    expect(
      () => HydraBoxSubscriptionParser.parse(source),
      throwsFormatException,
    );
  });

  test('duplicate or malformed envelope discriminators fail closed', () {
    final encoded = jsonEncode(document());
    final marker = '"api_version":"hydrabox.io/subscription/v1"';
    for (final replacement in const [
      '"api_version":"hydrabox.io/subscription/v1",'
          '"api_version":"not-hydrabox"',
      '"api_version":"not-hydrabox",'
          '"api_version":"hydrabox.io/subscription/v1"',
    ]) {
      expect(
        () =>
            SubscriptionParser.parse(encoded.replaceFirst(marker, replacement)),
        throwsFormatException,
      );
    }

    final malformedVersion = document()..['api_version'] = 1;
    expect(
      () => SubscriptionParser.parse(jsonEncode(malformedVersion)),
      throwsFormatException,
    );
  });

  test('RFC 3339 timestamps reject calendar normalization', () {
    for (final invalidTimestamp in const [
      '2026-02-30T18:00:00Z',
      '2026-07-30T24:00:00Z',
      '2026-07-30T18:00:60Z',
      '2026-07-30T18:00:00+24:00',
    ]) {
      final source = document()..['issued_at'] = invalidTimestamp;
      expect(
        () => HydraBoxSubscriptionParser.parse(jsonEncode(source)),
        throwsFormatException,
        reason: '$invalidTimestamp must not be normalized into another instant',
      );
    }
  });

  test('identity and native tags are never normalized ambiguously', () {
    final paddedId = document();
    final idProfiles = paddedId['profiles'] as List<dynamic>;
    (idProfiles.single as Map<String, dynamic>)['id'] = ' trojan-shadowtls';
    expect(
      () => HydraBoxSubscriptionParser.parse(jsonEncode(paddedId)),
      throwsFormatException,
    );

    final paddedTag = document();
    final runtime = paddedTag['runtime'] as Map<String, dynamic>;
    final native = runtime['document'] as Map<String, dynamic>;
    final outbounds = native['outbounds'] as List<dynamic>;
    (outbounds.first as Map<String, dynamic>)['tag'] = 'trojan-main ';
    expect(
      () => HydraBoxSubscriptionParser.parse(jsonEncode(paddedTag)),
      throwsFormatException,
    );
  });

  test('outbound and endpoint tags share one unambiguous namespace', () {
    final source = document();
    final runtime = source['runtime'] as Map<String, dynamic>;
    final native = runtime['document'] as Map<String, dynamic>;
    native['endpoints'] = [
      {
        'type': 'wireguard',
        'tag': 'trojan-main',
        'address': ['10.0.0.2/32'],
        'private_key': 'test',
        'peers': <dynamic>[],
      },
    ];

    expect(
      () => HydraBoxSubscriptionParser.parse(jsonEncode(source)),
      throwsFormatException,
    );
  });

  test('every native tag rejects HydraBox-owned runtime collisions', () {
    for (final reservedTag in const [
      '__hydrabox.internal',
      'select',
      'direct',
      'lowest',
    ]) {
      final source = document();
      final runtime = source['runtime'] as Map<String, dynamic>;
      final native = runtime['document'] as Map<String, dynamic>;
      (native['outbounds'] as List<dynamic>).add({
        'type': 'future-helper',
        'tag': reservedTag,
      });
      expect(
        () => HydraBoxSubscriptionParser.parse(jsonEncode(source)),
        throwsFormatException,
        reason: 'unreferenced native tag $reservedTag must not be renamed',
      );
    }
  });

  test('JWE dir+A256GCM round trip and authentication', () {
    final key = encodeKey(List<int>.generate(32, (index) => index));
    final plaintext = jsonEncode(document());
    final encrypted = HydraBoxJweCodec.encrypt(
      plaintext,
      encodedKey: key,
      keyId: 'customer-key-1',
      nonce: Uint8List.fromList(List<int>.generate(12, (index) => index + 1)),
    );

    final parsed = SubscriptionParser.parse(encrypted, decryptionKey: key);
    expect(parsed.format, SubscriptionFormat.hydraboxV1);
    expect(parsed.sourceMetadata['encrypted'], isTrue);
    expect(parsed.sourceMetadata['key_id'], 'customer-key-1');

    final envelope = Map<String, dynamic>.from(jsonDecode(encrypted) as Map);
    final ciphertext = envelope['ciphertext'] as String;
    envelope['ciphertext'] =
        '${ciphertext.startsWith('A') ? 'B' : 'A'}'
        '${ciphertext.substring(1)}';
    expect(
      () => SubscriptionParser.parse(jsonEncode(envelope), decryptionKey: key),
      throwsFormatException,
    );
  });

  test('JWE output matches the shared HYDRA interoperability vector', () {
    final vector = Map<String, dynamic>.from(
      jsonDecode(File('test/fixtures/hydrabox-jwe-v1.json').readAsStringSync())
          as Map,
    );
    final key = vector['key'] as String;
    final plaintext = jsonEncode(vector['plaintext']);
    final expected = Map<String, dynamic>.from(vector['jwe'] as Map);
    final encrypted = HydraBoxJweCodec.encrypt(
      plaintext,
      encodedKey: key,
      keyId: vector['kid'] as String,
      nonce: Uint8List.fromList(
        List<int>.generate(
          12,
          (index) => int.parse(
            (vector['iv_hex'] as String).substring(index * 2, index * 2 + 2),
            radix: 16,
          ),
        ),
      ),
    );

    expect(jsonDecode(encrypted), expected);
    expect(HydraBoxJweCodec.decrypt(encrypted, encodedKey: key), plaintext);
  });

  test('supplying an hbx-key rejects a plaintext subscription', () {
    final key = encodeKey(List<int>.filled(32, 9));

    expect(
      () =>
          SubscriptionParser.parse(jsonEncode(document()), decryptionKey: key),
      throwsFormatException,
    );

    final encrypted = HydraBoxJweCodec.encrypt(
      jsonEncode(document()),
      encodedKey: key,
      nonce: Uint8List.fromList(List<int>.generate(12, (index) => index + 3)),
    );
    expect(
      () => SubscriptionParser.parse(encrypted, decryptionKey: ' $key'),
      throwsFormatException,
      reason: 'hbx-key whitespace must never be normalized silently',
    );
  });

  test('security-sensitive URLs reject empty delimiters and userinfo', () {
    for (final invalidIssuer in const [
      'https://provider.example?',
      'https://provider.example#',
      'https://@provider.example',
    ]) {
      final source = document()..['issuer'] = invalidIssuer;
      expect(
        () => SubscriptionParser.parse(jsonEncode(source)),
        throwsFormatException,
        reason: 'invalid issuer $invalidIssuer must fail closed',
      );
    }

    final emptyFragmentUrl = document();
    emptyFragmentUrl['update'] = {
      'url': 'https://provider.example/subscription#',
    };
    expect(
      () => SubscriptionParser.parse(jsonEncode(emptyFragmentUrl)),
      throwsFormatException,
    );
  });

  test('partial JWE containers fail closed instead of parser fallback', () {
    final key = encodeKey(List<int>.generate(32, (index) => 255 - index));
    final encrypted = HydraBoxJweCodec.encrypt(
      jsonEncode(document()),
      encodedKey: key,
      nonce: Uint8List.fromList(List<int>.generate(12, (index) => index + 2)),
    );
    final complete = Map<String, dynamic>.from(jsonDecode(encrypted) as Map);

    for (final missingMember in const [
      'protected',
      'iv',
      'ciphertext',
      'tag',
    ]) {
      final partial = Map<String, dynamic>.from(complete)
        ..remove(missingMember);
      expect(
        () => SubscriptionParser.parse(jsonEncode(partial), decryptionKey: key),
        throwsFormatException,
        reason: 'missing JWE member $missingMember must not fall back',
      );
    }
  });

  test('outer byte limit is enforced before whitespace normalization', () {
    const partialJwe = '{"protected":"x"}';
    const maxOuterBytes = 16 * 1024 * 1024;
    final exactBoundary =
        '${_asciiSpaces(maxOuterBytes - utf8.encode(partialJwe).length)}'
        '$partialJwe';

    expect(
      () => SubscriptionParser.parse(exactBoundary),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('requires an hbx-key'),
        ),
      ),
    );
    expect(
      () => SubscriptionParser.parse(' $exactBoundary'),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('response is too large'),
        ),
      ),
    );
  });

  test('unsafe remote runtime capabilities require local consent', () {
    final unsafeSections = <String, dynamic>{
      'inbounds': [
        {
          'type': 'mixed',
          'tag': 'remote-listener',
          'listen': '0.0.0.0',
          'listen_port': 1080,
        },
      ],
      'services': [
        {
          'type': 'manager-api',
          'tag': 'remote-service',
          'listen': '0.0.0.0',
          'listen_port': 9090,
        },
      ],
      'experimental': {
        'clash_api': {'external_controller': '0.0.0.0:9091'},
      },
      'Services': [
        {
          'type': 'manager-api',
          'tag': 'folded-remote-service',
          'listen_port': 9091,
        },
      ],
      'Experimental': {
        'clash_api': {'external_controller': '0.0.0.0:9092'},
      },
    };

    for (final unsafeSection in unsafeSections.entries) {
      final source = document();
      final runtime = source['runtime'] as Map<String, dynamic>;
      final native = runtime['document'] as Map<String, dynamic>;
      native[unsafeSection.key] = unsafeSection.value;
      expect(
        () => SubscriptionParser.parse(jsonEncode(source)),
        throwsFormatException,
        reason:
            'runtime.document.${unsafeSection.key} must require local consent',
      );
    }
  });

  test('local resources and incomplete ownership fail closed', () {
    final localProvider = document();
    final localRuntime = localProvider['runtime'] as Map<String, dynamic>;
    final localNative = localRuntime['document'] as Map<String, dynamic>;
    localNative['providers'] = [
      {'type': 'local', 'tag': 'disk', 'path': 'profiles.json'},
    ];
    expect(
      () => SubscriptionParser.parse(jsonEncode(localProvider)),
      throwsFormatException,
    );

    final localState = document();
    final stateRuntime = localState['runtime'] as Map<String, dynamic>;
    final stateNative = stateRuntime['document'] as Map<String, dynamic>;
    stateNative['endpoints'] = [
      {
        'type': 'tailscale',
        'tag': 'tailscale-helper',
        'state_directory': '/data/local/tmp/provider-state',
      },
    ];
    expect(
      () => SubscriptionParser.parse(jsonEncode(localState)),
      throwsFormatException,
    );

    final partialOwnership = document();
    final ownershipRuntime =
        partialOwnership['runtime'] as Map<String, dynamic>;
    ownershipRuntime['ownership'] = {'inbounds': 'client'};
    expect(
      () => SubscriptionParser.parse(jsonEncode(partialOwnership)),
      throwsFormatException,
    );
  });

  test(
    'known local filesystem and system-network capabilities fail closed',
    () {
      void expectRejected(
        void Function(Map<String, dynamic> native) mutate,
        String reason,
      ) {
        final source = document();
        final runtime = source['runtime'] as Map<String, dynamic>;
        final native = runtime['document'] as Map<String, dynamic>;
        mutate(native);
        expect(
          () => SubscriptionParser.parse(jsonEncode(source)),
          throwsFormatException,
          reason: reason,
        );
      }

      expectRejected(
        (native) => native['route'] = {
          'geoip': {'path': '/data/local/geoip.db'},
        },
        'route.geoip.path must not read a local file',
      );
      expectRejected(
        (native) => native['route'] = {
          'geosite': {'download_url': 'http://provider.example/geosite.db'},
        },
        'remote routing databases require HTTPS',
      );
      expectRejected(
        (native) => native['dns'] = {
          'servers': [
            {
              'type': 'hosts',
              'tag': 'disk-hosts',
              'path': ['/system/etc/hosts'],
            },
          ],
        },
        'hosts DNS must not read local paths',
      );
      expectRejected(
        (native) => native['dns'] = {
          'servers': [
            {'type': 'dhcp', 'tag': 'lan-dhcp'},
          ],
        },
        'DHCP discovery needs a local consent grant',
      );
      expectRejected(
        (native) => native['ntp'] = {
          'enabled': true,
          'write_to_system': true,
          'server': 'time.example',
          'server_port': 123,
        },
        'remote NTP must not change the system clock',
      );
      expectRejected(
        (native) => native['log'] = {'output': '/data/local/hydracore.log'},
        'remote logging must not write a local file',
      );
      expectRejected(
        (native) => native['log'] = {'Output': '/data/local/hydracore.log'},
        'case-folded remote logging output must not bypass the policy',
      );
      expectRejected(
        (native) => native['Providers'] = [
          {'Type': 'local', 'Tag': 'folded-disk', 'Path': 'profiles.json'},
        ],
        'case-folded provider fields must not bypass the policy',
      );
      expectRejected((native) {
        final outbounds = native['outbounds'] as List<dynamic>;
        (outbounds.first as Map<String, dynamic>)['bind_interface'] = 'wlan0';
      }, 'remote outbounds must not choose a local interface');
      expectRejected(
        (native) => native['route'] = {
          'rules': [
            {
              'process_name': ['banking-app'],
              'outbound': 'trojan-main',
            },
          ],
        },
        'remote route rules must not inspect local processes',
      );
      expectRejected(
        (native) => native['dns'] = {
          'rules': [
            {
              'wifi_ssid': ['private-network'],
              'server': 'dns-remote',
            },
          ],
        },
        'remote DNS rules must not inspect local Wi-Fi state',
      );
      expectRejected(
        (native) => native['outbounds'] = [
          {'type': 'tor', 'tag': 'spawn-tor'},
        ],
        'Tor process execution requires explicit consent',
      );
      expectRejected(
        (native) => native['endpoints'] = [
          {'type': 'vpn-client', 'tag': 'reverse-vpn'},
        ],
        'reverse VPN endpoints require explicit consent',
      );
      expectRejected(
        (native) => native['endpoints'] = [
          {
            'type': 'wireguard',
            'tag': 'system-wireguard',
            'system': true,
            'address': ['10.0.0.2/32'],
            'private_key': 'test',
          },
        ],
        'system WireGuard interfaces require local consent',
      );
      expectRejected(
        (native) => native['endpoints'] = [
          {
            'type': 'wireguard',
            'tag': 'pause-bypass-wireguard',
            'disable_pauses': true,
            'address': ['10.0.0.2/32'],
            'private_key': 'test',
          },
        ],
        'remote WireGuard cannot bypass the app pause lifecycle',
      );
      expectRejected(
        (native) => native['endpoints'] = [
          {
            'type': 'tailscale',
            'tag': 'system-tailscale',
            'system_interface': true,
          },
        ],
        'Tailscale system interfaces require local consent',
      );
      expectRejected(
        (native) => native['endpoints'] = [
          {
            'type': 'wireguard',
            'tag': 'listener-endpoint',
            'listen_port': 0,
            'address': ['10.0.0.2/32'],
            'private_key': 'opaque',
            'peers': <dynamic>[],
          },
        ],
        'even an ephemeral userspace listener requires local consent',
      );
    },
  );

  test('DNS and route resources reject HydraBox-owned tag collisions', () {
    final dnsCollision = document();
    final dnsRuntime = dnsCollision['runtime'] as Map<String, dynamic>;
    final dnsNative = dnsRuntime['document'] as Map<String, dynamic>;
    dnsNative['dns'] = {
      'servers': [
        {'type': 'https', 'tag': 'dns-remote', 'server': 'resolver.example'},
      ],
    };
    expect(
      () => SubscriptionParser.parse(jsonEncode(dnsCollision)),
      throwsFormatException,
    );

    final ruleSetCollision = document();
    final routeRuntime = ruleSetCollision['runtime'] as Map<String, dynamic>;
    final routeNative = routeRuntime['document'] as Map<String, dynamic>;
    routeNative['route'] = {
      'rule_set': [
        {
          'type': 'remote',
          'tag': 'adblock-block',
          'format': 'binary',
          'url': 'https://provider.example/rules.srs',
        },
      ],
    };
    expect(
      () => SubscriptionParser.parse(jsonEncode(ruleSetCollision)),
      throwsFormatException,
    );
  });

  test('unknown structural fields require a namespaced extension', () {
    final unknownEnvelope = document()..['future_field'] = true;
    expect(
      () => SubscriptionParser.parse(jsonEncode(unknownEnvelope)),
      throwsFormatException,
    );

    final unknownProfile = document();
    final profiles = unknownProfile['profiles'] as List<dynamic>;
    (profiles.single as Map<String, dynamic>)['future_field'] = true;
    expect(
      () => SubscriptionParser.parse(jsonEncode(unknownProfile)),
      throwsFormatException,
    );

    final optionalExtension = document();
    final optionalProfiles = optionalExtension['profiles'] as List<dynamic>;
    (optionalProfiles.single as Map<String, dynamic>)['extensions'] = {
      'example.provider/profile-labels/v1': {'future_field': true},
    };
    final parsed = SubscriptionParser.parse(jsonEncode(optionalExtension));
    expect(
      parsed.profiles.single.metadata['extensions'],
      containsPair('example.provider/profile-labels/v1', {
        'future_field': true,
      }),
    );
  });

  test('explicit null never substitutes for omission in the strict shape', () {
    final mutations = <String, void Function(Map<String, dynamic>)>{
      'channel': (source) => source['channel'] = null,
      'not_before': (source) => source['not_before'] = null,
      'expires_at': (source) => source['expires_at'] = null,
      'metadata': (source) => source['metadata'] = null,
      'metadata.homepage': (source) =>
          (source['metadata'] as Map<String, dynamic>)['homepage'] = null,
      'metadata.support_url': (source) =>
          (source['metadata'] as Map<String, dynamic>)['support_url'] = null,
      'metadata.tags': (source) =>
          (source['metadata'] as Map<String, dynamic>)['tags'] = null,
      'metadata.extensions': (source) =>
          (source['metadata'] as Map<String, dynamic>)['extensions'] = null,
      'compatibility': (source) => source['compatibility'] = null,
      'compatibility.client': (source) =>
          source['compatibility'] = {'client': null},
      'compatibility.core': (source) =>
          source['compatibility'] = {'core': null},
      'compatibility.extensions': (source) =>
          source['compatibility'] = {'extensions': null},
      'compatibility.client.min_version': (source) =>
          source['compatibility'] = {
            'client': {'min_version': null},
          },
      'compatibility.client.required_features': (source) =>
          source['compatibility'] = {
            'client': {'required_features': null},
          },
      'compatibility.core.id': (source) => source['compatibility'] = {
        'core': {'id': null},
      },
      'compatibility.core.version_range': (source) =>
          source['compatibility'] = {
            'core': {'version_range': null},
          },
      'compatibility.core.required_features': (source) =>
          source['compatibility'] = {
            'core': {'required_features': null},
          },
      'update': (source) => source['update'] = null,
      'update.minimum_interval_seconds': (source) => source['update'] = {
        'url': 'https://provider.example/update',
        'minimum_interval_seconds': null,
      },
      'update.extensions': (source) => source['update'] = {
        'url': 'https://provider.example/update',
        'extensions': null,
      },
      'runtime.ownership': (source) =>
          (source['runtime'] as Map<String, dynamic>)['ownership'] = null,
      'runtime.extensions': (source) =>
          (source['runtime'] as Map<String, dynamic>)['extensions'] = null,
      'profile.enabled': (source) =>
          ((source['profiles'] as List).single
                  as Map<String, dynamic>)['enabled'] =
              null,
      'profile.country': (source) =>
          ((source['profiles'] as List).single
                  as Map<String, dynamic>)['country'] =
              null,
      'profile.tags': (source) =>
          ((source['profiles'] as List).single
                  as Map<String, dynamic>)['tags'] =
              null,
      'profile.required_features': (source) =>
          ((source['profiles'] as List).single
                  as Map<String, dynamic>)['required_features'] =
              null,
      'profile.extensions': (source) =>
          ((source['profiles'] as List).single
                  as Map<String, dynamic>)['extensions'] =
              null,
      'required_extensions': (source) => source['required_extensions'] = null,
      'extensions': (source) => source['extensions'] = null,
    };

    for (final mutation in mutations.entries) {
      final source = document();
      mutation.value(source);
      expect(
        () => SubscriptionParser.parse(jsonEncode(source)),
        throwsFormatException,
        reason: '${mutation.key}: explicit null is not schema-valid',
      );
    }
  });

  test('omission and opaque extension null values remain valid', () {
    final source = document();
    source['extensions'] = {
      'example.provider/opaque/v1': {'optional_value': null},
    };
    final runtime = source['runtime'] as Map<String, dynamic>;
    final native = runtime['document'] as Map<String, dynamic>;
    native['future_top_level'] = {'opaque_null': null};

    final parsed = SubscriptionParser.parse(jsonEncode(source));
    expect(
      parsed.sourceMetadata['extensions'],
      contains('example.provider/opaque/v1'),
    );
    expect(parsed.nativeConfig?['future_top_level'], {'opaque_null': null});
  });

  test('JWE key is accepted only from an out-of-band URL fragment', () {
    final key = encodeKey(List<int>.filled(32, 7));
    final uri = Uri.parse(
      'https://provider.example/subscription'
      '#hbx-key=$key',
    );

    expect(HydraBoxJweCodec.keyFromUri(uri), key);
    expect(
      HydraBoxJweCodec.uriWithoutSecretFragment(uri).toString(),
      'https://provider.example/subscription',
    );

    final empty = Uri.parse('https://provider.example/subscription#hbx-key=');
    final duplicate = Uri.parse(
      'https://provider.example/subscription#hbx-key=$key&hbx-key=$key',
    );
    final padded = Uri.parse(
      'https://provider.example/subscription#hbx-key=%20$key',
    );
    expect(HydraBoxJweCodec.hasKeyFragment(empty), isTrue);
    expect(HydraBoxJweCodec.keyFromUri(empty), isNull);
    expect(HydraBoxJweCodec.hasKeyFragment(duplicate), isTrue);
    expect(HydraBoxJweCodec.keyFromUri(duplicate), isNull);
    expect(HydraBoxJweCodec.hasKeyFragment(padded), isTrue);
    expect(HydraBoxJweCodec.keyFromUri(padded), isNull);
    expect(
      HydraBoxJweCodec.hasKeyQueryParameter(
        Uri.parse('https://provider.example/sub?hbx%2Dkey=$key'),
      ),
      isTrue,
    );
  });
}

String _asciiSpaces(int length) =>
    String.fromCharCodes(Uint8List(length)..fillRange(0, length, 0x20));

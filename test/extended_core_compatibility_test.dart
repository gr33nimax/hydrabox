import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:meow_client/data/local/app_settings_store.dart';
import 'package:meow_client/data/subscription/hydrabox_subscription_crypto.dart';
import 'package:meow_client/data/subscription/outbound_schema.dart';
import 'package:meow_client/data/subscription/subscription_parser.dart';
import 'package:meow_client/data/subscription/subscription_store.dart';
import 'package:meow_client/models/subscription.dart';
import 'package:meow_client/singbox/extended_core_protocols.dart';
import 'package:meow_client/singbox/libbox_capabilities.dart';
import 'package:meow_client/singbox/singbox_config_builder.dart';

void main() {
  test('catalogue uses the exact extended-core registry names', () {
    expect(
      ExtendedCoreProtocolCatalog.outboundTypes,
      equals(<String>{
        'direct',
        'block',
        'fallback',
        'selector',
        'urltest',
        'socks',
        'http',
        'shadowsocks',
        'vmess',
        'trojan',
        'naive',
        'tor',
        'ssh',
        'shadowtls',
        'vless',
        'mieru',
        'anytls',
        'masque',
        'openvpn',
        'bond',
        'failover',
        'trusttunnel',
        'bandwidth-limiter',
        'connection-limiter',
        'traffic-limiter',
        'rate-limiter',
        'parser',
        'hysteria',
        'tuic',
        'hysteria2',
        'sudoku',
        'snell',
      }),
    );
    expect(
      ExtendedCoreProtocolCatalog.inboundTypes,
      equals(<String>{
        'tun',
        'redirect',
        'tproxy',
        'direct',
        'socks',
        'http',
        'mixed',
        'shadowsocks',
        'vmess',
        'trojan',
        'naive',
        'shadowtls',
        'vless',
        'anytls',
        'mieru',
        'ssh',
        'bond',
        'failover',
        'trusttunnel',
        'hysteria',
        'tuic',
        'hysteria2',
        'mtproxy',
        'sudoku',
        'snell',
      }),
    );
    expect(
      ExtendedCoreProtocolCatalog.endpointTypes,
      equals(<String>{
        'vpn-server',
        'vpn-client',
        'wireguard',
        'wdtt',
        'warp',
        'tailscale',
      }),
    );
    expect(
      ExtendedCoreProtocolCatalog.dnsTransportTypes,
      equals(<String>{
        'tcp',
        'udp',
        'tls',
        'https',
        'quic',
        'h3',
        'sdns',
        'hosts',
        'local',
        'fakeip',
        'fallback',
        'resolved',
        'dhcp',
        'tailscale',
      }),
    );
    expect(
      ExtendedCoreProtocolCatalog.v2rayTransportTypes,
      equals(<String>{
        'http',
        'ws',
        'quic',
        'grpc',
        'httpupgrade',
        'xhttp',
        'mkcp',
      }),
    );
    expect(
      ExtendedCoreProtocolCatalog.providerTypes,
      equals(<String>{'inline', 'local', 'remote'}),
    );
    expect(
      ExtendedCoreProtocolCatalog.serviceTypes,
      equals(<String>{
        'admin-panel',
        'manager',
        'manager-api',
        'node',
        'node-manager-api',
        'resolved',
        'ssm-api',
        'derp',
        'ccm',
        'ocm',
        'oom-killer',
        'profiler',
      }),
    );
    expect(
      ExtendedCoreProtocolCatalog.requiredAndroidBuildTags,
      equals(<String>{
        'with_gvisor',
        'with_quic',
        'with_dhcp',
        'with_wireguard',
        'with_wdtt',
        'with_masque',
        'with_mtproxy',
        'with_ccm',
        'with_ocm',
        'with_openvpn',
        'with_trusttunnel',
        'with_sudoku',
        'with_snell',
        'with_utls',
        'with_naive_outbound',
        'with_clash_api',
        'with_manager',
        'with_admin_panel',
        'with_profiler',
        'with_v2ray_api',
        'with_acme',
        'with_tailscale',
        'badlinkname',
        'tfogo_checklinkname0',
        'ts_omit_logtail',
        'ts_omit_ssh',
        'ts_omit_drive',
        'ts_omit_taildrop',
        'ts_omit_webclient',
        'ts_omit_doctor',
        'ts_omit_capture',
        'ts_omit_kube',
        'ts_omit_aws',
        'ts_omit_synology',
        'ts_omit_bird',
      }),
    );
    expect(
      ExtendedCoreProtocolCatalog.stubbedInboundTypes,
      equals(<String>{'shadowsocksr'}),
    );
    expect(
      ExtendedCoreProtocolCatalog.stubbedOutboundTypes,
      equals(<String>{'shadowsocksr', 'wireguard'}),
    );
    expect(
      ParsedOutboundSchema.extendedOutboundTypes,
      ExtendedCoreProtocolCatalog.outboundTypes,
    );
    expect(
      ParsedOutboundSchema.extendedInboundTypes,
      ExtendedCoreProtocolCatalog.inboundTypes,
    );
    expect(
      ParsedOutboundSchema.extendedTransportTypes,
      ExtendedCoreProtocolCatalog.v2rayTransportTypes,
    );
    expect(
      ExtendedCoreProtocolCatalog.outboundTypes,
      isNot(contains('bandwidth')),
    );
    expect(ExtendedCoreProtocolCatalog.dnsTransportTypes, contains('h3'));
    expect(
      ExtendedCoreProtocolCatalog.dnsTransportTypes,
      isNot(contains('http3')),
    );
  });

  test('full sing-box JSON is imported without normalizing native fields', () {
    final parsed = SubscriptionParser.parse(jsonEncode(_fullExtendedConfig()));

    expect(parsed.format, SubscriptionFormat.singboxConfig);
    expect(parsed.outbounds, hasLength(6));

    final masque = parsed.outbounds.firstWhere(
      (entry) => entry['type'] == 'masque',
    );
    expect(masque['future_outbound_field'], {
      'nested': [1, 2, 3],
    });
    expect(
      (masque['transport'] as Map)['future_transport_field'],
      'preserve-me',
    );

    final vless = parsed.outbounds.firstWhere(
      (entry) => entry['type'] == 'vless',
    );
    expect((vless['tls'] as Map)['alpn'], ['custom-alpn', 'h2']);
    expect(
      vless['encryption'],
      'mlkem768x25519plus.native.0rtt.extended-value',
    );

    final hysteria2 = parsed.outbounds.firstWhere(
      (entry) => entry['type'] == 'hysteria2',
    );
    expect((hysteria2['tls'] as Map)['utls'], {
      'enabled': true,
      'fingerprint': 'firefox',
      'future_utls_field': true,
    });

    final bond = parsed.outbounds.firstWhere(
      (entry) => entry['type'] == 'bond',
    );
    expect(bond['future_group_field'], true);
    expect(ParsedOutboundSchema.validate(bond), isNull);
  });

  test('runtime builder retains every non-app-owned full-config section', () {
    final source = jsonEncode(_fullExtendedConfig());
    final config = _defaultBuilder(_subscriptionFromContent(source)).build();

    expect(config['experimental'], {
      'extended_feature': {'enabled': true},
    });
    expect(config['endpoints'], _fullExtendedConfig()['endpoints']);
    expect(config['services'], _fullExtendedConfig()['services']);
    expect(config['providers'], _fullExtendedConfig()['providers']);

    final inbounds = (config['inbounds'] as List).cast<Map<String, dynamic>>();
    expect(
      inbounds.firstWhere((entry) => entry['tag'] == 'mt-in'),
      containsPair('future_inbound_field', 'preserve-me'),
    );

    final dns = config['dns'] as Map;
    final dnsServers = (dns['servers'] as List).cast<Map<String, dynamic>>();
    expect(
      dnsServers.firstWhere((entry) => entry['tag'] == 'secure-dns'),
      containsPair('future_option', {'keep': true}),
    );

    final outbounds = (config['outbounds'] as List)
        .cast<Map<String, dynamic>>();
    final masque = outbounds.firstWhere(
      (entry) => entry['tag'] == 'masque-node',
    );
    expect(masque['future_outbound_field'], {
      'nested': [1, 2, 3],
    });
    expect(masque, isNot(contains('server')));
    expect(masque, isNot(contains('_etonify_core_passthrough')));

    final vless = outbounds.firstWhere(
      (entry) => entry['tag'] == 'encrypted-vless',
    );
    expect(
      vless['encryption'],
      'mlkem768x25519plus.native.0rtt.extended-value',
    );
  });

  test('known full-config outbounds bypass Flutter field assumptions', () {
    final source = jsonEncode({
      'outbounds': [
        {
          'type': 'http',
          'tag': 'alternate-http',
          // Deliberately uses a future/alternate core shape that does not
          // satisfy the legacy Flutter parser's server/server_port gate.
          'servers': [
            {'address': 'proxy.example', 'port': 443},
          ],
          'future_http_option': {'mode': 'native-authoritative'},
        },
      ],
    });

    final parsed = SubscriptionParser.parse(source);
    expect(parsed.outbounds, hasLength(1));
    expect(ParsedOutboundSchema.validate(parsed.outbounds.single), isNull);

    final config = _defaultBuilder(_subscriptionFromContent(source)).build();
    final http = (config['outbounds'] as List)
        .cast<Map<String, dynamic>>()
        .singleWhere((entry) => entry['tag'] == 'alternate-http');
    expect(http['servers'], [
      {'address': 'proxy.example', 'port': 443},
    ]);
    expect(http['future_http_option'], {'mode': 'native-authoritative'});
  });

  test('untagged native entries are replaced by one tagged app copy', () {
    final source = jsonEncode({
      'outbounds': [
        {
          'type': 'ssh',
          'server': 'ssh.example',
          'server_port': 22,
          'user': 'root',
          'private_key': 'opaque',
          'future_outbound_field': 'keep-outbound',
        },
      ],
      'endpoints': [
        {
          'type': 'warp',
          'private_key': 'opaque',
          'future_endpoint_field': 'keep-endpoint',
        },
      ],
    });

    final config = _defaultBuilder(_subscriptionFromContent(source)).build();
    final outbounds = (config['outbounds'] as List)
        .cast<Map<String, dynamic>>();
    final endpoints = (config['endpoints'] as List)
        .cast<Map<String, dynamic>>();
    final sshEntries = outbounds
        .where((entry) => entry['type'] == 'ssh')
        .toList(growable: false);
    final warpEntries = endpoints
        .where((entry) => entry['type'] == 'warp')
        .toList(growable: false);

    expect(sshEntries, hasLength(1));
    expect(sshEntries.single['tag'], isNotEmpty);
    expect(sshEntries.single['future_outbound_field'], 'keep-outbound');
    expect(warpEntries, hasLength(1));
    expect(warpEntries.single['tag'], isNotEmpty);
    expect(warpEntries.single['future_endpoint_field'], 'keep-endpoint');
    expect(jsonEncode(config), isNot(contains('_etonify_')));
  });

  test(
    'inbound, service and DNS-only configs are retained without proxies',
    () {
      final source = jsonEncode({
        'dns': {
          'servers': [
            {'type': 'h3', 'tag': 'dns-only', 'server': 'dns.example'},
          ],
        },
        'inbounds': [
          {
            'type': 'mtproxy',
            'tag': 'inbound-only',
            'listen': '127.0.0.1',
            'listen_port': 8443,
            'users': const [],
          },
        ],
        'providers': [
          {'type': 'inline', 'tag': 'provider-only', 'outbounds': const []},
        ],
        'services': [
          {
            'type': 'manager-api',
            'tag': 'service-only',
            'listen': '127.0.0.1',
            'listen_port': 9090,
          },
        ],
      });

      final parsed = SubscriptionParser.parse(source);
      expect(parsed.format, SubscriptionFormat.singboxConfig);
      expect(parsed.outbounds, isEmpty);

      final plan = _defaultBuilder(
        _subscriptionFromContent(source),
      ).buildPlan();
      expect(plan.hasRawCoreConfig, isTrue);
      expect(plan.allowsZeroSelectableEntries, isTrue);
      expect(plan.visibleProxyOutboundCount, 0);
      expect(plan.proxyOutboundTagsByIndex, isEmpty);
      expect(
        (plan.config['inbounds'] as List).cast<Map>().single['tag'],
        'inbound-only',
      );
      expect(
        (plan.config['services'] as List).cast<Map>().single['tag'],
        'service-only',
      );
      expect(
        (plan.config['providers'] as List).cast<Map>().single['tag'],
        'provider-only',
      );
      final dnsServers = ((plan.config['dns'] as Map)['servers'] as List)
          .cast<Map>();
      expect(
        dnsServers.singleWhere((entry) => entry['tag'] == 'dns-only')['type'],
        'h3',
      );
    },
  );

  test('arrays of native documents keep every runtime section', () {
    final source = jsonEncode([
      {
        'outbounds': [
          {
            'type': 'socks',
            'tag': 'array-socks',
            'server': 'socks.example',
            'server_port': 1080,
          },
        ],
        'services': [
          {
            'type': 'manager-api',
            'tag': 'array-manager',
            'listen': '127.0.0.1',
            'listen_port': 9090,
          },
        ],
      },
      {
        'outbounds': [
          {
            'type': 'http',
            'tag': 'array-http',
            'server': 'http.example',
            'server_port': 8080,
          },
        ],
        'inbounds': [
          {
            'type': 'mixed',
            'tag': 'array-inbound',
            'listen': '127.0.0.1',
            'listen_port': 2080,
          },
        ],
        'providers': [
          {'type': 'inline', 'tag': 'array-provider', 'outbounds': const []},
        ],
        'dns': {
          'servers': [
            {'type': 'local', 'tag': 'array-dns'},
          ],
        },
      },
    ]);

    final parsed = SubscriptionParser.parse(source);
    expect(parsed.format, SubscriptionFormat.singboxConfig);
    expect(parsed.outbounds, hasLength(2));
    expect(parsed.outbounds.map((entry) => entry['_etonify_source_index']), [
      0,
      1,
    ]);

    final config = _defaultBuilder(_subscriptionFromContent(source)).build();
    final outbounds = (config['outbounds'] as List)
        .cast<Map<String, dynamic>>();
    expect(
      outbounds.map((entry) => entry['tag']),
      containsAll(<String>['array-socks', 'array-http']),
    );
    expect(
      (config['services'] as List).cast<Map>().single['tag'],
      'array-manager',
    );
    expect(
      (config['inbounds'] as List).cast<Map>().singleWhere(
        (entry) => entry['tag'] == 'array-inbound',
      )['type'],
      'mixed',
    );
    expect(
      (config['providers'] as List).cast<Map>().single['tag'],
      'array-provider',
    );
    expect(
      ((config['dns'] as Map)['servers'] as List).cast<Map>().singleWhere(
        (entry) => entry['tag'] == 'array-dns',
      )['type'],
      'local',
    );
  });

  test('array profiles scope duplicate outbound and provider tags', () {
    final source = jsonEncode([
      {
        'providers': [
          {
            'type': 'remote',
            'tag': 'nodes',
            'url': 'https://one.example/provider.json',
          },
        ],
        'outbounds': [
          {
            'type': 'urltest',
            'tag': 'auto',
            'providers': ['nodes'],
          },
        ],
        'route': {
          'rules': [
            {
              'domain_suffix': ['one.example'],
              'outbound': 'auto',
            },
          ],
        },
      },
      {
        'providers': [
          {
            'type': 'remote',
            'tag': 'nodes',
            'url': 'https://two.example/provider.json',
          },
        ],
        'outbounds': [
          {
            'type': 'urltest',
            'tag': 'auto',
            'providers': ['nodes'],
          },
        ],
        'route': {
          'rules': [
            {
              'domain_suffix': ['two.example'],
              'outbound': 'auto',
            },
          ],
        },
      },
    ]);

    final parsed = SubscriptionParser.parse(source);
    expect(parsed.outbounds, hasLength(2));
    expect(
      parsed.outbounds.map((entry) => entry['_etonify_original_tag']),
      containsAll(<String>['auto@profile-1', 'auto@profile-2']),
    );

    final plan = _defaultBuilder(_subscriptionFromContent(source)).buildPlan();
    expect(plan.visibleProxyOutboundCount, 2);
    expect(plan.allowsZeroSelectableEntries, isFalse);

    final providers = (plan.config['providers'] as List).cast<Map>();
    expect(
      providers.map((entry) => entry['tag']),
      containsAll(<String>['nodes@profile-1', 'nodes@profile-2']),
    );
    final outbounds = (plan.config['outbounds'] as List).cast<Map>();
    final firstGroup = outbounds.singleWhere(
      (entry) => entry['tag'] == 'auto@profile-1',
    );
    final secondGroup = outbounds.singleWhere(
      (entry) => entry['tag'] == 'auto@profile-2',
    );
    expect(firstGroup['providers'], ['nodes@profile-1']);
    expect(secondGroup['providers'], ['nodes@profile-2']);

    final rules = ((plan.config['route'] as Map)['rules'] as List).cast<Map>();
    expect(
      rules.singleWhere(
        (entry) =>
            (entry['domain_suffix'] as List?)?.contains('one.example') ?? false,
      )['outbound'],
      'auto@profile-1',
    );
    expect(
      rules.singleWhere(
        (entry) =>
            (entry['domain_suffix'] as List?)?.contains('two.example') ?? false,
      )['outbound'],
      'auto@profile-2',
    );
    expect((plan.config['route'] as Map)['final'], 'select');
  });

  test('provider-backed native groups cannot fall back to direct', () {
    final source = jsonEncode({
      'providers': [
        {
          'type': 'remote',
          'tag': 'nodes',
          'url': 'https://provider.example/config.json',
        },
      ],
      'outbounds': [
        {'type': 'urltest', 'tag': 'provider-auto', 'use_all_providers': true},
      ],
      'route': {'final': 'provider-auto'},
    });

    final plan = _defaultBuilder(_subscriptionFromContent(source)).buildPlan();
    expect(plan.visibleProxyOutboundCount, 1);
    expect(plan.allowsZeroSelectableEntries, isFalse);
    final selector = (plan.config['outbounds'] as List).cast<Map>().singleWhere(
      (entry) => entry['tag'] == 'select',
    );
    expect(selector['outbounds'], contains('provider-auto'));
    expect((plan.config['route'] as Map)['final'], 'select');
  });

  test('detour helpers stay in runtime but outside the app selector', () {
    final source = jsonEncode({
      'outbounds': [
        {
          'type': 'shadowtls',
          'tag': 'shadowtls-transport',
          'server': 'transport.example',
          'server_port': 443,
          'version': 3,
          'password': 'test-password',
          'tls': {'enabled': true, 'server_name': 'front.example'},
        },
        {
          'type': 'trojan',
          'tag': 'trojan-over-shadowtls',
          'server': 'proxy.example',
          'server_port': 443,
          'password': 'test-password',
          'detour': 'shadowtls-transport',
        },
      ],
      'route': {'final': 'trojan-over-shadowtls'},
    });

    final subscription = _subscriptionFromContent(source);
    expect(subscription.outbounds, hasLength(2));
    expect(subscription.outbounds.first.config['_group_only'], isTrue);

    final plan = _defaultBuilder(subscription).buildPlan();

    expect(plan.visibleProxyOutboundCount, 1);
    final outbounds = (plan.config['outbounds'] as List).cast<Map>();
    expect(
      outbounds.map((entry) => entry['tag']),
      containsAll(<String>[
        'shadowtls-transport',
        'trojan-over-shadowtls',
        'select',
      ]),
    );
    final selector = outbounds.singleWhere((entry) => entry['tag'] == 'select');
    expect(selector['outbounds'], ['trojan-over-shadowtls']);
    expect(selector['default'], 'trojan-over-shadowtls');
  });

  test(
    'HydraBox builder consumes native config and selects explicit profiles only',
    () {
      final sourceDocument = _hydraboxBuilderDocument();
      final subscription = _hydraboxSubscriptionFromContent(
        jsonEncode(sourceDocument),
      );

      expect(subscription.profiles, hasLength(1));
      expect(subscription.selectedProfileId, 'profile-main');
      expect(subscription.selectedProxyTag, 'profile-out');

      final plan = _defaultBuilder(
        subscription,
        capabilities: _hydraboxTestCapabilities(),
      ).buildPlan();
      expect(plan.hasRawCoreConfig, isTrue);
      expect(plan.visibleProxyOutboundCount, 1);

      final outbounds = (plan.config['outbounds'] as List).cast<Map>();
      expect(
        outbounds.map((entry) => entry['tag']),
        containsAll(<String>['profile-out', 'helper-out', 'select']),
      );
      final selector = outbounds.singleWhere(
        (entry) => entry['tag'] == 'select',
      );
      expect(selector['outbounds'], ['profile-out']);
      expect(selector['default'], 'profile-out');

      final profile = outbounds.singleWhere(
        (entry) => entry['tag'] == 'profile-out',
      );
      final sourceRuntime = sourceDocument['runtime'] as Map<String, dynamic>;
      final sourceNative = sourceRuntime['document'] as Map<String, dynamic>;
      final sourceOutbounds = (sourceNative['outbounds'] as List)
          .cast<Map<String, dynamic>>();
      expect(profile, sourceOutbounds.first);
      expect(profile['future_protocol_field'], {'kept': true});
      expect(profile.containsKey('_hydrabox_profile_id'), isFalse);
      expect(profile.containsKey('_group_only'), isFalse);
      expect(profile.containsKey('_etonify_original_tag'), isFalse);

      final helper = outbounds.singleWhere(
        (entry) => entry['tag'] == 'helper-out',
      );
      expect(helper['type'], 'shadowtls');
      expect(helper, sourceOutbounds[1]);
      expect(helper.containsKey('_group_only'), isFalse);
      expect((selector['outbounds'] as List), isNot(contains('helper-out')));

      final endpoints = (plan.config['endpoints'] as List).cast<Map>();
      final wireGuard = endpoints.singleWhere(
        (entry) => entry['tag'] == 'wg-helper',
      );
      final sourceEndpoints = (sourceNative['endpoints'] as List)
          .cast<Map<String, dynamic>>();
      expect(wireGuard, sourceEndpoints.single);
      expect(wireGuard['reserved'], [0, 0, 0]);
      expect((wireGuard['peers'] as List).single['reserved'], [0, 0, 0]);
      expect(wireGuard['amnezia'], {
        'jc': 120,
        'jmin': 23,
        'jmax': 911,
        's1': 1,
        's2': 2,
        's3': 3,
        's4': 4,
        'h1': 1,
        'h2': 2,
        'h3': 3,
        'h4': 4,
      });
    },
  );

  test(
    'HydraBox activation requires a trusted versioned HydraCore contract',
    () {
      final subscription = _hydraboxSubscriptionFromContent(
        jsonEncode(_hydraboxBuilderDocument()),
      );

      expect(() => _defaultBuilder(subscription).buildPlan(), throwsStateError);
    },
  );

  test('HydraBox activation rechecks stored subscription expiry', () {
    final now = DateTime.now().toUtc();
    final source = _hydraboxBuilderDocument()
      ..['issued_at'] = now.subtract(const Duration(hours: 2)).toIso8601String()
      ..['expires_at'] = now
          .subtract(const Duration(minutes: 10))
          .toIso8601String();
    final subscription = _hydraboxSubscriptionFromContent(jsonEncode(source));

    expect(
      () => _defaultBuilder(
        subscription,
        capabilities: _hydraboxTestCapabilities(),
      ).buildPlan(),
      throwsA(
        isA<StateError>().having(
          (error) => error.toString(),
          'message',
          contains('expired'),
        ),
      ),
    );
  });

  test('remote policy v1 cannot be widened by an advertised future type', () {
    final source = _hydraboxBuilderDocument();
    final runtime = source['runtime'] as Map<String, dynamic>;
    final native = runtime['document'] as Map<String, dynamic>;
    (native['outbounds'] as List<dynamic>).add({
      'type': 'future-leaf-protocol',
      'tag': 'future-helper',
      'server': 'future.example',
      'future_option': {'kept': true},
    });
    final subscription = _hydraboxSubscriptionFromContent(jsonEncode(source));

    expect(
      () => _defaultBuilder(
        subscription,
        capabilities: _hydraboxTestCapabilities(),
      ).buildPlan(),
      throwsStateError,
    );

    expect(
      () => _defaultBuilder(
        subscription,
        capabilities: _hydraboxTestCapabilities(
          extraOutboundTypes: const {'future-leaf-protocol'},
        ),
      ).buildPlan(),
      throwsStateError,
    );
  });

  test('remote policy v1 cannot re-enable recursive executable sources', () {
    final composite = _hydraboxBuilderDocument();
    final compositeRuntime = composite['runtime'] as Map<String, dynamic>;
    final compositeNative =
        compositeRuntime['document'] as Map<String, dynamic>;
    (compositeNative['outbounds'] as List<dynamic>).add({
      'type': 'bond',
      'tag': 'recursive-bond',
      'outbounds': [
        {
          'outbound': {'type': 'tor', 'tag': 'nested-tor'},
          'download_ratio': 1,
          'upload_ratio': 1,
          'count': 1,
        },
      ],
    });
    final compositeSubscription = _hydraboxSubscriptionFromContent(
      jsonEncode(composite),
    );
    expect(
      () => _defaultBuilder(
        compositeSubscription,
        capabilities: _hydraboxTestCapabilities(
          extraOutboundTypes: const {'bond', 'tor'},
        ),
      ).buildPlan(),
      throwsStateError,
    );

    final provider = _hydraboxBuilderDocument();
    final providerRuntime = provider['runtime'] as Map<String, dynamic>;
    final providerNative = providerRuntime['document'] as Map<String, dynamic>;
    providerNative['providers'] = [
      {
        'type': 'inline',
        'tag': 'recursive-provider',
        'outbounds': [
          {'type': 'tor', 'tag': 'provider-tor'},
        ],
      },
    ];
    final providerSubscription = _hydraboxSubscriptionFromContent(
      jsonEncode(provider),
    );
    expect(
      () => _defaultBuilder(
        providerSubscription,
        capabilities: _hydraboxTestCapabilities(
          extraTopLevelFields: const {'providers'},
          extraOutboundTypes: const {'tor'},
          extraProviderTypes: const {'inline'},
        ),
      ).buildPlan(),
      throwsStateError,
    );
  });

  test('builder revalidates local authority in hydrated HydraBox payloads', () {
    final original = _hydraboxSubscriptionFromContent(
      jsonEncode(_hydraboxBuilderDocument()),
    );
    for (final mutate in <void Function(Map<String, dynamic>)>[
      (native) =>
          ((native['outbounds'] as List<dynamic>).first
                  as Map<String, dynamic>)['private_key_path'] =
              '/data/local/tmp/provider-key',
      (native) => native['log'] = {'output': '/data/local/tmp/provider.log'},
    ]) {
      final native =
          jsonDecode(jsonEncode(original.nativeConfig)) as Map<String, dynamic>;
      mutate(native);
      expect(
        () => _defaultBuilder(
          original.copyWith(nativeConfig: native),
          capabilities: _hydraboxTestCapabilities(),
        ).buildPlan(),
        throwsStateError,
      );
    }
  });

  test('remote policy v1 bounds WireGuard and Amnezia resource knobs', () {
    final mutations = <void Function(Map<String, dynamic>)>[
      (endpoint) => endpoint['workers'] = -1,
      (endpoint) => endpoint['workers'] = 65,
      (endpoint) => endpoint['preallocated_buffers_per_pool'] = 4097,
      (endpoint) => (endpoint['amnezia'] as Map<String, dynamic>)['jc'] = 129,
      (endpoint) {
        final amnezia = endpoint['amnezia'] as Map<String, dynamic>;
        amnezia['jmin'] = 912;
        amnezia['jmax'] = 911;
      },
      (endpoint) {
        final amnezia = endpoint['amnezia'] as Map<String, dynamic>;
        amnezia['jc'] = 128;
        amnezia['jmax'] = 32769;
      },
      (endpoint) => (endpoint['amnezia'] as Map<String, dynamic>)['s4'] = 65536,
    ];

    for (final mutate in mutations) {
      final source = _hydraboxBuilderDocument();
      final runtime = source['runtime'] as Map<String, dynamic>;
      final native = runtime['document'] as Map<String, dynamic>;
      final endpoint =
          (native['endpoints'] as List<dynamic>).single as Map<String, dynamic>;
      mutate(endpoint);
      final subscription = _hydraboxSubscriptionFromContent(jsonEncode(source));

      expect(
        () => _defaultBuilder(
          subscription,
          capabilities: _hydraboxTestCapabilities(),
        ).buildPlan(),
        throwsStateError,
      );
    }
  });

  test('remote policy v1 closes references and rejects detour cycles', () {
    for (final mutation in <void Function(List<dynamic>)>[
      (outbounds) =>
          (outbounds.first as Map<String, dynamic>)['detour'] = 'direct',
      (outbounds) =>
          (outbounds.last as Map<String, dynamic>)['detour'] = 'profile-out',
    ]) {
      final source = _hydraboxBuilderDocument();
      final runtime = source['runtime'] as Map<String, dynamic>;
      final native = runtime['document'] as Map<String, dynamic>;
      mutation(native['outbounds'] as List<dynamic>);
      final subscription = _hydraboxSubscriptionFromContent(jsonEncode(source));
      expect(
        () => _defaultBuilder(
          subscription,
          capabilities: _hydraboxTestCapabilities(),
        ).buildPlan(),
        throwsStateError,
      );
    }
  });

  test('remote policy v2 activates a JWE-only WDTT endpoint losslessly', () {
    final source = _hydraboxBuilderDocument();
    final runtime = source['runtime'] as Map<String, dynamic>;
    final native = runtime['document'] as Map<String, dynamic>;
    native['endpoints'] = [
      {
        'type': 'wdtt',
        'tag': 'provider-wdtt',
        'server': '203.0.113.10',
        'server_port': 56000,
        'password': 'subscription-secret',
        'vk_hashes': ['8UkewARpV0aJoWheFZlR942el6unTZvhneulo-eU8gA'],
        'workers': 9,
        'obfs': 'audio',
        'vk_auth': 'anonymous',
        'vk_anon_path': 'vkcalls',
      },
    ];
    source['default_profile_id'] = 'wdtt-profile';
    source['profiles'] = [
      {
        'id': 'wdtt-profile',
        'name': {'default': 'WDTT Moscow'},
        'entrypoint': {'section': 'endpoints', 'tag': 'provider-wdtt'},
      },
    ];
    final key = base64Url
        .encode(List<int>.generate(32, (index) => index))
        .replaceAll('=', '');
    final encrypted = HydraBoxJweCodec.encrypt(
      jsonEncode(source),
      encodedKey: key,
    );
    final subscription = _hydraboxSubscriptionFromContent(
      encrypted,
      decryptionKey: key,
    );

    final plan = _defaultBuilder(
      subscription,
      capabilities: _hydraboxTestCapabilities(
        remotePolicyVersion: 2,
        extraEndpointTypes: const {'wdtt'},
        supportsWdtt: true,
      ),
    ).buildPlan();
    final endpoint = (plan.config['endpoints'] as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .singleWhere((entry) => entry['tag'] == 'provider-wdtt');
    expect(endpoint, native['endpoints']!.first);
    expect(endpoint, isNot(contains('device_id')));
    expect(endpoint, isNot(contains('listen_port')));
    expect(
      (plan.config['outbounds'] as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .where((entry) => entry['type'] == 'wdtt'),
      isEmpty,
    );
  });

  test('remote policy v2 rejects WDTT runtime authority and resource abuse', () {
    final mutations = <void Function(Map<String, dynamic>)>[
      (endpoint) => endpoint['workers'] = 37,
      (endpoint) => endpoint['vk_hashes'] = ['a', 'b', 'c', 'd', 'e'],
      (endpoint) => endpoint['device_id'] = 'publisher-owned',
      (endpoint) => endpoint['listen_port'] = 9000,
      (endpoint) => endpoint['detour'] = 'profile-out',
      (endpoint) => endpoint['vk_auth'] = 'account',
    ];
    final key = base64Url
        .encode(List<int>.generate(32, (index) => index))
        .replaceAll('=', '');
    for (final mutate in mutations) {
      final source = _hydraboxBuilderDocument();
      final runtime = source['runtime'] as Map<String, dynamic>;
      final native = runtime['document'] as Map<String, dynamic>;
      final endpoint = <String, dynamic>{
        'type': 'wdtt',
        'tag': 'provider-wdtt',
        'server': '203.0.113.10',
        'server_port': 56000,
        'password': 'subscription-secret',
        'vk_hashes': ['hash'],
      };
      mutate(endpoint);
      native['endpoints'] = [endpoint];
      source['default_profile_id'] = 'wdtt-profile';
      source['profiles'] = [
        {
          'id': 'wdtt-profile',
          'name': {'default': 'WDTT'},
          'entrypoint': {'section': 'endpoints', 'tag': 'provider-wdtt'},
        },
      ];
      final encrypted = HydraBoxJweCodec.encrypt(
        jsonEncode(source),
        encodedKey: key,
      );
      expect(
        () {
          final subscription = _hydraboxSubscriptionFromContent(
            encrypted,
            decryptionKey: key,
          );
          return _defaultBuilder(
            subscription,
            capabilities: _hydraboxTestCapabilities(
              remotePolicyVersion: 2,
              extraEndpointTypes: const {'wdtt'},
              supportsWdtt: true,
            ),
          ).buildPlan();
        },
        throwsA(anyOf(isA<FormatException>(), isA<StateError>())),
      );
    }
  });

  test('HydraBox builder refuses tag remapping for persisted opaque data', () {
    final subscription = _hydraboxSubscriptionFromContent(
      jsonEncode(_hydraboxBuilderDocument()),
    );
    final tamperedOutbounds = subscription.outbounds
        .map(
          (outbound) => outbound.tag == 'profile-out'
              ? outbound.copyWith(tag: 'renamed-profile-out')
              : outbound,
        )
        .toList(growable: false);

    expect(
      () => _defaultBuilder(
        subscription.copyWith(outbounds: tamperedOutbounds),
        capabilities: _hydraboxTestCapabilities(),
      ).buildPlan(),
      throwsStateError,
    );
  });

  test(
    'HydraBox future-only zero-profile document is retained but not activated',
    () {
      final source = _hydraboxBuilderDocument()
        ..remove('default_profile_id')
        ..['profiles'] = <dynamic>[];
      final runtime = source['runtime'] as Map<String, dynamic>;
      runtime['document'] = {
        'future_safe_section': {
          'opaque': {'version': 7, 'outbound': 'not-a-reference-to-rewrite'},
        },
      };

      final subscription = _hydraboxSubscriptionFromContent(jsonEncode(source));
      expect(subscription.outbounds, isEmpty);
      expect(subscription.profiles, isEmpty);

      expect(subscription.nativeConfig?['future_safe_section'], {
        'opaque': {'version': 7, 'outbound': 'not-a-reference-to-rewrite'},
      });
      expect(
        () => _defaultBuilder(
          subscription,
          capabilities: _hydraboxTestCapabilities(),
        ).buildPlan(),
        throwsStateError,
      );
    },
  );

  test('checked-in HydraBox example matches the exact policy-v1 manifest', () {
    final source = File(
      'docs/examples/hydrabox-subscription-v1.json',
    ).readAsStringSync();
    final subscription = _hydraboxSubscriptionFromContent(source);
    final native = subscription.nativeConfig!;
    const safeTopLevel = <String>{r'$schema', 'outbounds', 'endpoints'};
    expect(native.keys.every(safeTopLevel.contains), isTrue);
    expect(
      (native['outbounds'] as List<dynamic>)
          .map((entry) => (entry as Map)['type'])
          .toSet(),
      everyElement(isIn(_hydraPolicyV1OutboundTypes)),
    );

    final plan = _defaultBuilder(
      subscription,
      capabilities: _hydraboxTestCapabilities(),
    ).buildPlan();
    expect(plan.hasRawCoreConfig, isTrue);
  });

  test('endpoint-only configs stay selectable and never become outbounds', () {
    final rawEndpoints = <Map<String, dynamic>>[
      {
        'type': 'wireguard',
        'tag': 'wg',
        'address': ['10.0.0.2/32'],
        'private_key': 'opaque',
        'peers': const [],
      },
      {'type': 'warp', 'tag': 'warp', 'private_key': 'opaque'},
      {
        'type': 'tailscale',
        'tag': 'tailnet',
        'state_directory': '/tmp/tailscale',
      },
      {'type': 'vpn-client', 'tag': 'vpn-client', 'server': 'vpn.example'},
      {'type': 'vpn-server', 'tag': 'vpn-server', 'listen': '127.0.0.1'},
    ];
    final source = jsonEncode({'endpoints': rawEndpoints});

    final parsed = SubscriptionParser.parse(source);
    expect(parsed.format, SubscriptionFormat.singboxConfig);
    expect(parsed.outbounds, hasLength(rawEndpoints.length));
    expect(
      parsed.outbounds.map((entry) => entry['type']),
      containsAll(
        ExtendedCoreProtocolCatalog.endpointTypes.difference(const {'wdtt'}),
      ),
    );
    expect(
      parsed.outbounds,
      everyElement(containsPair('_etonify_source_section', 'endpoints')),
    );

    final plan = _defaultBuilder(_subscriptionFromContent(source)).buildPlan();
    final config = plan.config;
    expect(plan.visibleProxyOutboundCount, rawEndpoints.length);
    expect(plan.allowsZeroSelectableEntries, isFalse);
    expect(plan.proxyOutboundTagsByIndex, isEmpty);
    expect(config['endpoints'], rawEndpoints);

    final outbounds = (config['outbounds'] as List)
        .cast<Map<String, dynamic>>();
    expect(
      outbounds.where(
        (entry) =>
            ExtendedCoreProtocolCatalog.endpointTypes.contains(entry['type']),
      ),
      isEmpty,
    );
    final selector = outbounds.firstWhere((entry) => entry['tag'] == 'select');
    expect(
      selector['outbounds'],
      containsAll(rawEndpoints.map((entry) => entry['tag'])),
    );
  });

  test('direct sing-box WDTT endpoints are rejected outside HydraBox JWE', () {
    final source = jsonEncode({
      'endpoints': [
        {
          'type': 'wdtt',
          'tag': 'direct-wdtt',
          'server': '203.0.113.10',
          'server_port': 56000,
          'password': 'must-not-import',
          'vk_hashes': ['hash'],
        },
      ],
    });

    expect(() => SubscriptionParser.parse(source), throwsFormatException);

    final forgedStoredSubscription = Subscription(
      id: 'forged-direct-wdtt',
      name: 'Forged direct WDTT',
      url: 'file:///forged-direct-wdtt.json',
      rawContent: source,
    );
    expect(
      () => _defaultBuilder(forgedStoredSubscription).buildPlan(),
      throwsStateError,
    );

    final forgedOutboundSource = jsonEncode({
      'outbounds': [
        {
          'type': 'wdtt',
          'tag': 'invalid-outbound-wdtt',
          'server': '203.0.113.10',
          'server_port': 56000,
          'password': 'must-not-import',
          'vk_hashes': ['hash'],
        },
      ],
    });
    expect(
      () => _defaultBuilder(
        Subscription(
          id: 'forged-outbound-wdtt',
          name: 'Forged outbound WDTT',
          url: 'file:///forged-outbound-wdtt.json',
          rawContent: forgedOutboundSource,
        ),
      ).buildPlan(),
      throwsStateError,
    );
  });

  test('reserved native tags are remapped across full-config references', () {
    final source = jsonEncode({
      'endpoints': [
        {
          'type': 'wireguard',
          'tag': 'select',
          'address': ['10.0.0.2/32'],
          'private_key': 'opaque',
          'peers': const [],
        },
      ],
      'outbounds': [
        {
          'type': 'selector',
          'tag': 'raw-selector',
          'outbounds': ['select'],
          'default': 'select',
        },
        {
          'type': 'vless',
          'tag': 'managed-vless',
          'server': 'vless.example',
          'server_port': 443,
          'uuid': '00000000-0000-4000-8000-000000000001',
          'detour': 'select',
        },
      ],
      'experimental': {
        'clash_api': {'external_ui_download_detour': 'select'},
      },
      'services': [
        {
          'type': 'derp',
          'tag': 'derp-service',
          'verify_client_endpoint': ['select'],
        },
      ],
      'dns': {
        'servers': [
          {'type': 'local', 'tag': 'select'},
          {'type': 'tailscale', 'tag': 'tailscale-dns', 'endpoint': 'select'},
        ],
        'rules': [
          {
            'domain_suffix': ['dns-namespace.example'],
            'action': 'route',
            'server': 'select',
          },
        ],
      },
      'route': {
        'geoip': {'path': 'geoip.db', 'download_detour': 'select'},
        'rule_set': [
          {
            'type': 'remote',
            'tag': 'remote-rules',
            'url': 'https://rules.example/rules.srs',
            'download_detour': 'select',
          },
        ],
        'rules': [
          {
            'domain_suffix': ['remap.example'],
            'outbound': 'select',
          },
        ],
        'final': 'select',
      },
    });
    final parsed = SubscriptionParser.parse(source);
    final endpointConfig = Map<String, dynamic>.from(
      parsed.outbounds.singleWhere((entry) => entry['type'] == 'wireguard'),
    )..remove('_name');
    endpointConfig['tag'] = 'wireguard-0';
    final vlessConfig = Map<String, dynamic>.from(
      parsed.outbounds.singleWhere((entry) => entry['type'] == 'vless'),
    )..remove('_name');
    final subscription = Subscription(
      id: 'remapped-endpoint',
      name: 'Remapped endpoint',
      url: '',
      rawContent: source,
      outbounds: [
        Outbound(tag: 'wireguard-0', name: 'select', config: endpointConfig),
        Outbound(
          tag: 'managed-vless',
          name: 'managed-vless',
          config: vlessConfig,
        ),
      ],
    );

    final config = _defaultBuilder(subscription).build();
    final endpoints = (config['endpoints'] as List)
        .cast<Map<String, dynamic>>();
    expect(endpoints.single['tag'], 'wireguard-0');

    final route = config['route'] as Map;
    final rules = (route['rules'] as List).cast<Map<String, dynamic>>();
    final remappedRule = rules.firstWhere(
      (entry) => entry['domain_suffix'] is List,
    );
    expect(remappedRule['outbound'], 'wireguard-0');
    expect((route['geoip'] as Map)['download_detour'], 'wireguard-0');
    expect(
      ((route['rule_set'] as List).cast<Map>().singleWhere(
        (entry) => entry['tag'] == 'remote-rules',
      ))['download_detour'],
      'wireguard-0',
    );
    expect(route['final'], 'select');

    final dns = config['dns'] as Map;
    final dnsRules = (dns['rules'] as List).cast<Map<String, dynamic>>();
    final dnsNamespaceRule = dnsRules.firstWhere(
      (entry) => entry['domain_suffix'] is List,
    );
    expect(dnsNamespaceRule['server'], 'select');
    final tailscaleDns = (dns['servers'] as List).cast<Map>().singleWhere(
      (entry) => entry['tag'] == 'tailscale-dns',
    );
    expect(tailscaleDns['endpoint'], 'wireguard-0');

    final derpService = (config['services'] as List).cast<Map>().singleWhere(
      (entry) => entry['tag'] == 'derp-service',
    );
    expect(derpService['verify_client_endpoint'], ['wireguard-0']);

    final outbounds = (config['outbounds'] as List)
        .cast<Map<String, dynamic>>();
    final selector = outbounds.firstWhere((entry) => entry['tag'] == 'select');
    expect(selector['outbounds'], contains('wireguard-0'));
    final rawSelector = outbounds.firstWhere(
      (entry) => entry['tag'] == 'raw-selector',
    );
    expect(rawSelector['outbounds'], ['wireguard-0']);
    expect(rawSelector['default'], 'wireguard-0');
    final managedVless = outbounds.firstWhere(
      (entry) => entry['tag'] == 'managed-vless',
    );
    expect(managedVless['detour'], 'wireguard-0');
    expect(
      ((config['experimental'] as Map)['clash_api']
          as Map)['external_ui_download_detour'],
      'wireguard-0',
    );
  });

  test('WireGuard ini imports are migrated to a top-level endpoint', () {
    const source = '''
[Interface]
PrivateKey = opaque-private-key
Address = 10.0.0.2/32

[Peer]
PublicKey = opaque-public-key
AllowedIPs = 0.0.0.0/0
Endpoint = wg.example:51820
PersistentKeepalive = 25
''';

    final parsed = SubscriptionParser.parse(source);
    expect(parsed.format, SubscriptionFormat.wireguardConfig);
    expect(parsed.outbounds, hasLength(1));
    expect(parsed.outbounds.single['_etonify_source_section'], 'endpoints');

    final config = _defaultBuilder(_subscriptionFromContent(source)).build();
    final endpoints = (config['endpoints'] as List)
        .cast<Map<String, dynamic>>();
    expect(endpoints, hasLength(1));
    expect(endpoints.single['type'], 'wireguard');
    expect(endpoints.single, isNot(contains('_etonify_source_section')));

    final outbounds = (config['outbounds'] as List)
        .cast<Map<String, dynamic>>();
    expect(outbounds.where((entry) => entry['type'] == 'wireguard'), isEmpty);
    final selector = outbounds.firstWhere((entry) => entry['tag'] == 'select');
    expect(selector['outbounds'], contains(endpoints.single['tag']));
  });

  test('removed outbound stubs are excluded while endpoints remain', () {
    final source = jsonEncode({
      'endpoints': [
        {
          'type': 'wireguard',
          'tag': 'wg-endpoint',
          'address': ['10.0.0.2/32'],
          'private_key': 'opaque',
          'peers': const [],
        },
      ],
      'outbounds': [
        {'type': 'dns', 'tag': 'legacy-dns-outbound'},
        {
          'type': 'shadowsocksr',
          'tag': 'ssr',
          'server': 'example.com',
          'server_port': 443,
          'method': 'aes-128-ctr',
          'password': 'secret',
        },
        {
          'type': 'wireguard',
          'tag': 'legacy-wireguard-outbound',
          'server': 'wg.example',
          'server_port': 51820,
          'system_interface': true,
          'interface_name': 'wg0',
          'local_address': ['10.0.0.2/32'],
          'private_key': 'opaque',
          'peer_public_key': 'peer-key',
          'pre_shared_key': 'psk',
          'reserved': [0, 0, 0],
          'gso': true,
          'network': 'udp',
        },
        {
          'type': 'ssh',
          'tag': 'ssh',
          'server': 'example.com',
          'server_port': 22,
          'user': 'root',
          'private_key': 'opaque',
        },
      ],
    });

    final parsed = SubscriptionParser.parse(source);
    final parsedOutbounds = parsed.outbounds.where(
      (entry) => entry['_etonify_source_section'] == 'outbounds',
    );
    final parsedEndpoints = parsed.outbounds.where(
      (entry) => entry['_etonify_source_section'] == 'endpoints',
    );
    expect(parsedOutbounds, hasLength(1));
    expect(parsedOutbounds.single['type'], 'ssh');
    expect(parsedEndpoints, hasLength(2));
    expect(
      parsedEndpoints.every((entry) => entry['type'] == 'wireguard'),
      isTrue,
    );
    final migrated = parsedEndpoints.singleWhere(
      (entry) => entry['_etonify_original_tag'] == 'legacy-wireguard-outbound',
    );
    expect(migrated['system'], isTrue);
    expect(migrated['name'], 'wg0');
    expect(migrated['address'], ['10.0.0.2/32']);
    expect(migrated, isNot(contains('server')));
    expect(migrated, isNot(contains('gso')));
    expect(migrated, isNot(contains('network')));
    expect((migrated['peers'] as List).single, {
      'address': 'wg.example',
      'port': 51820,
      'public_key': 'peer-key',
      'pre_shared_key': 'psk',
      'allowed_ips': ['0.0.0.0/0', '::/0'],
    });

    final config = _defaultBuilder(_subscriptionFromContent(source)).build();
    final outbounds = (config['outbounds'] as List)
        .cast<Map<String, dynamic>>();
    expect(
      outbounds.where(
        (entry) =>
            const {'dns', 'shadowsocksr', 'wireguard'}.contains(entry['type']),
      ),
      isEmpty,
    );
    expect(config['endpoints'], hasLength(2));
    final runtimeMigrated = (config['endpoints'] as List)
        .cast<Map<String, dynamic>>()
        .singleWhere((entry) => entry['tag'] == 'legacy-wireguard-outbound');
    expect(runtimeMigrated, isNot(contains('server')));
    expect(runtimeMigrated['peers'], migrated['peers']);
  });

  test('legacy WireGuard peer arrays are migrated to endpoint peer fields', () {
    final source = jsonEncode({
      'outbounds': [
        {
          'type': 'wireguard',
          'tag': 'legacy-wireguard-peers',
          'local_address': ['10.0.0.2/32'],
          'private_key': 'opaque-private-key',
          'peers': [
            {
              'server': 'first.wg.example',
              'server_port': 51820,
              'peer_public_key': 'first-public-key',
            },
            {
              'server': 'second.wg.example',
              'server_port': 51821,
              'peer_public_key': 'second-public-key',
              'allowed_ips': ['10.0.0.0/8'],
            },
          ],
        },
      ],
    });
    final parsed = SubscriptionParser.parse(source).outbounds.single;

    expect(parsed['_etonify_source_section'], 'endpoints');
    expect(parsed['address'], ['10.0.0.2/32']);
    expect(parsed, isNot(contains('local_address')));
    final peers = (parsed['peers'] as List).cast<Map>();
    expect(peers, hasLength(2));
    expect(peers[0], {
      'address': 'first.wg.example',
      'port': 51820,
      'public_key': 'first-public-key',
      'allowed_ips': ['0.0.0.0/0', '::/0'],
    });
    expect(peers[1], {
      'address': 'second.wg.example',
      'port': 51821,
      'public_key': 'second-public-key',
      'allowed_ips': ['10.0.0.0/8'],
    });
    expect(peers, everyElement(isNot(contains('server'))));
    expect(peers, everyElement(isNot(contains('server_port'))));
    expect(peers, everyElement(isNot(contains('peer_public_key'))));

    final runtime = _defaultBuilder(_subscriptionFromContent(source)).build();
    expect(
      ((runtime['endpoints'] as List).cast<Map>().single['peers'] as List),
      peers,
    );
  });

  test(
    'non-zero legacy WireGuard reserved override is rejected explicitly',
    () {
      final parsed = SubscriptionParser.parse(
        jsonEncode({
          'outbounds': [
            {
              'type': 'wireguard',
              'tag': 'legacy-wireguard-reserved',
              'server': 'wg.example',
              'server_port': 51820,
              'local_address': ['10.0.0.2/32'],
              'private_key': 'opaque',
              'peer_public_key': 'peer-key',
              'reserved': [1, 2, 3],
            },
          ],
        }),
      ).outbounds.single;

      expect((parsed['peers'] as List).single['reserved'], [1, 2, 3]);
      expect(
        ParsedOutboundSchema.validate(parsed),
        contains('unsupported wireguard peer 0 reserved override'),
      );
    },
  );
}

Map<String, dynamic> _fullExtendedConfig() {
  return {
    'experimental': {
      'extended_feature': {'enabled': true},
    },
    'dns': {
      'servers': [
        {
          'type': 'sdns',
          'tag': 'secure-dns',
          'address': 'sdns://example',
          'future_option': {'keep': true},
        },
      ],
    },
    'route': {
      'rules': [
        {
          'domain_suffix': ['internal.example'],
          'outbound': 'bond-node',
        },
      ],
    },
    'endpoints': [
      {
        'type': 'wireguard',
        'tag': 'wg-endpoint',
        'address': ['10.0.0.2/32'],
        'private_key': 'opaque',
        'peers': const [],
      },
      {'type': 'warp', 'tag': 'warp-endpoint', 'private_key': 'opaque'},
    ],
    'providers': [
      {
        'type': 'remote',
        'tag': 'remote-provider',
        'url': 'https://provider.example/config.json',
      },
    ],
    'services': [
      {
        'type': 'manager-api',
        'tag': 'manager',
        'listen': '127.0.0.1',
        'listen_port': 9090,
      },
    ],
    'inbounds': [
      {
        'type': 'mtproxy',
        'tag': 'mt-in',
        'listen': '127.0.0.1',
        'listen_port': 8443,
        'users': const [],
        'future_inbound_field': 'preserve-me',
      },
    ],
    'outbounds': [
      {
        'type': 'masque',
        'tag': 'masque-node',
        'profile': {'token': 'opaque', 'future_profile_field': true},
        'tls': {
          'server_name': 'masque.example',
          'future_tls_field': 'preserve-me',
        },
        'transport': {
          'type': 'xhttp',
          'mode': 'stream-up',
          'future_transport_field': 'preserve-me',
        },
        'future_outbound_field': {
          'nested': [1, 2, 3],
        },
      },
      {
        'type': 'vless',
        'tag': 'encrypted-vless',
        'server': 'vless.example',
        'server_port': 443,
        'uuid': '00000000-0000-4000-8000-000000000001',
        'encryption': 'mlkem768x25519plus.native.0rtt.extended-value',
        'tls': {
          'enabled': true,
          'alpn': ['custom-alpn', 'h2'],
        },
        'transport': {'type': 'grpc', 'service_name': 'extended'},
      },
      {
        'type': 'hysteria2',
        'tag': 'hy2-node',
        'server': 'hy2.example',
        'server_port': 443,
        'password': 'secret',
        'tls': {
          'enabled': true,
          'utls': {
            'enabled': true,
            'fingerprint': 'firefox',
            'future_utls_field': true,
          },
        },
      },
      {
        'type': 'bond',
        'tag': 'bond-node',
        'outbounds': [
          {
            'outbound': {'type': 'direct', 'tag': 'nested-direct'},
            'download_ratio': 1,
            'upload_ratio': 1,
            'count': 1,
          },
        ],
        'future_group_field': true,
      },
    ],
  };
}

Subscription _subscriptionFromContent(String source) {
  final parsed = SubscriptionParser.parse(source);
  final payload = SubscriptionStore.buildSubscriptionPayloadForTest(parsed);
  final outbounds = payload.outbounds
      .map(Outbound.fromMap)
      .toList(growable: false);
  return Subscription(
    id: 'extended',
    name: 'Extended',
    url: '',
    rawContent: source,
    outbounds: outbounds,
  );
}

Subscription _hydraboxSubscriptionFromContent(
  String source, {
  String? decryptionKey,
}) {
  final parsed = SubscriptionParser.parse(
    source,
    decryptionKey: decryptionKey,
  );
  final payload = SubscriptionStore.buildSubscriptionPayloadForTest(parsed);
  final outbounds = payload.outbounds
      .map(Outbound.fromMap)
      .toList(growable: false);
  final profiles = parsed.profiles
      .map((profile) {
        final outbound = outbounds.singleWhere((candidate) {
          final sourceSection =
              candidate.config['_etonify_source_index_section']?.toString() ??
              candidate.config['_etonify_source_section']?.toString() ??
              '';
          final sourceTag =
              candidate.config['_etonify_original_tag']?.toString() ?? '';
          return sourceSection == profile.entrypointSection &&
              sourceTag == profile.entrypointTag;
        });
        return SubscriptionProfile(
          id: profile.id,
          name: profile.name,
          entrypointSection: profile.entrypointSection,
          entrypointTag: profile.entrypointTag,
          runtimeTag: outbound.tag,
          enabled: profile.enabled,
          country: profile.country,
          metadata: profile.metadata,
        );
      })
      .toList(growable: false);
  SubscriptionProfile? selected;
  for (final profile in profiles) {
    if (profile.id == parsed.defaultProfileId) {
      selected = profile;
      break;
    }
  }
  return Subscription(
    id: 'hydrabox-builder',
    name: 'HydraBox builder',
    url: 'https://provider.example/subscription',
    selectedProxyTag: selected?.runtimeTag ?? '',
    selectedProfileId: selected?.id ?? '',
    rawContent: source,
    outbounds: outbounds,
    profiles: profiles,
    nativeConfig: parsed.nativeConfig,
    sourceMetadata: parsed.sourceMetadata,
  );
}

Map<String, dynamic> _hydraboxBuilderDocument() => {
  'api_version': 'hydrabox.io/subscription/v1',
  'kind': 'SubscriptionData',
  'issuer': 'https://provider.example',
  'subscription_id': 'builder-main',
  'channel': 'stable',
  'sequence': 11,
  'issued_at': '2026-07-30T18:00:00Z',
  'default_profile_id': 'profile-main',
  'runtime': {
    'format': 'sing-box-json',
    'ownership': {
      'inbounds': 'client',
      'route_final': 'selected-profile',
      'dns': 'merge-safe',
      'route_rules': 'merge-safe',
      'log': 'client-overlay',
      'global': 'client-overlay',
    },
    'document': {
      'outbounds': [
        {
          'type': 'trojan',
          'tag': 'profile-out',
          'server': 'proxy.example',
          'server_port': 443,
          'password': 'secret',
          'detour': 'helper-out',
          'future_protocol_field': {'kept': true},
        },
        {
          'type': 'shadowtls',
          'tag': 'helper-out',
          'server': 'transport.example',
          'server_port': 443,
          'version': 3,
          'password': 'secret',
        },
      ],
      'endpoints': [
        {
          'type': 'wireguard',
          'tag': 'wg-helper',
          'address': ['10.0.0.2/32'],
          'private_key': 'opaque-private-key',
          'reserved': [0, 0, 0],
          'amnezia': {
            'jc': 120,
            'jmin': 23,
            'jmax': 911,
            's1': 1,
            's2': 2,
            's3': 3,
            's4': 4,
            'h1': 1,
            'h2': 2,
            'h3': 3,
            'h4': 4,
          },
          'peers': [
            {
              'address': '192.0.2.1',
              'port': 51820,
              'public_key': 'opaque-public-key',
              'allowed_ips': ['0.0.0.0/0', '::/0'],
              'reserved': [0, 0, 0],
            },
          ],
        },
      ],
    },
  },
  'profiles': [
    {
      'id': 'profile-main',
      'name': {'default': 'Main profile'},
      'entrypoint': {'section': 'outbounds', 'tag': 'profile-out'},
      'enabled': true,
    },
  ],
  'required_extensions': <dynamic>[],
  'extensions': <String, dynamic>{},
};

SingboxConfigBuilder _defaultBuilder(
  Subscription subscription, {
  LibboxCapabilities capabilities = LibboxCapabilities.bundledLegacy,
}) {
  return SingboxConfigBuilder(
    activeSubscription: subscription,
    selectedProxyTag: '',
    vpnInboundEnabled: false,
    vpnMtu: 3400,
    vpnStrictRoute: true,
    vpnTunImplementation: TunImplementationPreference.mixed,
    proxyInboundEnabled: false,
    proxyMixedListen: '127.0.0.1',
    proxyMixedPort: 1080,
    dnsDirectResolver: 'udp://1.1.1.1',
    dnsProxyResolver: 'https://dns.cloudflare.com/dns-query',
    dnsPreferIpv6: false,
    urlTestUrl: 'https://www.gstatic.com/generate_204',
    urlTestIntervalSeconds: 180,
    urlTestTimeoutSeconds: 15,
    urlTestConcurrency: 8,
    urlTestUnavailableCheckIntervalSeconds: 120,
    blockLeaks: false,
    adBlockEnabled: false,
    useRussiaRouteData: false,
    bypassLocalNetwork: true,
    splitRoutingMode: SplitRoutingMode.disabled,
    splitRoutingPackages: const <String>[],
    logLevel: 'warning',
    tcpFastOpenEnabled: true,
    tcpMultiPathEnabled: false,
    tlsFragmentationMode: TlsFragmentationMode.disabled,
    interruptExistingConnections: true,
    urlTestStrictTolerance: true,
    markAllServersRussia: false,
    capabilities: capabilities,
  );
}

LibboxCapabilities _hydraboxTestCapabilities({
  int remotePolicyVersion = 1,
  bool supportsWdtt = false,
  Set<String> extraTopLevelFields = const <String>{},
  Set<String> extraOutboundTypes = const <String>{},
  Set<String> extraEndpointTypes = const <String>{},
  Set<String> extraProviderTypes = const <String>{},
}) {
  return LibboxCapabilities.parseOrLegacy(
    jsonEncode({
      'api_version': 1,
      'core_id': LibboxCapabilities.hydraCoreId,
      'core_name': 'HydraCore test double',
      'core_version': 'test',
      'upstream_project': 'etonify-core',
      'supports_config_check': true,
      'supports_wdtt': supportsWdtt,
      'wdtt_max_workers': supportsWdtt ? 36 : 0,
      'wdtt_max_hashes': supportsWdtt ? 4 : 0,
      'wdtt_auth_modes': supportsWdtt ? const ['anonymous'] : const <String>[],
      'wdtt_obfs_modes': supportsWdtt
          ? const ['audio', 'video']
          : const <String>[],
      'remote_policy_version': remotePolicyVersion,
      'remote_safe_top_level_fields': <String>{
        r'$schema',
        'outbounds',
        'endpoints',
        ...extraTopLevelFields,
      }.toList(),
      'remote_safe_outbound_types': <String>{
        ..._hydraPolicyV1OutboundTypes,
        ...extraOutboundTypes,
      }.toList(),
      'remote_safe_endpoint_types': <String>{
        'wireguard',
        ...extraEndpointTypes,
      }.toList(),
      'remote_safe_dns_server_types': const <String>[],
      'remote_safe_provider_types': extraProviderTypes.toList(),
    }),
  );
}

const Set<String> _hydraPolicyV1OutboundTypes = {
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
};

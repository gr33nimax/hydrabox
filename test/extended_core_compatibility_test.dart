import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:meow_client/data/local/app_settings_store.dart';
import 'package:meow_client/data/subscription/outbound_schema.dart';
import 'package:meow_client/data/subscription/subscription_parser.dart';
import 'package:meow_client/data/subscription/subscription_store.dart';
import 'package:meow_client/models/subscription.dart';
import 'package:meow_client/singbox/extended_core_protocols.dart';
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
      containsAll(ExtendedCoreProtocolCatalog.endpointTypes),
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

SingboxConfigBuilder _defaultBuilder(Subscription subscription) {
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
  );
}

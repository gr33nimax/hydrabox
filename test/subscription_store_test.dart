import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:hydrabox/core/hydra_profile_identity.dart';
import 'package:hydrabox/data/subscription/subscription_store.dart';
import 'package:hydrabox/models/subscription.dart';

void main() {
  late Directory tempDir;
  HttpOverrides? previousHttpOverrides;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    previousHttpOverrides = HttpOverrides.current;
    HttpOverrides.global = _PassthroughHttpOverrides();
    tempDir = await Directory.systemTemp.createTemp('hydrabox-client-hive-');
    Hive.init(tempDir.path);
    await SubscriptionStore.init();
  });

  setUp(SubscriptionStore.clear);

  tearDownAll(() async {
    await SubscriptionStore.clear();
    await Hive.close();
    HttpOverrides.global = previousHttpOverrides;
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  test('resource documents and profiles survive secure payload hydration', () {
    const subscription = Subscription(
      id: 'resource-payload',
      name: 'Resources',
      url: 'https://provider.example/subscription',
      selectedProfileId: 'profile-b',
      profiles: [
        SubscriptionProfile(
          id: 'profile-a',
          resourceId: 'resource-a',
          name: 'A',
          entrypointSection: 'outbounds',
          entrypointTag: 'a',
          runtimeTag: 'a',
        ),
        SubscriptionProfile(
          id: 'profile-b',
          resourceId: 'resource-b',
          name: 'B',
          entrypointSection: 'outbounds',
          entrypointTag: 'b',
          runtimeTag: 'b',
        ),
      ],
      resourceConfigs: {
        'resource-a': {
          'outbounds': [
            {'type': 'vless', 'tag': 'a', 'server': 'a.example'},
          ],
        },
        'resource-b': {
          'outbounds': [
            {'type': 'trojan', 'tag': 'b', 'server': 'b.example'},
          ],
        },
      },
      sourceMetadata: {
        'api_version': 'hydra.io/subscription/v2',
        'permissions_automatic': true,
      },
    );

    final metadataOnly = Subscription.fromMetadataMap(
      subscription.toMetadataMap(),
    );
    final hydrated = SubscriptionStore.hydratePayloadJson(
      metadataOnly,
      jsonEncode(subscription.toSecurePayloadMap()),
    );

    expect(hydrated.profiles, hasLength(2));
    expect(hydrated.resourceConfigs, hasLength(2));
    expect(hydrated.activeNativeConfig.toString(), contains('b.example'));
    expect(
      hydrated.activeNativeConfig.toString(),
      isNot(contains('a.example')),
    );
    expect(hydrated.sourceMetadata['permissions_automatic'], isTrue);
  });

  test('runtime info updates use Hydra profile identity, not native tag', () {
    final runtimeTagA = HydraProfileIdentity.runtimeTag(
      profileId: 'profile-a',
      resourceId: 'resource-a',
    );
    final runtimeTagB = HydraProfileIdentity.runtimeTag(
      profileId: 'profile-b',
      resourceId: 'resource-b',
    );
    final subscription = Subscription(
      id: 'runtime-info-resource-identity',
      name: 'Runtime info',
      url: 'https://provider.example/subscription',
      selectedProfileId: 'profile-b',
      profiles: <SubscriptionProfile>[
        SubscriptionProfile(
          id: 'profile-a',
          resourceId: 'resource-a',
          name: 'A',
          entrypointSection: 'outbounds',
          entrypointTag: 'proxy',
          runtimeTag: runtimeTagA,
        ),
        SubscriptionProfile(
          id: 'profile-b',
          resourceId: 'resource-b',
          name: 'B',
          entrypointSection: 'outbounds',
          entrypointTag: 'proxy',
          runtimeTag: runtimeTagB,
        ),
      ],
      outbounds: const <Outbound>[
        Outbound(
          tag: 'proxy',
          name: 'A',
          config: <String, dynamic>{
            'type': 'vless',
            'tag': 'proxy',
            '_source_scope': 'resource-a',
            '_hydra_source_section': 'outbounds',
            '_hydra_original_tag': 'proxy',
          },
        ),
        Outbound(
          tag: 'proxy',
          name: 'B',
          config: <String, dynamic>{
            'type': 'trojan',
            'tag': 'proxy',
            '_source_scope': 'resource-b',
            '_hydra_source_section': 'outbounds',
            '_hydra_original_tag': 'proxy',
          },
        ),
      ],
      resourceConfigs: const <String, Map<String, dynamic>>{
        'resource-a': <String, dynamic>{'marker': 'a'},
        'resource-b': <String, dynamic>{'marker': 'b'},
      },
    );
    final rewritten =
        SubscriptionStore.rewriteOutboundRuntimeInfoPayloadForTest(
          jsonEncode(subscription.toSecurePayloadMap()),
          <String, Map<String, Object?>>{
            runtimeTagB: <String, Object?>{
              'external_ip': '203.0.113.22',
              'exit_country': 'DE',
            },
          },
        );
    final hydrated = SubscriptionStore.hydratePayloadJson(
      Subscription.fromMetadataMap(subscription.toMetadataMap()),
      rewritten!,
    );

    expect(hydrated.outbounds.first.info.externalIp, isNull);
    expect(hydrated.outbounds.last.info.externalIp, '203.0.113.22');
    expect(hydrated.outbounds.last.info.exitCountry, 'DE');
  });

  test('refresh preserves same-tag Hydra state by resource identity', () {
    Outbound hydraOutbound(String resourceId, {int? latestPing}) => Outbound(
      tag: 'proxy',
      name: resourceId,
      config: <String, dynamic>{
        'type': 'vless',
        'tag': 'proxy',
        'server': 'same.example',
        'server_port': 443,
        'uuid': '11111111-1111-1111-1111-111111111111',
        '_source_scope': resourceId,
        '_hydra_source_section': 'outbounds',
        '_hydra_original_tag': 'proxy',
      },
      info: OutboundInfo(latestPing: latestPing),
    );

    final refreshed = SubscriptionStore.preserveUserStateForTest(
      <Outbound>[
        hydraOutbound('resource-a', latestPing: 101),
        hydraOutbound('resource-b', latestPing: 202),
      ],
      <Outbound>[
        hydraOutbound('resource-b'),
        hydraOutbound('resource-a'),
      ],
    );

    expect(refreshed.first.info.latestPing, 202);
    expect(refreshed.last.info.latestPing, 101);
  });

  test('generic file import persists parsed proxy data', () async {
    final result = await SubscriptionStore.addFromContent(
      'vless://3a1a58e6-e167-4d9f-8b60-34fee9ee51e9@server.example:443'
      '?encryption=none&security=tls#Node',
      sourceName: 'nodes.txt',
    );

    expect(result.hasWarning, isFalse);
    expect(result.subscription.disableAutoUpdate, isTrue);
    expect(result.subscription.outbounds, hasLength(1));
    expect(SubscriptionStore.getAllMetadata(), hasLength(1));
    expect(
      SubscriptionStore.payloadJsonFor(result.subscription.id),
      isNotEmpty,
    );
  });

  test('hydra-key is rejected in the URL query', () async {
    const key = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';
    const subscription = Subscription(
      id: 'query-key-source',
      name: 'Leaky source',
      url: 'https://provider.example/subscription?hydra-key=$key',
    );

    await expectLater(
      SubscriptionStore.save(subscription, allowCreate: true),
      throwsFormatException,
    );
    expect(SubscriptionStore.getAllMetadata(), isEmpty);
  });

  test('non-Android storage refuses a persistent hydra-key fragment', () async {
    if (Platform.isAndroid) return;
    const key = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';
    const subscription = Subscription(
      id: 'fragment-key-source',
      name: 'Encrypted source',
      url: 'https://provider.example/subscription#hydra-key=$key',
    );

    await expectLater(
      SubscriptionStore.save(subscription, allowCreate: true),
      throwsA(isA<UnsupportedError>()),
    );
    expect(SubscriptionStore.getAllMetadata(), isEmpty);
  });

  test('key-bearing fetch failures never create a placeholder', () async {
    const key = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';

    await expectLater(
      SubscriptionStore.addFromUrl(
        'http://127.0.0.1/subscription#hydra-key=$key',
      ),
      throwsA(anyOf(isA<HttpException>(), isA<SocketException>())),
    );
    expect(SubscriptionStore.getAllMetadata(), isEmpty);
  });

  test('metadata edit cannot erase the stored payload', () async {
    const subscription = Subscription(
      id: 'metadata-edit',
      name: 'Before',
      url: 'https://provider.example/subscription',
      rawContent: 'vless://payload-that-is-long-enough',
      outbounds: [
        Outbound(
          tag: 'proxy',
          name: 'Proxy',
          config: {'type': 'vless', 'tag': 'proxy'},
        ),
      ],
    );
    await SubscriptionStore.save(subscription, allowCreate: true);
    final stored = SubscriptionStore.get(subscription.id)!;

    await SubscriptionStore.saveMetadata(stored.copyWith(name: 'After'));

    final updated = SubscriptionStore.get(subscription.id)!;
    expect(updated.name, 'After');
    expect(updated.rawContent, subscription.rawContent);
    expect(updated.outbounds, hasLength(1));
  });
}

class _PassthroughHttpOverrides extends HttpOverrides {}

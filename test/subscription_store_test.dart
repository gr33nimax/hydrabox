import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:meow_client/data/subscription/hydrabox_subscription_crypto.dart';
import 'package:meow_client/data/subscription/subscription_parser.dart';
import 'package:meow_client/data/subscription/subscription_failure.dart';
import 'package:meow_client/data/subscription/subscription_store.dart';
import 'package:meow_client/logging/app_log_store.dart';
import 'package:meow_client/models/subscription.dart';

void main() {
  late Directory tempDir;
  HttpOverrides? previousHttpOverrides;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    previousHttpOverrides = HttpOverrides.current;
    HttpOverrides.global = _PassthroughHttpOverrides();
    tempDir = await Directory.systemTemp.createTemp('meow-client-hive-');
    Hive.init(tempDir.path);
    await SubscriptionStore.init();
  });

  setUp(() async {
    await SubscriptionStore.clear();
    AppLogStore.clear();
  });

  tearDownAll(() async {
    await SubscriptionStore.clear();
    await Hive.close();
    HttpOverrides.global = previousHttpOverrides;
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  test(
    'addFromUrl saves placeholder subscription when initial fetch fails',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);

      server.listen((request) async {
        request.response.statusCode = HttpStatus.forbidden;
        await request.response.close();
      });

      const secretPath = 'customer-bearer-path-secret';

      final result = await SubscriptionStore.addFromUrl(
        'http://${server.address.host}:${server.port}/$secretPath',
        customName: 'Saved Anyway',
        requestInfo: const SubscriptionInfo(
          requireHwid: true,
          customHwid: 'spoofed-hwid',
        ),
      );

      expect(result.hasWarning, isTrue);
      expect(result.subscription.name, 'Saved Anyway');
      expect(result.subscription.outbounds, isEmpty);

      final saved = SubscriptionStore.get(result.subscription.id);
      expect(saved, isNotNull);
      expect(
        saved!.url,
        'http://${server.address.host}:${server.port}/$secretPath',
      );
      expect(saved.info?.requireHwid, isTrue);
      expect(saved.info?.customHwid, 'spoofed-hwid');
      expect(saved.outbounds, isEmpty);
      expect(AppLogStore.dump(), isNot(contains(secretPath)));
    },
  );

  test('key-bearing source failures never save a placeholder', () async {
    final key = base64Url.encode(List<int>.filled(32, 7)).replaceAll('=', '');

    await expectLater(
      SubscriptionStore.addFromUrl(
        'http://127.0.0.1/subscription#hbx-key=$key',
      ),
      throwsA(isA<HttpException>()),
    );
    expect(SubscriptionStore.getAllMetadata(), isEmpty);
  });

  test(
    'HydraBox media-type failures never save a legacy placeholder',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);
      server.listen((request) async {
        request.response.headers.set(
          HttpHeaders.contentTypeHeader,
          'application/vnd.hydrabox.subscription+json',
        );
        request.response.write(
          'vless://uuid@server.example:443?security=tls#Legacy',
        );
        await request.response.close();
      });

      await expectLater(
        SubscriptionStore.addFromUrl(
          'http://${server.address.host}:${server.port}/subscription',
        ),
        throwsA(isA<FormatException>()),
      );
      expect(SubscriptionStore.getAllMetadata(), isEmpty);
    },
  );

  test(
    'non-Android store refuses plaintext persistence of hbx-key URLs',
    () async {
      if (Platform.isAndroid) return;
      final key = base64Url
          .encode(List<int>.filled(32, 11))
          .replaceAll('=', '');
      final subscription = Subscription(
        id: 'insecure-key-source',
        name: 'Encrypted source',
        url: 'https://provider.example/subscription#hbx-key=$key',
      );

      await expectLater(
        SubscriptionStore.save(subscription, allowCreate: true),
        throwsA(isA<UnsupportedError>()),
      );
      expect(SubscriptionStore.getAllMetadata(), isEmpty);
    },
  );

  test('store rejects hbx-key in URL query on every platform', () async {
    const key = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';
    const subscription = Subscription(
      id: 'query-key-source',
      name: 'Leaky encrypted source',
      url: 'https://provider.example/subscription?hbx-key=$key',
    );

    await expectLater(
      SubscriptionStore.save(subscription, allowCreate: true),
      throwsFormatException,
    );
    expect(SubscriptionStore.getAllMetadata(), isEmpty);
  });

  test('addFromContent imports a subscription from file content', () async {
    final result = await SubscriptionStore.addFromContent(
      'vless://uuid@server.com:443?type=tcp&security=tls#Node1',
      sourceName: 'nodes.txt',
    );

    expect(result.hasWarning, isFalse);
    expect(
      SubscriptionStore.isLocalFileImportUrl(result.subscription.url),
      isTrue,
    );
    expect(result.subscription.disableAutoUpdate, isTrue);
    expect(result.subscription.outbounds, isNotEmpty);

    final metadata = SubscriptionStore.getAllMetadata().single;
    expect(metadata.cachedVisibleProxyCount, greaterThan(0));
    expect(metadata.hasRawPayload, isTrue);
  });

  test(
    'persistent encrypted HydraBox file import fails closed without key storage',
    () async {
      final key = base64Url.encode(List<int>.filled(32, 7)).replaceAll('=', '');
      final encrypted = HydraBoxJweCodec.encrypt(
        jsonEncode(_hydraboxPersistenceDocument()),
        encodedKey: key,
        keyId: 'file-import-key',
      );

      await expectLater(
        SubscriptionStore.addFromContent(
          encrypted,
          sourceName: 'customer.hbx.jwe.json',
          decryptionKey: key,
        ),
        throwsA(
          isA<UnsupportedError>().having(
            (error) => error.message,
            'message',
            contains('key-bearing HTTPS subscription URL'),
          ),
        ),
      );
      expect(SubscriptionStore.getAllMetadata(), isEmpty);
    },
  );

  test(
    'addFromContent accepts a native config without selectable entries',
    () async {
      final source = jsonEncode({
        'inbounds': [
          {
            'type': 'mtproxy',
            'tag': 'inbound-only',
            'listen': '127.0.0.1',
            'listen_port': 8443,
            'users': const [],
          },
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

      final result = await SubscriptionStore.addFromContent(
        source,
        sourceName: 'native-service.json',
      );

      expect(result.subscription.outbounds, isEmpty);
      expect(result.subscription.selectedProxyTag, isEmpty);
      expect(result.subscription.rawContent, source);
      expect(SubscriptionStore.get(result.subscription.id)?.rawContent, source);
    },
  );

  test(
    'full-config endpoints keep native tags with safe reserved-tag fallback',
    () async {
      final source = jsonEncode({
        'endpoints': [
          {
            'type': 'wireguard',
            'tag': 'WG endpoint / primary',
            'address': ['10.0.0.2/32'],
            'private_key': 'opaque',
            'peers': const [],
          },
          {
            'type': 'tailscale',
            'tag': 'select',
            'state_directory': '/tmp/tailscale',
          },
        ],
      });

      final result = await SubscriptionStore.addFromContent(
        source,
        sourceName: 'extended.json',
      );

      expect(result.subscription.outbounds, hasLength(2));
      final wireguard = result.subscription.outbounds.first;
      final tailscale = result.subscription.outbounds.last;
      expect(wireguard.tag, 'WG endpoint / primary');
      expect(wireguard.config['_etonify_source_section'], 'endpoints');
      expect(wireguard.config['_etonify_original_tag'], wireguard.tag);
      expect(tailscale.tag, isNot('select'));
      expect(tailscale.config['_etonify_original_tag'], 'select');
    },
  );

  test('cancelled file import does not persist a subscription', () async {
    var cancellationChecks = 0;

    await expectLater(
      SubscriptionStore.addFromContent(
        'vless://uuid@server.com:443?type=tcp&security=tls#Node1',
        sourceName: 'nodes.txt',
        isCancelled: () => ++cancellationChecks >= 3,
      ),
      throwsA(isA<SubscriptionImportCancelledException>()),
    );

    expect(SubscriptionStore.getAllMetadata(), isEmpty);
  });

  test(
    'stores payloads compressed without changing hydrated profiles',
    () async {
      final subscription = Subscription(
        id: 'compressed-profile',
        name: 'Compressed profile',
        url: 'file:///compressed.txt',
        rawContent: ''.padRight(512 * 1024, 'a'),
        outbounds: const [
          Outbound(
            tag: 'node-1',
            name: 'Node 1',
            config: {'type': 'vless', 'server': 'server.example'},
          ),
        ],
      );

      await SubscriptionStore.save(subscription, allowCreate: true);

      final metadata = SubscriptionStore.getAllMetadata().single;
      expect(
        metadata.payloadStorageKey,
        startsWith('${subscription.id}::payload::'),
      );
      final payloadBox = Hive.box('subscription_payloads_secure_v1');
      final stored = payloadBox.get(metadata.payloadStorageKey);
      expect(stored, isA<String>());
      expect(stored as String, startsWith('gzip-base64-v1:'));
      expect(stored.length, lessThan(subscription.rawContent.length ~/ 10));
      expect(payloadBox.get(subscription.id), isNull);
      expect(SubscriptionStore.payloadSnapshotFor(subscription.id), stored);
      expect(
        jsonDecode(SubscriptionStore.payloadJsonFor(subscription.id)!)
            as Map<String, dynamic>,
        containsPair('raw_content', subscription.rawContent),
      );

      final hydrated = await SubscriptionStore.getInBackground(subscription.id);
      expect(hydrated, isNotNull);
      expect(hydrated!.rawContent, subscription.rawContent);
      expect(hydrated.outbounds.single.tag, 'node-1');
    },
  );

  test(
    'payload commits switch generations and metadata saves keep the pointer',
    () async {
      const original = Subscription(
        id: 'generation-profile',
        name: 'Generation profile',
        url: 'file:///generation.txt',
        rawContent: 'first payload content',
      );
      await SubscriptionStore.save(original, allowCreate: true);
      final firstMetadata = SubscriptionStore.getAllMetadata().single;
      final firstKey = firstMetadata.payloadStorageKey;
      expect(firstKey, isNotEmpty);

      await SubscriptionStore.saveMetadata(
        firstMetadata.copyWith(name: 'Renamed'),
      );
      expect(
        SubscriptionStore.getAllMetadata().single.payloadStorageKey,
        firstKey,
      );

      await SubscriptionStore.save(
        SubscriptionStore.get(
          original.id,
        )!.copyWith(name: 'Renamed', rawContent: 'second payload content'),
      );
      final secondMetadata = SubscriptionStore.getAllMetadata().single;
      final secondKey = secondMetadata.payloadStorageKey;
      expect(secondKey, isNot(firstKey));
      expect(Hive.box('subscription_payloads_secure_v1').get(firstKey), isNull);
      expect(
        SubscriptionStore.get(original.id)?.rawContent,
        'second payload content',
      );
    },
  );

  test(
    'stale legacy saves cannot overwrite a newer payload revision',
    () async {
      const original = Subscription(
        id: 'stale-legacy-save',
        name: 'Original',
        url: 'https://provider.example/subscription',
        rawContent: 'vless://old-payload',
      );
      await SubscriptionStore.save(original, allowCreate: true);
      final stale = SubscriptionStore.get(original.id)!;

      await SubscriptionStore.save(
        stale.copyWith(rawContent: 'vless://new-payload'),
      );

      await expectLater(
        SubscriptionStore.save(stale.copyWith(name: 'Stale full save')),
        throwsA(isA<StateError>()),
      );
      await expectLater(
        SubscriptionStore.saveMetadata(
          stale.copyWith(name: 'Stale metadata save'),
        ),
        throwsA(isA<StateError>()),
      );

      final stored = SubscriptionStore.get(original.id)!;
      expect(stored.rawContent, 'vless://new-payload');
      expect(stored.name, 'Original');
    },
  );

  test('selection metadata rebases onto the latest payload revision', () async {
    const original = Subscription(
      id: 'rebased-selection',
      name: 'Original',
      url: 'https://provider.example/subscription',
      selectedProxyTag: 'proxy-1',
      rawContent: 'vless://old-payload',
    );
    await SubscriptionStore.save(original, allowCreate: true);
    final stale = SubscriptionStore.get(original.id)!;

    await SubscriptionStore.save(
      stale.copyWith(
        name: 'Refreshed',
        lastUpdated: 123,
        rawContent: 'vless://new-payload',
      ),
    );
    final latestPointer =
        SubscriptionStore.getAllMetadata().single.payloadStorageKey;

    await SubscriptionStore.saveSelectedProxyMetadata(
      stale.copyWith(
        selectedProxyTag: 'proxy-2',
        selectedProfileId: 'profile-2',
      ),
    );

    final stored = SubscriptionStore.get(original.id)!;
    expect(stored.payloadStorageKey, latestPointer);
    expect(stored.rawContent, 'vless://new-payload');
    expect(stored.name, 'Refreshed');
    expect(stored.lastUpdated, 123);
    expect(stored.selectedProxyTag, 'proxy-2');
    expect(stored.selectedProfileId, 'profile-2');
  });

  test(
    'stale legacy reparse cannot replace a newer payload revision',
    () async {
      final oldRaw = List<String>.generate(
        3000,
        (index) =>
            'vless://3a1a58e6-e167-4d9f-8b60-34fee9ee51e9@old$index.example:443'
            '?encryption=none&security=tls#Old$index',
      ).join('\n');
      final original = Subscription(
        id: 'stale-legacy-reparse',
        name: 'Legacy reparse',
        url: 'https://provider.example/subscription',
        rawContent: oldRaw,
      );
      await SubscriptionStore.save(original, allowCreate: true);
      final stale = SubscriptionStore.get(original.id)!;

      final reparse = SubscriptionStore.reparseFromRaw(original.id);
      await Future<void>.delayed(Duration.zero);
      await SubscriptionStore.save(
        stale.copyWith(
          rawContent:
              'vless://3a1a58e6-e167-4d9f-8b60-34fee9ee51e9@new.example:443'
              '?encryption=none&security=tls#New',
        ),
      );

      await expectLater(reparse, throwsA(isA<StateError>()));
      expect(
        SubscriptionStore.get(original.id)!.rawContent,
        contains('@new.example:443'),
      );
    },
  );

  test(
    'HydraBox payload reload retains profiles native config and source metadata',
    () async {
      final source = jsonEncode(_hydraboxPersistenceDocument());
      final parsedSource = SubscriptionParser.parse(source);
      final imported = await SubscriptionStore.addFromContent(
        source,
        sourceName: 'customer.hbx.json',
      );

      expect(imported.subscription.profiles, hasLength(1));
      expect(imported.subscription.selectedProfileId, 'profile-main');
      expect(imported.subscription.selectedProxyTag, 'profile-out');
      expect(imported.subscription.nativeConfig?['future_safe_section'], {
        'opaque': true,
      });
      expect(imported.subscription.sourceMetadata['sequence'], 7);
      expect(
        SubscriptionStore.getAllMetadata().single.sourceMetadata,
        isNot(contains('extensions')),
      );

      final storedPayload =
          jsonDecode(
                SubscriptionStore.payloadJsonFor(imported.subscription.id)!,
              )
              as Map<String, dynamic>;
      expect(storedPayload['profiles'], isA<List<dynamic>>());
      expect(storedPayload['native_config'], isA<Map<String, dynamic>>());

      final reloaded = await SubscriptionStore.getInBackground(
        imported.subscription.id,
      );
      expect(reloaded, isNotNull);
      expect(reloaded!.profiles, hasLength(1));
      expect(reloaded.profiles.single.id, 'profile-main');
      expect(reloaded.profiles.single.entrypointSection, 'outbounds');
      expect(reloaded.profiles.single.entrypointTag, 'profile-out');
      expect(reloaded.profiles.single.runtimeTag, 'profile-out');
      expect(reloaded.selectedProfileId, 'profile-main');
      expect(reloaded.selectedProxyTag, 'profile-out');
      expect(reloaded.nativeConfig, parsedSource.nativeConfig);
      expect(reloaded.nativeConfig?['future_safe_section'], {'opaque': true});
      expect(reloaded.nativeConfig?['outbounds'], hasLength(2));
      expect(reloaded.sourceMetadata['format'], 'hydrabox.io/subscription/v1');
      expect(reloaded.sourceMetadata['issuer'], 'https://provider.example');
      expect(reloaded.sourceMetadata['subscription_id'], 'persistence-main');
      expect(reloaded.sourceMetadata['sequence'], 7);
      expect(reloaded.sourceMetadata['payload_sha256'], isNotEmpty);
      expect(reloaded.sourceMetadata['extensions'], {
        'example.provider/labels': {'tier': 'test'},
      });

      final visible = reloaded.outbounds.singleWhere(
        (outbound) => outbound.tag == 'profile-out',
      );
      final helper = reloaded.outbounds.singleWhere(
        (outbound) => outbound.tag == 'helper-out',
      );
      expect(visible.config['_hydrabox_profile_id'], 'profile-main');
      expect(visible.config['_group_only'], isNot(true));
      expect(helper.config['_group_only'], isTrue);
    },
  );

  test('HydraBox issued_at is the effective not_before when omitted', () async {
    final source = _hydraboxPersistenceDocument()
      ..['issued_at'] = DateTime.now()
          .toUtc()
          .add(const Duration(hours: 2))
          .toIso8601String();

    await expectLater(
      SubscriptionStore.addFromContent(jsonEncode(source)),
      throwsFormatException,
    );
    expect(SubscriptionStore.getAllMetadata(), isEmpty);
  });

  test(
    'HydraBox anti-replay high-water is global to the trust tuple',
    () async {
      final firstDocument = _hydraboxPersistenceDocument()..['sequence'] = 12;
      final firstSource = jsonEncode(firstDocument);
      await SubscriptionStore.addFromContent(
        firstSource,
        sourceName: 'tuple-primary.hbx.json',
      );

      final rollback = Map<String, dynamic>.from(firstDocument)
        ..['sequence'] = 10;
      await expectLater(
        SubscriptionStore.addFromContent(
          jsonEncode(rollback),
          sourceName: 'tuple-rollback.hbx.json',
        ),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('sequence rollback'),
          ),
        ),
      );

      final equivocation = jsonDecode(firstSource) as Map<String, dynamic>;
      final runtime = equivocation['runtime'] as Map<String, dynamic>;
      final native = runtime['document'] as Map<String, dynamic>;
      final outbounds = native['outbounds'] as List<dynamic>;
      (outbounds.first as Map<String, dynamic>)['server'] = 'other.example';
      await expectLater(
        SubscriptionStore.addFromContent(
          jsonEncode(equivocation),
          sourceName: 'tuple-equivocation.hbx.json',
        ),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('publisher equivocation'),
          ),
        ),
      );

      await expectLater(
        SubscriptionStore.addFromContent(
          firstSource,
          sourceName: 'tuple-duplicate.hbx.json',
        ),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('tuple is already stored'),
          ),
        ),
      );
      expect(SubscriptionStore.getAllMetadata(), hasLength(1));
    },
  );

  test(
    'HydraBox backup runtime and digest are rebuilt from raw wire data',
    () async {
      final imported = await SubscriptionStore.addFromContent(
        jsonEncode(_hydraboxPersistenceDocument()),
        sourceName: 'backup-source.hbx.json',
      );
      final trusted = SubscriptionStore.get(imported.subscription.id)!;
      await SubscriptionStore.clear();

      final unsafeNative = trusted.copyWith(
        nativeConfig: {
          'outbounds': [
            {
              'type': 'ssh',
              'tag': 'forged',
              'server': 'proxy.example',
              'private_key_path': '/data/local/tmp/attacker-key',
            },
          ],
          'log': {'output': '/data/local/tmp/provider.log'},
        },
      );
      await expectLater(
        SubscriptionStore.importFromBackup(unsafeNative),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('native config does not match'),
          ),
        ),
      );

      final forgedTrust = trusted.copyWith(
        sourceMetadata: {
          ...trusted.sourceMetadata,
          'payload_sha256': ''.padRight(64, '0'),
        },
      );
      await expectLater(
        SubscriptionStore.importFromBackup(forgedTrust),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('payload_sha256'),
          ),
        ),
      );
      expect(SubscriptionStore.getAllMetadata(), isEmpty);

      await SubscriptionStore.importFromBackup(trusted);
      final restored = SubscriptionStore.get(trusted.id)!;
      expect(restored.nativeConfig, trusted.nativeConfig);
      expect(
        restored.sourceMetadata['payload_sha256'],
        trusted.sourceMetadata['payload_sha256'],
      );
    },
  );

  test('HydraBox reparse revalidates sequence inside the write lock', () async {
    final originalDocument = _hydraboxPersistenceDocument()..['sequence'] = 10;
    final imported = await SubscriptionStore.addFromContent(
      jsonEncode(originalDocument),
      sourceName: 'anti-replay.hbx.json',
    );

    final newerDocument = _hydraboxPersistenceDocument()..['sequence'] = 12;
    final newerRaw = jsonEncode(newerDocument);
    final newerParseResult = SubscriptionParser.parse(newerRaw);

    // reparseFromRaw captures the sequence-10 raw payload before its first
    // asynchronous parse. The concurrent save then commits sequence 12 and
    // holds/queues the same per-subscription lock before the stale reparse
    // can persist its result.
    final staleReparseExpectation = expectLater(
      SubscriptionStore.reparseFromRaw(imported.subscription.id),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('HydraBox sequence rollback: 10 < 12'),
        ),
      ),
    );
    await SubscriptionStore.saveParsedImportForTest(
      imported.subscription.copyWith(
        rawContent: newerRaw,
        sourceMetadata: newerParseResult.sourceMetadata,
      ),
    );
    await staleReparseExpectation;

    final stored = SubscriptionStore.get(imported.subscription.id);
    expect(stored, isNotNull);
    expect(stored!.sourceMetadata['sequence'], 12);
    expect(stored.rawContent, newerRaw);
  });

  test('stale public save cannot roll back HydraBox trust state', () async {
    final sequenceTen = _hydraboxPersistenceDocument()..['sequence'] = 10;
    final imported = await SubscriptionStore.addFromContent(
      jsonEncode(sequenceTen),
      sourceName: 'stale-save.hbx.json',
    );
    final stale = SubscriptionStore.get(imported.subscription.id)!;

    final sequenceTwelve = _hydraboxPersistenceDocument()..['sequence'] = 12;
    final newerRaw = jsonEncode(sequenceTwelve);
    final newerMetadata = SubscriptionParser.parse(newerRaw).sourceMetadata;
    await SubscriptionStore.saveParsedImportForTest(
      stale.copyWith(rawContent: newerRaw, sourceMetadata: newerMetadata),
    );

    await expectLater(
      SubscriptionStore.save(stale.copyWith(name: 'Stale UI edit')),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('HydraBox sequence rollback: 10 < 12'),
        ),
      ),
    );
    final stored = SubscriptionStore.get(imported.subscription.id)!;
    expect(stored.sourceMetadata['sequence'], 12);
    expect(stored.rawContent, newerRaw);
  });

  test(
    'stale reorder and summary writes preserve HydraBox trust state',
    () async {
      final sequenceTen = _hydraboxPersistenceDocument()..['sequence'] = 10;
      final imported = await SubscriptionStore.addFromContent(
        jsonEncode(sequenceTen),
        sourceName: 'stale-metadata.hbx.json',
      );
      final staleOrder = SubscriptionStore.getAllMetadata();

      final sequenceTwelve = _hydraboxPersistenceDocument()..['sequence'] = 12;
      final newerRaw = jsonEncode(sequenceTwelve);
      final newerMetadata = SubscriptionParser.parse(newerRaw).sourceMetadata;
      await SubscriptionStore.saveParsedImportForTest(
        imported.subscription.copyWith(
          rawContent: newerRaw,
          sourceMetadata: newerMetadata,
        ),
      );
      final committedPointer =
          SubscriptionStore.getAllMetadata().single.payloadStorageKey;

      await SubscriptionStore.reorder(staleOrder);
      await SubscriptionStore.cachePayloadSummaries({
        imported.subscription.id: (visibleProxyCount: 41, hasRawPayload: true),
      });
      await SubscriptionStore.saveSelectedProxyMetadata(
        staleOrder.single.copyWith(
          selectedProxyTag: 'runtime-profile-2',
          selectedProfileId: 'profile-2',
        ),
      );

      final storedMetadata = SubscriptionStore.getAllMetadata().single;
      expect(storedMetadata.sourceMetadata['sequence'], 12);
      expect(storedMetadata.payloadStorageKey, committedPointer);
      expect(storedMetadata.cachedVisibleProxyCount, 41);
      expect(storedMetadata.selectedProxyTag, 'runtime-profile-2');
      expect(storedMetadata.selectedProfileId, 'profile-2');
      expect(
        SubscriptionStore.get(imported.subscription.id)!.rawContent,
        newerRaw,
      );
    },
  );

  test('addFromUrl reports a successful response without proxies', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);

    server.listen((request) async {
      request.response.statusCode = HttpStatus.ok;
      request.response.write('{"message":"subscription expired"}');
      await request.response.close();
    });

    final result = await SubscriptionStore.addFromUrl(
      'http://${server.address.host}:${server.port}/sub',
    );

    expect(result.hasWarning, isTrue);
    expect(
      result.warning,
      isA<SubscriptionContentException>().having(
        (error) => error.kind,
        'kind',
        SubscriptionContentFailureKind.noUsableProxies,
      ),
    );
    expect(result.subscription.outbounds, isEmpty);
  });

  test('coalesces concurrent refreshes of the same subscription', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    var requestCount = 0;

    server.listen((request) async {
      requestCount++;
      request.response.statusCode = HttpStatus.ok;
      request.response.headers.contentType = ContentType.text;
      request.response.write(
        'vless://3a1a58e6-e167-4d9f-8b60-34fee9ee51e9@server.example.com:443'
        '?encryption=none&security=tls#Node',
      );
      await request.response.close();
    });

    final url = 'http://${server.address.host}:${server.port}/subscription';
    await SubscriptionStore.save(
      Subscription(
        id: 'single-flight-refresh',
        name: 'Single flight',
        url: url,
        outbounds: const [
          Outbound(
            tag: 'old-node',
            name: 'Old node',
            config: {
              'type': 'vless',
              'server': 'old.example.com',
              'server_port': 443,
            },
          ),
        ],
      ),
      allowCreate: true,
    );

    final first = SubscriptionStore.refresh('single-flight-refresh');
    final second = SubscriptionStore.refresh('single-flight-refresh');

    final results = await Future.wait([first, second]);
    expect(requestCount, 1);
    expect(results[0].outbounds.single.tag, results[1].outbounds.single.tag);
  });

  test('delete wins over an in-flight refresh without resurrection', () async {
    final requestStarted = Completer<void>();
    final releaseResponse = Completer<void>();
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      if (!requestStarted.isCompleted) requestStarted.complete();
      await releaseResponse.future;
      request.response.write(
        'vless://3a1a58e6-e167-4d9f-8b60-34fee9ee51e9@new.example:443'
        '?encryption=none&security=tls#New',
      );
      await request.response.close();
    });
    final subscription = Subscription(
      id: 'delete-during-refresh',
      name: 'Delete during refresh',
      url: 'http://${server.address.host}:${server.port}/subscription',
      rawContent:
          'vless://3a1a58e6-e167-4d9f-8b60-34fee9ee51e9@old.example:443'
          '?encryption=none&security=tls#Old',
    );
    await SubscriptionStore.save(subscription, allowCreate: true);

    final refresh = SubscriptionStore.refresh(subscription.id);
    await requestStarted.future;
    await SubscriptionStore.delete(subscription.id);
    releaseResponse.complete();

    await expectLater(refresh, throwsA(isA<StateError>()));
    expect(SubscriptionStore.get(subscription.id), isNull);
  });

  test('source URL changes invalidate an in-flight refresh', () async {
    final requestStarted = Completer<void>();
    final releaseResponse = Completer<void>();
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() async {
      if (!releaseResponse.isCompleted) releaseResponse.complete();
      await server.close(force: true);
    });
    server.listen((request) async {
      if (!requestStarted.isCompleted) requestStarted.complete();
      await releaseResponse.future;
      request.response.write(
        'vless://3a1a58e6-e167-4d9f-8b60-34fee9ee51e9@fetched.example:443'
        '?encryption=none&security=tls#Fetched',
      );
      await request.response.close();
    });
    final subscription = Subscription(
      id: 'url-change-during-refresh',
      name: 'URL change during refresh',
      url: 'http://${server.address.host}:${server.port}/subscription',
      rawContent: 'vless://old-payload',
    );
    await SubscriptionStore.save(subscription, allowCreate: true);

    final refresh = SubscriptionStore.refresh(subscription.id);
    await requestStarted.future;
    final latest = SubscriptionStore.get(subscription.id)!;
    await SubscriptionStore.saveMetadata(
      latest.copyWith(url: 'https://replacement.example/subscription'),
    );
    releaseResponse.complete();

    await expectLater(refresh, throwsA(isA<StateError>()));
    final stored = SubscriptionStore.get(subscription.id)!;
    expect(stored.url, 'https://replacement.example/subscription');
    expect(stored.rawContent, 'vless://old-payload');
  });

  test('delete and recreate defeats in-flight refresh ABA', () async {
    final requestStarted = Completer<void>();
    final releaseResponse = Completer<void>();
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() async {
      if (!releaseResponse.isCompleted) releaseResponse.complete();
      await server.close(force: true);
    });
    server.listen((request) async {
      if (!requestStarted.isCompleted) requestStarted.complete();
      await releaseResponse.future;
      request.response.write(
        'vless://3a1a58e6-e167-4d9f-8b60-34fee9ee51e9@stale.example:443'
        '?encryption=none&security=tls#Stale',
      );
      await request.response.close();
    });
    final subscription = Subscription(
      id: 'refresh-aba',
      name: 'Original incarnation',
      url: 'http://${server.address.host}:${server.port}/subscription',
      rawContent: 'vless://original-payload',
    );
    await SubscriptionStore.save(subscription, allowCreate: true);

    final refresh = SubscriptionStore.refresh(subscription.id);
    await requestStarted.future;
    await SubscriptionStore.delete(subscription.id);
    await SubscriptionStore.save(
      subscription.copyWith(
        name: 'Replacement incarnation',
        rawContent: 'vless://replacement-payload',
      ),
      allowCreate: true,
    );
    releaseResponse.complete();

    await expectLater(refresh, throwsA(isA<StateError>()));
    final stored = SubscriptionStore.get(subscription.id)!;
    expect(stored.name, 'Replacement incarnation');
    expect(stored.rawContent, 'vless://replacement-payload');
  });

  test('stale update cannot recreate a deleted subscription', () async {
    const subscription = Subscription(
      id: 'deleted-stale-update',
      name: 'Before delete',
      url: 'file:///stale.txt',
      rawContent: 'vless://payload',
    );
    await SubscriptionStore.save(subscription, allowCreate: true);
    await SubscriptionStore.delete(subscription.id);

    await expectLater(
      SubscriptionStore.save(subscription.copyWith(name: 'Stale edit')),
      throwsA(isA<StateError>()),
    );
    expect(SubscriptionStore.get(subscription.id), isNull);
  });

  test('builds Husi-style proxy chain detours from parsed links', () {
    const raw =
        'vless://3a1a58e6-e167-4d9f-8b60-34fee9ee51e9@144.31.94.151:443'
        '?encryption=none&flow=xtls-rprx-vision&security=reality'
        '&sni=kinopoisk.ru&fp=chrome'
        '&pbk=mhvT7-nUtXaWrw1Xf7JmBsB0Twj4-alH73mgsN4PZz0'
        '&sid=29f847c151f96091#%D0%90%D0%B2%D1%81%D1%82%D1%80%D0%B8%D1%8F%E2%9A%A1%F0%9F%A4%96%C2%B7%20TCP'
        ' -> socks5://VzBzbTRTOkJETEx0Vw==@178.171.42.39:9909#178.171.42.39%3A9909';

    final payload = SubscriptionStore.buildSubscriptionPayloadForTest(
      SubscriptionParser.parse(raw),
    );

    expect(payload.warnings, isEmpty);
    expect(payload.outbounds.length, 2);
    final firstHop = payload.outbounds[0];
    final chained = payload.outbounds[1];
    expect(firstHop['config']['type'], 'vless');
    expect(firstHop['config']['_group_only'], true);
    expect(chained['config']['type'], 'socks');
    expect(chained['config']['detour'], firstHop['tag']);
    expect(chained['config']['username'], 'W0sm4S');
    expect(chained['config']['password'], 'BDLLtW');
  });

  test('native detour helper is stored but not exposed as a profile', () {
    final source = jsonEncode({
      'route': {'final': 'trojan-over-shadowtls'},
      'outbounds': [
        {
          'type': 'trojan',
          'tag': 'trojan-over-shadowtls',
          'server': 'proxy.example',
          'server_port': 443,
          'password': 'test-password',
          'detour': 'shadowtls-transport',
        },
        {
          'type': 'shadowtls',
          'tag': 'shadowtls-transport',
          'server': 'transport.example',
          'server_port': 443,
          'version': 3,
          'password': 'test-password',
          'tls': {'enabled': true, 'server_name': 'front.example'},
        },
      ],
    });

    final payload = SubscriptionStore.buildSubscriptionPayloadForTest(
      SubscriptionParser.parse(source),
    );

    expect(payload.warnings, isEmpty);
    expect(payload.outbounds, hasLength(2));
    final visible = payload.outbounds
        .where((entry) => entry['config']['_group_only'] != true)
        .toList(growable: false);
    expect(visible, hasLength(1));
    expect(visible.single['tag'], 'trojan-over-shadowtls');
    final helper = payload.outbounds.singleWhere(
      (entry) => entry['tag'] == 'shadowtls-transport',
    );
    expect(helper['config']['_group_only'], isTrue);
  });

  test('selection ignores a transit-only outbound declared first', () {
    const outbounds = [
      Outbound(
        tag: 'shadowtls-transport',
        name: 'ShadowTLS transport',
        config: {
          'type': 'shadowtls',
          'tag': 'shadowtls-transport',
          '_group_only': true,
        },
      ),
      Outbound(
        tag: 'trojan-over-shadowtls',
        name: 'Trojan over ShadowTLS',
        config: {
          'type': 'trojan',
          'tag': 'trojan-over-shadowtls',
          'detour': 'shadowtls-transport',
        },
      ),
    ];

    final selected = SubscriptionStore.selectedProxyTagForOutboundsForTest(
      outbounds,
      preferredTag: 'shadowtls-transport',
    );

    expect(selected, 'trojan-over-shadowtls');
  });

  test('get hydrates saved proxy groups from payload storage', () async {
    const subscription = Subscription(
      id: 'grouped-sub',
      name: 'Grouped subscription',
      url: 'https://example.com/sub',
      outbounds: [
        Outbound(
          tag: 'leaf-1',
          name: 'Leaf 1',
          config: {'type': 'vless', 'tag': 'leaf-1'},
        ),
        Outbound(
          tag: 'leaf-2',
          name: 'Leaf 2',
          config: {'type': 'vless', 'tag': 'leaf-2'},
        ),
      ],
      groups: [
        SubscriptionGroup(
          tag: 'group-auto',
          name: 'Auto group',
          outboundTags: ['leaf-1', 'leaf-2'],
        ),
      ],
    );

    await SubscriptionStore.save(subscription, allowCreate: true);

    final saved = SubscriptionStore.get(subscription.id);
    expect(saved, isNotNull);
    expect(saved!.outbounds.map((entry) => entry.tag), ['leaf-1', 'leaf-2']);
    expect(saved.groups, hasLength(1));
    expect(saved.groups.single.tag, 'group-auto');
    expect(saved.groups.single.outboundTags, ['leaf-1', 'leaf-2']);
  });

  test('keeps selected proxy group when group still has live children', () {
    const outbounds = [
      Outbound(
        tag: 'leaf-1',
        name: 'Leaf 1',
        config: {'type': 'vless', 'tag': 'leaf-1'},
      ),
      Outbound(
        tag: 'leaf-2',
        name: 'Leaf 2',
        config: {'type': 'vless', 'tag': 'leaf-2'},
      ),
    ];
    const groups = [
      SubscriptionGroup(
        tag: 'group-auto',
        name: 'Auto group',
        outboundTags: ['leaf-1', 'leaf-2'],
      ),
    ];

    final selected = SubscriptionStore.selectedProxyTagForOutboundsForTest(
      outbounds,
      preferredTag: 'group-auto',
      groups: groups,
    );

    expect(selected, 'group-auto');
  });

  test('falls back when selected proxy group has no live children', () {
    const outbounds = [
      Outbound(
        tag: 'leaf-1',
        name: 'Leaf 1',
        config: {'type': 'vless', 'tag': 'leaf-1'},
      ),
      Outbound(
        tag: 'leaf-2',
        name: 'Leaf 2',
        config: {'type': 'vless', 'tag': 'leaf-2'},
      ),
    ];
    const groups = [
      SubscriptionGroup(
        tag: 'group-auto',
        name: 'Auto group',
        outboundTags: ['missing'],
      ),
    ];

    final selected = SubscriptionStore.selectedProxyTagForOutboundsForTest(
      outbounds,
      preferredTag: 'group-auto',
      groups: groups,
    );

    expect(selected, 'lowest');
  });

  test('keeps latency runtime-only without clearing location fields', () async {
    const subscription = Subscription(
      id: 'runtime-sub',
      name: 'Runtime subscription',
      url: 'https://example.com/sub',
      outbounds: [
        Outbound(
          tag: 'leaf-1',
          name: 'Leaf 1',
          config: {'type': 'vless', 'tag': 'leaf-1'},
          info: OutboundInfo(
            externalIp: '1.1.1.1',
            country: 'FI',
            exitCountry: 'SE',
          ),
        ),
      ],
    );

    await SubscriptionStore.save(subscription, allowCreate: true);
    await SubscriptionStore.saveOutboundRuntimeInfoInBackground(
      subscription.id,
      latestPings: const {'leaf-1': 42},
    );

    var saved = SubscriptionStore.get(subscription.id);
    expect(saved, isNotNull);
    expect(saved!.outbounds.single.info.latestPing, isNull);
    expect(saved.outbounds.single.info.externalIp, '1.1.1.1');
    expect(saved.outbounds.single.info.country, 'FI');
    expect(saved.outbounds.single.info.exitCountry, 'SE');

    await SubscriptionStore.saveOutboundRuntimeInfoInBackground(
      subscription.id,
      externalInfos: const {
        'leaf-1': {
          'external_ip': '2.2.2.2',
          'source_country': 'FI',
          'exit_country': 'DE',
        },
      },
    );

    saved = SubscriptionStore.get(subscription.id);
    expect(saved, isNotNull);
    expect(saved!.outbounds.single.info.latestPing, isNull);
    expect(saved.outbounds.single.info.externalIp, '2.2.2.2');
    expect(saved.outbounds.single.info.country, 'FI');
    expect(saved.outbounds.single.info.exitCountry, 'DE');
  });

  test('preserves state across duplicate endpoints when credentials match', () {
    final oldOutbounds = [
      _outbound(
        tag: 'proxy',
        name: 'proxy',
        server: '89.106.85.2',
        country: 'DE',
        latestPing: 42,
      ),
      _outbound(
        tag: 'germany',
        name: 'Germany',
        server: '89.106.85.2',
        country: 'SE',
        latestPing: 84,
      ),
    ];
    final newOutbounds = [
      _outbound(tag: 'proxy', name: 'proxy', server: '89.106.85.2'),
      _outbound(tag: 'germany', name: 'Germany', server: '89.106.85.2'),
    ];

    final preserved = SubscriptionStore.preserveUserStateForTest(
      oldOutbounds,
      newOutbounds,
    );

    expect(preserved[0].info.country, 'DE');
    expect(preserved[0].info.latestPing, 42);
    expect(preserved[1].info.country, 'SE');
    expect(preserved[1].info.latestPing, 84);
  });

  test('does not preserve runtime state when outbound credentials change', () {
    final oldOutbounds = [
      _outbound(
        tag: 'proxy',
        name: 'proxy',
        server: '89.106.85.2',
        country: 'DE',
        latestPing: 42,
      ),
    ];
    final newOutbounds = [
      _outbound(
        tag: 'proxy',
        name: 'proxy',
        server: '89.106.85.2',
        uuid: 'changed-uuid',
      ),
    ];

    final preserved = SubscriptionStore.preserveUserStateForTest(
      oldOutbounds,
      newOutbounds,
    );

    expect(preserved.single.info.country, isNull);
    expect(preserved.single.info.latestPing, isNull);
  });

  test('preserves runtime state when outbound credentials stay the same', () {
    final oldOutbounds = [
      _outbound(
        tag: 'proxy',
        name: 'proxy',
        server: '89.106.85.2',
        country: 'DE',
        latestPing: 42,
      ),
    ];
    final newOutbounds = [
      _outbound(tag: 'proxy', name: 'proxy', server: '89.106.85.2'),
    ];

    final preserved = SubscriptionStore.preserveUserStateForTest(
      oldOutbounds,
      newOutbounds,
    );

    expect(preserved.single.info.country, 'DE');
    expect(preserved.single.info.latestPing, 42);
  });

  test('normalizes LagomVPN full-profile outbounds', () {
    final payload = SubscriptionStore.buildSubscriptionPayloadForTest(
      ParseResult(
        format: SubscriptionFormat.xrayConfig,
        outbounds: [
          _parsedLagomVless(
            sourceTag: 'proxy',
            sourceScope: 'xray-0',
            profileName: '🇫🇮 Финляндия',
            server: 'pro-fi.emrata.top',
          ),
          _parsedLagomVless(
            sourceTag: 'proxy',
            sourceScope: 'xray-1',
            profileName: 'YouTube (Глобальный)',
            server: 'pro-se.emrata.top',
          ),
          _parsedLagomVless(sourceTag: 'WL-01-VKC-01-02'),
          _parsedLagomVless(sourceTag: 'WL-01-VKC-01-07'),
          _parsedLagomVless(sourceTag: 'WL-01-CON-01-04'),
          _parsedLagomVless(sourceTag: 'WL-02-SEL-01-04'),
          _parsedLagomVless(sourceTag: 'WL-02-CDN-YA-01'),
          _parsedLagomVless(sourceTag: 'WL-03-YAD-01-04'),
          _parsedLagomVless(sourceTag: 'WL-03-YAD-02-04'),
          _parsedLagomVless(
            sourceTag: 'WL-03-YAD-02-04',
            sourceScope: 'xray-1',
          ),
          {
            '_name': 'WL-IN',
            '_source_tag': 'WL-IN',
            '_source_scope': 'xray-0',
            'type': 'socks',
            'server': '127.0.0.1',
            'server_port': 10810,
          },
        ],
        groups: const [
          ParsedOutboundGroup(
            sourceTag: '01-FALLBACK',
            name: 'fallback',
            sourceOutboundTags: ['WL-01-VKC-01-02', 'WL-01-VKC-01-07'],
            url: 'https://www.google.com/generate_204',
            intervalSeconds: 300,
          ),
        ],
      ),
      providerName: 'LagomVPN 🫠',
    );

    expect(payload.outbounds.map((entry) => entry['name']), [
      'Direct',
      'WL',
      'Direct',
      'WL',
      'WL VK Cloud',
      'WL VK Cloud 2',
      'WL Contell',
      'WL SEL',
      'WL CDN Yandex',
      'WL Yandex',
      'WL Yandex 2',
    ]);
    expect(payload.outbounds.map((entry) => entry['info']?['country']), [
      'FI',
      'FI',
      null,
      null,
      'RU',
      'RU',
      'RU',
      'RU',
      'RU',
      'RU',
      'RU',
    ]);
    final finlandWhitelist = payload.outbounds[1]['config'] as Map;
    final youtubeWhitelist = payload.outbounds[3]['config'] as Map;
    expect(finlandWhitelist['detour'], 'whitelist');
    expect(finlandWhitelist['_group_only'], isTrue);
    expect(youtubeWhitelist['detour'], 'whitelist');
    expect(youtubeWhitelist['_group_only'], isTrue);

    expect(payload.groups, hasLength(3));
    expect(payload.groups[0]['name'], 'Финляндия');
    expect(payload.groups[0]['type'], 'urltest');
    expect(payload.groups[0]['outbounds'], ['vless-0', 'wl']);
    expect(payload.groups[0]['urltest_config'], {
      'method': 'setback',
      'url': 'https://www.google.com/generate_204',
      'interval': 300,
    });
    expect(payload.groups[1]['name'], 'YouTube');
    expect(payload.groups[1]['type'], 'urltest');
    expect(payload.groups[1]['outbounds'], ['vless-2', 'vless-3']);
    expect(payload.groups[1]['urltest_config'], {
      'method': 'setback',
      'url': 'https://www.google.com/generate_204',
      'interval': 300,
    });
    expect(payload.groups[2]['tag'], 'whitelist');
    expect(payload.groups[2]['name'], 'Whitelist');
    expect(payload.groups[2]['type'], 'urltest');
    expect(payload.groups[2]['outbounds'], [
      'wl-vk-cloud',
      'wl-vk-cloud-2',
      'wl-contell',
      'wl-sel',
      'wl-cdn-yandex',
      'wl-yandex',
      'wl-yandex-2',
    ]);
    expect(payload.groups[2]['urltest_config'], {
      'method': 'lowest',
      'url': 'https://www.google.com/generate_204',
      'interval': 300,
    });
  });
}

Map<String, dynamic> _hydraboxPersistenceDocument() => {
  'api_version': 'hydrabox.io/subscription/v1',
  'kind': 'SubscriptionData',
  'issuer': 'https://provider.example',
  'subscription_id': 'persistence-main',
  'channel': 'stable',
  'sequence': 7,
  'issued_at': DateTime.now()
      .toUtc()
      .subtract(const Duration(minutes: 1))
      .toIso8601String(),
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
      'future_safe_section': {'opaque': true},
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
  'extensions': {
    'example.provider/labels': {'tier': 'test'},
  },
};

class _PassthroughHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    client.connectionTimeout = const Duration(seconds: 15);
    return client;
  }
}

Outbound _outbound({
  required String tag,
  required String name,
  required String server,
  String? uuid,
  String? country,
  int? latestPing,
}) {
  return Outbound(
    tag: tag,
    name: name,
    config: {
      'type': 'vless',
      'tag': tag,
      'server': server,
      'server_port': 443,
      'uuid': uuid ?? '$tag-uuid',
    },
    info: OutboundInfo(country: country, latestPing: latestPing),
  );
}

Map<String, dynamic> _parsedLagomVless({
  required String sourceTag,
  String sourceScope = 'xray-0',
  String? profileName,
  String server = 'server.example.com',
}) {
  return {
    '_name': sourceTag,
    '_source_tag': sourceTag,
    '_source_scope': sourceScope,
    '_source_profile_name': ?profileName,
    'type': 'vless',
    'tag': '',
    'server': server,
    'server_port': 443,
    'uuid': '84efe0da-6bad-4008-98e6-37c6b6f3846b',
  };
}

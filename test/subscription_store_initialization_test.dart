import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:hydrabox/data/subscription/subscription_storage_id.dart';
import 'package:hydrabox/data/subscription/subscription_store.dart';
import 'package:hydrabox/models/subscription.dart';

void main() {
  const metadataBoxName = 'subscriptions_secure_v1';
  const payloadBoxName = 'subscription_payloads_secure_v1';
  late Directory directory;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    directory = await Directory.systemTemp.createTemp(
      'hydrabox-store-initialization-',
    );
    Hive.init(directory.path);
  });

  tearDownAll(() async {
    await Hive.close();
    if (directory.existsSync()) {
      await directory.delete(recursive: true);
    }
  });

  test(
    'initialization is single-flight, cleans failures, and migrates payload first',
    () async {
      final unsupportedMetadata = await Hive.openBox(metadataBoxName);
      await unsupportedMetadata.put(subscriptionStorageSchemaVersionKey, 999);
      await unsupportedMetadata.flush();
      await unsupportedMetadata.close();

      final failedAttempts = List<Future<void>>.generate(
        3,
        (_) => SubscriptionStore.init(),
      );
      final failures = await Future.wait<Object?>(
        failedAttempts.map(
          (attempt) => attempt.then<Object?>(
            (_) => null,
            onError: (Object error, StackTrace _) => error,
          ),
        ),
      );

      expect(failures, everyElement(isA<UnsupportedError>()));
      expect(Hive.isBoxOpen(metadataBoxName), isFalse);
      expect(Hive.isBoxOpen(payloadBoxName), isFalse);

      final metadata = await Hive.openBox(metadataBoxName);
      final payload = await Hive.openBox(payloadBoxName);
      await metadata.put(subscriptionStorageSchemaVersionKey, 0);
      const legacy = Subscription(
        id: 'embedded-legacy',
        name: 'Embedded legacy',
        url: 'file:///legacy.txt',
        rawContent: 'vless://legacy-payload',
        outbounds: [
          Outbound(
            tag: 'legacy-node',
            name: 'Legacy node',
            config: {'type': 'vless', 'server': 'legacy.example'},
          ),
        ],
      );
      await metadata.put(legacy.id, jsonEncode(legacy.toMap()));
      await metadata.flush();

      final writes = <String>[];
      final metadataEvents = metadata.watch(key: legacy.id).listen((_) {
        writes.add('metadata');
      });
      final payloadEvents = payload.watch(key: legacy.id).listen((_) {
        writes.add('payload');
      });
      addTearDown(metadataEvents.cancel);
      addTearDown(payloadEvents.cancel);

      await Future.wait<void>([
        SubscriptionStore.init(),
        SubscriptionStore.init(),
        SubscriptionStore.init(),
      ]);
      await Future<void>.delayed(Duration.zero);

      expect(writes, ['payload', 'metadata']);
      final restored = SubscriptionStore.get(legacy.id);
      expect(restored, isNotNull);
      expect(restored!.rawContent, legacy.rawContent);
      expect(restored.outbounds.single.tag, 'legacy-node');
    },
  );
}

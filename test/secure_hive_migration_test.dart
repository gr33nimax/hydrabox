import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:meow_client/data/subscription/subscription_store.dart';
import 'package:meow_client/models/subscription.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('subscription storage migrates and removes plaintext boxes', () async {
    final directory = await Directory.systemTemp.createTemp(
      'etonify-hive-migration-',
    );
    addTearDown(() async {
      await Hive.close();
      if (directory.existsSync()) await directory.delete(recursive: true);
    });
    Hive.init(directory.path);

    const subscription = Subscription(
      id: 'legacy-subscription',
      name: 'Legacy',
      url: 'https://example.com/sub?token=private',
      rawContent: 'vless://private-credential@example.com',
      outbounds: <Outbound>[
        Outbound(
          tag: 'node',
          name: 'Node',
          config: <String, dynamic>{
            'type': 'vless',
            'tag': 'node',
            'uuid': '00000000-0000-4000-8000-000000000001',
          },
        ),
      ],
    );
    final metadata = await Hive.openBox('subscriptions');
    final payloads = await Hive.openBox('subscription_payloads');
    await metadata.put(
      subscription.id,
      jsonEncode(subscription.toMetadataMap()),
    );
    await payloads.put(
      subscription.id,
      jsonEncode(subscription.toPayloadMap()),
    );
    await metadata.close();
    await payloads.close();

    await SubscriptionStore.init();

    final migrated = SubscriptionStore.get(subscription.id);
    expect(migrated?.url, subscription.url);
    expect(migrated?.rawContent, subscription.rawContent);
    expect(migrated?.outbounds.single.config['uuid'], isNotEmpty);
    expect(await Hive.boxExists('subscriptions'), isFalse);
    expect(await Hive.boxExists('subscription_payloads'), isFalse);
    expect(await Hive.boxExists('subscriptions_secure_v1'), isTrue);
    expect(await Hive.boxExists('subscription_payloads_secure_v1'), isTrue);
  });
}

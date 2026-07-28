import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:meow_client/app/subscription_profile_import_controller.dart';
import 'package:meow_client/data/backup/etonify_backup_service.dart';
import 'package:meow_client/models/subscription.dart';

void main() {
  Subscription profile({
    required String id,
    required String name,
    required String url,
    int? sortOrder,
    String selectedProxyTag = '',
    List<Outbound> outbounds = const <Outbound>[],
  }) {
    return Subscription(
      id: id,
      name: name,
      url: url,
      sortOrder: sortOrder,
      selectedProxyTag: selectedProxyTag,
      outbounds: outbounds,
    );
  }

  test(
    'empty import does not touch persistence or refresh the client',
    () async {
      var loadCalls = 0;
      var saveCalls = 0;
      var appliedCalls = 0;
      final controller = SubscriptionProfileImportController(
        loadExisting: () async {
          loadCalls++;
          return const <Subscription>[];
        },
        save: (_) async => saveCalls++,
        onApplied: () async => appliedCalls++,
      );

      final result = await controller.apply(const <Subscription>[]);

      expect(result.subscriptions, isEmpty);
      expect(loadCalls, 0);
      expect(saveCalls, 0);
      expect(appliedCalls, 0);
    },
  );

  test('existing profile keeps identity, position and selected server', () {
    final existing = profile(
      id: 'stored-id',
      name: 'Stored',
      url: 'https://example.com/profile',
      sortOrder: 7,
      selectedProxyTag: 'stored-node',
    );
    final imported = profile(
      id: 'backup-id',
      name: 'Imported',
      url: 'https://example.com/profile',
    );

    final result = SubscriptionProfileImportController.merge(
      existing: [existing],
      imported: [imported],
    );

    expect(result.addedCount, 0);
    expect(result.updatedCount, 1);
    expect(result.subscriptions.single.id, 'stored-id');
    expect(result.subscriptions.single.sortOrder, 7);
    expect(result.subscriptions.single.selectedProxyTag, 'stored-node');
    expect(result.subscriptions.single.name, 'Imported');
  });

  test('new profiles append after existing profiles in backup order', () {
    final result = SubscriptionProfileImportController.merge(
      existing: [
        profile(
          id: 'existing',
          name: 'Existing',
          url: 'https://example.com/existing',
          sortOrder: 12,
        ),
      ],
      imported: [
        profile(
          id: 'first',
          name: 'First',
          url: 'https://example.com/first',
          sortOrder: 1,
        ),
        profile(
          id: 'second',
          name: 'Second',
          url: 'https://example.com/second',
          sortOrder: 0,
        ),
      ],
    );

    expect(result.addedCount, 2);
    expect(result.updatedCount, 0);
    expect(result.subscriptions.map((item) => item.id), ['first', 'second']);
    expect(result.subscriptions.map((item) => item.sortOrder), [13, 14]);
  });

  test('duplicate imported identities are persisted once with latest data', () {
    final result = SubscriptionProfileImportController.merge(
      existing: const <Subscription>[],
      imported: [
        profile(
          id: 'duplicate',
          name: 'First value',
          url: 'https://example.com/duplicate',
        ),
        profile(
          id: 'duplicate',
          name: 'Latest value',
          url: 'https://example.com/duplicate',
        ),
      ],
    );

    expect(result.addedCount, 1);
    expect(result.updatedCount, 0);
    expect(result.subscriptions, hasLength(1));
    expect(result.subscriptions.single.name, 'Latest value');
    expect(result.subscriptions.single.sortOrder, 0);
  });

  test(
    'decoded backup applies profiles without mixing their servers',
    () async {
      const codec = EtonifyBackupService();
      final source = [
        profile(
          id: 'first',
          name: 'First profile',
          url: 'https://example.com/first',
          outbounds: const [
            Outbound(
              tag: 'first-node',
              name: 'First node',
              config: {'type': 'vless'},
            ),
          ],
        ),
        profile(
          id: 'second',
          name: 'Second profile',
          url: 'https://example.com/second',
          outbounds: const [
            Outbound(
              tag: 'second-node',
              name: 'Second node',
              config: {'type': 'trojan'},
            ),
          ],
        ),
      ];
      final encoded = codec.buildProfileExport(
        subscriptions: source,
        clientVersion: '0.3.0',
        encryption: EtonifyProfileEncryption.plain,
      );
      final decoded = codec.parseProfileExport(
        bytes: utf8.encode(encoded),
        currentClientVersion: '0.3.0',
      );
      final saved = <Subscription>[];
      var applied = false;
      final controller = SubscriptionProfileImportController(
        loadExisting: () async => const <Subscription>[],
        save: (subscription) async => saved.add(subscription),
        onApplied: () async => applied = true,
      );

      final result = await controller.apply(decoded.subscriptions);

      expect(result.addedCount, 2);
      expect(saved, hasLength(2));
      expect(saved[0].outbounds.single.tag, 'first-node');
      expect(saved[1].outbounds.single.tag, 'second-node');
      expect(applied, isTrue);
    },
  );
}

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hydrabox/data/backup/hydrabox_backup_service.dart';
import 'package:hydrabox/models/subscription.dart';

void main() {
  const service = HydraBoxBackupService();

  Subscription sampleSubscription() {
    return const Subscription(
      id: 'sub-1',
      name: 'Demo',
      url: 'https://example.com/sub',
      selectedProxyTag: 'node-1',
      rawContent: 'vless://secret@example.com',
    );
  }

  test('encrypted profile decrypts only with the correct password', () {
    final content = service.buildProfileExport(
      subscriptions: [sampleSubscription()],
      clientVersion: '0.2.0',
      encryption: HydraBoxProfileEncryption.encrypted,
      password: 'correct-password',
    );

    expect(
      () => service.parseProfileExport(
        bytes: utf8.encode(content),
        currentClientVersion: '0.2.0',
        password: 'wrong-password',
      ),
      throwsA(isA<HydraBoxBackupException>()),
    );

    final parsed = service.parseProfileExport(
      bytes: utf8.encode(content),
      currentClientVersion: '0.2.0',
      password: 'correct-password',
    );

    expect(parsed.encryption, HydraBoxProfileEncryption.encrypted);
    expect(parsed.subscriptions.single.id, 'sub-1');
    expect(
      parsed.subscriptions.single.rawContent,
      'vless://secret@example.com',
    );
  });

  test('plain profile imports with plaintext warning metadata', () {
    final content = service.buildProfileExport(
      subscriptions: [sampleSubscription()],
      clientVersion: '0.2.0',
      encryption: HydraBoxProfileEncryption.plain,
    );

    final parsed = service.parseProfileExport(
      bytes: utf8.encode(content),
      currentClientVersion: '0.2.0',
    );

    expect(parsed.encryption, HydraBoxProfileEncryption.plain);
    expect(parsed.warning.compatibility, ExportCompatibilityStatus.compatible);
    expect(parsed.subscriptions.single.selectedProxyTag, 'node-1');
  });

  test('large backup keeps profiles and their servers separate', () async {
    final first = sampleSubscription().copyWith(
      name: 'First profile',
      rawContent: ''.padRight(9 * 1024 * 1024, 'a'),
      outbounds: const [
        Outbound(
          tag: 'first-1',
          name: 'First one',
          config: {'type': 'vless', 'server': 'first.example'},
        ),
        Outbound(
          tag: 'first-2',
          name: 'First two',
          config: {'type': 'vless', 'server': 'second.example'},
        ),
      ],
    );
    final second = sampleSubscription().copyWith(
      id: 'sub-2',
      url: 'https://example.com/sub-2',
      name: 'Second profile',
      selectedProxyTag: 'second-1',
      rawContent: 'vless://second',
      outbounds: const [
        Outbound(
          tag: 'second-1',
          name: 'Second one',
          config: {'type': 'vless', 'server': 'third.example'},
        ),
      ],
    );

    final content = await service.buildProfileExportInBackground(
      subscriptions: [first, second],
      clientVersion: '0.2.2',
      encryption: HydraBoxProfileEncryption.plain,
    );
    expect(utf8.encode(content).length, greaterThan(8 * 1024 * 1024));
    expect(
      utf8.encode(content).length,
      lessThanOrEqualTo(HydraBoxBackupService.maxImportBytes),
    );

    final parsed = await service.parseProfileExportInBackground(
      bytes: utf8.encode(content),
      currentClientVersion: '0.2.2',
    );

    expect(parsed.subscriptions.map((item) => item.name), [
      'First profile',
      'Second profile',
    ]);
    expect(parsed.subscriptions[0].outbounds.map((item) => item.tag), [
      'first-1',
      'first-2',
    ]);
    expect(parsed.subscriptions[1].outbounds.map((item) => item.tag), [
      'second-1',
    ]);
  });

  test('exporter never creates a profile larger than the import limit', () {
    final oversized = sampleSubscription().copyWith(
      rawContent: ''.padRight(17 * 1024 * 1024, 'é'),
    );

    expect(
      () => service.buildProfileExport(
        subscriptions: [oversized],
        clientVersion: '0.2.2',
        encryption: HydraBoxProfileEncryption.plain,
      ),
      throwsA(
        isA<HydraBoxBackupException>().having(
          (error) => error.message,
          'message',
          contains('too large to import'),
        ),
      ),
    );
  });

  test('rejects backups that require a newer minimum client version', () {
    final content = service.buildProfileExport(
      subscriptions: [sampleSubscription()],
      clientVersion: '0.3.0',
      encryption: HydraBoxProfileEncryption.plain,
    );
    final map = jsonDecode(content) as Map<String, dynamic>;
    map['minClientVersion'] = '0.3.0';

    final parsed = service.parseProfileExport(
      bytes: utf8.encode(jsonEncode(map)),
      currentClientVersion: '0.2.0',
    );

    expect(parsed.warning.compatibility, ExportCompatibilityStatus.unsupported);
  });

  test('rejects unknown top-level sections', () {
    final content = service.buildProfileExport(
      subscriptions: [sampleSubscription()],
      clientVersion: '0.2.0',
      encryption: HydraBoxProfileEncryption.plain,
    );
    final map = jsonDecode(content) as Map<String, dynamic>;
    map['unexpected'] = true;

    expect(
      () => service.parseProfileExport(
        bytes: utf8.encode(jsonEncode(map)),
        currentClientVersion: '0.2.0',
      ),
      throwsA(isA<HydraBoxBackupException>()),
    );
  });
}

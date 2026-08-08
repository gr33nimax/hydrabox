import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hydrabox/app/app_background_tasks.dart';

void main() {
  test('fast retry prunes empty proxy groups after removing an outbound', () {
    final tempDir = Directory.systemTemp.createTempSync(
      'hydrabox-config-mutation-',
    );
    addTearDown(() => tempDir.deleteSync(recursive: true));

    final result = mutateSingboxConfig(
      ConfigMutationInput(
        config: {
          'outbounds': [
            {
              'type': 'selector',
              'tag': 'select',
              'outbounds': ['group-1', 'vless-2'],
              'default': 'group-1',
            },
            {
              'type': 'urltest',
              'tag': 'group-1',
              'outbounds': ['vless-1'],
            },
            {'type': 'vless', 'tag': 'vless-1'},
            {'type': 'vless', 'tag': 'vless-2'},
            {'type': 'direct', 'tag': 'direct'},
          ],
        },
        proxyOutboundTagsByIndex: const {2: 'vless-1', 3: 'vless-2'},
        tagToRemove: 'vless-1',
        outputPath: '${tempDir.path}/config.json',
      ),
    );

    final outbounds = (result.config['outbounds'] as List)
        .cast<Map<String, dynamic>>();

    expect(outbounds.map((outbound) => outbound['tag']), [
      'select',
      'vless-2',
      'direct',
    ]);
    expect(outbounds.first['outbounds'], ['vless-2']);
    expect(outbounds.first['default'], 'vless-2');
    expect(result.proxyOutboundTagsByIndex, {1: 'vless-2'});
    expect(result.startableProxyCount, 1);
  });

  test('fast retry retains native-config identity after the last proxy', () {
    final tempDir = Directory.systemTemp.createTempSync(
      'hydrabox-native-config-mutation-',
    );
    addTearDown(() => tempDir.deleteSync(recursive: true));

    final result = mutateSingboxConfig(
      ConfigMutationInput(
        config: {
          'services': [
            {'type': 'manager-api', 'tag': 'manager'},
          ],
          'outbounds': [
            {
              'type': 'selector',
              'tag': 'select',
              'outbounds': ['broken'],
              'default': 'broken',
            },
            {'type': 'vless', 'tag': 'broken'},
            {'type': 'direct', 'tag': 'direct'},
          ],
        },
        proxyOutboundTagsByIndex: const {1: 'broken'},
        tagToRemove: 'broken',
        outputPath: '${tempDir.path}/config.json',
        hasRawCoreConfig: true,
      ),
    );

    expect(result.startableProxyCount, 0);
    expect(result.hasRawCoreConfig, isTrue);
    expect(result.allowsZeroSelectableEntries, isFalse);
    expect(result.config['services'], isNotEmpty);
    expect(
      (result.config['outbounds'] as List).cast<Map<String, dynamic>>().map(
        (entry) => entry['tag'],
      ),
      ['direct'],
    );
  });

  test('fast retry preserves object-valued extended outbound groups', () {
    final tempDir = Directory.systemTemp.createTempSync(
      'hydrabox-object-group-mutation-',
    );
    addTearDown(() => tempDir.deleteSync(recursive: true));

    final result = mutateSingboxConfig(
      ConfigMutationInput(
        config: {
          'outbounds': [
            {
              'type': 'selector',
              'tag': 'select',
              'outbounds': ['bond-node', 'broken'],
              'default': 'broken',
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
            },
            {'type': 'vless', 'tag': 'broken'},
            {'type': 'direct', 'tag': 'direct'},
          ],
        },
        proxyOutboundTagsByIndex: const {2: 'broken'},
        tagToRemove: 'broken',
        outputPath: '${tempDir.path}/config.json',
        hasRawCoreConfig: true,
      ),
    );

    final outbounds = (result.config['outbounds'] as List)
        .cast<Map<String, dynamic>>();
    final selector = outbounds.singleWhere(
      (outbound) => outbound['tag'] == 'select',
    );
    final bond = outbounds.singleWhere(
      (outbound) => outbound['tag'] == 'bond-node',
    );
    expect(selector['outbounds'], ['bond-node']);
    expect(selector['default'], 'bond-node');
    expect(bond['outbounds'], hasLength(1));
    expect(
      ((bond['outbounds'] as List).single as Map)['outbound'],
      containsPair('type', 'direct'),
    );
  });

  test('fast retry remains startable while a native endpoint survives', () {
    final tempDir = Directory.systemTemp.createTempSync(
      'hydrabox-endpoint-config-mutation-',
    );
    addTearDown(() => tempDir.deleteSync(recursive: true));

    final result = mutateSingboxConfig(
      ConfigMutationInput(
        config: {
          'endpoints': [
            {'type': 'warp', 'tag': 'warp-endpoint', 'private_key': 'opaque'},
          ],
          'outbounds': [
            {
              'type': 'selector',
              'tag': 'select',
              'outbounds': ['warp-endpoint', 'broken'],
              'default': 'broken',
            },
            {'type': 'vless', 'tag': 'broken'},
            {'type': 'direct', 'tag': 'direct'},
          ],
        },
        proxyOutboundTagsByIndex: const {1: 'broken'},
        tagToRemove: 'broken',
        outputPath: '${tempDir.path}/config.json',
        hasRawCoreConfig: true,
      ),
    );

    expect(result.startableProxyCount, 1);
    expect(result.allowsZeroSelectableEntries, isFalse);
    expect(((result.config['outbounds'] as List).first as Map)['outbounds'], [
      'warp-endpoint',
    ]);
  });
}

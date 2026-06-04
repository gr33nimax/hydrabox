import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:meow_client/app/app_background_tasks.dart';

void main() {
  test('fast retry prunes empty proxy groups after removing an outbound', () {
    final tempDir = Directory.systemTemp.createTempSync(
      'meow-config-mutation-',
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
}

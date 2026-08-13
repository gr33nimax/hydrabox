import 'package:flutter_test/flutter_test.dart';
import 'package:hydrabox/data/subscription/outbound_schema.dart';

void main() {
  Map<String, dynamic> valid() => <String, dynamic>{
    'type': 'call',
    'tag': 'call-vk-out',
    'platform': 'vk',
    'mode': 'vk_parasite',
    'server': 'vpn.example',
    'server_port': 2443,
    'join_links': <String>[
      'https://calls.example/join/room-a',
      'https://calls.example/join/room-b',
    ],
    'user': 'alice',
    'password': 'per-user-secret',
    'obfs_password': 'ooooooooooooooooooooooooooooooooooooooooooo',
    'workers': 4,
    'worker_connect_timeout': '12s',
  };

  test('retains and validates the VK parasite outbound', () {
    final sanitized = ParsedOutboundSchema.sanitize(valid());

    expect(sanitized, isNotNull);
    expect(sanitized?['mode'], 'vk_parasite');
    expect(sanitized?['join_links'], hasLength(2));
    expect(sanitized?['workers'], 4);
    expect(ParsedOutboundSchema.validate(sanitized!), isNull);
  });

  test('rejects incomplete four-lane configurations', () {
    final wrongLaneCount = valid()..['workers'] = 3;
    final tooManyLinks = valid()
      ..['join_links'] = <String>['a', 'b', 'c', 'd', 'e'];
    final duplicateLinks = valid()
      ..['join_links'] = <String>[
        'https://calls.example/join/same',
        'https://calls.example/join/same',
      ];
    final noSharedObfs = valid()..remove('obfs_password');
    final excessiveTimeout = valid()..['worker_connect_timeout'] = '121s';

    expect(
      ParsedOutboundSchema.validate(wrongLaneCount),
      contains('exactly four'),
    );
    expect(ParsedOutboundSchema.validate(tooManyLinks), contains('1..4'));
    expect(
      ParsedOutboundSchema.validate(duplicateLinks),
      contains('must be unique'),
    );
    expect(
      ParsedOutboundSchema.validate(noSharedObfs),
      contains('obfs_password'),
    );
    expect(
      ParsedOutboundSchema.validate(excessiveTimeout),
      contains('between 1s and 2m'),
    );
  });

  test('keeps the legacy joiner role contract unchanged', () {
    final legacy = <String, dynamic>{
      'type': 'call',
      'tag': 'call-vk-legacy',
      'platform': 'vk',
      'mode': 'joiner',
      'join_link': 'https://calls.example/join/legacy-room',
    };

    expect(ParsedOutboundSchema.validate(legacy), isNull);
    expect(ParsedOutboundSchema.sanitize(legacy)?['mode'], 'joiner');
  });
}

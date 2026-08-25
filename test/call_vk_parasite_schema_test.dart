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
      'https://calls.example/join/room-c',
      'https://calls.example/join/room-d',
    ],
    'user': 'alice',
    'password': 'per-user-secret',
    'obfs_password': 'ooooooooooooooooooooooooooooooooooooooooooo',
    'worker_connect_timeout': '12s',
  };

  test('retains and validates the VK parasite outbound', () {
    final sanitized = ParsedOutboundSchema.sanitize(valid());

    expect(sanitized, isNotNull);
    expect(sanitized?['mode'], 'vk_parasite');
    expect(sanitized?['join_links'], hasLength(4));
    expect(sanitized?['workers'], isNull);
    expect(ParsedOutboundSchema.validate(sanitized!), isNull);
  });

  test(
    'accepts and preserves every supported worker count',
    () {
      for (final count in [4, 8, 12, 16, 20]) {
        final input = valid()..['workers'] = count;
        expect(ParsedOutboundSchema.validate(input), isNull);
        final sanitized = ParsedOutboundSchema.sanitize(input);
        expect(sanitized, isNotNull);
        expect(sanitized?['workers'], count);
      }
    },
  );

  test('rejects invalid worker counts and configurations', () {
    final wrongLaneCount5 = valid()..['workers'] = 5;
    final wrongLaneCount18 = valid()..['workers'] = 18;
    final tooManyLinks = valid()
      ..['join_links'] = <String>['a', 'b', 'c', 'd', 'e'];
    final duplicateLinks = valid()
      ..['join_links'] = <String>[
        'https://calls.example/join/same',
        'https://calls.example/join/same',
      ];
    final noSharedObfs = valid()..remove('obfs_password');
    final excessiveTimeout = valid()..['worker_connect_timeout'] = '121s';

    expect(ParsedOutboundSchema.validate(wrongLaneCount5), contains('4, 8, 12, 16, or 20'));
    expect(ParsedOutboundSchema.validate(wrongLaneCount18), contains('4, 8, 12, 16, or 20'));
    expect(ParsedOutboundSchema.validate(tooManyLinks), contains('exactly 4'));
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

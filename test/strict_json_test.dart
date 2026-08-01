import 'package:flutter_test/flutter_test.dart';
import 'package:meow_client/data/subscription/strict_json.dart';

void main() {
  group('decodeStrictJson nesting limit', () {
    const maxDepth = 4;

    test('accepts exactly the configured maximum depth', () {
      expect(
        () => decodeStrictJson(_nestedContainers(maxDepth), maxDepth: maxDepth),
        returnsNormally,
      );
    });

    test('rejects an empty container one level beyond the maximum', () {
      expect(
        () => decodeStrictJson(
          _nestedContainers(maxDepth + 1),
          maxDepth: maxDepth,
        ),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('JSON nesting exceeds $maxDepth levels'),
          ),
        ),
      );
    });
  });

  test('format errors never expose attacker-controlled source excerpts', () {
    const sentinel = 'TOP-SECRET-SUBSCRIPTION-CREDENTIAL';
    late FormatException error;
    try {
      decodeStrictJson('{"password":"$sentinel","sequence":1,"sequence":2}');
      fail('duplicate key must be rejected');
    } on FormatException catch (caught) {
      error = caught;
    }

    expect(error.source, isNull);
    expect(error.toString(), isNot(contains(sentinel)));
  });
}

String _nestedContainers(int depth) {
  var source = '{}';
  for (var level = 1; level < depth; level++) {
    source = level.isOdd ? '[$source]' : '{"value":$source}';
  }
  return source;
}

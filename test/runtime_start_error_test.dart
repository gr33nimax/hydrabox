import 'package:flutter_test/flutter_test.dart';
import 'package:meow_client/singbox/runtime_start_error.dart';

void main() {
  group('parseRuntimeInvalidOutboundError', () {
    test('parses initialize outbound errors', () {
      final parsed = parseRuntimeInvalidOutboundError(
        'start service: initialize outbound[17]: tls: invalid server name',
      );

      expect(parsed, isNotNull);
      expect(parsed!.outboundIndex, 17);
      expect(parsed.reason, 'tls: invalid server name');
    });

    test('parses decode config outbound errors', () {
      final parsed = parseRuntimeInvalidOutboundError(
        'start or reload service: decode config: outbounds[153].transport.x_padding_bytes: '
        'json: cannot unmarshal string into Go value of type option.V2RayXHTTPRangeConfig',
      );

      expect(parsed, isNotNull);
      expect(parsed!.outboundIndex, 153);
      expect(
        parsed.reason,
        'transport.x_padding_bytes: json: cannot unmarshal string into Go value of type option.V2RayXHTTPRangeConfig',
      );
    });

    test('returns null for unrelated errors', () {
      final parsed = parseRuntimeInvalidOutboundError(
        'start or reload service: decode config: unexpected eof',
      );

      expect(parsed, isNull);
    });
  });
}

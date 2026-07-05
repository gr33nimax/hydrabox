import 'package:flutter_test/flutter_test.dart';
import 'package:meow_client/app/fast_exit_ip_lookup.dart';

void main() {
  test('parses Cloudflare trace with IPv4 and country', () {
    final result = parseCloudflareTrace('fl=1\nip=203.0.113.8\nloc=DE\n');

    expect(result?.ip, '203.0.113.8');
    expect(result?.countryCode, 'DE');
    expect(result?.source, 'cloudflare_trace');
  });

  test('parses ipwho response with IPv6', () {
    final result = parseIpWhoResponse(
      '{"success":true,"ip":"2001:db8::1","country_code":"nl"}',
    );

    expect(result?.ip, '2001:db8::1');
    expect(result?.countryCode, 'NL');
  });

  test('rejects malformed or unsuccessful responses', () {
    expect(parseCloudflareTrace('ip=not-an-ip\nloc=DE'), isNull);
    expect(parseIpWhoResponse('{"success":false,"ip":"1.1.1.1"}'), isNull);
    expect(parseIpWhoResponse('not json'), isNull);
  });
}

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:meow_client/data/subscription/subscription_fetcher.dart';
import 'package:meow_client/data/subscription/subscription_failure.dart';
import 'package:meow_client/data/subscription/subscription_store.dart';
import 'package:meow_client/logging/app_log_store.dart';
import 'package:meow_client/models/subscription.dart';

void main() {
  group('SubscriptionFetcher', () {
    tearDown(() {
      SubscriptionFetcher.configureAppVersion(
        SubscriptionFetcher.fallbackAppVersion,
      );
      AppLogStore.clear();
    });

    test('derives user agent from the installed app version', () {
      SubscriptionFetcher.configureAppVersion('v0.3.7');
      expect(SubscriptionFetcher.defaultUserAgent, 'HydraBox/0.3.7');
    });

    test('uses current HydraBox user agent by default', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);

      late String? userAgent;
      server.listen((request) async {
        userAgent = request.headers.value('user-agent');
        request.response.write(
          'vless://uuid@server.com:443?type=tcp&security=tls#Node1',
        );
        await request.response.close();
      });

      await SubscriptionFetcher.fetch(
        'http://${server.address.host}:${server.port}/sub',
      );

      expect(userAgent, SubscriptionFetcher.defaultUserAgent);
    });

    test('rejects a malformed hbx-key policy before network access', () async {
      await expectLater(
        SubscriptionFetcher.fetch(
          'https://provider.invalid/subscription#hbx-key=',
        ),
        throwsFormatException,
      );
    });

    test('rejects hbx-key in query before network access', () async {
      const key = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';
      for (final url in [
        'https://provider.invalid/subscription?hbx-key=$key',
        'https://provider.invalid/subscription?hbx%2Dkey=$key#hbx-key=$key',
      ]) {
        await expectLater(
          SubscriptionFetcher.fetch(url),
          throwsFormatException,
        );
      }
    });

    test('rejects hbx-key introduced by a redirect query', () {
      expect(
        () => SubscriptionFetcher.validateRequestSecurityForTest(
          Uri.parse('https://provider.example/sub?hbx%2Dkey=secret'),
          const {'Accept': '*/*'},
        ),
        throwsA(isA<HttpException>()),
      );
    });

    test('does not write subscription URL paths to logs', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);
      server.listen((request) async {
        request.response.write(
          'vless://uuid@server.com:443?type=tcp&security=tls#Node1',
        );
        await request.response.close();
      });

      const secretPath = 'customer-bearer-path-secret';
      await SubscriptionFetcher.fetch(
        'http://${server.address.host}:${server.port}/$secretPath',
      );

      expect(AppLogStore.dump(), isNot(contains(secretPath)));
    });

    test('malformed HydraBox source excerpts never reach logs', () async {
      const sentinel = 'TOP-SECRET-PROVIDER-CREDENTIAL';
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);
      server.listen((request) async {
        request.response.headers.set(
          HttpHeaders.contentTypeHeader,
          'application/vnd.hydrabox.subscription+json',
        );
        request.response.write(
          '{"password":"$sentinel",'
          '"api_version":"hydrabox.io/subscription/v1",'
          '"sequence":1,"sequence":2}',
        );
        await request.response.close();
      });

      await expectLater(
        SubscriptionFetcher.fetch(
          'http://${server.address.host}:${server.port}/subscription',
        ),
        throwsA(isA<FormatException>()),
      );
      expect(AppLogStore.dump(), isNot(contains(sentinel)));
    });

    test('malformed URLs never attach key-bearing input to errors', () {
      const sentinel = 'TOP-SECRET-HBX-KEY';
      Object? captured;

      try {
        SubscriptionFetcher.parseRequestUriForTest(
          'https://[пример.рф/subscription#hbx-key=$sentinel',
        );
      } catch (error) {
        captured = error;
      }

      expect(captured, isA<FormatException>());
      expect((captured! as FormatException).source, isNull);
      expect(captured.toString(), isNot(contains(sentinel)));
    });

    test(
      'does not persist hbx-key sources without protected storage',
      () async {
        if (Platform.isAndroid) return;
        const key = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';
        await expectLater(
          SubscriptionFetcher.fetch(
            'https://provider.invalid/subscription#hbx-key=$key',
          ),
          throwsA(isA<UnsupportedError>()),
        );
      },
    );

    test('rejects X-HWID over plain HTTP', () async {
      await expectLater(
        SubscriptionFetcher.fetch(
          'http://127.0.0.1/sub',
          requestInfo: const SubscriptionInfo(
            customUserAgent: 'CustomClient/9.9',
            requireHwid: true,
            customHwid: 'spoofed-hwid',
          ),
        ),
        throwsA(isA<HttpException>()),
      );
    });

    test('strips custom and credential headers on cross-origin redirect', () {
      final redirected =
          SubscriptionFetcher.headersForCrossOriginRedirectForTest({
            'User-Agent': 'Etonify/test',
            'Accept': '*/*',
            'Authorization': 'Bearer secret',
            'X-HWID': 'device-id',
            'X-Custom': 'provider-value',
          });

      expect(redirected, {'User-Agent': 'Etonify/test', 'Accept': '*/*'});
    });

    test('Hydra JWE request forces identity headers and strips raw HWID', () {
      const hydraId = 'hbx1_AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';
      SubscriptionFetcher.configureAppVersion('0.3.0-beta.3');
      final headers = SubscriptionFetcher.hydraRequestHeadersForTest(const {
        'User-Agent': 'Spoofed/1',
        'Accept': '*/*',
        'X-HWID': 'raw-android-id',
        'X-Hydra-HWID': 'spoofed',
        'Authorization': 'Bearer provider-token',
      }, hydraId);

      expect(headers['User-Agent'], 'HydraBox/0.3.0-beta.3');
      expect(headers['Accept'], 'application/jose+json');
      expect(headers['X-Hydra-HWID'], hydraId);
      expect(headers, isNot(contains('X-HWID')));
      expect(headers['Authorization'], 'Bearer provider-token');
    });

    test('Hydra origin is canonical and excludes path and default port', () {
      expect(
        SubscriptionFetcher.canonicalHttpsOriginForTest(
          Uri.parse('https://EXAMPLE.com:443/a/subscription?format=hydrabox'),
        ),
        'https://example.com',
      );
      expect(
        SubscriptionFetcher.canonicalHttpsOriginForTest(
          Uri.parse('https://example.com:9443/subscription'),
        ),
        'https://example.com:9443',
      );
    });

    test('cross-origin redirect removes Hydra device identity', () {
      final redirected =
          SubscriptionFetcher.headersForCrossOriginRedirectForTest({
            'User-Agent': 'HydraBox/0.3.0',
            'Accept': 'application/jose+json',
            'X-Hydra-HWID': 'hbx1_AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
          });

      expect(redirected, {
        'User-Agent': 'HydraBox/0.3.0',
        'Accept': 'application/jose+json',
      });
    });

    test('rejects secret query values over plain HTTP', () {
      expect(
        () => SubscriptionFetcher.validateRequestSecurityForTest(
          Uri.parse('http://example.com/sub?token=secret'),
          const {'Accept': '*/*'},
        ),
        throwsA(isA<HttpException>()),
      );
    });

    test('rejects remote plain HTTP even without explicit credentials', () {
      expect(
        () => SubscriptionFetcher.validateRequestSecurityForTest(
          Uri.parse('http://provider.example/subscription'),
          const {'Accept': '*/*'},
        ),
        throwsA(isA<HttpException>()),
      );
    });

    test('rejects HydraBox format over loopback HTTP', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);
      server.listen((request) async {
        request.response.write(
          jsonEncode({
            'api_version': 'hydrabox.io/subscription/v1',
            'kind': 'SubscriptionData',
            'issuer': 'https://provider.example',
            'subscription_id': 'https-required',
            'sequence': 1,
            'issued_at': '2026-07-31T10:00:00Z',
            'runtime': {
              'format': 'sing-box-json',
              'document': {
                'outbounds': [
                  {'type': 'future-protocol', 'tag': 'main'},
                ],
              },
            },
            'profiles': [
              {
                'id': 'main',
                'name': {'default': 'Main'},
                'entrypoint': {'section': 'outbounds', 'tag': 'main'},
              },
            ],
          }),
        );
        await request.response.close();
      });

      await expectLater(
        SubscriptionFetcher.fetch(
          'http://${server.address.host}:${server.port}/subscription',
        ),
        throwsA(isA<HttpException>()),
      );
    });

    test(
      'vendor HydraBox Content-Type rejects a legacy body on first import',
      () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(server.close);
        server.listen((request) async {
          request.response.headers.set(
            HttpHeaders.contentTypeHeader,
            'Application/Vnd.HydraBox.Subscription+Json; Charset=UTF-8',
          );
          request.response.write(
            'vless://uuid@server.com:443?type=tcp&security=tls#Node1',
          );
          await request.response.close();
        });

        await expectLater(
          SubscriptionFetcher.fetch(
            'http://${server.address.host}:${server.port}/subscription',
          ),
          throwsA(
            isA<FormatException>().having(
              (error) => error.message,
              'message',
              contains('plaintext v1 JSON'),
            ),
          ),
        );
      },
    );

    test(
      'JOSE Content-Type requires JWE and an hbx-key on first import',
      () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(server.close);
        server.listen((request) async {
          request.response.headers.set(
            HttpHeaders.contentTypeHeader,
            'APPLICATION/JOSE+JSON; charset=utf-8',
          );
          request.response.write(
            'vless://uuid@server.com:443?type=tcp&security=tls#Node1',
          );
          await request.response.close();
        });

        await expectLater(
          SubscriptionFetcher.fetch(
            'http://${server.address.host}:${server.port}/subscription',
          ),
          throwsA(
            isA<FormatException>().having(
              (error) => error.message,
              'message',
              contains('require an hbx-key'),
            ),
          ),
        );
      },
    );

    test('decodes profile-title with base64 prefix', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);

      server.listen((request) async {
        request.response.headers.set(
          'profile-title',
          'base64:${base64Encode(utf8.encode('MeowVPN Premium'))}',
        );
        request.response.write(
          'vless://uuid@server.com:443?type=tcp&security=tls#Node1',
        );
        await request.response.close();
      });

      final result = await SubscriptionFetcher.fetch(
        'http://${server.address.host}:${server.port}/sub',
      );

      expect(result.headerInfo.title, 'MeowVPN Premium');
      expect(result.parseResult.outbounds, isNotEmpty);
    });

    test('falls back to content-disposition filename', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);

      server.listen((request) async {
        request.response.headers.set(
          'content-disposition',
          'attachment; filename="MyProfile"',
        );
        request.response.write(
          'vless://uuid@server.com:443?type=tcp&security=tls#Node1',
        );
        await request.response.close();
      });

      final result = await SubscriptionFetcher.fetch(
        'http://${server.address.host}:${server.port}/sub',
      );

      expect(result.headerInfo.title, 'MyProfile');
    });

    test('rejects oversized responses before parsing', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);

      server.listen((request) async {
        final chunk = List<int>.filled(64 * 1024, 65);
        var remaining = 16 * 1024 * 1024 + 1;
        try {
          while (remaining > 0) {
            final take = remaining < chunk.length ? remaining : chunk.length;
            request.response.add(chunk.take(take).toList(growable: false));
            await request.response.flush();
            remaining -= take;
          }
        } catch (_) {
          // The client is expected to stop reading as soon as the cap is hit.
        } finally {
          await request.response.close();
        }
      });

      await expectLater(
        SubscriptionFetcher.fetch(
          'http://${server.address.host}:${server.port}/sub',
        ),
        throwsA(
          isA<SubscriptionContentException>().having(
            (error) => error.kind,
            'kind',
            SubscriptionContentFailureKind.responseTooLarge,
          ),
        ),
      );
    });

    test('preserves the HTTP status returned by the provider', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);

      server.listen((request) async {
        request.response.statusCode = HttpStatus.badGateway;
        await request.response.close();
      });

      await expectLater(
        SubscriptionFetcher.fetch(
          'http://${server.address.host}:${server.port}/sub',
        ),
        throwsA(
          isA<SubscriptionHttpStatusException>().having(
            (error) => error.statusCode,
            'statusCode',
            HttpStatus.badGateway,
          ),
        ),
      );
    });

    test('rejects an empty successful response', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);

      server.listen((request) async {
        request.response.statusCode = HttpStatus.ok;
        await request.response.close();
      });

      await expectLater(
        SubscriptionFetcher.fetch(
          'http://${server.address.host}:${server.port}/sub',
        ),
        throwsA(
          isA<SubscriptionContentException>().having(
            (error) => error.kind,
            'kind',
            SubscriptionContentFailureKind.emptyResponse,
          ),
        ),
      );
    });

    test('rejects an HTML error page returned with HTTP 200', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);

      server.listen((request) async {
        request.response.statusCode = HttpStatus.ok;
        request.response.headers.contentType = ContentType.html;
        request.response.write(
          '<!doctype html><html><body>Provider error</body></html>',
        );
        await request.response.close();
      });

      await expectLater(
        SubscriptionFetcher.fetch(
          'http://${server.address.host}:${server.port}/sub',
        ),
        throwsA(
          isA<SubscriptionContentException>().having(
            (error) => error.kind,
            'kind',
            SubscriptionContentFailureKind.htmlResponse,
          ),
        ),
      );
    });

    test('parses unicode domains in subscription urls', () {
      final uri = SubscriptionFetcher.parseRequestUriForTest(
        'https://стасян.рф/sub.txt',
      );

      expect(uri.scheme, 'https');
      expect(uri.host, 'xn--80a0akbd4f.xn--p1ai');
      expect(uri.path, '/sub.txt');
    });

    test('extracts country from leading emoji in outbound name', () {
      final parsed = SubscriptionStore.extractCountryFromNameForTest(
        '🇩🇪   Germany Premium  ',
      );

      expect(parsed.countryCode, 'DE');
      expect(parsed.name, 'Germany Premium');
    });

    test('extracts european union flag from outbound name', () {
      final parsed = SubscriptionStore.extractCountryFromNameForTest(
        '🇪🇺 Europe Relay',
      );

      expect(parsed.countryCode, 'EU');
      expect(parsed.name, 'Europe Relay');
    });

    test('extracts country from leading english country/city name', () {
      final parsedCountry = SubscriptionStore.extractCountryFromNameForTest(
        'Germany Premium',
      );
      final parsedCity = SubscriptionStore.extractCountryFromNameForTest(
        'Amsterdam Fast 01',
      );

      expect(parsedCountry.countryCode, 'DE');
      expect(parsedCountry.name, 'Germany Premium');
      expect(parsedCity.countryCode, 'NL');
      expect(parsedCity.name, 'Amsterdam Fast 01');
    });

    test('extracts country from leading russian country/city name', () {
      final parsedCountry = SubscriptionStore.extractCountryFromNameForTest(
        'Финляндия Premium',
      );
      final parsedCity = SubscriptionStore.extractCountryFromNameForTest(
        'Москва 01',
      );

      expect(parsedCountry.countryCode, 'FI');
      expect(parsedCountry.name, 'Финляндия Premium');
      expect(parsedCity.countryCode, 'RU');
      expect(parsedCity.name, 'Москва 01');
    });

    test('extracts country from common location abbreviations', () {
      final parsedMsk = SubscriptionStore.extractCountryFromNameForTest(
        'msk Premium',
      );
      final parsedNyc = SubscriptionStore.extractCountryFromNameForTest(
        'nyc Edge 01',
      );
      final parsedFra = SubscriptionStore.extractCountryFromNameForTest(
        'fra ws 02',
      );
      final parsedHkg = SubscriptionStore.extractCountryFromNameForTest(
        'hkg relay',
      );

      expect(parsedMsk.countryCode, 'RU');
      expect(parsedNyc.countryCode, 'US');
      expect(parsedFra.countryCode, 'DE');
      expect(parsedHkg.countryCode, 'HK');
    });

    test('extracts country from flag with leading decorative emoji', () {
      final parsedRu = SubscriptionStore.extractCountryFromNameForTest(
        '⚡ 🇷🇺 Россия Москва',
      );
      final parsedFi = SubscriptionStore.extractCountryFromNameForTest(
        '✈️🇫🇮 Финляндия',
      );

      expect(parsedRu.countryCode, 'RU');
      expect(parsedRu.name, '⚡ Россия Москва');
      expect(parsedFi.countryCode, 'FI');
      expect(parsedFi.name, '✈️ Финляндия');
    });

    test('skips outbounds with invalid reality public key during import', () {
      final outbounds = SubscriptionStore.buildOutboundsForTest([
        {
          'type': 'vless',
          'server': 'example.com',
          'server_port': 443,
          'tls': {
            'enabled': true,
            'reality': {'enabled': true, 'public_key': 'broken'},
          },
          '_name': 'Broken Reality',
        },
      ]);

      expect(outbounds, isEmpty);
    });

    test('skips outbounds with unsupported reality flow during import', () {
      final outbounds = SubscriptionStore.buildOutboundsForTest([
        {
          'type': 'vless',
          'server': 'example.com',
          'server_port': 443,
          'uuid': '7c6a5b3e-4f1a-4d2b-8c9e-1a2b3c4d5e6f',
          'flow': 'xtls-rprx-direct',
          'tls': {
            'enabled': true,
            'reality': {
              'enabled': true,
              'public_key': 'thwa3P0vSbbPNr0n94LqAzpFJGwTX3bpIlTyrIis7S8',
            },
          },
          '_name': 'Broken Reality Flow',
        },
      ]);

      expect(outbounds, isEmpty);
    });

    test(
      'skips outbounds with invalid transport URL escapes during import',
      () {
        final outbounds = SubscriptionStore.buildOutboundsForTest([
          {
            'type': 'vless',
            'server': 'example.com',
            'server_port': 443,
            'uuid': '7c6a5b3e-4f1a-4d2b-8c9e-1a2b3c4d5e6f',
            'transport': {'type': 'ws', 'path': '/api/%zz'},
            '_name': 'Broken WS Path',
          },
        ]);

        expect(outbounds, isEmpty);
      },
    );

    test('skips unsupported shadowsocks methods during import', () {
      final outbounds = SubscriptionStore.buildOutboundsForTest([
        {
          'type': 'shadowsocks',
          'server': 'example.com',
          'server_port': 443,
          'method': 'chacha20-poly1305',
          'password': 'secret',
          '_name': 'Broken SS',
        },
      ]);

      expect(outbounds, isEmpty);
    });
  });
}

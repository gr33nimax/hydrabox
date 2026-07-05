import 'dart:async';
import 'dart:convert';
import 'dart:io';

class FastExitIpResult {
  const FastExitIpResult({
    required this.ip,
    this.countryCode,
    required this.source,
  });

  final String ip;
  final String? countryCode;
  final String source;
}

FastExitIpResult? parseCloudflareTrace(String body) {
  final values = <String, String>{};
  for (final line in const LineSplitter().convert(body)) {
    final separator = line.indexOf('=');
    if (separator <= 0) continue;
    values[line.substring(0, separator).trim()] = line
        .substring(separator + 1)
        .trim();
  }
  final ip = _validIp(values['ip']);
  if (ip == null) return null;
  return FastExitIpResult(
    ip: ip,
    countryCode: _countryCode(values['loc']),
    source: 'cloudflare_trace',
  );
}

FastExitIpResult? parseIpWhoResponse(String body) {
  final Object? decoded;
  try {
    decoded = jsonDecode(body);
  } catch (_) {
    return null;
  }
  if (decoded is! Map) return null;
  if (decoded['success'] == false) return null;
  final ip = _validIp(decoded['ip']?.toString());
  if (ip == null) return null;
  return FastExitIpResult(
    ip: ip,
    countryCode: _countryCode(decoded['country_code']?.toString()),
    source: 'ipwho',
  );
}

Future<FastExitIpResult?> lookupFastExitIp({
  Duration timeout = const Duration(seconds: 4),
}) async {
  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 2)
    ..idleTimeout = const Duration(seconds: 2);
  final completer = Completer<FastExitIpResult?>();
  var pending = 2;

  void settle(FastExitIpResult? value) {
    if (value != null && !completer.isCompleted) {
      completer.complete(value);
    }
    pending--;
    if (pending == 0 && !completer.isCompleted) {
      completer.complete(null);
    }
  }

  Future<void>(() async {
    try {
      final body = await _getSmallText(
        client,
        Uri.https('www.cloudflare.com', '/cdn-cgi/trace'),
      );
      settle(parseCloudflareTrace(body));
    } catch (_) {
      settle(null);
    }
  });
  Future<void>(() async {
    try {
      final body = await _getSmallText(client, Uri.https('ipwho.is', '/'));
      settle(parseIpWhoResponse(body));
    } catch (_) {
      settle(null);
    }
  });

  final timer = Timer(timeout, () {
    if (!completer.isCompleted) completer.complete(null);
  });
  try {
    return await completer.future;
  } finally {
    timer.cancel();
    client.close(force: true);
  }
}

Future<String> _getSmallText(HttpClient client, Uri uri) async {
  final request = await client.getUrl(uri);
  request.headers.set(HttpHeaders.acceptHeader, 'text/plain, application/json');
  request.headers.set(HttpHeaders.userAgentHeader, 'Etonify/exit-ip');
  final response = await request.close();
  if (response.statusCode < 200 || response.statusCode >= 300) {
    throw HttpException('Unexpected status ${response.statusCode}', uri: uri);
  }
  const maxBytes = 64 * 1024;
  final bytes = <int>[];
  await for (final chunk in response) {
    if (bytes.length + chunk.length > maxBytes) {
      throw HttpException('Response is too large', uri: uri);
    }
    bytes.addAll(chunk);
  }
  return utf8.decode(bytes, allowMalformed: false);
}

String? _validIp(String? raw) {
  final value = raw?.trim();
  if (value == null || value.isEmpty) return null;
  return InternetAddress.tryParse(value) == null ? null : value;
}

String? _countryCode(String? raw) {
  final value = raw?.trim().toUpperCase();
  if (value == null || !RegExp(r'^[A-Z]{2}$').hasMatch(value)) return null;
  return value;
}

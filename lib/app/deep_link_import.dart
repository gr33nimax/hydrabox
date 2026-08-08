import 'dart:async';

import 'package:flutter/services.dart';

enum DeepLinkImportSource {
  unknown,
  hydraboxImport,
  happAdd,
  happCrypto,
  singBoxRemoteProfile,
}

class DeepLinkImportRequest {
  const DeepLinkImportRequest({
    required this.url,
    this.name,
    this.scheme,
    this.sourceType = DeepLinkImportSource.unknown,
  });

  final String url;
  final String? name;
  final String? scheme;
  final DeepLinkImportSource sourceType;

  bool get isHapp =>
      sourceType == DeepLinkImportSource.happAdd ||
      sourceType == DeepLinkImportSource.happCrypto ||
      scheme?.toLowerCase() == 'happ';

  static DeepLinkImportRequest? fromPayload(Object? payload) {
    if (payload is! Map) {
      return null;
    }

    final rawUrl = payload['url'];
    if (rawUrl is! String) {
      return null;
    }
    final rawName = payload['name'];
    final name = rawName is String && rawName.trim().isNotEmpty
        ? rawName.trim()
        : null;
    final rawScheme = payload['scheme'];
    final scheme = rawScheme is String && rawScheme.trim().isNotEmpty
        ? rawScheme.trim()
        : null;
    final sourceType =
        _parseSourceType(payload['sourceType']) ??
        _inferSourceType(rawUrl.trim(), scheme: scheme);

    final url = _normalizeImportUrl(rawUrl.trim(), name: name);
    if (url == null) {
      return null;
    }

    return DeepLinkImportRequest(
      url: url,
      name: name,
      scheme: scheme,
      sourceType: sourceType,
    );
  }

  static String? _normalizeImportUrl(String rawUrl, {String? name}) {
    if (rawUrl.isEmpty) {
      return null;
    }
    return _normalizeHappAddUrl(rawUrl, name: name) ??
        _normalizeSingBoxRemoteProfileUrl(rawUrl) ??
        rawUrl;
  }

  static DeepLinkImportSource? _parseSourceType(Object? value) {
    if (value is! String) {
      return null;
    }
    return switch (value.trim()) {
      'hydraboxImport' => DeepLinkImportSource.hydraboxImport,
      'happAdd' => DeepLinkImportSource.happAdd,
      'happCrypto' => DeepLinkImportSource.happCrypto,
      'singBoxRemoteProfile' => DeepLinkImportSource.singBoxRemoteProfile,
      _ => null,
    };
  }

  static DeepLinkImportSource _inferSourceType(
    String rawUrl, {
    String? scheme,
  }) {
    final uri = Uri.tryParse(rawUrl);
    final rawScheme = uri?.scheme.toLowerCase() ?? '';
    final normalizedScheme = rawScheme == 'happ' || rawScheme == 'sing-box'
        ? rawScheme
        : (scheme ?? rawScheme).toLowerCase();
    if (normalizedScheme == 'happ') {
      final host = uri?.host.toLowerCase() ?? '';
      final path =
          (uri?.path.startsWith('/') == true
                  ? uri!.path.substring(1)
                  : uri?.path ?? '')
              .toLowerCase();
      if (_isHappCryptoPart(host) ||
          _isHappCryptoPart(path) ||
          _startsWithHappCryptoPrefix(path)) {
        return DeepLinkImportSource.happCrypto;
      }
      return DeepLinkImportSource.happAdd;
    }
    if (normalizedScheme == 'sing-box') {
      return DeepLinkImportSource.singBoxRemoteProfile;
    }
    if (normalizedScheme == 'hydrabox') {
      return DeepLinkImportSource.hydraboxImport;
    }
    return DeepLinkImportSource.unknown;
  }

  static bool _isHappCryptoPart(String value) {
    return value == 'crypt' ||
        value == 'crypt2' ||
        value == 'crypt3' ||
        value == 'crypt4' ||
        value == 'crypt5';
  }

  static bool _startsWithHappCryptoPrefix(String value) {
    return value.startsWith('crypt/') ||
        value.startsWith('crypt2/') ||
        value.startsWith('crypt3/') ||
        value.startsWith('crypt4/') ||
        value.startsWith('crypt5/');
  }

  static String? _normalizeHappAddUrl(String rawUrl, {String? name}) {
    final uri = Uri.tryParse(rawUrl);
    if (uri == null || uri.scheme.toLowerCase() != 'happ') {
      return null;
    }

    final host = uri.host.toLowerCase();
    final trimmedPath = uri.path.startsWith('/')
        ? uri.path.substring(1)
        : uri.path;
    final lowercasePath = trimmedPath.toLowerCase();

    String embeddedUrl;
    final queryUrl = uri.queryParameters['url']?.trim();
    if (queryUrl != null && queryUrl.isNotEmpty) {
      embeddedUrl = queryUrl;
    } else if (host == 'add') {
      embeddedUrl = trimmedPath;
    } else if (lowercasePath == 'add') {
      embeddedUrl = '';
    } else if (lowercasePath.startsWith('add/')) {
      embeddedUrl = trimmedPath.substring(4);
    } else {
      return null;
    }

    embeddedUrl = embeddedUrl.trim();
    if (embeddedUrl.isEmpty) {
      return null;
    }

    final remainingQuery = <String, List<String>>{};
    for (final entry in uri.queryParametersAll.entries) {
      if (entry.key == 'name' && name != null) {
        continue;
      }
      if (entry.key == 'url') {
        continue;
      }
      remainingQuery[entry.key] = entry.value;
    }
    if (remainingQuery.isNotEmpty) {
      final query = Uri(
        queryParameters: {
          for (final entry in remainingQuery.entries)
            if (entry.value.isNotEmpty)
              entry.key: entry.value.length == 1
                  ? entry.value.first
                  : entry.value,
        },
      ).query;
      if (query.isNotEmpty) {
        embeddedUrl = embeddedUrl.contains('?')
            ? '$embeddedUrl&$query'
            : '$embeddedUrl?$query';
      }
    }

    if (embeddedUrl.startsWith('//')) {
      return 'https:$embeddedUrl';
    }

    final embeddedUri = Uri.tryParse(embeddedUrl);
    if (embeddedUri != null && embeddedUri.hasScheme) {
      return embeddedUrl;
    }
    return 'https://$embeddedUrl';
  }

  static String? _normalizeSingBoxRemoteProfileUrl(String rawUrl) {
    final uri = Uri.tryParse(rawUrl);
    if (uri == null || uri.scheme.toLowerCase() != 'sing-box') {
      return null;
    }
    final host = uri.host.toLowerCase();
    final path = uri.path.startsWith('/') ? uri.path.substring(1) : uri.path;
    if (host != 'import-remote-profile' &&
        path.toLowerCase() != 'import-remote-profile') {
      return null;
    }
    final url = uri.queryParameters['url']?.trim();
    if (url == null || url.isEmpty) {
      return null;
    }
    return url;
  }
}

class DeepLinkImportBridge {
  DeepLinkImportBridge._();

  static const MethodChannel _methods = MethodChannel('io.hydrabox.client/deep_links');
  static const EventChannel _events = EventChannel(
    'io.hydrabox.client/deep_link_events',
  );

  static Stream<DeepLinkImportRequest> get stream async* {
    await for (final payload in _events.receiveBroadcastStream()) {
      final request = DeepLinkImportRequest.fromPayload(payload);
      if (request != null) {
        yield request;
      }
    }
  }

  static Future<DeepLinkImportRequest?> getInitialRequest() async {
    final payload = await _methods.invokeMethod<Object?>(
      'getInitialImportRequest',
    );
    return DeepLinkImportRequest.fromPayload(payload);
  }
}

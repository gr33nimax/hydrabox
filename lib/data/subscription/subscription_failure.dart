import 'dart:async';
import 'dart:io';

import 'happ_crypto_link.dart';

enum SubscriptionFailureKind {
  invalidUrl,
  credentialsRequireHttps,
  unsafeRedirect,
  redirect,
  httpStatus,
  timeout,
  dns,
  connection,
  tls,
  emptyResponse,
  htmlResponse,
  responseTooLarge,
  noUsableProxies,
  invalidContent,
  happUnsupported,
  happInvalid,
  unknown,
}

enum SubscriptionContentFailureKind {
  emptyResponse,
  htmlResponse,
  responseTooLarge,
  noUsableProxies,
  invalidContent,
}

class SubscriptionFailure {
  const SubscriptionFailure(this.kind, {this.httpStatus, this.diagnostic});

  final SubscriptionFailureKind kind;
  final int? httpStatus;
  final String? diagnostic;
}

/// A non-secret HydraCore validation result that is safe to surface to users.
///
/// HydraCore owns both [code] and [path]. The constructor normalizes them so a
/// server-controlled document cannot inject arbitrary text into logs or UI.
class HydraSubscriptionValidationException extends FormatException {
  HydraSubscriptionValidationException({
    required String operation,
    required String code,
    required String path,
  }) : operation = _safeToken(operation, fallback: 'validation'),
       code = _safeToken(code, fallback: 'invalid'),
       path = _safePath(path),
       super(
         'HydraCore ${_safeToken(operation, fallback: 'validation')} failed: '
         '${_safeToken(code, fallback: 'invalid')} at ${_safePath(path)}',
       );

  final String operation;
  final String code;
  final String path;

  String get diagnostic => '$operation: $code at $path';

  @override
  String toString() => 'HydraSubscriptionValidationException: $diagnostic';

  static String _safeToken(String value, {required String fallback}) {
    final normalized = value.trim();
    return RegExp(r'^[A-Za-z0-9_. -]{1,80}$').hasMatch(normalized)
        ? normalized
        : fallback;
  }

  static String _safePath(String value) {
    final normalized = value.trim();
    return RegExp(
          r'^\$(?:\.[A-Za-z0-9_]+|\[[0-9]+\]){0,32}$',
        ).hasMatch(normalized)
        ? normalized
        : r'$';
  }
}

class SubscriptionHttpStatusException extends HttpException {
  SubscriptionHttpStatusException(this.statusCode, {super.uri})
    : super('Subscription server returned HTTP $statusCode');

  final int statusCode;

  @override
  String toString() => 'Subscription server returned HTTP $statusCode';
}

class SubscriptionContentException implements Exception {
  const SubscriptionContentException(this.kind);

  final SubscriptionContentFailureKind kind;

  @override
  String toString() => switch (kind) {
    SubscriptionContentFailureKind.emptyResponse =>
      'Subscription server returned an empty response',
    SubscriptionContentFailureKind.htmlResponse =>
      'Subscription server returned an HTML page instead of a subscription',
    SubscriptionContentFailureKind.responseTooLarge =>
      'Subscription response is too large',
    SubscriptionContentFailureKind.noUsableProxies =>
      'Subscription contains no usable proxies',
    SubscriptionContentFailureKind.invalidContent =>
      'Subscription content is invalid',
  };
}

class SubscriptionImportCancelledException implements Exception {
  const SubscriptionImportCancelledException();

  @override
  String toString() => 'Subscription import was cancelled';
}

SubscriptionFailure classifySubscriptionFailure(Object error) {
  if (error is HydraSubscriptionValidationException) {
    return SubscriptionFailure(
      SubscriptionFailureKind.invalidContent,
      diagnostic: error.diagnostic,
    );
  }
  if (error is SubscriptionHttpStatusException) {
    return SubscriptionFailure(
      SubscriptionFailureKind.httpStatus,
      httpStatus: error.statusCode,
    );
  }
  if (error is SubscriptionContentException) {
    return SubscriptionFailure(switch (error.kind) {
      SubscriptionContentFailureKind.emptyResponse =>
        SubscriptionFailureKind.emptyResponse,
      SubscriptionContentFailureKind.htmlResponse =>
        SubscriptionFailureKind.htmlResponse,
      SubscriptionContentFailureKind.responseTooLarge =>
        SubscriptionFailureKind.responseTooLarge,
      SubscriptionContentFailureKind.noUsableProxies =>
        SubscriptionFailureKind.noUsableProxies,
      SubscriptionContentFailureKind.invalidContent =>
        SubscriptionFailureKind.invalidContent,
    });
  }
  if (error is UnsupportedHappCryptoLinkException) {
    return const SubscriptionFailure(SubscriptionFailureKind.happUnsupported);
  }
  if (error is HappCryptoLinkException) {
    return const SubscriptionFailure(SubscriptionFailureKind.happInvalid);
  }
  if (error is TimeoutException) {
    return const SubscriptionFailure(SubscriptionFailureKind.timeout);
  }
  if (error is TlsException) {
    return const SubscriptionFailure(SubscriptionFailureKind.tls);
  }
  if (error is SocketException) {
    final message = error.message.toLowerCase();
    return SubscriptionFailure(
      _looksLikeDnsFailure(message)
          ? SubscriptionFailureKind.dns
          : SubscriptionFailureKind.connection,
    );
  }
  if (error is HttpException) {
    return _classifyMessage(error.message.toLowerCase());
  }
  if (error is FormatException) {
    final message = error.message.toLowerCase();
    return SubscriptionFailure(
      _looksLikeUrlFailure(message)
          ? SubscriptionFailureKind.invalidUrl
          : SubscriptionFailureKind.invalidContent,
    );
  }
  if (error is StateError) {
    final message = error.message.toString().toLowerCase();
    if (_looksLikeMissingProxies(message)) {
      return const SubscriptionFailure(SubscriptionFailureKind.noUsableProxies);
    }
  }
  return _classifyMessage(error.toString().toLowerCase());
}

SubscriptionFailure _classifyMessage(String message) {
  final httpStatus = _extractHttpStatus(message);
  if (httpStatus != null) {
    return SubscriptionFailure(
      SubscriptionFailureKind.httpStatus,
      httpStatus: httpStatus,
    );
  }
  if (message.contains('credentials require https') ||
      message.contains('sensitive subscription credentials')) {
    return const SubscriptionFailure(
      SubscriptionFailureKind.credentialsRequireHttps,
    );
  }
  if (message.contains('https to http') ||
      message.contains('https→http') ||
      message.contains('insecure redirect')) {
    return const SubscriptionFailure(SubscriptionFailureKind.unsafeRedirect);
  }
  if (message.contains('too many') && message.contains('redirect') ||
      message.contains('redirect has no location') ||
      message.contains('redirect loop')) {
    return const SubscriptionFailure(SubscriptionFailureKind.redirect);
  }
  if (message.contains('response is larger') ||
      message.contains('response is too large')) {
    return const SubscriptionFailure(SubscriptionFailureKind.responseTooLarge);
  }
  if (message.contains('empty response') ||
      message.contains('response is empty')) {
    return const SubscriptionFailure(SubscriptionFailureKind.emptyResponse);
  }
  if (message.contains('html page')) {
    return const SubscriptionFailure(SubscriptionFailureKind.htmlResponse);
  }
  if (_looksLikeMissingProxies(message)) {
    return const SubscriptionFailure(SubscriptionFailureKind.noUsableProxies);
  }
  if (_looksLikeDnsFailure(message)) {
    return const SubscriptionFailure(SubscriptionFailureKind.dns);
  }
  if (message.contains('certificate') ||
      message.contains('handshake') ||
      message.contains('tls') ||
      message.contains('ssl')) {
    return const SubscriptionFailure(SubscriptionFailureKind.tls);
  }
  if (message.contains('timed out') ||
      message.contains('timeout') ||
      message.contains('time limit')) {
    return const SubscriptionFailure(SubscriptionFailureKind.timeout);
  }
  if (message.contains('socket closed') ||
      message.contains('connection refused') ||
      message.contains('connection reset') ||
      message.contains('connection aborted') ||
      message.contains('network is unreachable') ||
      message.contains('network unreachable') ||
      message.contains('broken pipe') ||
      message.contains('underlying_http_failed')) {
    return const SubscriptionFailure(SubscriptionFailureKind.connection);
  }
  if (_looksLikeUrlFailure(message)) {
    return const SubscriptionFailure(SubscriptionFailureKind.invalidUrl);
  }
  if (message.contains('format') ||
      message.contains('parse') ||
      message.contains('invalid content')) {
    return const SubscriptionFailure(SubscriptionFailureKind.invalidContent);
  }
  return const SubscriptionFailure(SubscriptionFailureKind.unknown);
}

int? _extractHttpStatus(String message) {
  final match = RegExp(
    r'(?:returned|status)(?:\s+http)?(?:\s+status)?\s*[:=]?\s*(\d{3})',
  ).firstMatch(message);
  if (match == null) {
    return null;
  }
  return int.tryParse(match.group(1)!);
}

bool _looksLikeDnsFailure(String message) =>
    message.contains('failed host lookup') ||
    message.contains('unknown host') ||
    message.contains('name or service not known') ||
    message.contains('no address associated') ||
    message.contains('nodename nor servname') ||
    message.contains('getaddrinfo') ||
    message.contains('dns');

bool _looksLikeMissingProxies(String message) =>
    message.contains('no proxies') ||
    message.contains('no usable proxies') ||
    message.contains('contains no proxies') ||
    message.contains('returned no usable');

bool _looksLikeUrlFailure(String message) =>
    message.contains('invalid url') ||
    message.contains('invalid uri') ||
    message.contains('unsupported url') ||
    message.contains('unsupported uri') ||
    message.contains('unsupported scheme') ||
    message.contains('only http and https');

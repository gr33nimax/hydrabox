import 'dart:convert';

import 'package:flutter/foundation.dart';

class AppLogEntry {
  const AppLogEntry({
    required this.timestamp,
    required this.level,
    required this.title,
    required this.message,
  });

  final DateTime timestamp;
  final String level;
  final String title;
  final String message;
}

class AppLogStore {
  AppLogStore._();

  static const _maxEntries = 120;
  static const _maxEntryMessageChars = 16 * 1024;
  static const _dedupeWindow = Duration(milliseconds: 900);
  static final ValueNotifier<List<AppLogEntry>> entries =
      ValueNotifier<List<AppLogEntry>>(const []);
  static AppLogEntry? _lastEntry;

  static void info(String title, String message) {
    _append(
      AppLogEntry(
        timestamp: DateTime.now(),
        level: 'info',
        title: title,
        message: message,
      ),
    );
  }

  static void error(String title, String message) {
    _append(
      AppLogEntry(
        timestamp: DateTime.now(),
        level: 'error',
        title: title,
        message: message,
      ),
    );
  }

  static void warning(String title, String message) {
    _append(
      AppLogEntry(
        timestamp: DateTime.now(),
        level: 'warning',
        title: title,
        message: message,
      ),
    );
  }

  static void debug(String title, String message) {
    _append(
      AppLogEntry(
        timestamp: DateTime.now(),
        level: 'debug',
        title: title,
        message: message,
      ),
    );
  }

  static void appendBatch(Iterable<AppLogEntry> batch) {
    final normalized = <AppLogEntry>[];
    for (final entry in batch.map(_boundedEntry)) {
      if (_isDuplicateEntry(entry)) {
        continue;
      }
      normalized.add(entry);
      _lastEntry = entry;
    }
    if (normalized.isEmpty) {
      return;
    }
    final next = List<AppLogEntry>.from(entries.value)..addAll(normalized);
    if (next.length > _maxEntries) {
      next.removeRange(0, next.length - _maxEntries);
    }
    entries.value = List<AppLogEntry>.unmodifiable(next);
  }

  static void ingest(
    String title,
    String message, {
    String fallbackLevel = 'info',
    bool trustFallbackLevel = false,
  }) {
    final normalizedMessage = _normalizeMessage(message);
    if (normalizedMessage.isEmpty) {
      return;
    }
    final normalizedLevel = trustFallbackLevel
        ? fallbackLevel
        : (_inferLevel(normalizedMessage) ?? fallbackLevel);
    switch (normalizedLevel) {
      case 'error':
        error(title, normalizedMessage);
        break;
      case 'warning':
        warning(title, normalizedMessage);
        break;
      case 'debug':
        debug(title, normalizedMessage);
        break;
      default:
        info(title, normalizedMessage);
        break;
    }
  }

  static void config(String reason, Map<String, dynamic> config) {
    final outbounds = (config['outbounds'] as List?) ?? const [];
    final inbounds = (config['inbounds'] as List?) ?? const [];
    final route = config['route'] as Map?;
    final rules = (route?['rules'] as List?) ?? const [];
    final outboundTypes = <String, int>{};
    for (final outbound in outbounds.whereType<Map>()) {
      final type = outbound['type']?.toString().trim();
      if (type == null || type.isEmpty) {
        continue;
      }
      outboundTypes[type] = (outboundTypes[type] ?? 0) + 1;
    }
    final typeSummary = outboundTypes.entries
        .map((entry) => '${entry.key}=${entry.value}')
        .join(', ');
    final encodedLength = jsonEncode(config).length;
    info(
      'sing-box config ($reason)',
      'config summary: ${outbounds.length} outbounds, '
          '${inbounds.length} inbounds, ${rules.length} route rules, '
          'jsonBytes=$encodedLength'
          '${typeSummary.isEmpty ? '' : '\noutboundTypes: $typeSummary'}',
    );
  }

  static String normalizeMessage(String message) => _normalizeMessage(message);

  static String redact(String value) => _redactSecrets(value);

  static String? inferLevel(String message) =>
      _inferLevel(_normalizeMessage(message));

  static void clear() {
    entries.value = const [];
    _lastEntry = null;
  }

  static String dump() {
    return entries.value
        .map((entry) {
          final timestamp = entry.timestamp.toIso8601String();
          return '[$timestamp] ${entry.level.toUpperCase()} ${entry.title}\n${entry.message}';
        })
        .join('\n\n');
  }

  static void _append(AppLogEntry entry) {
    final bounded = _boundedEntry(entry);
    if (_isDuplicateEntry(bounded)) {
      return;
    }
    _lastEntry = bounded;
    final next = List<AppLogEntry>.from(entries.value)..add(bounded);
    if (next.length > _maxEntries) {
      next.removeRange(0, next.length - _maxEntries);
    }
    entries.value = List<AppLogEntry>.unmodifiable(next);
  }

  static bool _isDuplicateEntry(AppLogEntry entry) {
    final previous = _lastEntry;
    if (previous == null) {
      return false;
    }
    return entry.level == previous.level &&
        entry.title == previous.title &&
        entry.message == previous.message &&
        entry.timestamp.difference(previous.timestamp).abs() <= _dedupeWindow;
  }

  static AppLogEntry _boundedEntry(AppLogEntry entry) {
    final title = _redactSecrets(entry.title);
    final message = _boundedMessage(_redactSecrets(entry.message));
    if (identical(title, entry.title) && identical(message, entry.message)) {
      return entry;
    }
    return AppLogEntry(
      timestamp: entry.timestamp,
      level: entry.level,
      title: title,
      message: message,
    );
  }

  static String _boundedMessage(String message) {
    if (message.length <= _maxEntryMessageChars) {
      return message;
    }
    return '${message.substring(0, _maxEntryMessageChars)}\n'
        '... log entry truncated at $_maxEntryMessageChars chars '
        '(${message.length} chars original)';
  }

  static String _normalizeMessage(String message) {
    return message
        // ANSI escape sequences, including color codes from libbox.
        .replaceAll(RegExp(r'\x1B\[[0-9;]*[A-Za-z]'), '')
        // Some logs arrive with escaped control bytes rendered as visible junk.
        .replaceAll(RegExp(r'\[[0-9;]*m'), '')
        .replaceAll('\u0000', '')
        .trim();
  }

  static String _redactSecrets(String value) {
    var result = value;
    result = result.replaceAllMapped(
      RegExp(
        r'\b(vless|vmess|trojan|ss|ssr|hysteria2|tuic)://[^\s]+',
        caseSensitive: false,
      ),
      (match) => '${match.group(1)}://<redacted>',
    );
    result = result.replaceAllMapped(
      RegExp(
        r'\b(https?://)([^/\s?#"\x27<>]+)(?:[^\s"\x27<>]*)?',
        caseSensitive: false,
      ),
      (match) => '${match.group(1)}${match.group(2)}/<redacted>',
    );
    result = result.replaceAllMapped(
      RegExp(r'([a-z][a-z0-9+.-]*://)([^/@\s]+)@', caseSensitive: false),
      (match) => '${match.group(1)}<redacted>@',
    );
    result = result.replaceAllMapped(
      RegExp(
        r'([?&](?:token|access_token|password|passwd|key|secret|uuid|auth|authorization|sub|url)=)[^&\s]+',
        caseSensitive: false,
      ),
      (match) => '${match.group(1)}<redacted>',
    );
    result = result.replaceAllMapped(
      RegExp(
        r'("(?:uuid|password|private_key|pre_shared_key|server_key|token|access_token|authorization|cookie|headers?)"\s*:\s*)"[^"]*"',
        caseSensitive: false,
      ),
      (match) => '${match.group(1)}"<redacted>"',
    );
    result = result.replaceAllMapped(
      RegExp(
        r'\b(uuid|password|private_key|pre_shared_key|server_key|token|access_token|authorization|cookie|x-hwid|custom_hwid)\s*[:=]\s*([^\s,;]+)',
        caseSensitive: false,
      ),
      (match) => '${match.group(1)}=<redacted>',
    );
    result = result.replaceAll(
      RegExp(
        r'\b[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\b',
        caseSensitive: false,
      ),
      '<uuid>',
    );
    return result;
  }

  static String? _inferLevel(String message) {
    final upper = message.toUpperCase();
    if (upper.startsWith('ERROR') || upper.startsWith('[ERROR]')) {
      return 'error';
    }
    if (upper.startsWith('WARN') ||
        upper.startsWith('[WARN]') ||
        upper.startsWith('WARNING')) {
      return 'warning';
    }
    if (upper.startsWith('DEBUG') || upper.startsWith('[DEBUG]')) {
      return 'debug';
    }
    if (upper.startsWith('TRACE') || upper.startsWith('[TRACE]')) {
      return 'debug';
    }
    if (upper.startsWith('INFO') || upper.startsWith('[INFO]')) {
      return 'info';
    }
    return null;
  }
}

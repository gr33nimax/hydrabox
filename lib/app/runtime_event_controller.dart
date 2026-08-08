import 'dart:async';

import 'package:hydrabox/logging/app_log_store.dart';

class RuntimeStateEvent {
  const RuntimeStateEvent({
    required this.running,
    this.error,
    this.raw = const <String, dynamic>{},
  });

  final bool running;
  final String? error;
  final Map<String, dynamic> raw;

  bool get hasError => error != null && error!.isNotEmpty;
}

class RuntimeGroupsEvent {
  const RuntimeGroupsEvent({
    required this.groups,
    required this.runtimeGeneration,
  });

  final List<dynamic> groups;
  final int runtimeGeneration;
}

class RuntimeUrlTestSessionsEvent {
  const RuntimeUrlTestSessionsEvent({
    required this.sessions,
    required this.runtimeGeneration,
    required this.sequence,
    required this.reset,
  });

  final List<dynamic> sessions;
  final int runtimeGeneration;
  final int sequence;
  final bool reset;

  /// Converts the managed URL-test stream into the same group telemetry shape
  /// consumed by the proxy runtime controller. Native managed sessions report
  /// `observedAt` in Unix milliseconds, while group snapshots use seconds.
  List<Map<String, dynamic>> toGroupUpdates() {
    final groups = <Map<String, dynamic>>[];
    for (final rawSession in sessions) {
      if (rawSession is! Map) {
        continue;
      }
      final session = Map<String, dynamic>.from(rawSession);
      final rawResults = session['results'];
      if (rawResults is! List || rawResults.isEmpty) {
        continue;
      }
      final items = <Map<String, dynamic>>[];
      for (final rawResult in rawResults) {
        if (rawResult is! Map) {
          continue;
        }
        final result = Map<String, dynamic>.from(rawResult);
        final tag = result['outboundTag']?.toString().trim() ?? '';
        if (tag.isEmpty) {
          continue;
        }
        final observedAt = (result['observedAt'] as num?)?.toInt() ?? 0;
        final errorMessage = result['errorMessage']?.toString().trim() ?? '';
        final errorCode = result['errorCode']?.toString().trim() ?? '';
        items.add(<String, dynamic>{
          'tag': tag,
          'delay': (result['delayMillis'] as num?)?.toInt() ?? 0,
          'time': observedAt >= 100000000000 ? observedAt ~/ 1000 : observedAt,
          'status': result['status']?.toString() ?? '',
          'error': errorMessage.isNotEmpty ? errorMessage : errorCode,
          'errorCode': errorCode,
        });
      }
      if (items.isNotEmpty) {
        groups.add(<String, dynamic>{
          'tag': session['groupTag']?.toString() ?? '',
          'items': items,
        });
      }
    }
    return groups;
  }
}

typedef RuntimeStateHandler = void Function(RuntimeStateEvent event);
typedef RuntimeRawEventHandler = void Function(Map<String, dynamic> event);
typedef RuntimeGroupsHandler = void Function(RuntimeGroupsEvent event);
typedef RuntimeUrlTestSessionsHandler =
    void Function(RuntimeUrlTestSessionsEvent event);
typedef RuntimeLogFilter = bool Function(String level);
typedef RuntimeLogIssueHandler = void Function(String reason, String message);
typedef RuntimeCaptchaRequiredHandler = void Function(Uri uri);
typedef RuntimeCaptchaSolvedHandler = void Function();

class RuntimeEventController {
  RuntimeEventController({
    required Stream<Map<String, dynamic>> events,
    required RuntimeStateHandler onState,
    required RuntimeRawEventHandler onStatus,
    required RuntimeRawEventHandler onNetwork,
    required RuntimeGroupsHandler onGroups,
    required RuntimeLogFilter shouldRecordLog,
    RuntimeUrlTestSessionsHandler? onUrlTestSessions,
    RuntimeCaptchaRequiredHandler? onCaptchaRequired,
    RuntimeCaptchaSolvedHandler? onCaptchaSolved,
    RuntimeLogIssueHandler? onRuntimeLogIssue,
    DateTime Function()? now,
  }) : _events = events,
       _onState = onState,
       _onStatus = onStatus,
       _onNetwork = onNetwork,
       _onGroups = onGroups,
       _onUrlTestSessions = onUrlTestSessions,
       _onCaptchaRequired = onCaptchaRequired,
       _onCaptchaSolved = onCaptchaSolved,
       _shouldRecordLog = shouldRecordLog,
       _onRuntimeLogIssue = onRuntimeLogIssue,
       _now = now ?? DateTime.now;

  static final RegExp _interfaceDialFailurePattern = RegExp(
    r'\bdial\s+(?:ccmni|wlan|rmnet|swlan|eth|usb|ap)\w*\s*\(\d+\).*?\b(?:network is unreachable|no route to host)\b',
    caseSensitive: false,
  );
  static final RegExp _vkCaptchaUrlPattern = RegExp(
    r'vk-auth:\s*solve the captcha to continue:\s*(http://(?:127\.0\.0\.1|localhost):\d+(?:/\S*)?)',
    caseSensitive: false,
  );

  final Stream<Map<String, dynamic>> _events;
  final RuntimeStateHandler _onState;
  final RuntimeRawEventHandler _onStatus;
  final RuntimeRawEventHandler _onNetwork;
  final RuntimeGroupsHandler _onGroups;
  final RuntimeUrlTestSessionsHandler? _onUrlTestSessions;
  final RuntimeCaptchaRequiredHandler? _onCaptchaRequired;
  final RuntimeCaptchaSolvedHandler? _onCaptchaSolved;
  final RuntimeLogFilter _shouldRecordLog;
  final RuntimeLogIssueHandler? _onRuntimeLogIssue;
  final DateTime Function() _now;

  StreamSubscription<Map<String, dynamic>>? _subscription;

  void start() {
    _subscription?.cancel();
    _subscription = _events.listen(dispatch);
  }

  Future<void> dispose() async {
    await _subscription?.cancel();
    _subscription = null;
  }

  void dispatch(Map<String, dynamic> event) {
    final type = event['type'] as String? ?? '';
    switch (type) {
      case 'state':
        _onState(
          RuntimeStateEvent(
            running: event['running'] == true,
            error: event['error']?.toString(),
            raw: event,
          ),
        );
        break;
      case 'status':
        _onStatus(event);
        break;
      case 'network':
        _onNetwork(event);
        break;
      case 'groups':
        _onGroups(
          RuntimeGroupsEvent(
            groups: (event['groups'] as List?) ?? const [],
            runtimeGeneration:
                (event['runtimeGeneration'] as num?)?.toInt() ?? 0,
          ),
        );
        break;
      case 'urlTestSessions':
        _onUrlTestSessions?.call(
          RuntimeUrlTestSessionsEvent(
            sessions: (event['sessions'] as List?) ?? const [],
            runtimeGeneration:
                (event['runtimeGeneration'] as num?)?.toInt() ?? 0,
            sequence: (event['sequence'] as num?)?.toInt() ?? 0,
            reset: event['reset'] == true,
          ),
        );
        break;
      case 'nativeLog':
        _recordNativeLog(event);
        break;
      case 'logs':
        _recordLogBatch(event);
        break;
      case 'logLevel':
        break;
      default:
        break;
    }
  }

  void _recordNativeLog(Map<String, dynamic> event) {
    final level = (event['level']?.toString() ?? 'info').toLowerCase();
    final message = event['message']?.toString() ?? '';
    if (message.isEmpty) {
      return;
    }
    _emitCaptchaRequiredIfNeeded(message);
    _emitCaptchaSolvedIfNeeded(message);
    _emitRuntimeLogIssueIfNeeded(message);
    final normalizedLevel = _normalizeNativeLevel(level);
    final effectiveLevel = AppLogStore.inferLevel(message) ?? normalizedLevel;
    if (!_shouldRecordLog(effectiveLevel)) {
      return;
    }
    AppLogStore.ingest(
      'sing-box',
      message,
      fallbackLevel: _fallbackLogLevel(effectiveLevel),
      trustFallbackLevel: true,
    );
  }

  void _recordLogBatch(Map<String, dynamic> event) {
    final logs = (event['logs'] as List?) ?? const [];
    final batch = <AppLogEntry>[];
    for (final entry in logs) {
      if (entry is! Map) {
        continue;
      }
      final map = Map<String, dynamic>.from(entry);
      final level = (map['level'] as num?)?.toInt() ?? 0;
      final message = map['message']?.toString() ?? '';
      if (message.isEmpty) {
        continue;
      }
      _emitCaptchaRequiredIfNeeded(message);
      _emitCaptchaSolvedIfNeeded(message);
      _emitRuntimeLogIssueIfNeeded(message);
      final fallbackLevel = _fallbackBatchLogLevel(level);
      final effectiveLevel = AppLogStore.inferLevel(message) ?? fallbackLevel;
      if (!_shouldRecordLog(effectiveLevel)) {
        continue;
      }
      batch.add(
        AppLogEntry(
          timestamp: _now(),
          level: effectiveLevel,
          title: 'sing-box',
          message: AppLogStore.normalizeMessage(message),
        ),
      );
    }
    AppLogStore.appendBatch(batch);
  }

  void _emitRuntimeLogIssueIfNeeded(String message) {
    final reason = _runtimeLogIssueReason(message);
    if (reason == null) {
      return;
    }
    _onRuntimeLogIssue?.call(reason, message);
  }

  void _emitCaptchaRequiredIfNeeded(String message) {
    final match = _vkCaptchaUrlPattern.firstMatch(message);
    final rawUri = match?.group(1);
    if (rawUri == null) {
      return;
    }
    final uri = Uri.tryParse(rawUri);
    if (uri == null ||
        uri.scheme != 'http' ||
        (uri.host != '127.0.0.1' && uri.host != 'localhost') ||
        !uri.hasPort ||
        uri.port <= 0) {
      return;
    }
    _onCaptchaRequired?.call(uri);
  }

  void _emitCaptchaSolvedIfNeeded(String message) {
    if (message.toLowerCase().contains('vk-auth: captcha solved')) {
      _onCaptchaSolved?.call();
    }
  }

  String? _runtimeLogIssueReason(String message) {
    final lower = message.toLowerCase();
    if (lower.contains('no available network interface')) {
      return 'core_no_available_interface';
    }
    if (lower.contains('no usable network interface') ||
        lower.contains('error=no_interface')) {
      return 'core_no_usable_interface';
    }
    if (_interfaceDialFailurePattern.hasMatch(message)) {
      return 'core_interface_dial_failure';
    }
    return null;
  }

  String _normalizeNativeLevel(String level) {
    return switch (level) {
      'warn' => 'warning',
      'trace' => 'debug',
      _ => level,
    };
  }

  String _fallbackLogLevel(String effectiveLevel) {
    return switch (effectiveLevel) {
      'error' => 'error',
      'debug' => 'debug',
      'warning' => 'warning',
      _ => 'info',
    };
  }

  String _fallbackBatchLogLevel(int level) {
    return switch (level) {
      >= 4 => 'error',
      3 => 'warning',
      2 => 'info',
      _ => 'debug',
    };
  }
}

import 'dart:async';

import 'package:meow_client/logging/app_log_store.dart';

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

typedef RuntimeStateHandler = void Function(RuntimeStateEvent event);
typedef RuntimeRawEventHandler = void Function(Map<String, dynamic> event);
typedef RuntimeGroupsHandler = void Function(List<dynamic> groups);
typedef RuntimeLogFilter = bool Function(String level);

class RuntimeEventController {
  RuntimeEventController({
    required Stream<Map<String, dynamic>> events,
    required RuntimeStateHandler onState,
    required RuntimeRawEventHandler onStatus,
    required RuntimeRawEventHandler onNetwork,
    required RuntimeGroupsHandler onGroups,
    required RuntimeLogFilter shouldRecordLog,
    DateTime Function()? now,
  }) : _events = events,
       _onState = onState,
       _onStatus = onStatus,
       _onNetwork = onNetwork,
       _onGroups = onGroups,
       _shouldRecordLog = shouldRecordLog,
       _now = now ?? DateTime.now;

  final Stream<Map<String, dynamic>> _events;
  final RuntimeStateHandler _onState;
  final RuntimeRawEventHandler _onStatus;
  final RuntimeRawEventHandler _onNetwork;
  final RuntimeGroupsHandler _onGroups;
  final RuntimeLogFilter _shouldRecordLog;
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
        _onGroups((event['groups'] as List?) ?? const []);
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

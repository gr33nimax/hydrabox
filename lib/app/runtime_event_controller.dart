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

class RuntimeTransportHealthEvent {
  const RuntimeTransportHealthEvent({
    required this.applicable,
    required this.state,
    required this.activeLanes,
    required this.totalLanes,
    required this.demand,
    this.failureCode,
    this.challengeId,
    this.challengeUri,
  });

  final bool applicable;
  final String state;
  final int activeLanes;
  final int totalLanes;
  final bool demand;
  final String? failureCode;
  final String? challengeId;
  final Uri? challengeUri;

  bool get connected =>
      !applicable || state == 'healthy' || state == 'degraded';
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
typedef RuntimeTransportHealthHandler =
    void Function(RuntimeTransportHealthEvent event);

class RuntimeEventController {
  RuntimeEventController({
    required Stream<Map<String, dynamic>> events,
    required RuntimeStateHandler onState,
    required RuntimeRawEventHandler onStatus,
    required RuntimeRawEventHandler onNetwork,
    required RuntimeGroupsHandler onGroups,
    required RuntimeLogFilter shouldRecordLog,
    RuntimeUrlTestSessionsHandler? onUrlTestSessions,
    RuntimeTransportHealthHandler? onTransportHealth,
    DateTime Function()? now,
  }) : _events = events,
       _onState = onState,
       _onStatus = onStatus,
       _onNetwork = onNetwork,
       _onGroups = onGroups,
       _onUrlTestSessions = onUrlTestSessions,
       _onTransportHealth = onTransportHealth,
       _shouldRecordLog = shouldRecordLog,
       _now = now ?? DateTime.now;

  final Stream<Map<String, dynamic>> _events;
  final RuntimeStateHandler _onState;
  final RuntimeRawEventHandler _onStatus;
  final RuntimeRawEventHandler _onNetwork;
  final RuntimeGroupsHandler _onGroups;
  final RuntimeUrlTestSessionsHandler? _onUrlTestSessions;
  final RuntimeTransportHealthHandler? _onTransportHealth;
  final RuntimeLogFilter _shouldRecordLog;
  final DateTime Function() _now;

  StreamSubscription<Map<String, dynamic>>? _subscription;
  String? _lastTransportHealthLogKey;

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
        _recordNetwork(event);
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
      case 'transportHealth':
        final health = _transportHealthEvent(event);
        _recordTransportHealth(health);
        _onTransportHealth?.call(health);
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

  void _recordNetwork(Map<String, dynamic> event) {
    final reason = event['reason']?.toString().trim() ?? '';
    final interfaceName = event['interfaceName']?.toString().trim() ?? '';
    final index = (event['interfaceIndex'] as num?)?.toInt() ?? -1;
    AppLogStore.info(
      'network handover',
      'reason=${reason.isEmpty ? 'unknown' : reason} '
          'interface=${interfaceName.isEmpty ? 'none' : interfaceName} index=$index',
    );
  }

  void _recordTransportHealth(RuntimeTransportHealthEvent health) {
    if (!health.applicable) return;
    final key =
        '${health.state}|${health.activeLanes}|${health.totalLanes}|'
        '${health.demand}|${health.failureCode}|${health.challengeId}';
    if (key == _lastTransportHealthLogKey) return;
    _lastTransportHealthLogKey = key;
    final message =
        'state=${health.state} lanes=${health.activeLanes}/${health.totalLanes} '
        'demand=${health.demand}'
        '${health.failureCode == null || health.failureCode!.isEmpty ? '' : ' failure=${health.failureCode}'}'
        '${health.challengeId == null || health.challengeId!.isEmpty ? '' : ' captcha_pending=true'}';
    if (health.state == 'failed' || health.state == 'waiting_user') {
      AppLogStore.warning('vk-parasite transport', message);
    } else {
      AppLogStore.info('vk-parasite transport', message);
    }
  }

  RuntimeTransportHealthEvent _transportHealthEvent(
    Map<String, dynamic> event,
  ) {
    final challenge = event['challenge'];
    final challengeMap = challenge is Map
        ? Map<String, dynamic>.from(challenge)
        : const <String, dynamic>{};
    final rawUri = challengeMap['url']?.toString();
    final uri = rawUri == null ? null : Uri.tryParse(rawUri);
    final safeChallengeUri =
        uri != null &&
            uri.scheme == 'http' &&
            (uri.host == '127.0.0.1' || uri.host == 'localhost') &&
            uri.hasPort &&
            uri.port > 0
        ? uri
        : null;
    final failure = event['failure'];
    final failureMap = failure is Map
        ? Map<String, dynamic>.from(failure)
        : const <String, dynamic>{};
    return RuntimeTransportHealthEvent(
      applicable: event['applicable'] == true,
      state: event['state']?.toString() ?? '',
      activeLanes: (event['activeLanes'] as num?)?.toInt() ?? 0,
      totalLanes: (event['totalLanes'] as num?)?.toInt() ?? 0,
      demand: event['demand'] == true,
      failureCode: failureMap['code']?.toString(),
      challengeId: challengeMap['id']?.toString(),
      challengeUri: safeChallengeUri,
    );
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

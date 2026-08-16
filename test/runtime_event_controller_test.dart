import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hydrabox/app/runtime_event_controller.dart';
import 'package:hydrabox/logging/app_log_store.dart';

void main() {
  tearDown(AppLogStore.clear);

  test('dispatch routes typed runtime events to callbacks', () {
    RuntimeStateEvent? state;
    Map<String, dynamic>? status;
    Map<String, dynamic>? network;
    RuntimeGroupsEvent? groups;
    RuntimeUrlTestSessionsEvent? urlTestSessions;

    final controller = RuntimeEventController(
      events: const Stream.empty(),
      onState: (event) => state = event,
      onStatus: (event) => status = event,
      onNetwork: (event) => network = event,
      onGroups: (event) => groups = event,
      onUrlTestSessions: (event) => urlTestSessions = event,
      shouldRecordLog: (_) => true,
    );

    controller.dispatch({'type': 'state', 'running': true});
    controller.dispatch({'type': 'status', 'uplink': 11});
    controller.dispatch({'type': 'network', 'reason': 'default_interface'});
    controller.dispatch({
      'type': 'groups',
      'groups': [
        {'tag': 'select'},
      ],
    });
    controller.dispatch({
      'type': 'urlTestSessions',
      'runtimeGeneration': 7,
      'sequence': 12,
      'reset': true,
      'sessions': [
        {
          'groupTag': 'proxy',
          'results': [
            {
              'outboundTag': 'vless-1',
              'delayMillis': 83,
              'observedAt': 1700000000123,
              'status': 'success',
            },
          ],
        },
      ],
    });

    expect(state?.running, isTrue);
    expect(state?.hasError, isFalse);
    expect(status?['uplink'], 11);
    expect(network?['reason'], 'default_interface');
    expect(groups?.groups, [
      {'tag': 'select'},
    ]);
    expect(groups?.runtimeGeneration, 0);
    expect(urlTestSessions?.runtimeGeneration, 7);
    expect(urlTestSessions?.sequence, 12);
    expect(urlTestSessions?.reset, isTrue);
    expect(urlTestSessions?.toGroupUpdates(), [
      {
        'tag': 'proxy',
        'items': [
          {
            'tag': 'vless-1',
            'delay': 83,
            'time': 1700000000,
            'status': 'success',
            'error': '',
            'errorCode': '',
          },
        ],
      },
    ]);
  });

  test('structured transport health exposes only a safe local challenge', () {
    RuntimeTransportHealthEvent? health;
    final controller = RuntimeEventController(
      events: const Stream.empty(),
      onState: (_) {},
      onStatus: (_) {},
      onNetwork: (_) {},
      onGroups: (_) {},
      onTransportHealth: (event) => health = event,
      shouldRecordLog: (_) => false,
    );

    controller.dispatch({
      'type': 'transportHealth',
      'applicable': true,
      'state': 'waiting_user',
      'activeLanes': 0,
      'totalLanes': 4,
      'challenge': {
        'id': 'challenge-1',
        'kind': 'captcha',
        'url': 'http://127.0.0.1:35887/session',
      },
    });

    expect(health?.state, 'waiting_user');
    expect(health?.connected, isFalse);
    expect(health?.challengeId, 'challenge-1');
    expect(health?.challengeUri, Uri.parse('http://127.0.0.1:35887/session'));

    controller.dispatch({
      'type': 'transportHealth',
      'applicable': true,
      'state': 'waiting_user',
      'challenge': {'id': 'challenge-2', 'url': 'http://example.com:35887/'},
    });

    expect(health?.challengeId, 'challenge-2');
    expect(health?.challengeUri, isNull);
  });

  test('nativeLog normalizes warn and records through AppLogStore', () {
    final controller = RuntimeEventController(
      events: const Stream.empty(),
      onState: (_) {},
      onStatus: (_) {},
      onNetwork: (_) {},
      onGroups: (_) {},
      shouldRecordLog: (_) => true,
    );

    controller.dispatch({
      'type': 'nativeLog',
      'level': 'warn',
      'message': 'default interface unavailable',
    });

    final entry = AppLogStore.entries.value.single;
    expect(entry.title, 'sing-box');
    expect(entry.level, 'warning');
    expect(entry.message, 'default interface unavailable');
  });

  test('logs batch filters debug entries and keeps inferred error level', () {
    final controller = RuntimeEventController(
      events: const Stream.empty(),
      onState: (_) {},
      onStatus: (_) {},
      onNetwork: (_) {},
      onGroups: (_) {},
      shouldRecordLog: (level) => level != 'debug',
      now: () => DateTime.fromMillisecondsSinceEpoch(42),
    );

    controller.dispatch({
      'type': 'logs',
      'logs': [
        {'level': 0, 'message': 'debug details'},
        {'level': 4, 'message': 'connection failed'},
      ],
    });

    final entries = AppLogStore.entries.value;
    expect(entries.length, 1);
    expect(entries.single.level, 'error');
    expect(entries.single.title, 'sing-box');
    expect(entries.single.message, 'connection failed');
    expect(entries.single.timestamp, DateTime.fromMillisecondsSinceEpoch(42));
  });

  test('log text never drives structured transport recovery', () {
    final health = <RuntimeTransportHealthEvent>[];
    final controller = RuntimeEventController(
      events: const Stream.empty(),
      onState: (_) {},
      onStatus: (_) {},
      onNetwork: (_) {},
      onGroups: (_) {},
      shouldRecordLog: (_) => true,
      onTransportHealth: health.add,
    );

    controller.dispatch({
      'type': 'logs',
      'logs': [
        {
          'level': 4,
          'message': 'manual URLTest skipped: no usable network interface',
        },
        {'level': 4, 'message': 'regular proxy timeout'},
      ],
    });

    expect(health, isEmpty);
  });

  test('start subscribes to stream and dispose cancels subscription', () async {
    final stream = StreamController<Map<String, dynamic>>();
    addTearDown(stream.close);
    final states = <RuntimeStateEvent>[];
    final controller = RuntimeEventController(
      events: stream.stream,
      onState: states.add,
      onStatus: (_) {},
      onNetwork: (_) {},
      onGroups: (_) {},
      shouldRecordLog: (_) => true,
    );

    controller.start();
    stream.add({'type': 'state', 'running': true});
    await Future<void>.delayed(Duration.zero);

    expect(states.single.running, isTrue);

    await controller.dispose();
    stream.add({'type': 'state', 'running': false});
    await Future<void>.delayed(Duration.zero);

    expect(states.length, 1);
  });
}

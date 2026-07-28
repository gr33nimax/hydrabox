import 'package:flutter/foundation.dart';
import 'package:meow_client/models/app_view_models.dart';

@immutable
class ProxyRuntimeVisualState {
  const ProxyRuntimeVisualState({
    this.latency,
    this.latencyFresh = false,
    this.latencyChecking = false,
    this.latencyUnavailable = false,
    this.latencyError,
    this.networkUnavailable = false,
    this.highlighted = false,
    this.selecting = false,
  });

  final int? latency;
  final bool latencyFresh;
  final bool latencyChecking;
  final bool latencyUnavailable;
  final String? latencyError;
  final bool networkUnavailable;
  final bool highlighted;
  final bool selecting;

  @override
  bool operator ==(Object other) {
    return other is ProxyRuntimeVisualState &&
        other.latency == latency &&
        other.latencyFresh == latencyFresh &&
        other.latencyChecking == latencyChecking &&
        other.latencyUnavailable == latencyUnavailable &&
        other.latencyError == latencyError &&
        other.networkUnavailable == networkUnavailable &&
        other.highlighted == highlighted &&
        other.selecting == selecting;
  }

  @override
  int get hashCode => Object.hash(
    latency,
    latencyFresh,
    latencyChecking,
    latencyUnavailable,
    latencyError,
    networkUnavailable,
    highlighted,
    selecting,
  );
}

class ProxyRuntimeVisualStore {
  final Map<String, ValueNotifier<ProxyRuntimeVisualState?>> _notifiers =
      <String, ValueNotifier<ProxyRuntimeVisualState?>>{};
  final ValueNotifier<int> _revision = ValueNotifier<int>(0);
  Map<String, ProxyRuntimeVisualState> _states =
      const <String, ProxyRuntimeVisualState>{};

  ValueListenable<int> get revision => _revision;

  ValueListenable<ProxyRuntimeVisualState?> listenableFor(String tag) {
    return _notifiers.putIfAbsent(
      tag,
      () => ValueNotifier<ProxyRuntimeVisualState?>(_states[tag]),
    );
  }

  void replaceAll(Map<String, ProxyRuntimeVisualState> next) {
    if (mapEquals(_states, next)) {
      return;
    }
    final previousKeys = _states.keys.toSet();
    _states = Map.unmodifiable(next);
    final changed = <String>{...previousKeys, ...next.keys};
    for (final tag in changed) {
      final notifier = _notifiers[tag];
      if (notifier == null) {
        continue;
      }
      final value = next[tag];
      if (notifier.value != value) {
        notifier.value = value;
      }
    }
    for (final tag
        in _notifiers.keys
            .where((tag) => !next.containsKey(tag))
            .toList(growable: false)) {
      // The old row can finish its current frame. Removing our strong
      // reference is enough for the notifier and row to be collected later.
      _notifiers.remove(tag);
    }
    _revision.value++;
  }

  ProxyRuntimeVisualState? valueFor(String tag) => _states[tag];

  @visibleForTesting
  int get retainedNotifierCount => _notifiers.length;

  void dispose() {
    for (final notifier in _notifiers.values) {
      notifier.dispose();
    }
    _notifiers.clear();
    _revision.dispose();
  }
}

AppProxySummary applyProxyRuntimeVisualState(
  AppProxySummary proxy,
  ProxyRuntimeVisualState? state,
) {
  if (state == null) {
    return proxy;
  }
  return proxy.copyWith(
    latency: state.latency,
    clearLatency: state.latency == null,
    latencyFresh: state.latencyFresh,
    latencyChecking: state.latencyChecking,
    latencyUnavailable: state.latencyUnavailable,
    latencyError: state.latencyError,
    clearLatencyError: state.latencyError == null,
    highlighted: state.highlighted,
  );
}

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
    this.highlighted = false,
    this.selecting = false,
  });

  final int? latency;
  final bool latencyFresh;
  final bool latencyChecking;
  final bool latencyUnavailable;
  final String? latencyError;
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
    highlighted,
    selecting,
  );
}

class ProxyRuntimeVisualStore {
  final Map<String, ValueNotifier<ProxyRuntimeVisualState?>> _notifiers =
      <String, ValueNotifier<ProxyRuntimeVisualState?>>{};
  Map<String, ProxyRuntimeVisualState> _states =
      const <String, ProxyRuntimeVisualState>{};

  ValueListenable<ProxyRuntimeVisualState?> listenableFor(String tag) {
    return _notifiers.putIfAbsent(
      tag,
      () => ValueNotifier<ProxyRuntimeVisualState?>(_states[tag]),
    );
  }

  void replaceAll(Map<String, ProxyRuntimeVisualState> next) {
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
  }

  ProxyRuntimeVisualState? valueFor(String tag) => _states[tag];

  void dispose() {
    for (final notifier in _notifiers.values) {
      notifier.dispose();
    }
    _notifiers.clear();
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

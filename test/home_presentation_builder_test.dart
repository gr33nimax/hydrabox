import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hydrabox/features/home/home_presentation_builder.dart';
import 'package:hydrabox/models/app_view_models.dart';
import 'package:hydrabox/models/proxy_runtime_visual_state.dart';

void main() {
  group('HomePresentationData', () {
    test('hides traffic metrics while the runtime is disconnected', () {
      final traffic = ValueNotifier<TrafficUiSnapshot>(TrafficUiSnapshot.zero);
      final runtimeStates = ProxyRuntimeVisualStore();
      addTearDown(traffic.dispose);
      addTearDown(runtimeStates.dispose);

      final state = _data(
        connected: false,
        trafficAvailable: true,
        traffic: traffic,
        runtimeStates: runtimeStates,
      ).toViewState();

      expect(state.speedBytesPerSecond, 0);
      expect(state.uplinkBytesPerSecond, 0);
      expect(state.trafficBytes, 0);
    });

    test('forwards live totals only while traffic is available', () {
      final traffic = ValueNotifier<TrafficUiSnapshot>(TrafficUiSnapshot.zero);
      final runtimeStates = ProxyRuntimeVisualStore();
      addTearDown(traffic.dispose);
      addTearDown(runtimeStates.dispose);

      final state = _data(
        connected: true,
        trafficAvailable: true,
        traffic: traffic,
        runtimeStates: runtimeStates,
      ).toViewState();

      expect(state.speedBytesPerSecond, 1536);
      expect(state.uplinkBytesPerSecond, 768);
      expect(state.trafficBytes, 7168);
      expect(state.trafficListenable, same(traffic));
    });
  });
}

HomePresentationData _data({
  required bool connected,
  required bool trafficAvailable,
  required ValueNotifier<TrafficUiSnapshot> traffic,
  required ProxyRuntimeVisualStore runtimeStates,
}) {
  return HomePresentationData(
    connected: connected,
    connecting: false,
    resolvingProxy: false,
    connectionStatusLabel: '',
    activeProfile: null,
    activeProxy: null,
    runtimeStates: runtimeStates,
    hideServerIp: false,
    hapticEnabled: true,
    trafficAvailable: trafficAvailable,
    downlinkBytesPerSecond: 1536,
    uplinkBytesPerSecond: 768,
    uplinkTotalBytes: 2048,
    downlinkTotalBytes: 5120,
    trafficListenable: traffic,
    activeProfileRefreshing: false,
    showActiveProfileRefreshAction: false,
    brandName: 'Etonify',
    versionLabel: '0.3.0-beta.1',
  );
}

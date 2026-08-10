import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hydrabox/features/proxies/proxies_presentation_builder.dart';
import 'package:hydrabox/models/app_view_models.dart';
import 'package:hydrabox/models/proxy_runtime_visual_state.dart';

void main() {
  final traffic = ValueNotifier<TrafficUiSnapshot>(TrafficUiSnapshot.zero);
  final runtimeStates = ProxyRuntimeVisualStore();

  ProxiesPresentationData createData({
    required bool connected,
    required bool trafficAvailable,
  }) {
    return ProxiesPresentationData(
      proxies: const [],
      groupChildrenByTag: const {},
      selectedTag: '',
      activeProxy: null,
      hideActiveProxyIp: false,
      connected: connected,
      hapticEnabled: true,
      trafficAvailable: trafficAvailable,
      downlinkBytesPerSecond: 1536,
      uplinkBytesPerSecond: 768,
      uplinkTotalBytes: 4096,
      downlinkTotalBytes: 7168,
      trafficListenable: traffic,
      initialSort: ProxySort.source,
      progressiveBlurEnabled: true,
      runtimeStates: runtimeStates,
    );
  }

  test('proxy panel hides stale traffic while disconnected', () {
    final data = createData(connected: false, trafficAvailable: true);

    expect(data.speedBytesPerSecond, 0);
    expect(data.uplinkSpeedBytesPerSecond, 0);
    expect(data.trafficBytes, 0);
  });

  test('proxy panel forwards current traffic when connected', () {
    final data = createData(connected: true, trafficAvailable: true);

    expect(data.speedBytesPerSecond, 1536);
    expect(data.uplinkSpeedBytesPerSecond, 768);
    expect(data.trafficBytes, 11264);
  });
}

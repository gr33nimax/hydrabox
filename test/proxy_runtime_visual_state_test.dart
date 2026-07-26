import 'package:flutter_test/flutter_test.dart';
import 'package:meow_client/models/proxy_runtime_visual_state.dart';

void main() {
  test(
    'visual store releases notifiers for proxies no longer in the profile',
    () {
      final store = ProxyRuntimeVisualStore();
      addTearDown(store.dispose);

      store.listenableFor('old-server');
      store.replaceAll(const {
        'old-server': ProxyRuntimeVisualState(latency: 120),
      });

      expect(store.retainedNotifierCount, 1);

      store.replaceAll(const {
        'new-server': ProxyRuntimeVisualState(latency: 80),
      });

      expect(store.retainedNotifierCount, 0);
      expect(store.valueFor('old-server'), isNull);
      expect(store.valueFor('new-server')?.latency, 80);
    },
  );
}

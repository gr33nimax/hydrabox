import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:meow_client/app/proxy_selection_controller.dart';
import 'package:meow_client/models/subscription.dart';

void main() {
  test('valid selection accepts proxy groups and proxy chains', () {
    final controller = ProxySelectionController();
    addTearDown(controller.dispose);

    const subscription = Subscription(
      id: 'sub-1',
      name: 'Subscription',
      url: 'https://example.test/sub',
      outbounds: [
        Outbound(
          tag: 'leaf-1',
          name: 'Leaf 1',
          config: {'type': 'vless', 'tag': 'leaf-1'},
        ),
        Outbound(
          tag: 'leaf-2',
          name: 'Leaf 2',
          config: {'type': 'vless', 'tag': 'leaf-2'},
        ),
      ],
      groups: [
        SubscriptionGroup(
          tag: 'group-auto',
          name: 'Auto group',
          outboundTags: ['leaf-1', 'leaf-2'],
        ),
      ],
      proxyChains: [
        SubscriptionProxyChain(
          tag: 'chain-exit',
          name: 'Chain',
          targetTag: 'leaf-1',
          detourTag: 'leaf-2',
        ),
      ],
    );

    expect(
      controller.validSelectedProxyTagForSubscription(
        subscription,
        'group-auto',
      ),
      'group-auto',
    );
    expect(
      controller.validSelectedProxyTagForSubscription(
        subscription,
        'chain-exit',
      ),
      'chain-exit',
    );
  });

  test(
    'local selection clears pending runtime selection and cancels timeout',
    () async {
      final controller = ProxySelectionController();
      addTearDown(controller.dispose);
      ProxySelectionTimeout? timeout;

      final runtimeGeneration = controller.beginRuntimeSelection(
        tag: 'leaf-1',
        previousTag: 'leaf-0',
        confirmationTimeout: Duration.zero,
        onTimeout: (value) => timeout = value,
      );
      expect(controller.pendingRuntimeSelectTag, 'leaf-1');

      final localGeneration = controller.beginLocalSelection();
      expect(localGeneration, greaterThan(runtimeGeneration));
      expect(controller.pendingRuntimeSelectTag, isNull);

      await Future<void>.delayed(Duration.zero);
      expect(timeout, isNull);
    },
  );

  test('runtime selection timeout reports current pending tag', () async {
    final controller = ProxySelectionController();
    addTearDown(controller.dispose);
    ProxySelectionTimeout? timeout;

    final generation = controller.beginRuntimeSelection(
      tag: 'leaf-1',
      previousTag: 'leaf-0',
      confirmationTimeout: Duration.zero,
      onTimeout: (value) => timeout = value,
    );

    await Future<void>.delayed(Duration.zero);
    expect(timeout, isNotNull);
    expect(timeout!.generation, generation);
    expect(timeout!.tag, 'leaf-1');
    expect(timeout!.previousTag, 'leaf-0');
  });

  test('clear runtime selection ignores stale generation', () {
    final controller = ProxySelectionController();
    addTearDown(controller.dispose);

    final generation = controller.beginRuntimeSelection(
      tag: 'leaf-1',
      previousTag: 'leaf-0',
      onTimeout: (_) {},
    );

    expect(
      controller.clearRuntimeSelection(generation: generation + 1),
      isFalse,
    );
    expect(controller.pendingRuntimeSelectTag, 'leaf-1');
    expect(controller.clearRuntimeSelection(generation: generation), isTrue);
    expect(controller.pendingRuntimeSelectTag, isNull);
  });

  test('persistence writes are serialized in selection order', () async {
    final controller = ProxySelectionController();
    addTearDown(controller.dispose);
    final writes = <String>[];
    final firstGate = Completer<void>();

    final firstGeneration = controller.beginLocalSelection();
    final first = controller.enqueuePersistence(
      generation: firstGeneration,
      action: () async {
        await firstGate.future;
        writes.add('france');
      },
    );
    await Future<void>.delayed(Duration.zero);

    final secondGeneration = controller.beginLocalSelection();
    final second = controller.enqueuePersistence(
      generation: secondGeneration,
      action: () async => writes.add('germany'),
    );

    firstGate.complete();
    await Future.wait<void>([first, second]);
    await controller.waitForPersistence();

    expect(writes, ['france', 'germany']);
  });

  test('stale queued write cannot overwrite latest selection', () async {
    final controller = ProxySelectionController();
    addTearDown(controller.dispose);
    final writes = <String>[];
    final queueGate = Completer<void>();

    final blockingGeneration = controller.beginLocalSelection();
    final blocking = controller.enqueuePersistence(
      generation: blockingGeneration,
      action: () => queueGate.future,
    );
    await Future<void>.delayed(Duration.zero);

    final staleGeneration = controller.beginLocalSelection();
    final stale = controller.enqueuePersistence(
      generation: staleGeneration,
      action: () async => writes.add('france'),
    );
    final latestGeneration = controller.beginLocalSelection();
    final latest = controller.enqueuePersistence(
      generation: latestGeneration,
      action: () async => writes.add('germany'),
    );

    queueGate.complete();
    await Future.wait<void>([blocking, stale, latest]);

    expect(writes, ['germany']);
  });

  test('runtime start guard preserves current selection generation', () {
    final controller = ProxySelectionController();
    addTearDown(controller.dispose);

    final generation = controller.beginLocalSelection();
    final guardedGeneration = controller.guardCurrentSelectionForRuntime(
      tag: 'france',
      previousTag: 'france',
      onTimeout: (_) {},
    );

    expect(guardedGeneration, generation);
    expect(controller.pendingRuntimeSelectTag, 'france');
  });

  test(
    'effective selected tag prefers explicit local choice when requested',
    () {
      expect(
        ProxySelectionController.effectiveSelectedProxyTag(
          metadataSelectedProxyTag: 'old-leaf',
          preferredSelectedProxyTag: 'new-leaf',
          preferPreferred: true,
        ),
        'new-leaf',
      );
      expect(
        ProxySelectionController.effectiveSelectedProxyTag(
          metadataSelectedProxyTag: 'old-leaf',
          preferredSelectedProxyTag: 'new-leaf',
          preferPreferred: false,
        ),
        'old-leaf',
      );
    },
  );

  test('runtime selection is used only for a stable connected core', () {
    final controller = ProxySelectionController();
    addTearDown(controller.dispose);

    expect(
      controller.runtimeSelectionUpdatesAllowed(
        connected: true,
        connectionStable: true,
        transitionInProgress: false,
      ),
      isTrue,
    );
    expect(
      controller.runtimeSelectionUpdatesAllowed(
        connected: true,
        connectionStable: false,
        transitionInProgress: false,
      ),
      isFalse,
    );
    expect(
      controller.runtimeSelectionUpdatesAllowed(
        connected: false,
        connectionStable: false,
        transitionInProgress: false,
      ),
      isFalse,
    );
  });
}

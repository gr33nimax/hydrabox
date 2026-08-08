import 'package:flutter_test/flutter_test.dart';
import 'package:hydrabox/models/subscription.dart';
import 'package:hydrabox/singbox/preconnect_url_test_policy.dart';

void main() {
  const direct = Outbound(
    tag: 'nl-1',
    name: 'Netherlands',
    config: <String, dynamic>{'type': 'vless'},
  );
  const second = Outbound(
    tag: 'de-1',
    name: 'Germany',
    config: <String, dynamic>{'type': 'trojan'},
  );
  final outbounds = <String, Outbound>{direct.tag: direct, second.tag: second};

  test('accepts a selected concrete outbound', () {
    expect(
      resolvePreconnectUrlTestTarget(
        selectedTag: direct.tag,
        groupsByTag: const {},
        runtimeGroupSelections: const {},
        outboundsByTag: outbounds,
      ),
      direct.tag,
    );
  });

  test('selector requires one valid concrete runtime child', () {
    const selector = SubscriptionGroup(
      tag: 'manual',
      name: 'Manual',
      type: 'selector',
      outboundTags: <String>['nl-1', 'de-1'],
    );
    final groups = <String, SubscriptionGroup>{selector.tag: selector};

    expect(
      resolvePreconnectUrlTestTarget(
        selectedTag: selector.tag,
        groupsByTag: groups,
        runtimeGroupSelections: const {},
        outboundsByTag: outbounds,
      ),
      isNull,
    );
    expect(
      resolvePreconnectUrlTestTarget(
        selectedTag: selector.tag,
        groupsByTag: groups,
        runtimeGroupSelections: const {'manual': 'nl-1'},
        outboundsByTag: outbounds,
      ),
      'nl-1',
    );
  });

  test('rejects auto, lowest, nested, and group-only selections', () {
    const auto = SubscriptionGroup(
      tag: 'auto',
      name: 'Auto',
      type: 'urltest',
      outboundTags: <String>['nl-1'],
    );
    const nested = SubscriptionGroup(
      tag: 'nested',
      name: 'Nested',
      type: 'selector',
      outboundTags: <String>['auto'],
    );
    const groupOnly = Outbound(
      tag: 'hidden-group',
      name: 'Hidden group',
      config: <String, dynamic>{'type': 'vless', '_group_only': true},
    );
    final groups = <String, SubscriptionGroup>{
      auto.tag: auto,
      nested.tag: nested,
    };
    final allOutbounds = <String, Outbound>{
      ...outbounds,
      groupOnly.tag: groupOnly,
    };

    for (final selected in <String>['lowest', 'auto', 'hidden-group']) {
      expect(
        resolvePreconnectUrlTestTarget(
          selectedTag: selected,
          groupsByTag: groups,
          runtimeGroupSelections: const {},
          outboundsByTag: allOutbounds,
        ),
        isNull,
      );
    }
    expect(
      resolvePreconnectUrlTestTarget(
        selectedTag: nested.tag,
        groupsByTag: groups,
        runtimeGroupSelections: const {'nested': 'auto'},
        outboundsByTag: allOutbounds,
      ),
      isNull,
    );
  });

  test('accepts an explicit proxy chain target', () {
    expect(
      resolvePreconnectUrlTestTarget(
        selectedTag: 'chain-1',
        groupsByTag: const {},
        runtimeGroupSelections: const {},
        outboundsByTag: const {},
        proxyChainTags: const {'chain-1'},
      ),
      'chain-1',
    );
  });
}

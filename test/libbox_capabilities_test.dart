import 'package:flutter_test/flutter_test.dart';
import 'package:meow_client/singbox/libbox_capabilities.dart';

void main() {
  group('LibboxCapabilities', () {
    test('uses the legacy profile when the handshake is absent', () {
      expect(
        LibboxCapabilities.parseOrLegacy(null),
        same(LibboxCapabilities.bundledLegacy),
      );
      expect(
        LibboxCapabilities.parseOrLegacy('not-json'),
        same(LibboxCapabilities.bundledLegacy),
      );
      expect(
        LibboxCapabilities.parseOrLegacy('{"api_version":0}'),
        same(LibboxCapabilities.bundledLegacy),
      );
      expect(LibboxCapabilities.bundledLegacy.hasRemoteSafetyManifest, isFalse);
    });

    test('parses the versioned core contract and ignores unknown fields', () {
      final capabilities = LibboxCapabilities.parseOrLegacy('''
        {
          "api_version": 1,
          "core_id": "io.hydrabox.hydracore",
          "core_name": "HydraCore",
          "core_version": "1.13.14-etonify",
          "upstream_project": "etonify-core",
          "supports_targeted_url_test": true,
          "supports_preconnect_url_test": true,
          "supports_group_url_test_sessions": true,
          "supports_structured_probe_errors": true,
          "supports_outbound_external_info": true,
          "supports_mixed_routing_outbound": true,
          "supports_url_test_timeout": true,
          "supports_url_test_concurrency": true,
          "supports_url_test_deadline": true,
          "supports_url_test_force": true,
          "supports_url_test_unavailable_check_interval": true,
          "supports_url_test_method": true,
          "supports_url_test_interrupt_delay_threshold": true,
          "url_test_completion_model": "rpc_completion",
          "supports_config_check": true,
          "supports_close_connections": true,
          "supports_reality_spider_x": true,
          "tun_stacks": ["SYSTEM", "gvisor", "mixed", ""],
          "remote_policy_version": 1,
          "remote_safe_top_level_fields": ["outbounds", "endpoints"],
          "remote_safe_outbound_types": ["trojan", "future-leaf"],
          "remote_safe_endpoint_types": ["wireguard"],
          "remote_safe_dns_server_types": ["https"],
          "remote_safe_provider_types": [],
          "future_field": "ignored"
        }
      ''');

      expect(capabilities.hasVersionedContract, isTrue);
      expect(capabilities.apiVersion, 1);
      expect(capabilities.coreId, 'io.hydrabox.hydracore');
      expect(capabilities.coreName, 'HydraCore');
      expect(capabilities.coreVersion, '1.13.14-etonify');
      expect(capabilities.upstreamProject, 'etonify-core');
      expect(capabilities.supportsTargetedUrlTest, isTrue);
      expect(capabilities.supportsPreconnectUrlTest, isTrue);
      expect(capabilities.supportsGroupUrlTestSessions, isTrue);
      expect(capabilities.supportsStructuredProbeErrors, isTrue);
      expect(capabilities.supportsOutboundExternalInfo, isTrue);
      expect(capabilities.supportsMixedRoutingOutbound, isTrue);
      expect(capabilities.supportsUrlTestTimeout, isTrue);
      expect(capabilities.supportsUrlTestConcurrency, isTrue);
      expect(capabilities.supportsUrlTestDeadline, isTrue);
      expect(capabilities.supportsUrlTestForce, isTrue);
      expect(capabilities.supportsUrlTestUnavailableCheckInterval, isTrue);
      expect(capabilities.supportsUrlTestMethod, isTrue);
      expect(capabilities.supportsUrlTestInterruptDelayThreshold, isTrue);
      expect(
        capabilities.urlTestCompletionModel,
        UrlTestCompletionModel.rpcCompletion,
      );
      expect(capabilities.supportsConfigCheck, isTrue);
      expect(capabilities.supportsCloseConnections, isTrue);
      expect(capabilities.supportsRealitySpiderX, isTrue);
      expect(capabilities.supportsTunStack('system'), isTrue);
      expect(capabilities.supportsTunStack(' GVISOR '), isTrue);
      expect(capabilities.supportsTunStack('mixed'), isTrue);
      expect(capabilities.hasRemoteSafetyManifest, isTrue);
      expect(capabilities.remoteSafeTopLevelFields, {'outbounds', 'endpoints'});
      expect(capabilities.remoteSafeOutboundTypes, {'trojan', 'future-leaf'});
      expect(capabilities.remoteSafeProviderTypes, isEmpty);
    });

    test('missing optional fields fail closed', () {
      final capabilities = LibboxCapabilities.parseOrLegacy(
        '{"api_version":1,"url_test_completion_model":"unknown"}',
      );

      expect(capabilities.hasVersionedContract, isTrue);
      expect(capabilities.supportsTargetedUrlTest, isFalse);
      expect(capabilities.supportsPreconnectUrlTest, isFalse);
      expect(capabilities.supportsConfigCheck, isFalse);
      expect(capabilities.supportsRealitySpiderX, isFalse);
      expect(capabilities.tunStacks, isEmpty);
      expect(capabilities.hasRemoteSafetyManifest, isFalse);
      expect(
        capabilities.urlTestCompletionModel,
        UrlTestCompletionModel.groupEvents,
      );
    });

    test('unknown capability and remote-policy versions fail closed', () {
      final unknownApi = LibboxCapabilities.parseOrLegacy(
        '{"api_version":2,"remote_policy_version":1,'
        '"remote_safe_top_level_fields":["outbounds"]}',
      );
      final unknownPolicy = LibboxCapabilities.parseOrLegacy(
        '{"api_version":1,"remote_policy_version":2,'
        '"remote_safe_top_level_fields":["outbounds"]}',
      );

      expect(unknownApi.hasVersionedContract, isFalse);
      expect(unknownApi.hasRemoteSafetyManifest, isFalse);
      expect(unknownPolicy.hasVersionedContract, isTrue);
      expect(unknownPolicy.hasRemoteSafetyManifest, isFalse);
    });

    test('fractional capability and remote-policy versions fail closed', () {
      final fractionalApi = LibboxCapabilities.parseOrLegacy(
        '{"api_version":1.9,"remote_policy_version":1,'
        '"remote_safe_top_level_fields":["outbounds"]}',
      );
      final fractionalPolicy = LibboxCapabilities.parseOrLegacy(
        '{"api_version":1,"remote_policy_version":1.9,'
        '"remote_safe_top_level_fields":["outbounds"]}',
      );

      expect(fractionalApi.hasVersionedContract, isFalse);
      expect(fractionalApi.hasRemoteSafetyManifest, isFalse);
      expect(fractionalPolicy.hasVersionedContract, isTrue);
      expect(fractionalPolicy.hasRemoteSafetyManifest, isFalse);
    });
  });
}

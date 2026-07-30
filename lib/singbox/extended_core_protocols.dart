/// Protocol inventory for the Android extended sing-box build.
///
/// The native registry remains authoritative at runtime.  This inventory is
/// deliberately kept in the Flutter layer so importers, diagnostics and
/// tests can assert that the app does not silently filter a protocol before
/// it reaches libbox.
class ExtendedCoreProtocolCatalog {
  ExtendedCoreProtocolCatalog._();

  static const String coreRepository =
      'https://github.com/shtorm-7/sing-box-extended';
  static const String coreBranch = 'extended';

  static const Set<String> inboundTypes = {
    'tun',
    'redirect',
    'tproxy',
    'direct',
    'socks',
    'http',
    'mixed',
    'shadowsocks',
    'vmess',
    'trojan',
    'naive',
    'shadowtls',
    'vless',
    'anytls',
    'mieru',
    'ssh',
    'bond',
    'failover',
    'trusttunnel',
    'hysteria',
    'tuic',
    'hysteria2',
    'mtproxy',
    'sudoku',
    'snell',
  };

  static const Set<String> outboundTypes = {
    'direct',
    'block',
    'fallback',
    'selector',
    'urltest',
    'socks',
    'http',
    'shadowsocks',
    'vmess',
    'trojan',
    'naive',
    'tor',
    'ssh',
    'shadowtls',
    'vless',
    'mieru',
    'anytls',
    'masque',
    'openvpn',
    'bond',
    'failover',
    'trusttunnel',
    'bandwidth-limiter',
    'connection-limiter',
    'traffic-limiter',
    'rate-limiter',
    'parser',
    'hysteria',
    'tuic',
    'hysteria2',
    'sudoku',
    'snell',
  };

  static const Set<String> endpointTypes = {
    'vpn-server',
    'vpn-client',
    'wireguard',
    'warp',
    'tailscale',
  };

  static const Set<String> dnsTransportTypes = {
    'tcp',
    'udp',
    'tls',
    'https',
    'quic',
    'h3',
    'sdns',
    'hosts',
    'local',
    'fakeip',
    'fallback',
    'resolved',
    'dhcp',
    'tailscale',
  };

  static const Set<String> v2rayTransportTypes = {
    'http',
    'ws',
    'quic',
    'grpc',
    'httpupgrade',
    'xhttp',
    'mkcp',
  };

  static const Set<String> providerTypes = {'inline', 'local', 'remote'};

  static const Set<String> serviceTypes = {
    'admin-panel',
    'manager',
    'manager-api',
    'node',
    'node-manager-api',
    'resolved',
    'ssm-api',
    'derp',
    'ccm',
    'ocm',
    'oom-killer',
    'profiler',
  };

  /// Names accepted only to return the core's explicit removal error.
  static const Set<String> stubbedInboundTypes = {'shadowsocksr'};

  /// WireGuard is runnable through [endpointTypes], not as an outbound.
  static const Set<String> stubbedOutboundTypes = {'shadowsocksr', 'wireguard'};

  /// Optional Go build tags required for the extended Android AAR.
  static const Set<String> requiredAndroidBuildTags = {
    'with_gvisor',
    'with_quic',
    'with_dhcp',
    'with_wireguard',
    'with_masque',
    'with_mtproxy',
    'with_ccm',
    'with_ocm',
    'with_trusttunnel',
    'with_openvpn',
    'with_sudoku',
    'with_snell',
    'with_utls',
    'with_naive_outbound',
    'with_clash_api',
    'with_manager',
    'with_admin_panel',
    'with_profiler',
    'with_v2ray_api',
    'with_acme',
    'with_tailscale',
    'badlinkname',
    'tfogo_checklinkname0',
    'ts_omit_logtail',
    'ts_omit_ssh',
    'ts_omit_drive',
    'ts_omit_taildrop',
    'ts_omit_webclient',
    'ts_omit_doctor',
    'ts_omit_capture',
    'ts_omit_kube',
    'ts_omit_aws',
    'ts_omit_synology',
    'ts_omit_bird',
  };

  static bool isKnownOutbound(String type) =>
      outboundTypes.contains(type.trim().toLowerCase());

  static bool isKnownInbound(String type) =>
      inboundTypes.contains(type.trim().toLowerCase());
}

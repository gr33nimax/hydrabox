/// Parses WireGuard `.conf` files into a sing-box WireGuard endpoint entry.
///
/// Example input:
/// ```ini
/// [Interface]
/// PrivateKey = abcdef…
/// Address = 10.0.0.2/32, fd00::2/128
/// DNS = 1.1.1.1
/// MTU = 1280
///
/// [Peer]
/// PublicKey = ghijkl…
/// PresharedKey = mnopqr…
/// AllowedIPs = 0.0.0.0/0, ::/0
/// Endpoint = server.example.com:51820
/// PersistentKeepalive = 25
/// ```
class WireGuardConfigParser {
  WireGuardConfigParser._();

  /// Returns `true` if [content] looks like a WireGuard .conf file.
  static bool canParse(String content) {
    return content.contains('[Interface]') && content.contains('[Peer]');
  }

  /// Parses a WireGuard config into a single sing-box outbound map.
  /// Returns a list with 0 or 1 element.
  static List<Map<String, dynamic>> parse(String content) {
    final sections = _parseSections(content);
    Map<String, String>? iface;
    final peerSections = <Map<String, String>>[];
    for (final section in sections) {
      if (section.name == 'Interface' && iface == null) {
        iface = section.values;
      } else if (section.name == 'Peer') {
        peerSections.add(section.values);
      }
    }
    if (iface == null) return [];

    final result = <String, dynamic>{
      'type': 'wireguard',
      'tag': '',
      '_etonify_source_section': 'endpoints',
    };

    // Interface → private_key, address, mtu
    final privateKey = iface['PrivateKey'] ?? '';
    if (privateKey.isNotEmpty) result['private_key'] = privateKey;

    final address = iface['Address'] ?? '';
    if (address.isNotEmpty) {
      result['address'] = address
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
    }

    final mtu = int.tryParse(iface['MTU'] ?? '');
    if (mtu != null && mtu > 0) result['mtu'] = mtu;

    // Peers
    final peers = <Map<String, dynamic>>[];
    for (final p in peerSections) {
      final peer = <String, dynamic>{};

      // Endpoint → address + port
      final endpoint = p['Endpoint'] ?? '';
      if (endpoint.isNotEmpty) {
        _parseEndpoint(endpoint, (host, port) {
          peer['address'] = host;
          peer['port'] = port;
        });
      }

      final publicKey = p['PublicKey'] ?? '';
      if (publicKey.isNotEmpty) peer['public_key'] = publicKey;

      final psk = p['PresharedKey'] ?? '';
      if (psk.isNotEmpty) peer['pre_shared_key'] = psk;

      final allowedIPs = p['AllowedIPs'] ?? '';
      if (allowedIPs.isNotEmpty) {
        peer['allowed_ips'] = allowedIPs
            .split(',')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList();
      } else {
        peer['allowed_ips'] = ['0.0.0.0/0', '::/0'];
      }

      final keepalive = p['PersistentKeepalive'] ?? '';
      final keepaliveSeconds = int.tryParse(keepalive);
      if (keepaliveSeconds != null &&
          keepaliveSeconds > 0 &&
          keepaliveSeconds <= 65535) {
        peer['persistent_keepalive_interval'] = keepaliveSeconds;
      }

      peers.add(peer);
    }

    if (peers.isEmpty) return [];
    result['peers'] = peers;

    // Build name from first peer endpoint
    final firstPeer = peers.first;
    final addr = firstPeer['address'] ?? 'WireGuard';
    final port = firstPeer['port'] ?? '';
    result['_name'] = port != '' ? '$addr:$port' : addr.toString();

    return [result];
  }

  // ─────────────────── INI parser ───────────────────

  /// Parses ordered INI-style section instances.
  /// Repeated `[Peer]` blocks remain separate so values cannot leak between
  /// peers.
  static List<_WireGuardSection> _parseSections(String content) {
    final result = <_WireGuardSection>[];
    _WireGuardSection? currentSection;

    for (final line in content.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty ||
          trimmed.startsWith('#') ||
          trimmed.startsWith(';')) {
        continue;
      }

      if (trimmed.startsWith('[') && trimmed.endsWith(']')) {
        currentSection = _WireGuardSection(
          trimmed.substring(1, trimmed.length - 1),
        );
        result.add(currentSection);
        continue;
      }

      if (currentSection != null) {
        final eqIdx = trimmed.indexOf('=');
        if (eqIdx > 0) {
          final key = trimmed.substring(0, eqIdx).trim();
          final value = trimmed.substring(eqIdx + 1).trim();
          currentSection.values[key] = value;
        }
      }
    }
    return result;
  }

  static void _parseEndpoint(
    String endpoint,
    void Function(String host, int port) cb,
  ) {
    if (endpoint.startsWith('[')) {
      // IPv6: [host]:port
      final closeBracket = endpoint.indexOf(']');
      if (closeBracket < 0) return;
      final host = endpoint.substring(1, closeBracket);
      final rest = endpoint.substring(closeBracket + 1);
      if (rest.startsWith(':')) {
        final port = int.tryParse(rest.substring(1));
        if (port != null) cb(host, port);
      }
    } else {
      final colonIdx = endpoint.lastIndexOf(':');
      if (colonIdx < 0) return;
      final host = endpoint.substring(0, colonIdx);
      final port = int.tryParse(endpoint.substring(colonIdx + 1));
      if (port != null) cb(host, port);
    }
  }
}

class _WireGuardSection {
  _WireGuardSection(this.name);

  final String name;
  final Map<String, String> values = <String, String>{};
}

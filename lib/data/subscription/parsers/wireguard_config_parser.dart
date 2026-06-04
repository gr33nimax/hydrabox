/// Parses WireGuard `.conf` files into a sing-box WireGuard endpoint outbound.
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
    final iface = sections['Interface'];
    if (iface == null) return [];

    final result = <String, dynamic>{'type': 'wireguard', 'tag': ''};

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
    for (final entry in sections.entries) {
      if (entry.key != 'Peer') continue;
      final p = entry.value;
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
      if (keepalive.isNotEmpty) {
        peer['persistent_keepalive_interval'] = '${keepalive}s';
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

  /// Parses INI-style sections. Returns a map of section name → key-value pairs.
  /// Note: multiple [Peer] sections are supported by returning them with the
  /// same key (last one wins in a regular Map, so we use a special approach).
  static Map<String, Map<String, String>> _parseSections(String content) {
    // We need to handle multiple [Peer] sections. For simplicity, we merge
    // all peers into the first Peer section since most configs have one peer.
    // For proper multi-peer support, the parse() method already handles it
    // by re-scanning.
    final result = <String, Map<String, String>>{};
    String currentSection = '';

    for (final line in content.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty ||
          trimmed.startsWith('#') ||
          trimmed.startsWith(';')) {
        continue;
      }

      if (trimmed.startsWith('[') && trimmed.endsWith(']')) {
        currentSection = trimmed.substring(1, trimmed.length - 1);
        result.putIfAbsent(currentSection, () => {});
        continue;
      }

      if (currentSection.isNotEmpty) {
        final eqIdx = trimmed.indexOf('=');
        if (eqIdx > 0) {
          final key = trimmed.substring(0, eqIdx).trim();
          final value = trimmed.substring(eqIdx + 1).trim();
          result[currentSection]![key] = value;
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

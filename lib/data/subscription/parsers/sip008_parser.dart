import 'dart:convert';

/// Parses SIP008 JSON format into sing-box outbound JSON maps.
///
/// SIP008 spec:
/// ```json
/// {
///   "version": 1,
///   "servers": [
///     {
///       "id": "uuid",
///       "remarks": "name",
///       "server": "host",
///       "server_port": 443,
///       "method": "aes-256-gcm",
///       "password": "pass",
///       "plugin": "...",
///       "plugin_opts": "..."
///     }
///   ]
/// }
/// ```
class Sip008Parser {
  Sip008Parser._();

  /// Returns `true` if [content] looks like a SIP008 JSON document.
  static bool canParse(String content) {
    try {
      final json = jsonDecode(content);
      if (json is! Map) return false;
      return json.containsKey('servers') && json['servers'] is List;
    } catch (_) {
      return false;
    }
  }

  /// Parses [content] as SIP008 JSON and returns sing-box outbound maps.
  static List<Map<String, dynamic>> parse(String content) {
    final json = jsonDecode(content) as Map<String, dynamic>;
    final servers = json['servers'] as List;
    final results = <Map<String, dynamic>>[];

    for (final entry in servers) {
      if (entry is! Map) continue;
      final s = Map<String, dynamic>.from(entry);

      final server = (s['server'] ?? '') as String;
      final port = s['server_port'] ?? s['port'] ?? 0;
      final method = (s['method'] ?? '') as String;
      final password = (s['password'] ?? '') as String;
      final name = (s['remarks'] ?? s['name'] ?? '') as String;

      if (server.isEmpty || method.isEmpty) continue;

      final result = <String, dynamic>{
        'type': 'shadowsocks',
        'tag': '',
        'server': server,
        'server_port': port is int ? port : int.tryParse(port.toString()) ?? 0,
        'method': method,
        'password': password,
      };

      final plugin = (s['plugin'] ?? '') as String;
      if (plugin.isNotEmpty) {
        result['plugin'] = plugin;
        final pluginOpts =
            (s['plugin_opts'] ?? s['plugin_args'] ?? '') as String;
        if (pluginOpts.isNotEmpty) result['plugin_opts'] = pluginOpts;
      }

      result['_name'] = name.isNotEmpty ? name : '$server:$port';
      results.add(result);
    }
    return results;
  }
}

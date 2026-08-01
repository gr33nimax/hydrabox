import 'dart:convert';

/// Decodes JSON after rejecting duplicate object keys and excessive nesting.
///
/// Dart's [jsonDecode] keeps the last value for a duplicate key. That behavior
/// is fine for many UI payloads, but it is unsafe for signed or encrypted
/// configuration documents because different implementations may validate a
/// different value. This lightweight scanner validates object key uniqueness
/// before delegating the actual value decoding to the SDK.
dynamic decodeStrictJson(String source, {int maxDepth = 64}) {
  _StrictJsonScanner(source, maxDepth: maxDepth).scan();
  return jsonDecode(source);
}

/// Lexically finds selected members of the root JSON object.
///
/// This deliberately does not validate the entire document: format detection
/// must still recognize a truncated JWE and fail closed. Unlike a regular
/// expression, the scanner never mistakes a discriminator inside a nested
/// protocol object or string for a root envelope member. Only requested keys
/// and short requested string values are decoded, keeping detection bounded.
Map<String, List<String?>> scanTopLevelJsonObjectForDetection(
  String source, {
  required Set<String> memberNames,
  Set<String> stringValueKeys = const {},
}) {
  final found = <String, List<String?>>{};
  var index = 0;

  bool isWhitespace(int code) =>
      code == 0x20 || code == 0x0a || code == 0x0d || code == 0x09;

  void skipWhitespace() {
    while (index < source.length && isWhitespace(source.codeUnitAt(index))) {
      index++;
    }
  }

  int? stringEnd(int start) {
    if (start >= source.length || source.codeUnitAt(start) != 0x22) {
      return null;
    }
    var cursor = start + 1;
    var escaped = false;
    while (cursor < source.length) {
      final code = source.codeUnitAt(cursor++);
      if (escaped) {
        escaped = false;
      } else if (code == 0x5c) {
        escaped = true;
      } else if (code == 0x22) {
        return cursor;
      } else if (code < 0x20) {
        return null;
      }
    }
    return null;
  }

  int valueEnd(int start) {
    if (start >= source.length) return start;
    if (source.codeUnitAt(start) == 0x22) {
      return stringEnd(start) ?? source.length;
    }

    var cursor = start;
    var objectDepth = 0;
    var arrayDepth = 0;
    while (cursor < source.length) {
      final code = source.codeUnitAt(cursor);
      if (code == 0x22) {
        cursor = stringEnd(cursor) ?? source.length;
        continue;
      }
      if (code == 0x7b) {
        objectDepth++;
      } else if (code == 0x7d) {
        if (objectDepth == 0 && arrayDepth == 0) return cursor;
        if (objectDepth > 0) objectDepth--;
      } else if (code == 0x5b) {
        arrayDepth++;
      } else if (code == 0x5d) {
        if (arrayDepth > 0) arrayDepth--;
      } else if (code == 0x2c && objectDepth == 0 && arrayDepth == 0) {
        return cursor;
      }
      cursor++;
    }
    return cursor;
  }

  skipWhitespace();
  if (index >= source.length || source.codeUnitAt(index) != 0x7b) {
    return found;
  }
  index++;

  while (index < source.length) {
    skipWhitespace();
    if (index >= source.length || source.codeUnitAt(index) == 0x7d) break;
    final keyStart = index;
    final keyEnd = stringEnd(keyStart);
    if (keyEnd == null) break;
    index = keyEnd;

    String? key;
    if (keyEnd - keyStart <= 256) {
      try {
        key = jsonDecode(source.substring(keyStart, keyEnd)) as String;
      } on FormatException {
        break;
      }
    }

    skipWhitespace();
    if (index >= source.length || source.codeUnitAt(index) != 0x3a) break;
    index++;
    skipWhitespace();

    final occurrences = key != null && memberNames.contains(key)
        ? found.putIfAbsent(key, () => <String?>[])
        : null;
    occurrences?.add(null);

    final start = index;
    final end = valueEnd(start);
    if (key != null &&
        occurrences != null &&
        stringValueKeys.contains(key) &&
        start < source.length &&
        source.codeUnitAt(start) == 0x22 &&
        end - start <= 2048) {
      try {
        occurrences[occurrences.length - 1] =
            jsonDecode(source.substring(start, end)) as String;
      } on FormatException {
        // Presence is enough for fail-closed detection; full parsing reports
        // the malformed value later.
      }
    }
    index = end;
    skipWhitespace();
    if (index >= source.length || source.codeUnitAt(index) == 0x7d) break;
    if (source.codeUnitAt(index) != 0x2c) break;
    index++;
  }

  return found;
}

class _StrictJsonScanner {
  _StrictJsonScanner(this.source, {required this.maxDepth});

  final String source;
  final int maxDepth;
  int _index = 0;

  void scan() {
    _skipWhitespace();
    _scanValue(0);
    _skipWhitespace();
    if (_index != source.length) {
      _fail('unexpected trailing data');
    }
  }

  void _scanValue(int depth) {
    _checkDepth(depth);
    _skipWhitespace();
    if (_index >= source.length) {
      _fail('unexpected end of input');
    }
    switch (source.codeUnitAt(_index)) {
      case 0x7b: // {
        _scanObject(depth + 1);
      case 0x5b: // [
        _scanArray(depth + 1);
      case 0x22: // "
        _scanString();
      default:
        _scanPrimitive();
    }
  }

  void _scanObject(int depth) {
    _checkDepth(depth);
    _expect(0x7b);
    _skipWhitespace();
    if (_consume(0x7d)) {
      return;
    }

    final keys = <String>{};
    while (true) {
      _skipWhitespace();
      if (_index >= source.length || source.codeUnitAt(_index) != 0x22) {
        _fail('object key must be a JSON string');
      }
      final key = _scanString();
      if (!keys.add(key)) {
        _fail('duplicate object key');
      }
      _skipWhitespace();
      _expect(0x3a); // :
      _scanValue(depth);
      _skipWhitespace();
      if (_consume(0x7d)) {
        return;
      }
      _expect(0x2c); // ,
    }
  }

  void _scanArray(int depth) {
    _checkDepth(depth);
    _expect(0x5b);
    _skipWhitespace();
    if (_consume(0x5d)) {
      return;
    }
    while (true) {
      _scanValue(depth);
      _skipWhitespace();
      if (_consume(0x5d)) {
        return;
      }
      _expect(0x2c);
    }
  }

  String _scanString() {
    final start = _index;
    _expect(0x22);
    var escaped = false;
    while (_index < source.length) {
      final code = source.codeUnitAt(_index++);
      if (escaped) {
        escaped = false;
        continue;
      }
      if (code == 0x5c) {
        escaped = true;
        continue;
      }
      if (code == 0x22) {
        final token = source.substring(start, _index);
        try {
          return jsonDecode(token) as String;
        } on FormatException {
          _fail('invalid JSON string');
        }
      }
      if (code < 0x20) {
        _fail('unescaped control character in string');
      }
    }
    _fail('unterminated JSON string');
  }

  void _scanPrimitive() {
    final start = _index;
    while (_index < source.length) {
      final code = source.codeUnitAt(_index);
      if (_isWhitespace(code) || code == 0x2c || code == 0x5d || code == 0x7d) {
        break;
      }
      _index++;
    }
    if (_index == start) {
      _fail('expected a JSON value');
    }
    final token = source.substring(start, _index);
    try {
      jsonDecode(token);
    } on FormatException {
      _fail('invalid JSON literal');
    }
  }

  void _skipWhitespace() {
    while (_index < source.length && _isWhitespace(source.codeUnitAt(_index))) {
      _index++;
    }
  }

  void _checkDepth(int depth) {
    if (depth > maxDepth) {
      _fail('JSON nesting exceeds $maxDepth levels');
    }
  }

  bool _consume(int expected) {
    if (_index < source.length && source.codeUnitAt(_index) == expected) {
      _index++;
      return true;
    }
    return false;
  }

  void _expect(int expected) {
    if (!_consume(expected)) {
      _fail('expected "${String.fromCharCode(expected)}"');
    }
  }

  Never _fail(String message) {
    // Never attach attacker-controlled JSON as FormatException.source: Dart's
    // toString() includes a source excerpt, and these errors may be persisted
    // in application diagnostics next to provider credentials or extensions.
    throw FormatException('$message at character $_index');
  }

  static bool _isWhitespace(int code) =>
      code == 0x20 || code == 0x0a || code == 0x0d || code == 0x09;
}

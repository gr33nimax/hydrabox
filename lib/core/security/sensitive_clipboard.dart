import 'dart:async';

import 'package:flutter/services.dart';

/// Copies a secret and clears it later without overwriting newer clipboard data.
class SensitiveClipboard {
  SensitiveClipboard._();

  static const defaultLifetime = Duration(minutes: 1);
  static Timer? _clearTimer;
  static int _generation = 0;

  static Future<void> copy(
    String value, {
    Duration clearAfter = defaultLifetime,
  }) async {
    final generation = ++_generation;
    _clearTimer?.cancel();
    await Clipboard.setData(ClipboardData(text: value));
    _clearTimer = Timer(clearAfter, () async {
      if (generation != _generation) return;
      try {
        final current = await Clipboard.getData(Clipboard.kTextPlain);
        if (generation == _generation && current?.text == value) {
          await Clipboard.setData(const ClipboardData(text: ''));
        }
      } on PlatformException {
        // Clipboard access can be denied while the app is in the background.
      }
    });
  }
}

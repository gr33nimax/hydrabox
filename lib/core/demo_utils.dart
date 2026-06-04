import 'package:flutter/material.dart';

bool isRu(BuildContext context) =>
    Localizations.localeOf(context).languageCode.toLowerCase() == 'ru';

String countryEmoji(String code) {
  if (code.length != 2) return '🌐';
  final upper = code.toUpperCase();
  final first = upper.codeUnitAt(0) + 127397;
  final second = upper.codeUnitAt(1) + 127397;
  return String.fromCharCodes([first, second]);
}

String formatBytes(double bytes) {
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var value = bytes;
  var unitIndex = 0;
  while (value >= 1024 && unitIndex < units.length - 1) {
    value /= 1024;
    unitIndex++;
  }
  final precision = value >= 100
      ? 0
      : value >= 10
      ? 1
      : 2;
  return '${value.toStringAsFixed(precision)} ${units[unitIndex]}';
}

String formatSpeed(double bytesPerSecond) => '${formatBytes(bytesPerSecond)}/s';

String formatTime(DateTime value) {
  final hours = value.hour.toString().padLeft(2, '0');
  final minutes = value.minute.toString().padLeft(2, '0');
  final seconds = value.second.toString().padLeft(2, '0');
  return '$hours:$minutes:$seconds';
}

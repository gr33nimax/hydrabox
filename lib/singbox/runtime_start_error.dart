class RuntimeInvalidOutboundError {
  const RuntimeInvalidOutboundError({
    required this.outboundIndex,
    required this.reason,
  });

  final int outboundIndex;
  final String reason;
}

RuntimeInvalidOutboundError? parseRuntimeInvalidOutboundError(String error) {
  final normalized = error.trim().replaceFirst(
    RegExp(r',\s*null,\s*null\)\s*$'),
    '',
  );
  if (normalized.isEmpty) {
    return null;
  }

  final initializeMatch = RegExp(
    r'initialize outbound\[(\d+)\]:\s*(.+)$',
    caseSensitive: false,
  ).firstMatch(normalized);
  if (initializeMatch != null) {
    final outboundIndex = int.tryParse(initializeMatch.group(1) ?? '');
    final reason = (initializeMatch.group(2) ?? '').trim();
    if (outboundIndex != null && reason.isNotEmpty) {
      return RuntimeInvalidOutboundError(
        outboundIndex: outboundIndex,
        reason: reason,
      );
    }
  }

  final decodeMatch = RegExp(
    r'decode config:\s*outbounds\[(\d+)\](?:\.(.+))?$',
    caseSensitive: false,
  ).firstMatch(normalized);
  if (decodeMatch != null) {
    final outboundIndex = int.tryParse(decodeMatch.group(1) ?? '');
    final reason = (decodeMatch.group(2) ?? '').trim();
    if (outboundIndex != null && reason.isNotEmpty) {
      return RuntimeInvalidOutboundError(
        outboundIndex: outboundIndex,
        reason: reason,
      );
    }
  }

  return null;
}

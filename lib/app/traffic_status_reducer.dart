class RuntimeTrafficStatus {
  const RuntimeTrafficStatus({
    required this.uplinkBytesPerSecond,
    required this.downlinkBytesPerSecond,
    required this.uplinkTotalBytes,
    required this.downlinkTotalBytes,
    required this.available,
  });

  const RuntimeTrafficStatus.zero()
    : uplinkBytesPerSecond = 0,
      downlinkBytesPerSecond = 0,
      uplinkTotalBytes = 0,
      downlinkTotalBytes = 0,
      available = false;

  final int uplinkBytesPerSecond;
  final int downlinkBytesPerSecond;
  final int uplinkTotalBytes;
  final int downlinkTotalBytes;
  final bool available;

  int get totalBytes => uplinkTotalBytes + downlinkTotalBytes;

  @override
  bool operator ==(Object other) {
    return other is RuntimeTrafficStatus &&
        other.uplinkBytesPerSecond == uplinkBytesPerSecond &&
        other.downlinkBytesPerSecond == downlinkBytesPerSecond &&
        other.uplinkTotalBytes == uplinkTotalBytes &&
        other.downlinkTotalBytes == downlinkTotalBytes &&
        other.available == available;
  }

  @override
  int get hashCode => Object.hash(
    uplinkBytesPerSecond,
    downlinkBytesPerSecond,
    uplinkTotalBytes,
    downlinkTotalBytes,
    available,
  );
}

class RuntimeTrafficEvent {
  const RuntimeTrafficEvent({
    required this.uplinkBytesPerSecond,
    required this.downlinkBytesPerSecond,
    required this.uplinkTotalBytes,
    required this.downlinkTotalBytes,
    required this.availableHint,
  });

  factory RuntimeTrafficEvent.fromMap(Map<String, dynamic> event) {
    return RuntimeTrafficEvent(
      uplinkBytesPerSecond: (event['uplink'] as num?)?.toInt() ?? 0,
      downlinkBytesPerSecond: (event['downlink'] as num?)?.toInt() ?? 0,
      uplinkTotalBytes: (event['uplinkTotal'] as num?)?.toInt() ?? 0,
      downlinkTotalBytes: (event['downlinkTotal'] as num?)?.toInt() ?? 0,
      availableHint: event['trafficAvailable'] == true,
    );
  }

  final int uplinkBytesPerSecond;
  final int downlinkBytesPerSecond;
  final int uplinkTotalBytes;
  final int downlinkTotalBytes;
  final bool availableHint;

  int get totalBytes => uplinkTotalBytes + downlinkTotalBytes;

  bool get available =>
      availableHint ||
      uplinkBytesPerSecond > 0 ||
      downlinkBytesPerSecond > 0 ||
      totalBytes > 0;
}

class TrafficStatusReduction {
  const TrafficStatusReduction({
    required this.status,
    required this.preservedTotals,
  });

  final RuntimeTrafficStatus status;
  final bool preservedTotals;
}

/// Reduces EventChannel and `status()` traffic snapshots into one monotonic
/// stream. A late native snapshot is allowed to update speed, but may not make
/// accumulated totals jump backwards while the runtime is still active.
class TrafficStatusReducer {
  const TrafficStatusReducer();

  TrafficStatusReduction reduce({
    required RuntimeTrafficStatus current,
    required RuntimeTrafficEvent event,
  }) {
    final preserveUplink =
        current.available &&
        event.available &&
        current.uplinkTotalBytes > event.uplinkTotalBytes;
    final preserveDownlink =
        current.available &&
        event.available &&
        current.downlinkTotalBytes > event.downlinkTotalBytes;
    final preservedTotals = preserveUplink || preserveDownlink;
    return TrafficStatusReduction(
      preservedTotals: preservedTotals,
      status: RuntimeTrafficStatus(
        uplinkBytesPerSecond: event.uplinkBytesPerSecond,
        downlinkBytesPerSecond: event.downlinkBytesPerSecond,
        uplinkTotalBytes: preserveUplink
            ? current.uplinkTotalBytes
            : event.uplinkTotalBytes,
        downlinkTotalBytes: preserveDownlink
            ? current.downlinkTotalBytes
            : event.downlinkTotalBytes,
        available: event.available,
      ),
    );
  }
}

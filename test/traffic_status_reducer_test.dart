import 'package:flutter_test/flutter_test.dart';
import 'package:hydrabox/app/traffic_status_reducer.dart';

void main() {
  const reducer = TrafficStatusReducer();

  test(
    'derives availability from traffic when native availability is absent',
    () {
      final reduction = reducer.reduce(
        current: const RuntimeTrafficStatus.zero(),
        event: const RuntimeTrafficEvent(
          uplinkBytesPerSecond: 0,
          downlinkBytesPerSecond: 128,
          uplinkTotalBytes: 32,
          downlinkTotalBytes: 256,
          availableHint: false,
        ),
      );

      expect(reduction.status.available, isTrue);
      expect(reduction.preservedTotals, isFalse);
      expect(reduction.status.downlinkTotalBytes, 256);
    },
  );

  test('keeps accumulated totals when a late snapshot is behind', () {
    final reduction = reducer.reduce(
      current: const RuntimeTrafficStatus(
        uplinkBytesPerSecond: 10,
        downlinkBytesPerSecond: 20,
        uplinkTotalBytes: 500,
        downlinkTotalBytes: 1000,
        available: true,
      ),
      event: const RuntimeTrafficEvent(
        uplinkBytesPerSecond: 30,
        downlinkBytesPerSecond: 40,
        uplinkTotalBytes: 200,
        downlinkTotalBytes: 800,
        availableHint: true,
      ),
    );

    expect(reduction.preservedTotals, isTrue);
    expect(reduction.status.uplinkBytesPerSecond, 30);
    expect(reduction.status.downlinkBytesPerSecond, 40);
    expect(reduction.status.uplinkTotalBytes, 500);
    expect(reduction.status.downlinkTotalBytes, 1000);
  });

  test('accepts a reset snapshot after traffic became unavailable', () {
    final reduction = reducer.reduce(
      current: const RuntimeTrafficStatus.zero(),
      event: const RuntimeTrafficEvent(
        uplinkBytesPerSecond: 0,
        downlinkBytesPerSecond: 0,
        uplinkTotalBytes: 0,
        downlinkTotalBytes: 0,
        availableHint: false,
      ),
    );

    expect(reduction.preservedTotals, isFalse);
    expect(reduction.status, const RuntimeTrafficStatus.zero());
  });

  test('accepts newer accumulated totals', () {
    final reduction = reducer.reduce(
      current: const RuntimeTrafficStatus(
        uplinkBytesPerSecond: 0,
        downlinkBytesPerSecond: 0,
        uplinkTotalBytes: 25,
        downlinkTotalBytes: 75,
        available: true,
      ),
      event: const RuntimeTrafficEvent(
        uplinkBytesPerSecond: 1,
        downlinkBytesPerSecond: 2,
        uplinkTotalBytes: 50,
        downlinkTotalBytes: 150,
        availableHint: true,
      ),
    );

    expect(reduction.preservedTotals, isFalse);
    expect(reduction.status.totalBytes, 200);
  });

  test('preserves a regressed upload even when the combined total grew', () {
    final reduction = reducer.reduce(
      current: const RuntimeTrafficStatus(
        uplinkBytesPerSecond: 10,
        downlinkBytesPerSecond: 20,
        uplinkTotalBytes: 500,
        downlinkTotalBytes: 100,
        available: true,
      ),
      event: const RuntimeTrafficEvent(
        uplinkBytesPerSecond: 30,
        downlinkBytesPerSecond: 40,
        uplinkTotalBytes: 0,
        downlinkTotalBytes: 800,
        availableHint: true,
      ),
    );

    expect(reduction.preservedTotals, isTrue);
    expect(reduction.status.uplinkTotalBytes, 500);
    expect(reduction.status.downlinkTotalBytes, 800);
    expect(reduction.status.totalBytes, 1300);
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:hydrabox/data/adblock/ad_block_rule_set_service.dart';

void main() {
  test('adblock byte progress is bounded', () {
    expect(
      const AdBlockUpdateProgress(
        stage: AdBlockUpdateStage.downloading,
        completedBytes: 25,
        totalBytes: 100,
      ).fraction,
      0.25,
    );
    expect(
      const AdBlockUpdateProgress(
        stage: AdBlockUpdateStage.downloading,
        completedBytes: 125,
        totalBytes: 100,
      ).fraction,
      1,
    );
    expect(
      const AdBlockUpdateProgress(
        stage: AdBlockUpdateStage.connecting,
      ).fraction,
      isNull,
    );
  });

  test('adblock ETA is derived only from measurable downloads', () {
    expect(
      const AdBlockUpdateProgress(
        stage: AdBlockUpdateStage.downloading,
        completedBytes: 250,
        totalBytes: 1000,
        elapsedMilliseconds: 1000,
      ).estimatedSecondsRemaining,
      3,
    );
    expect(
      const AdBlockUpdateProgress(
        stage: AdBlockUpdateStage.compiling,
        completedBytes: 1000,
        totalBytes: 1000,
        elapsedMilliseconds: 1000,
      ).estimatedSecondsRemaining,
      isNull,
    );
  });
}

import 'package:al_amin/domain/reset_epoch.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ResetEpoch.isCurrent', () {
    final resetAt = DateTime.utc(2026, 10, 5, 12);

    test('a tagged change is current only when its token equals the device token', () {
      expect(ResetEpoch.isCurrent('R2', 'R2'), isTrue);
      expect(ResetEpoch.isCurrent('R1', 'R2'), isFalse);
      expect(ResetEpoch.isCurrent('R1', ''), isFalse);
    });

    test('before any reset, untagged changes are accepted', () {
      expect(ResetEpoch.isCurrent(null, ''), isTrue);
      expect(ResetEpoch.isCurrent('', ''), isTrue);
    });

    test('after a reset, untagged changes made before it are rejected', () {
      expect(
        ResetEpoch.isCurrent(null, 'R1',
            changeCreatedAt: resetAt.subtract(const Duration(minutes: 1)), epochStart: resetAt),
        isFalse,
      );
    });

    test('after a reset, untagged changes made after it (older app version) are accepted', () {
      expect(
        ResetEpoch.isCurrent(null, 'R1',
            changeCreatedAt: resetAt.add(const Duration(minutes: 1)), epochStart: resetAt),
        isTrue,
      );
    });

    test('untagged changes without timestamps are rejected after a reset', () {
      expect(ResetEpoch.isCurrent(null, 'R1'), isFalse);
      expect(ResetEpoch.isCurrent(null, 'R1', epochStart: resetAt), isFalse);
    });
  });

  group('ResetEpoch other rules', () {
    test('a reset is pending only when Firebase holds a token this device lacks', () {
      expect(ResetEpoch.resetPending(remoteToken: '', appliedToken: ''), isFalse);
      expect(ResetEpoch.resetPending(remoteToken: 'R1', appliedToken: 'R1'), isFalse);
      expect(ResetEpoch.resetPending(remoteToken: 'R2', appliedToken: 'R1'), isTrue);
      expect(ResetEpoch.resetPending(remoteToken: 'R1', appliedToken: ''), isTrue);
    });

    test('devices on different generations must not exchange data', () {
      expect(ResetEpoch.sameGeneration('R1', 'R1'), isTrue);
      expect(ResetEpoch.sameGeneration('R1', ''), isFalse);
    });
  });
}

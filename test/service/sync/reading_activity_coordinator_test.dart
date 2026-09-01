import 'package:anx_reader/service/sync/reading_activity_coordinator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('automatic work is coalesced while any reading session is active', () {
    final coordinator = ReadingActivityCoordinator();
    final firstSession = Object();
    final secondSession = Object();

    coordinator.startReading(firstSession);
    coordinator.startReading(secondSession);

    expect(coordinator.state, ReadingActivityState.activeReading);
    expect(coordinator.deferAutomaticSyncIfReading(), isTrue);
    expect(coordinator.deferAutomaticSyncIfReading(), isTrue);
    expect(coordinator.hasPendingAutomaticSync, isTrue);

    coordinator.finishReading(firstSession);
    expect(coordinator.state, ReadingActivityState.activeReading);
    coordinator.finishReading(secondSession);
    expect(coordinator.state, ReadingActivityState.idle);
    expect(coordinator.consumePendingAutomaticSync(), isTrue);
    expect(coordinator.consumePendingAutomaticSync(), isFalse);
  });

  test('background waits for the reading checkpoint before permitting work',
      () {
    final coordinator = ReadingActivityCoordinator();
    final session = Object();

    coordinator.startReading(session);
    expect(coordinator.deferAutomaticSyncIfReading(), isTrue);

    coordinator.enterBackground();
    expect(coordinator.state, ReadingActivityState.background);
    expect(coordinator.deferAutomaticSyncIfReading(), isTrue);

    coordinator.permitBackgroundFlush();
    expect(coordinator.deferAutomaticSyncIfReading(), isFalse);
    expect(coordinator.consumePendingAutomaticSync(), isTrue);

    coordinator.enterForeground();
    expect(coordinator.state, ReadingActivityState.activeReading);
  });

  test('manual or idle callers do not create a pending intent', () {
    final coordinator = ReadingActivityCoordinator();

    expect(coordinator.state, ReadingActivityState.idle);
    expect(coordinator.deferAutomaticSyncIfReading(), isFalse);
    expect(coordinator.hasPendingAutomaticSync, isFalse);
  });
}

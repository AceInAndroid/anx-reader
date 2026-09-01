import 'dart:async';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/service/reading_experience_diagnostics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
  });

  test('keeps counters in memory until the reading session ends', () async {
    final batteryLevels = <int>[82, 79];
    final diagnostics = ReadingExperienceDiagnostics(
      batteryLevelReader: () async => batteryLevels.removeAt(0),
    );

    await diagnostics.beginSession(bookId: 7);
    diagnostics.recordAutomaticSyncRequest();
    diagnostics.recordSyncDeferred();
    diagnostics.recordNextActionShown();
    diagnostics.recordNextActionExecuted();
    diagnostics.recordModelRequest(
      elapsed: const Duration(milliseconds: 450),
      retries: 1,
      validationRejections: 2,
    );

    expect(
      Prefs().prefs.getString(readingExperienceDiagnosticsStorageKey),
      isNull,
    );

    await diagnostics.endSession();
    final summary = await diagnostics.summary();

    expect(summary.sessionCount, 1);
    expect(summary.batteryDelta, 3);
    expect(summary.automaticSyncRequests, 1);
    expect(summary.syncDeferred, 1);
    expect(summary.modelRequests, 1);
    expect(summary.modelRetries, 1);
    expect(summary.validationRejections, 2);
    expect(summary.nextActionShown, 1);
    expect(summary.nextActionExecuted, 1);
  });

  test('clear removes only the local diagnostics payload', () async {
    final diagnostics = ReadingExperienceDiagnostics(
      batteryLevelReader: () async => 50,
    );
    await diagnostics.beginSession(bookId: 9);
    await diagnostics.endSession();

    await diagnostics.clear();

    expect(await diagnostics.loadSessions(), isEmpty);
  });

  test('ending during the initial battery read does not orphan a session',
      () async {
    final firstBattery = Completer<int?>();
    var reads = 0;
    final diagnostics = ReadingExperienceDiagnostics(
      batteryLevelReader: () {
        reads++;
        return reads == 1 ? firstBattery.future : Future.value(48);
      },
    );

    final starting = diagnostics.beginSession(bookId: 11);
    expect(diagnostics.isSessionActive, isTrue);
    await diagnostics.endSession();
    firstBattery.complete(50);
    await starting;

    expect(diagnostics.isSessionActive, isFalse);
    expect((await diagnostics.summary()).sessionCount, 1);
  });
}

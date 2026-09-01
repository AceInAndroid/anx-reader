import 'dart:convert';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:uuid/uuid.dart';

const readingExperienceDiagnosticsStorageKey =
    'readingExperienceDiagnostics.v1';

typedef BatteryLevelReader = Future<int?> Function();

class ReadingExperienceDiagnosticSession {
  const ReadingExperienceDiagnosticSession({
    required this.id,
    required this.bookId,
    required this.startedAt,
    required this.endedAt,
    required this.durationSeconds,
    this.batteryStart,
    this.batteryEnd,
    this.unsolicitedDialogs = 0,
    this.automaticSyncRequests = 0,
    this.syncExecutions = 0,
    this.syncMerged = 0,
    this.syncDeferred = 0,
    this.syncFailures = 0,
    this.modelRequests = 0,
    this.modelElapsedMilliseconds = 0,
    this.modelRetries = 0,
    this.validationRejections = 0,
    this.taskExecutions = 0,
    this.taskElapsedMilliseconds = 0,
    this.nextActionShown = 0,
    this.nextActionExecuted = 0,
    this.sourceJumps = 0,
    this.sourceReturns = 0,
  });

  final String id;
  final int bookId;
  final int startedAt;
  final int endedAt;
  final int durationSeconds;
  final int? batteryStart;
  final int? batteryEnd;
  final int unsolicitedDialogs;
  final int automaticSyncRequests;
  final int syncExecutions;
  final int syncMerged;
  final int syncDeferred;
  final int syncFailures;
  final int modelRequests;
  final int modelElapsedMilliseconds;
  final int modelRetries;
  final int validationRejections;
  final int taskExecutions;
  final int taskElapsedMilliseconds;
  final int nextActionShown;
  final int nextActionExecuted;
  final int sourceJumps;
  final int sourceReturns;

  int? get batteryDelta => batteryStart == null || batteryEnd == null
      ? null
      : batteryStart! - batteryEnd!;

  Map<String, Object?> toJson() => {
        'id': id,
        'bookId': bookId,
        'startedAt': startedAt,
        'endedAt': endedAt,
        'durationSeconds': durationSeconds,
        'batteryStart': batteryStart,
        'batteryEnd': batteryEnd,
        'unsolicitedDialogs': unsolicitedDialogs,
        'automaticSyncRequests': automaticSyncRequests,
        'syncExecutions': syncExecutions,
        'syncMerged': syncMerged,
        'syncDeferred': syncDeferred,
        'syncFailures': syncFailures,
        'modelRequests': modelRequests,
        'modelElapsedMilliseconds': modelElapsedMilliseconds,
        'modelRetries': modelRetries,
        'validationRejections': validationRejections,
        'taskExecutions': taskExecutions,
        'taskElapsedMilliseconds': taskElapsedMilliseconds,
        'nextActionShown': nextActionShown,
        'nextActionExecuted': nextActionExecuted,
        'sourceJumps': sourceJumps,
        'sourceReturns': sourceReturns,
      };

  factory ReadingExperienceDiagnosticSession.fromJson(
    Map<String, dynamic> json,
  ) =>
      ReadingExperienceDiagnosticSession(
        id: json['id'] as String? ?? '',
        bookId: json['bookId'] as int? ?? 0,
        startedAt: json['startedAt'] as int? ?? 0,
        endedAt: json['endedAt'] as int? ?? 0,
        durationSeconds: json['durationSeconds'] as int? ?? 0,
        batteryStart: json['batteryStart'] as int?,
        batteryEnd: json['batteryEnd'] as int?,
        unsolicitedDialogs: json['unsolicitedDialogs'] as int? ?? 0,
        automaticSyncRequests: json['automaticSyncRequests'] as int? ?? 0,
        syncExecutions: json['syncExecutions'] as int? ?? 0,
        syncMerged: json['syncMerged'] as int? ?? 0,
        syncDeferred: json['syncDeferred'] as int? ?? 0,
        syncFailures: json['syncFailures'] as int? ?? 0,
        modelRequests: json['modelRequests'] as int? ?? 0,
        modelElapsedMilliseconds: json['modelElapsedMilliseconds'] as int? ?? 0,
        modelRetries: json['modelRetries'] as int? ?? 0,
        validationRejections: json['validationRejections'] as int? ?? 0,
        taskExecutions: json['taskExecutions'] as int? ?? 0,
        taskElapsedMilliseconds: json['taskElapsedMilliseconds'] as int? ?? 0,
        nextActionShown: json['nextActionShown'] as int? ?? 0,
        nextActionExecuted: json['nextActionExecuted'] as int? ?? 0,
        sourceJumps: json['sourceJumps'] as int? ?? 0,
        sourceReturns: json['sourceReturns'] as int? ?? 0,
      );
}

class ReadingExperienceDiagnosticsSummary {
  const ReadingExperienceDiagnosticsSummary(this.sessions);

  final List<ReadingExperienceDiagnosticSession> sessions;

  int get sessionCount => sessions.length;
  int get readingSeconds =>
      sessions.fold(0, (sum, item) => sum + item.durationSeconds);
  int get automaticSyncRequests =>
      sessions.fold(0, (sum, item) => sum + item.automaticSyncRequests);
  int get syncExecutions =>
      sessions.fold(0, (sum, item) => sum + item.syncExecutions);
  int get syncMerged => sessions.fold(0, (sum, item) => sum + item.syncMerged);
  int get syncDeferred =>
      sessions.fold(0, (sum, item) => sum + item.syncDeferred);
  int get syncFailures =>
      sessions.fold(0, (sum, item) => sum + item.syncFailures);
  int get modelRequests =>
      sessions.fold(0, (sum, item) => sum + item.modelRequests);
  int get modelRetries =>
      sessions.fold(0, (sum, item) => sum + item.modelRetries);
  int get validationRejections =>
      sessions.fold(0, (sum, item) => sum + item.validationRejections);
  int get taskExecutions =>
      sessions.fold(0, (sum, item) => sum + item.taskExecutions);
  int get nextActionShown =>
      sessions.fold(0, (sum, item) => sum + item.nextActionShown);
  int get nextActionExecuted =>
      sessions.fold(0, (sum, item) => sum + item.nextActionExecuted);
  int get sourceJumps =>
      sessions.fold(0, (sum, item) => sum + item.sourceJumps);
  int get sourceReturns =>
      sessions.fold(0, (sum, item) => sum + item.sourceReturns);
  int get batteryDelta => sessions.fold(
        0,
        (sum, item) => sum + (item.batteryDelta?.clamp(0, 100) ?? 0),
      );
}

class ReadingExperienceDiagnostics {
  ReadingExperienceDiagnostics({BatteryLevelReader? batteryLevelReader})
      : _batteryLevelReader = batteryLevelReader ?? _readBatteryLevel;

  static const _retention = Duration(days: 30);
  static const _maxSessions = 100;
  final BatteryLevelReader _batteryLevelReader;
  _MutableDiagnosticSession? _active;
  final Map<String, int> _runningTasks = {};

  bool get isSessionActive => _active != null;

  Future<void> beginSession({required int bookId}) async {
    if (_active != null) await endSession();
    final now = DateTime.now().millisecondsSinceEpoch;
    final active = _MutableDiagnosticSession(
      id: const Uuid().v4(),
      bookId: bookId,
      startedAt: now,
      batteryStart: null,
    );
    // Publish the in-memory session before the platform battery call. If the
    // reader closes while that call is pending, endSession can still freeze
    // and persist the session instead of leaving a late orphan active.
    _active = active;
    final batteryStart = await _batteryLevelReader();
    if (identical(_active, active)) active.batteryStart = batteryStart;
  }

  Future<void> endSession() async {
    final active = _active;
    if (active == null) return;
    _active = null;
    final endedAt = DateTime.now().millisecondsSinceEpoch;
    final session = active.freeze(
      endedAt: endedAt,
      batteryEnd: await _batteryLevelReader(),
    );
    final sessions = await loadSessions();
    sessions.add(session);
    final cutoff = endedAt - _retention.inMilliseconds;
    sessions.removeWhere((item) => item.endedAt < cutoff);
    if (sessions.length > _maxSessions) {
      sessions.removeRange(0, sessions.length - _maxSessions);
    }
    await Prefs().prefs.setString(
          readingExperienceDiagnosticsStorageKey,
          jsonEncode(sessions.map((item) => item.toJson()).toList()),
        );
  }

  void recordUnsolicitedDialog() => _active?.unsolicitedDialogs++;
  void recordAutomaticSyncRequest() => _active?.automaticSyncRequests++;
  void recordSyncExecution() => _active?.syncExecutions++;
  void recordSyncMerged() => _active?.syncMerged++;
  void recordSyncDeferred() => _active?.syncDeferred++;
  void recordSyncFailure() => _active?.syncFailures++;
  void recordNextActionShown() => _active?.nextActionShown++;
  void recordNextActionExecuted() => _active?.nextActionExecuted++;
  void recordSourceJump() => _active?.sourceJumps++;
  void recordSourceReturn() => _active?.sourceReturns++;

  void recordModelRequest({
    required Duration elapsed,
    required int retries,
    required int validationRejections,
  }) {
    final active = _active;
    if (active == null) return;
    active.modelRequests++;
    active.modelElapsedMilliseconds += elapsed.inMilliseconds;
    active.modelRetries += retries;
    active.validationRejections += validationRejections;
  }

  void recordTaskStarted(String taskId) {
    if (_active == null) return;
    _runningTasks[taskId] = DateTime.now().millisecondsSinceEpoch;
  }

  void recordTaskFinished(String taskId) {
    final startedAt = _runningTasks.remove(taskId);
    final active = _active;
    if (startedAt == null || active == null) return;
    active.taskExecutions++;
    active.taskElapsedMilliseconds +=
        DateTime.now().millisecondsSinceEpoch - startedAt;
  }

  Future<List<ReadingExperienceDiagnosticSession>> loadSessions() async {
    final raw = Prefs().prefs.getString(readingExperienceDiagnosticsStorageKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .whereType<Map>()
          .map(
            (item) => ReadingExperienceDiagnosticSession.fromJson(
              Map<String, dynamic>.from(item),
            ),
          )
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<ReadingExperienceDiagnosticsSummary> summary() async =>
      ReadingExperienceDiagnosticsSummary(await loadSessions());

  Future<void> clear() async {
    await Prefs().prefs.remove(readingExperienceDiagnosticsStorageKey);
  }

  static Future<int?> _readBatteryLevel() async {
    try {
      return await Battery().batteryLevel;
    } catch (_) {
      return null;
    }
  }
}

class _MutableDiagnosticSession {
  _MutableDiagnosticSession({
    required this.id,
    required this.bookId,
    required this.startedAt,
    required this.batteryStart,
  });

  final String id;
  final int bookId;
  final int startedAt;
  int? batteryStart;
  int unsolicitedDialogs = 0;
  int automaticSyncRequests = 0;
  int syncExecutions = 0;
  int syncMerged = 0;
  int syncDeferred = 0;
  int syncFailures = 0;
  int modelRequests = 0;
  int modelElapsedMilliseconds = 0;
  int modelRetries = 0;
  int validationRejections = 0;
  int taskExecutions = 0;
  int taskElapsedMilliseconds = 0;
  int nextActionShown = 0;
  int nextActionExecuted = 0;
  int sourceJumps = 0;
  int sourceReturns = 0;

  ReadingExperienceDiagnosticSession freeze({
    required int endedAt,
    required int? batteryEnd,
  }) =>
      ReadingExperienceDiagnosticSession(
        id: id,
        bookId: bookId,
        startedAt: startedAt,
        endedAt: endedAt,
        durationSeconds: Duration(milliseconds: endedAt - startedAt).inSeconds,
        batteryStart: batteryStart,
        batteryEnd: batteryEnd,
        unsolicitedDialogs: unsolicitedDialogs,
        automaticSyncRequests: automaticSyncRequests,
        syncExecutions: syncExecutions,
        syncMerged: syncMerged,
        syncDeferred: syncDeferred,
        syncFailures: syncFailures,
        modelRequests: modelRequests,
        modelElapsedMilliseconds: modelElapsedMilliseconds,
        modelRetries: modelRetries,
        validationRejections: validationRejections,
        taskExecutions: taskExecutions,
        taskElapsedMilliseconds: taskElapsedMilliseconds,
        nextActionShown: nextActionShown,
        nextActionExecuted: nextActionExecuted,
        sourceJumps: sourceJumps,
        sourceReturns: sourceReturns,
      );
}

final readingExperienceDiagnostics = ReadingExperienceDiagnostics();

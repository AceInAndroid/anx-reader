import 'dart:convert';

enum ReadingGoalStatus { active, completed, abandoned }

enum ReaderProfileStatus { candidate, confirmed, rejected }

enum AgentActionStatus { applied, undone, conflict }

enum AgentActionType { goal, profile, note, difficulty }

/// A durable reading outcome. Interpretation-based criteria are deliberately
/// represented as user-confirmed booleans; only [progress] is automatic.
class ReadingGoal {
  const ReadingGoal({
    required this.id,
    required this.bookId,
    required this.title,
    this.range = const {},
    this.timeBudgetMinutes,
    this.criteria = const [],
    this.progress = 0,
    this.status = ReadingGoalStatus.active,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final int bookId;
  final String title;
  final Map<String, dynamic> range;
  final int? timeBudgetMinutes;
  final List<Map<String, dynamic>> criteria;
  final double progress;
  final ReadingGoalStatus status;
  final int createdAt;
  final int updatedAt;

  ReadingGoal copyWith({
    String? title,
    Map<String, dynamic>? range,
    int? timeBudgetMinutes,
    bool clearTimeBudget = false,
    List<Map<String, dynamic>>? criteria,
    double? progress,
    ReadingGoalStatus? status,
    int? updatedAt,
  }) =>
      ReadingGoal(
        id: id,
        bookId: bookId,
        title: title ?? this.title,
        range: range ?? this.range,
        timeBudgetMinutes: clearTimeBudget
            ? null
            : timeBudgetMinutes ?? this.timeBudgetMinutes,
        criteria: criteria ?? this.criteria,
        progress: progress ?? this.progress,
        status: status ?? this.status,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  Map<String, Object?> toDb() => {
        'id': id,
        'book_id': bookId,
        'title': title,
        'range_json': jsonEncode(range),
        'time_budget_minutes': timeBudgetMinutes,
        'criteria_json': jsonEncode(criteria),
        'progress': progress,
        'status': status.name,
        'created_at': createdAt,
        'updated_at': updatedAt,
      };

  factory ReadingGoal.fromDb(Map<String, dynamic> row) => ReadingGoal(
        id: row['id'].toString(),
        bookId: _asInt(row['book_id']),
        title: row['title']?.toString() ?? '',
        range: _map(row['range_json']),
        timeBudgetMinutes: row['time_budget_minutes'] == null
            ? null
            : _asInt(row['time_budget_minutes']),
        criteria: _mapList(row['criteria_json']),
        progress: _asDouble(row['progress']),
        status: _enumByName(
          ReadingGoalStatus.values,
          row['status'],
          ReadingGoalStatus.active,
        ),
        createdAt: _asInt(row['created_at']),
        updatedAt: _asInt(row['updated_at']),
      );
}

class ReaderProfileItem {
  const ReaderProfileItem({
    required this.key,
    this.value = const {},
    this.status = ReaderProfileStatus.candidate,
    this.confidence = 0,
    this.evidenceSessionIds = const [],
    this.rejectedUntil,
    required this.createdAt,
    required this.updatedAt,
  });

  final String key;
  final Map<String, dynamic> value;
  final ReaderProfileStatus status;
  final double confidence;
  final List<String> evidenceSessionIds;
  int get evidenceCount => evidenceSessionIds.length;
  final int? rejectedUntil;
  final int createdAt;
  final int updatedAt;

  ReaderProfileItem copyWith({
    Map<String, dynamic>? value,
    ReaderProfileStatus? status,
    double? confidence,
    List<String>? evidenceSessionIds,
    int? rejectedUntil,
    bool clearRejectedUntil = false,
    int? updatedAt,
  }) =>
      ReaderProfileItem(
        key: key,
        value: value ?? this.value,
        status: status ?? this.status,
        confidence: confidence ?? this.confidence,
        evidenceSessionIds: evidenceSessionIds ?? this.evidenceSessionIds,
        rejectedUntil:
            clearRejectedUntil ? null : rejectedUntil ?? this.rejectedUntil,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  Map<String, Object?> toDb() => {
        'profile_key': key,
        'value_json': jsonEncode(value),
        'status': status.name,
        'confidence': confidence,
        'evidence_count': evidenceCount,
        'evidence_sessions_json': jsonEncode(evidenceSessionIds),
        'rejected_until': rejectedUntil,
        'created_at': createdAt,
        'updated_at': updatedAt,
      };

  factory ReaderProfileItem.fromDb(Map<String, dynamic> row) =>
      ReaderProfileItem(
        key: row['profile_key'].toString(),
        value: _map(row['value_json']),
        status: _enumByName(
          ReaderProfileStatus.values,
          row['status'],
          ReaderProfileStatus.candidate,
        ),
        confidence: _asDouble(row['confidence']),
        evidenceSessionIds: _stringList(row['evidence_sessions_json']),
        rejectedUntil: row['rejected_until'] == null
            ? null
            : _asInt(row['rejected_until']),
        createdAt: _asInt(row['created_at']),
        updatedAt: _asInt(row['updated_at']),
      );
}

class AgentAction {
  const AgentAction({
    required this.id,
    required this.type,
    required this.targetId,
    this.bookId,
    required this.beforeSnapshot,
    required this.afterSnapshot,
    required this.afterHash,
    this.status = AgentActionStatus.applied,
    required this.sessionId,
    required this.createdAt,
    required this.expiresAt,
    this.undoneAt,
  });

  final String id;
  final AgentActionType type;
  final String targetId;
  final int? bookId;
  final Map<String, dynamic>? beforeSnapshot;
  final Map<String, dynamic>? afterSnapshot;
  final String afterHash;
  final AgentActionStatus status;
  final String sessionId;
  final int createdAt;
  final int expiresAt;
  final int? undoneAt;

  Map<String, Object?> toDb() => {
        'id': id,
        'action_type': type.name,
        'target_id': targetId,
        'book_id': bookId,
        'before_snapshot':
            beforeSnapshot == null ? null : jsonEncode(beforeSnapshot),
        'after_snapshot':
            afterSnapshot == null ? null : jsonEncode(afterSnapshot),
        'after_hash': afterHash,
        'status': status.name,
        'session_id': sessionId,
        'created_at': createdAt,
        'expires_at': expiresAt,
        'undone_at': undoneAt,
      };

  factory AgentAction.fromDb(Map<String, dynamic> row) => AgentAction(
        id: row['id'].toString(),
        type: _enumByName(
            AgentActionType.values, row['action_type'], AgentActionType.goal),
        targetId: row['target_id'].toString(),
        bookId: row['book_id'] == null ? null : _asInt(row['book_id']),
        beforeSnapshot: row['before_snapshot'] == null
            ? null
            : _map(row['before_snapshot']),
        afterSnapshot:
            row['after_snapshot'] == null ? null : _map(row['after_snapshot']),
        afterHash: row['after_hash']?.toString() ?? '',
        status: _enumByName(
          AgentActionStatus.values,
          row['status'],
          AgentActionStatus.applied,
        ),
        sessionId: row['session_id']?.toString() ?? '',
        createdAt: _asInt(row['created_at']),
        expiresAt: _asInt(row['expires_at']),
        undoneAt: row['undone_at'] == null ? null : _asInt(row['undone_at']),
      );
}

enum UndoResult { undone, alreadyUndone, expired, conflict, missing }

class AgentMutation<T> {
  const AgentMutation({required this.value, required this.action});
  final T value;
  final AgentAction action;
}

T _enumByName<T extends Enum>(List<T> values, Object? raw, T fallback) =>
    values.where((value) => value.name == raw?.toString()).firstOrNull ??
    fallback;

int _asInt(Object? value) => value is int
    ? value
    : value is num
        ? value.toInt()
        : int.tryParse(value?.toString() ?? '') ?? 0;

double _asDouble(Object? value) => value is num
    ? value.toDouble()
    : double.tryParse(value?.toString() ?? '') ?? 0;

Map<String, dynamic> _map(Object? value) {
  if (value is Map) return Map<String, dynamic>.from(value);
  if (value is! String || value.isEmpty) return const {};
  final decoded = jsonDecode(value);
  return decoded is Map ? Map<String, dynamic>.from(decoded) : const {};
}

List<Map<String, dynamic>> _mapList(Object? value) {
  final decoded = value is String ? jsonDecode(value) : value;
  return decoded is List
      ? decoded
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList(growable: false)
      : const [];
}

List<String> _stringList(Object? value) {
  final decoded = value is String ? jsonDecode(value) : value;
  return decoded is List
      ? decoded.map((item) => item.toString()).toList(growable: false)
      : const [];
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

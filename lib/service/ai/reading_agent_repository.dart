import 'dart:convert';

import 'package:anx_reader/dao/reading_agent.dart';
import 'package:anx_reader/models/reading_agent.dart';
import 'package:anx_reader/models/reading_coach.dart';
import 'package:anx_reader/models/book_note.dart';
import 'package:anx_reader/models/reading_note.dart';
import 'package:crypto/crypto.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

const supportedReaderProfileKeys = {
  'explanationDepth',
  'explanationOrder',
  'teachingStyle',
  'outputStructure',
  'interruptionTolerance',
};

class ReadingAgentRepository {
  ReadingAgentRepository({
    ReadingAgentDao? dao,
    Uuid? uuid,
    int Function()? clock,
  })  : _dao = dao ?? readingAgentDao,
        _uuid = uuid ?? const Uuid(),
        _clock = clock ?? (() => DateTime.now().millisecondsSinceEpoch);

  static const retention = Duration(days: 30);
  static const rejectionSuppression = Duration(days: 90);
  static const maxActions = 200;

  final ReadingAgentDao _dao;
  final Uuid _uuid;
  final int Function() _clock;

  Future<ReadingGoal?> activeGoal(int bookId) => _dao.activeGoal(bookId);
  Future<List<ReadingGoal>> goals(int bookId) => _dao.goals(bookId);
  Future<List<ReadingChapterCheckpoint>> pendingCheckpoints(int bookId) =>
      _dao.pendingCheckpoints(bookId);
  Future<List<MasteryState>> masteryStates(int bookId) =>
      _dao.masteryStates(bookId);
  Future<List<KnowledgeCard>> dueKnowledgeCards(int bookId) =>
      _dao.dueKnowledgeCards(bookId, _clock());
  Future<List<ReadingMemoryDocument>> memoryDocuments(int bookId) =>
      _dao.memoryDocuments(bookId);

  Future<ReadingChapterCheckpoint> upsertCheckpoint(
      ReadingChapterCheckpoint checkpoint) async {
    await _dao.write((txn) async {
      await txn.insert('tb_reading_checkpoints', checkpoint.toDb(),
          conflictAlgorithm: ConflictAlgorithm.ignore);
    });
    return checkpoint;
  }

  Future<ReadingChapterCheckpoint> completeCheckpoint(
      ReadingChapterCheckpoint checkpoint,
      {required bool completed,
      String reflection = ''}) async {
    final updated = checkpoint.copyWith(
        status: completed
            ? ReadingCheckpointStatus.completed
            : ReadingCheckpointStatus.skipped,
        reflection: reflection,
        updatedAt: _clock());
    await _dao.write((txn) async {
      await txn.insert('tb_reading_checkpoints', updated.toDb(),
          conflictAlgorithm: ConflictAlgorithm.replace);
    });
    return updated;
  }

  Future<MasteryState> saveMastery(MasteryState state) async {
    await _dao.write((txn) async => txn.insert(
        'tb_reading_mastery', state.toDb(),
        conflictAlgorithm: ConflictAlgorithm.replace));
    return state;
  }

  Future<KnowledgeCard> saveKnowledgeCard(KnowledgeCard card) async {
    await _dao.write((txn) async => txn.insert(
        'tb_knowledge_cards', card.toDb(),
        conflictAlgorithm: ConflictAlgorithm.replace));
    return card;
  }

  Future<AgentMutation<ReadingMemoryDocument>> appendMemory(
      ReadingMemoryDocument document,
      {required String sessionId}) async {
    if (document.bookId <= 0 || document.markdown.trim().isEmpty) {
      throw ArgumentError('Markdown memory requires a book and content');
    }
    final now = _clock();
    return _dao.write((txn) async {
      final before = await _queryOne(
          txn, 'tb_reading_memory_documents', 'id = ?', [document.id]);
      await txn.insert('tb_reading_memory_documents', document.toDb(),
          conflictAlgorithm: ConflictAlgorithm.replace);
      final action = _action(
          type: AgentActionType.memory,
          targetId: document.id,
          bookId: document.bookId,
          sessionId: sessionId,
          before: before,
          after: document.toDb(),
          now: now);
      await _insertAction(txn, action, now);
      return AgentMutation(value: document, action: action);
    });
  }

  /// Location-derived progress is not a separate Agent action. Advance the
  /// latest goal-action snapshot with it so ordinary reading does not make an
  /// otherwise valid undo conflict immediately.
  Future<void> updateGoalProgress(ReadingGoal goal) => _dao.write((txn) async {
        await txn.update(
          'tb_reading_goals',
          {'progress': goal.progress, 'updated_at': goal.updatedAt},
          where: "id = ? AND status = 'active'",
          whereArgs: [goal.id],
        );
        final current = await _queryOne(
          txn,
          'tb_reading_goals',
          'id = ?',
          [goal.id],
        );
        if (current == null) return;
        final actions = await txn.query(
          'tb_agent_actions',
          where:
              "action_type = 'goal' AND target_id = ? AND status = 'applied'",
          whereArgs: [goal.id],
          orderBy: 'created_at DESC',
          limit: 1,
        );
        if (actions.isEmpty) return;
        await txn.update(
          'tb_agent_actions',
          {
            'after_snapshot': jsonEncode(current),
            'after_hash': _hash(current),
          },
          where: 'id = ?',
          whereArgs: [actions.first['id']],
        );
      });
  Future<List<ReaderProfileItem>> confirmedProfile() =>
      _dao.profileItems(status: ReaderProfileStatus.confirmed);
  Future<List<ReaderProfileItem>> profileCandidates() async =>
      (await _dao.profileItems(status: ReaderProfileStatus.candidate))
          .where((item) => item.confidence >= 1)
          .toList(growable: false);
  Future<List<AgentAction>> recentActions({int? bookId}) => _dao.recentActions(
        bookId: bookId,
        createdAfter: _clock() - retention.inMilliseconds,
        limit: maxActions,
      );

  Future<AgentMutation<ReadingGoal>> saveGoal(
    ReadingGoal goal, {
    required String sessionId,
  }) async {
    _validateGoal(goal);
    final now = _clock();
    return _dao.write((txn) async {
      final previousActive = await _queryOne(
        txn,
        'tb_reading_goals',
        "book_id = ? AND status = 'active'",
        [goal.bookId],
      );
      final targetBefore =
          await _queryOne(txn, 'tb_reading_goals', 'id = ?', [goal.id]);
      if (goal.status == ReadingGoalStatus.active) {
        await txn.update(
          'tb_reading_goals',
          {'status': ReadingGoalStatus.abandoned.name, 'updated_at': now},
          where: "book_id = ? AND status = 'active' AND id != ?",
          whereArgs: [goal.bookId, goal.id],
        );
      }
      await txn.insert('tb_reading_goals', goal.toDb(),
          conflictAlgorithm: ConflictAlgorithm.replace);
      final action = _action(
        type: AgentActionType.goal,
        targetId: goal.id,
        bookId: goal.bookId,
        sessionId: sessionId,
        before: {
          'target': targetBefore,
          'previousActive': previousActive,
        },
        after: goal.toDb(),
        now: now,
      );
      await _insertAction(txn, action, now);
      return AgentMutation(value: goal, action: action);
    });
  }

  /// Records one independent signal. Inferred preferences remain candidates;
  /// callers may surface them after three distinct session ids.
  Future<AgentMutation<ReaderProfileItem>?> recordProfileEvidence({
    required String key,
    required Map<String, dynamic> value,
    required String sessionId,
    bool explicit = false,
  }) async {
    _validateProfileKey(key);
    final now = _clock();
    return _dao.write((txn) async {
      final before = await _queryOne(
          txn, 'tb_reader_profile_items', 'profile_key = ?', [key]);
      final existing = before == null ? null : ReaderProfileItem.fromDb(before);
      if (existing?.status == ReaderProfileStatus.rejected &&
          (existing!.rejectedUntil ?? 0) > now) {
        return null;
      }
      final sameValue =
          existing != null && _hash(existing.value) == _hash(value);
      final sessions = <String>{
        if (sameValue) ...existing.evidenceSessionIds,
        sessionId,
      };
      final confidence =
          explicit ? 1.0 : (sessions.length / 3).clamp(0, 1).toDouble();
      final item = ReaderProfileItem(
        key: key,
        value: value,
        status: ReaderProfileStatus.candidate,
        confidence: confidence,
        evidenceSessionIds: sessions.toList(growable: false)..sort(),
        createdAt: existing?.createdAt ?? now,
        updatedAt: now,
      );
      await txn.insert('tb_reader_profile_items', item.toDb(),
          conflictAlgorithm: ConflictAlgorithm.replace);
      final action = _action(
        type: AgentActionType.profile,
        targetId: key,
        sessionId: sessionId,
        before: before,
        after: item.toDb(),
        now: now,
      );
      await _insertAction(txn, action, now);
      return AgentMutation(value: item, action: action);
    });
  }

  Future<AgentMutation<ReaderProfileItem>> setProfileStatus({
    required String key,
    required ReaderProfileStatus status,
    required String sessionId,
  }) async {
    _validateProfileKey(key);
    final now = _clock();
    return _dao.write((txn) async {
      final before = await _queryOne(
          txn, 'tb_reader_profile_items', 'profile_key = ?', [key]);
      if (before == null) throw StateError('Unknown reader profile item: $key');
      final existing = ReaderProfileItem.fromDb(before);
      final item = existing.copyWith(
        status: status,
        confidence:
            status == ReaderProfileStatus.confirmed ? 1 : existing.confidence,
        rejectedUntil: status == ReaderProfileStatus.rejected
            ? now + rejectionSuppression.inMilliseconds
            : null,
        clearRejectedUntil: status != ReaderProfileStatus.rejected,
        updatedAt: now,
      );
      await txn.update('tb_reader_profile_items', item.toDb(),
          where: 'profile_key = ?', whereArgs: [key]);
      final action = _action(
        type: AgentActionType.profile,
        targetId: key,
        sessionId: sessionId,
        before: before,
        after: item.toDb(),
        now: now,
      );
      await _insertAction(txn, action, now);
      return AgentMutation(value: item, action: action);
    });
  }

  Future<AgentMutation<ReadingNoteDocument>> createNote(
    ReadingNoteDocument document, {
    required String sessionId,
    int? ownedAnnotationId,
    BookNote? ownedAnnotation,
  }) async {
    if (document.sources.isEmpty ||
        document.sources.every((source) =>
            source.textSnapshot.trim().isEmpty &&
            (source.cfi?.trim().isEmpty ?? true))) {
      throw ArgumentError('Agent notes require a traceable source');
    }
    if (document.note.id.isEmpty || document.note.bookId <= 0) {
      throw ArgumentError('Invalid reading note');
    }
    final now = _clock();
    return _dao.write((txn) async {
      final existing = await _queryOne(
          txn, 'tb_reading_notes', 'id = ?', [document.note.id]);
      if (existing != null) throw StateError('Reading note already exists');
      var annotationId = ownedAnnotationId;
      if (ownedAnnotation != null) {
        annotationId = await txn.insert('tb_notes', ownedAnnotation.toMap());
        ownedAnnotation.id = annotationId;
      }
      await _insertDocument(txn, document);
      final after = await _noteSnapshot(txn, document.note.id);
      if (annotationId != null) {
        after!['ownedAnnotationId'] = annotationId;
      }
      final action = _action(
        type: AgentActionType.note,
        targetId: document.note.id,
        bookId: document.note.bookId,
        sessionId: sessionId,
        before: null,
        after: after,
        now: now,
      );
      await _insertAction(txn, action, now);
      return AgentMutation(value: document, action: action);
    });
  }

  Future<AgentMutation<ReadingDifficulty>> saveDifficulty(
    ReadingDifficulty difficulty, {
    required String sessionId,
  }) async {
    if (difficulty.bookId <= 0 ||
        difficulty.cfi.trim().isEmpty ||
        difficulty.text.trim().isEmpty) {
      throw ArgumentError('Difficulty requires book, CFI, and selected text');
    }
    final now = _clock();
    return _dao.write((txn) async {
      final before = await _queryOne(
        txn,
        'tb_reading_difficulties',
        'book_id = ? AND cfi = ? AND selected_text = ?',
        [difficulty.bookId, difficulty.cfi, difficulty.text],
      );
      final existing = before == null ? null : ReadingDifficulty.fromDb(before);
      final saved = existing == null
          ? difficulty
          : existing.status == ReadingDifficultyStatus.resolved
              ? existing.copyWith(
                  status: ReadingDifficultyStatus.unresolved, updatedAt: now)
              : existing;
      await txn.insert('tb_reading_difficulties', saved.toDb(),
          conflictAlgorithm: ConflictAlgorithm.replace);
      final action = _action(
        type: AgentActionType.difficulty,
        targetId: saved.id,
        bookId: saved.bookId,
        sessionId: sessionId,
        before: before,
        after: saved.toDb(),
        now: now,
      );
      await _insertAction(txn, action, now);
      return AgentMutation(value: saved, action: action);
    });
  }

  Future<UndoResult> undo(String actionId) async {
    final now = _clock();
    return _dao.write((txn) async {
      final row =
          await _queryOne(txn, 'tb_agent_actions', 'id = ?', [actionId]);
      if (row == null) return UndoResult.missing;
      final action = AgentAction.fromDb(row);
      if (action.status == AgentActionStatus.undone) {
        return UndoResult.alreadyUndone;
      }
      if (now > action.expiresAt) return UndoResult.expired;
      final current = await _currentSnapshot(txn, action);
      if (_hash(current) != action.afterHash) {
        await txn.update(
          'tb_agent_actions',
          {'status': AgentActionStatus.conflict.name},
          where: 'id = ?',
          whereArgs: [action.id],
        );
        return UndoResult.conflict;
      }
      await _restore(txn, action);
      await txn.update(
        'tb_agent_actions',
        {'status': AgentActionStatus.undone.name, 'undone_at': now},
        where: 'id = ?',
        whereArgs: [action.id],
      );
      return UndoResult.undone;
    });
  }

  void _validateGoal(ReadingGoal goal) {
    if (goal.id.isEmpty || goal.bookId <= 0 || goal.title.trim().isEmpty) {
      throw ArgumentError('Goal requires id, book, and title');
    }
    if (goal.criteria.length > 3) {
      throw ArgumentError('A reading goal supports at most three criteria');
    }
    if (goal.progress < 0 || goal.progress > 1) {
      throw ArgumentError.value(goal.progress, 'progress');
    }
    if (goal.timeBudgetMinutes != null && goal.timeBudgetMinutes! <= 0) {
      throw ArgumentError.value(goal.timeBudgetMinutes, 'timeBudgetMinutes');
    }
  }

  void _validateProfileKey(String key) {
    if (!supportedReaderProfileKeys.contains(key)) {
      throw ArgumentError.value(key, 'key', 'Unsupported reader preference');
    }
  }

  AgentAction _action({
    required AgentActionType type,
    required String targetId,
    int? bookId,
    required String sessionId,
    required Map<String, dynamic>? before,
    required Map<String, dynamic>? after,
    required int now,
  }) =>
      AgentAction(
        id: _uuid.v4(),
        type: type,
        targetId: targetId,
        bookId: bookId,
        beforeSnapshot: before,
        afterSnapshot: after,
        afterHash: _hash(after),
        sessionId: sessionId,
        createdAt: now,
        expiresAt: now + retention.inMilliseconds,
      );

  Future<void> _insertAction(
      Transaction txn, AgentAction action, int now) async {
    await txn.insert('tb_agent_actions', action.toDb());
    await txn
        .delete('tb_agent_actions', where: 'expires_at < ?', whereArgs: [now]);
    await txn.rawDelete('''DELETE FROM tb_agent_actions WHERE id IN (
      SELECT id FROM tb_agent_actions ORDER BY created_at DESC LIMIT -1 OFFSET ?
    )''', [maxActions]);
  }

  Future<Map<String, dynamic>?> _currentSnapshot(
      Transaction txn, AgentAction action) async {
    switch (action.type) {
      case AgentActionType.goal:
        return _queryOne(txn, 'tb_reading_goals', 'id = ?', [action.targetId]);
      case AgentActionType.profile:
        return _queryOne(txn, 'tb_reader_profile_items', 'profile_key = ?',
            [action.targetId]);
      case AgentActionType.note:
        final value = await _noteSnapshot(txn, action.targetId);
        final owned = action.afterSnapshot?['ownedAnnotationId'];
        if (value != null && owned != null) value['ownedAnnotationId'] = owned;
        return value;
      case AgentActionType.difficulty:
        return _queryOne(
            txn, 'tb_reading_difficulties', 'id = ?', [action.targetId]);
      case AgentActionType.memory:
        return _queryOne(
            txn, 'tb_reading_memory_documents', 'id = ?', [action.targetId]);
    }
  }

  Future<void> _restore(Transaction txn, AgentAction action) async {
    switch (action.type) {
      case AgentActionType.goal:
        final snapshot = action.beforeSnapshot ?? const {};
        await txn.delete('tb_reading_goals',
            where: 'id = ?', whereArgs: [action.targetId]);
        final target = snapshot['target'];
        if (target is Map) {
          await txn.insert(
              'tb_reading_goals', Map<String, Object?>.from(target));
        }
        final previous = snapshot['previousActive'];
        if (previous is Map && previous['id'] != action.targetId) {
          await txn.insert(
              'tb_reading_goals', Map<String, Object?>.from(previous),
              conflictAlgorithm: ConflictAlgorithm.replace);
        }
        return;
      case AgentActionType.profile:
        if (action.beforeSnapshot == null) {
          await txn.delete('tb_reader_profile_items',
              where: 'profile_key = ?', whereArgs: [action.targetId]);
        } else {
          await txn.insert('tb_reader_profile_items',
              Map<String, Object?>.from(action.beforeSnapshot!),
              conflictAlgorithm: ConflictAlgorithm.replace);
        }
        return;
      case AgentActionType.note:
        await _deleteDocument(txn, action.targetId);
        final owned = action.afterSnapshot?['ownedAnnotationId'];
        if (owned is int) {
          await txn.delete('tb_notes', where: 'id = ?', whereArgs: [owned]);
        }
        return;
      case AgentActionType.difficulty:
        if (action.beforeSnapshot == null) {
          await txn.delete('tb_reading_difficulties',
              where: 'id = ?', whereArgs: [action.targetId]);
        } else {
          await txn.insert('tb_reading_difficulties',
              Map<String, Object?>.from(action.beforeSnapshot!),
              conflictAlgorithm: ConflictAlgorithm.replace);
        }
        return;
      case AgentActionType.memory:
        await txn.delete('tb_reading_memory_documents',
            where: 'id = ?', whereArgs: [action.targetId]);
        if (action.beforeSnapshot != null) {
          await txn.insert('tb_reading_memory_documents',
              Map<String, Object?>.from(action.beforeSnapshot!),
              conflictAlgorithm: ConflictAlgorithm.replace);
        }
        return;
    }
  }

  Future<void> _insertDocument(
      Transaction txn, ReadingNoteDocument document) async {
    await txn.insert('tb_reading_notes', document.note.toDb());
    for (final block in document.blocks) {
      await txn.insert('tb_reading_note_blocks', block.toDb());
    }
    for (final source in document.sources) {
      await txn.insert('tb_reading_note_sources', source.toDb());
    }
    for (final tag in document.tags) {
      await txn.insert('tb_reading_tags', tag.toDb(),
          conflictAlgorithm: ConflictAlgorithm.ignore);
      await txn.insert('tb_reading_note_tags',
          {'note_id': document.note.id, 'tag_id': tag.id});
    }
  }

  Future<Map<String, dynamic>?> _noteSnapshot(
      Transaction txn, String noteId) async {
    final note = await _queryOne(txn, 'tb_reading_notes', 'id = ?', [noteId]);
    if (note == null) return null;
    final blocks = await txn.query('tb_reading_note_blocks',
        where: 'note_id = ?', whereArgs: [noteId], orderBy: 'sort_order, id');
    final sources = await txn.query('tb_reading_note_sources',
        where: 'note_id = ?',
        whereArgs: [noteId],
        orderBy: 'source_type, source_ref');
    final tags = await txn.rawQuery('''SELECT t.* FROM tb_reading_tags t
      JOIN tb_reading_note_tags nt ON nt.tag_id = t.id
      WHERE nt.note_id = ? ORDER BY t.id''', [noteId]);
    return {
      'note': note,
      'blocks': blocks,
      'sources': sources,
      'tags': tags,
    };
  }

  Future<void> _deleteDocument(Transaction txn, String noteId) async {
    for (final table in [
      'tb_reading_note_tags',
      'tb_reading_note_revisions',
      'tb_reading_note_sources',
      'tb_reading_note_blocks',
    ]) {
      await txn.delete(table, where: 'note_id = ?', whereArgs: [noteId]);
    }
    await txn.delete('tb_reading_notes', where: 'id = ?', whereArgs: [noteId]);
  }
}

Future<Map<String, dynamic>?> _queryOne(Transaction txn, String table,
    String where, List<Object?> whereArgs) async {
  final rows =
      await txn.query(table, where: where, whereArgs: whereArgs, limit: 1);
  return rows.isEmpty ? null : Map<String, dynamic>.from(rows.first);
}

String _hash(Object? value) =>
    sha256.convert(utf8.encode(jsonEncode(_canonical(value)))).toString();

Object? _canonical(Object? value) {
  if (value is Map) {
    final keys = value.keys.map((key) => key.toString()).toList()..sort();
    return {for (final key in keys) key: _canonical(value[key])};
  }
  if (value is List) return value.map(_canonical).toList(growable: false);
  return value;
}

final readingAgentRepository = ReadingAgentRepository();

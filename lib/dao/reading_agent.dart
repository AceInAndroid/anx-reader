import 'package:anx_reader/dao/base_dao.dart';
import 'package:anx_reader/models/reading_agent.dart';
import 'package:sqflite/sqflite.dart';

class ReadingAgentDao extends BaseDao {
  ReadingAgentDao({super.databaseProvider});

  Future<ReadingGoal?> activeGoal(int bookId) => querySingle(
        'tb_reading_goals',
        mapper: ReadingGoal.fromDb,
        where: "book_id = ? AND status = 'active'",
        whereArgs: [bookId],
      );

  Future<ReadingGoal?> goal(String id) => querySingle(
        'tb_reading_goals',
        mapper: ReadingGoal.fromDb,
        where: 'id = ?',
        whereArgs: [id],
      );

  Future<List<ReadingGoal>> goals(int bookId) => queryList(
        'tb_reading_goals',
        mapper: ReadingGoal.fromDb,
        where: 'book_id = ?',
        whereArgs: [bookId],
        orderBy: 'updated_at DESC',
      );

  Future<void> updateGoalProgress({
    required String id,
    required double progress,
    required int updatedAt,
  }) async {
    await update(
      'tb_reading_goals',
      {'progress': progress.clamp(0, 1), 'updated_at': updatedAt},
      where: "id = ? AND status = 'active'",
      whereArgs: [id],
    );
  }

  Future<ReaderProfileItem?> profileItem(String key) => querySingle(
        'tb_reader_profile_items',
        mapper: ReaderProfileItem.fromDb,
        where: 'profile_key = ?',
        whereArgs: [key],
      );

  Future<List<ReaderProfileItem>> profileItems({
    ReaderProfileStatus? status,
  }) =>
      queryList(
        'tb_reader_profile_items',
        mapper: ReaderProfileItem.fromDb,
        where: status == null ? null : 'status = ?',
        whereArgs: status == null ? null : [status.name],
        orderBy: 'updated_at DESC',
      );

  Future<AgentAction?> action(String id) => querySingle(
        'tb_agent_actions',
        mapper: AgentAction.fromDb,
        where: 'id = ?',
        whereArgs: [id],
      );

  Future<List<AgentAction>> recentActions({
    int? bookId,
    int? createdAfter,
    int limit = 200,
  }) {
    final where = <String>[];
    final args = <Object?>[];
    if (bookId != null) {
      where.add('book_id = ?');
      args.add(bookId);
    }
    if (createdAfter != null) {
      where.add('created_at >= ?');
      args.add(createdAfter);
    }
    return queryList(
      'tb_agent_actions',
      mapper: AgentAction.fromDb,
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'created_at DESC',
      limit: limit.clamp(1, 200),
    );
  }

  Future<R> write<R>(Future<R> Function(Transaction txn) operation) =>
      transaction(operation);
}

final readingAgentDao = ReadingAgentDao();

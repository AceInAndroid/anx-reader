import 'dart:io';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/dao/database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory tempDir;
  late DatabaseFactory dbFactory;
  late DBHelper helper;

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    Prefs().prefs = await SharedPreferences.getInstance();
    tempDir = await Directory.systemTemp.createTemp('anx_db_migration_test_');
    dbFactory = databaseFactoryFfi;
    helper = DBHelper();
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  Future<Database> openTempDb(String name) {
    return dbFactory.openDatabase(p.join(tempDir.path, name));
  }

  test('upgrade from version 7 succeeds when vocabulary table already exists',
      () async {
    final db = await openTempDb('existing_vocabulary.db');
    addTearDown(db.close);

    await db.execute(createVocabularySQL);
    await db.execute(createVocabularyReviewIndexSQL);

    await expectLater(
      helper.onUpgradeDatabase(db, 7, currentDbVersion),
      completes,
    );

    final columns = await db.rawQuery('PRAGMA table_info(tb_vocabulary)');
    final columnNames = columns.map((row) => row['name']).toSet();

    expect(columnNames, contains('source_sentence_translation'));
    expect(columnNames, contains('contextual_definition'));
    expect(columnNames, contains('example_sentence'));
    expect(columnNames, contains('example_translation'));

    final indexes = await db.rawQuery('''
      SELECT name
      FROM sqlite_master
      WHERE type = 'index' AND name = 'idx_vocabulary_next_review_at'
    ''');
    expect(indexes, isNotEmpty);
  });

  test('upgrade from version 7 creates vocabulary artifacts when missing',
      () async {
    final db = await openTempDb('missing_vocabulary.db');
    addTearDown(db.close);

    await expectLater(
      helper.onUpgradeDatabase(db, 7, currentDbVersion),
      completes,
    );

    final tables = await db.rawQuery('''
      SELECT name
      FROM sqlite_master
      WHERE type = 'table' AND name = 'tb_vocabulary'
    ''');
    expect(tables, isNotEmpty);

    final columns = await db.rawQuery('PRAGMA table_info(tb_vocabulary)');
    final columnNames = columns.map((row) => row['name']).toSet();

    expect(columnNames, contains('source_sentence_translation'));
    expect(columnNames, contains('contextual_definition'));
    expect(columnNames, contains('example_sentence'));
    expect(columnNames, contains('example_translation'));
  });

  test('version 12 migration creates AI sessions table with all columns',
      () async {
    final db = await openTempDb('ai_sessions.db');
    addTearDown(db.close);

    await helper.onUpgradeDatabase(db, 9, currentDbVersion);

    expect(currentDbVersion, 17);
    final columns = await db.rawQuery('PRAGMA table_info(tb_ai_sessions)');
    expect(
      columns.map((row) => row['name']).toSet(),
      containsAll({
        'id',
        'title',
        'service',
        'model',
        'bookId',
        'bookTitle',
        'chapterTitle',
        'chapterHref',
        'readingMode',
        'analysisDepth',
        'frameworks',
        'outputTemplate',
        'readingGoal',
        'analysisResult',
        'contextSnapshot',
        'agentTraces',
        'citations',
        'messages',
        'completed',
        'createdAt',
        'updatedAt',
      }),
    );
  });

  test('version 12 migration creates active reading coach tables', () async {
    final db = await openTempDb('reading_coach.db');
    addTearDown(db.close);

    await helper.onUpgradeDatabase(db, 11, currentDbVersion);

    final tables = await db.rawQuery('''
      SELECT name FROM sqlite_master
      WHERE type = 'table' AND name IN (
        'tb_reading_guides',
        'tb_reading_quizzes',
        'tb_reading_difficulties'
      )
    ''');
    expect(tables.map((row) => row['name']).toSet(), {
      'tb_reading_guides',
      'tb_reading_quizzes',
      'tb_reading_difficulties',
    });

    final indexes = await db.rawQuery('''
      SELECT name FROM sqlite_master
      WHERE type = 'index' AND name IN (
        'idx_reading_quizzes_book_chapter',
        'idx_reading_difficulties_book_status'
      )
    ''');
    expect(indexes, hasLength(2));
  });

  test('upgrade from version 10 adds deep-reading session columns', () async {
    final db = await openTempDb('ai_sessions_v10.db');
    addTearDown(db.close);
    await db.execute('''
      CREATE TABLE tb_ai_sessions (
        id TEXT PRIMARY KEY,
        title TEXT,
        service TEXT NOT NULL DEFAULT '',
        model TEXT NOT NULL DEFAULT '',
        bookId INTEGER,
        bookTitle TEXT,
        chapterTitle TEXT,
        chapterHref TEXT,
        readingMode TEXT,
        contextSnapshot TEXT,
        agentTraces TEXT NOT NULL DEFAULT '[]',
        citations TEXT NOT NULL DEFAULT '[]',
        messages TEXT NOT NULL DEFAULT '[]',
        completed INTEGER NOT NULL DEFAULT 0,
        createdAt INTEGER NOT NULL,
        updatedAt INTEGER NOT NULL
      )
    ''');

    await helper.onUpgradeDatabase(db, 10, currentDbVersion);

    final columns = await db.rawQuery('PRAGMA table_info(tb_ai_sessions)');
    expect(
      columns.map((row) => row['name']).toSet(),
      containsAll({
        'analysisDepth',
        'frameworks',
        'outputTemplate',
        'readingGoal',
        'analysisResult',
      }),
    );
  });

  test('version 13 migration creates reading memory tables and indexes',
      () async {
    final db = await openTempDb('reading_memory.db');
    addTearDown(db.close);

    await helper.onUpgradeDatabase(db, 12, currentDbVersion);

    final tables = await db.rawQuery('''
      SELECT name FROM sqlite_master WHERE type = 'table' AND name IN (
        'tb_reading_memory_sources', 'tb_reading_memory_topics',
        'tb_reading_topic_sources', 'tb_reading_knowledge_cards',
        'tb_reading_card_sources', 'tb_reading_card_reviews'
      )
    ''');
    expect(tables, hasLength(6));
    final indexes = await db.rawQuery('''
      SELECT name FROM sqlite_master WHERE type = 'index' AND name IN (
        'idx_memory_sources_book', 'idx_memory_topics_book_status',
        'idx_memory_cards_book_due', 'idx_memory_reviews_book_time'
      )
    ''');
    expect(indexes, hasLength(4));
  });

  test('version 14 migration creates reading note workspace tables and indexes',
      () async {
    final db = await openTempDb('reading_notes_workspace.db');
    addTearDown(db.close);

    await helper.onUpgradeDatabase(db, 13, currentDbVersion);

    final tables = await db.rawQuery('''
      SELECT name FROM sqlite_master WHERE type = 'table' AND name IN (
        'tb_reading_notes', 'tb_reading_note_blocks',
        'tb_reading_note_sources', 'tb_reading_tags',
        'tb_reading_note_tags', 'tb_reading_note_revisions'
      )
    ''');
    expect(tables, hasLength(6));
    final indexes = await db.rawQuery('''
      SELECT name FROM sqlite_master WHERE type = 'index' AND name IN (
        'idx_reading_notes_book_status', 'idx_reading_note_blocks_note',
        'idx_reading_note_sources_ref', 'idx_reading_note_tags_note',
        'idx_reading_note_revisions_note'
      )
    ''');
    expect(indexes, hasLength(5));
  });

  test('version 15 migration adds AI organizer tables and block metadata',
      () async {
    final db = await openTempDb('reading_note_ai.db');
    addTearDown(db.close);
    for (final statement in createReadingNotesWorkspaceSQL
        .split(';')
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)) {
      await db.execute(statement);
    }

    await helper.onUpgradeDatabase(db, 14, currentDbVersion);

    final columns =
        await db.rawQuery('PRAGMA table_info(tb_reading_note_blocks)');
    expect(columns.map((row) => row['name']), contains('metadata'));
    final tables = await db.rawQuery('''
      SELECT name FROM sqlite_master WHERE type = 'table' AND name IN (
        'tb_reading_note_ai_batches', 'tb_reading_note_ai_suggestions'
      )
    ''');
    expect(tables, hasLength(2));
    final indexes = await db.rawQuery('''
      SELECT name FROM sqlite_master WHERE type = 'index' AND name IN (
        'idx_note_ai_batches_book_status',
        'idx_note_ai_suggestions_batch_status',
        'idx_note_ai_suggestions_source'
      )
    ''');
    expect(indexes, hasLength(3));
  });

  test('version 17 migration creates reading closure tables and constraints',
      () async {
    final db = await openTempDb('reading_agent.db');
    addTearDown(db.close);

    await helper.onUpgradeDatabase(db, 15, currentDbVersion);

    final tables = await db.rawQuery('''
      SELECT name FROM sqlite_master WHERE type = 'table' AND name IN (
        'tb_reading_goals', 'tb_reader_profile_items', 'tb_agent_actions',
        'tb_reading_checkpoints', 'tb_reading_mastery', 'tb_knowledge_cards',
        'tb_reading_memory_documents'
      )
    ''');
    expect(tables, hasLength(7));
    final indexes = await db.rawQuery('''
      SELECT name FROM sqlite_master WHERE type = 'index' AND name IN (
        'idx_reading_goals_one_active_book',
        'idx_reading_goals_book_updated',
        'idx_reader_profile_status_updated',
        'idx_agent_actions_recent', 'idx_agent_actions_target'
      )
    ''');
    expect(indexes, hasLength(5));

    final now = DateTime.now().millisecondsSinceEpoch;
    Map<String, Object?> goal(String id) => {
          'id': id,
          'book_id': 1,
          'title': id,
          'created_at': now,
          'updated_at': now,
        };
    await db.insert('tb_reading_goals', goal('first'));
    await expectLater(
      db.insert('tb_reading_goals', goal('second')),
      throwsA(anything),
    );
  });

  test('database migration from version 7 through version 17 succeeds',
      () async {
    final db = await openTempDb('upgrade_v7_to_v15.db');
    addTearDown(db.close);

    await expectLater(
      helper.onUpgradeDatabase(db, 7, currentDbVersion),
      completes,
    );

    final columns =
        await db.rawQuery('PRAGMA table_info(tb_reading_note_blocks)');
    expect(columns.map((row) => row['name']), contains('metadata'));
  });
}

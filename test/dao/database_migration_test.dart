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

  test('version 11 migration creates AI sessions table with all columns',
      () async {
    final db = await openTempDb('ai_sessions.db');
    addTearDown(db.close);

    await helper.onUpgradeDatabase(db, 9, currentDbVersion);

    expect(currentDbVersion, 11);
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
}

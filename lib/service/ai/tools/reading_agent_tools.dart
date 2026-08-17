import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/models/book_note.dart';
import 'package:anx_reader/models/reading_coach.dart';
import 'package:anx_reader/models/reading_note.dart';
import 'package:anx_reader/providers/current_reading.dart';
import 'package:anx_reader/service/ai/agent_action_service.dart';
import 'package:anx_reader/service/ai/reading_agent_runtime.dart';
import 'package:anx_reader/service/ai/tools/ai_tool_registry.dart';
import 'package:anx_reader/service/ai/tools/base_tool.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

const readingAgentToolIds = {
  'reader_navigate',
  'reading_note_create',
  'reading_difficulty_save',
  'reading_goal_set',
};

class ReaderNavigateTool extends RepositoryTool<JsonMap, Map<String, dynamic>> {
  ReaderNavigateTool(this._ref)
      : super(
          name: 'reader_navigate',
          description:
              'Navigate inside the currently open book. CFI and href targets are validated by the active reader. This is non-persistent and offers return-to-previous-location.',
          inputJsonSchema: const {
            'type': 'object',
            'required': ['kind'],
            'properties': {
              'kind': {
                'type': 'string',
                'enum': ['cfi', 'href', 'return'],
              },
              'target': {'type': 'string'},
            },
          },
        );

  final WidgetRef _ref;

  @override
  JsonMap parseInput(Map<String, dynamic> json) => json;

  @override
  Map<String, dynamic> run(JsonMap input) {
    final reading = _ref.read(currentReadingProvider);
    final book = reading.book;
    if (!reading.isReading || book == null) {
      throw StateError('No active reading session');
    }
    final kind = input['kind']?.toString();
    final target = input['target']?.toString().trim() ?? '';
    final gateway = ReaderCommandGateway.instance;
    final ok = switch (kind) {
      'cfi' => gateway.navigateToCfi(bookId: book.id, cfi: target),
      'href' => gateway.navigateToHref(bookId: book.id, href: target),
      'return' => gateway.returnToPreviousLocation(bookId: book.id),
      _ => false,
    };
    if (!ok) throw ArgumentError('Invalid or unavailable reader target');
    return {
      'navigated': true,
      'kind': kind,
      'canReturn': kind != 'return',
    };
  }
}

class ReadingNoteCreateTool
    extends RepositoryTool<JsonMap, Map<String, dynamic>> {
  ReadingNoteCreateTool(this._ref)
      : super(
          name: 'reading_note_create',
          description:
              'Create a source-traceable AI reading note. Set userInitiated true only when the user explicitly asked to save/create a note; otherwise this returns a confirmation request without writing.',
          inputJsonSchema: const {
            'type': 'object',
            'required': ['body', 'userInitiated'],
            'properties': {
              'title': {'type': 'string'},
              'body': {'type': 'string'},
              'sourceText': {'type': 'string'},
              'cfi': {'type': 'string'},
              'chapterTitle': {'type': 'string'},
              'chapterHref': {'type': 'string'},
              'model': {'type': 'string'},
              'userInitiated': {'type': 'boolean'},
            },
          },
        );

  final WidgetRef _ref;

  @override
  JsonMap parseInput(Map<String, dynamic> json) => json;

  @override
  Future<Map<String, dynamic>> run(JsonMap input) async {
    final reading = _ref.read(currentReadingProvider);
    final book = reading.book;
    if (!reading.isReading || book == null) {
      throw StateError('No active reading session');
    }
    final selection = readingAgentRuntime.state.selection;
    final sourceText =
        (selection?.text ?? input['sourceText']?.toString() ?? '').trim();
    final cfi = (selection?.cfi ?? input['cfi']?.toString() ?? '').trim();
    if (sourceText.isEmpty || !_isValidCfi(cfi)) {
      throw ArgumentError('A current selection or explicit source is required');
    }
    if (input['userInitiated'] != true) {
      return {
        'requiresConfirmation': true,
        'preview': {
          'title': input['title']?.toString() ?? '',
          'body': input['body']?.toString() ?? '',
          'sourceText': sourceText,
          'cfi': cfi,
          'chapterTitle': reading.chapterTitle,
          'chapterHref': reading.chapterHref,
          'model': input['model']?.toString() ?? 'unknown',
        },
      };
    }
    final body = input['body']?.toString().trim() ?? '';
    if (body.isEmpty) throw ArgumentError('Note body is required');
    final now = DateTime.now().millisecondsSinceEpoch;
    final noteId = const Uuid().v4();
    final sessionId = readingAgentRuntime.state.sessionId!;
    final chapterTitle =
        input['chapterTitle']?.toString().trim().isNotEmpty == true
            ? input['chapterTitle'].toString().trim()
            : reading.chapterTitle ?? '';
    final chapterHref =
        input['chapterHref']?.toString().trim().isNotEmpty == true
            ? input['chapterHref'].toString().trim()
            : reading.chapterHref;
    final document = ReadingNoteDocument(
      note: ReadingNote(
        id: noteId,
        bookId: book.id,
        title: input['title']?.toString().trim() ?? '',
        status: ReadingNoteStatus.active,
        captureKind: ReadingNoteCaptureKind.manual,
        isFavorite: false,
        createdAt: now,
        updatedAt: now,
      ),
      blocks: [
        ReadingNoteBlock(
          id: const Uuid().v4(),
          noteId: noteId,
          type: ReadingNoteBlockType.quote,
          content: sourceText,
          sortOrder: 0,
          origin: ReadingNoteBlockOrigin.source,
          createdAt: now,
          updatedAt: now,
        ),
        ReadingNoteBlock(
          id: const Uuid().v4(),
          noteId: noteId,
          type: ReadingNoteBlockType.ai,
          content: body,
          sortOrder: 1,
          origin: ReadingNoteBlockOrigin.ai,
          metadata: {
            'model': input['model']?.toString() ?? 'unknown',
            'sessionId': sessionId,
          },
          createdAt: now,
          updatedAt: now,
        ),
      ],
      sources: [
        ReadingNoteSource(
          noteId: noteId,
          type: ReadingNoteSourceType.aiSession,
          sourceRef: sessionId,
          chapterHref: chapterHref,
          chapterTitle: chapterTitle,
          cfi: cfi,
          textSnapshot: sourceText,
          metadata: {'model': input['model']?.toString() ?? 'unknown'},
          createdAt: now,
        ),
      ],
    );
    final annotation = BookNote(
      bookId: book.id,
      content: sourceText,
      cfi: cfi,
      chapter: chapterTitle,
      type: 'highlight',
      color: Prefs().annotationColor,
      readerNote: body,
      createTime: DateTime.fromMillisecondsSinceEpoch(now),
      updateTime: DateTime.fromMillisecondsSinceEpoch(now),
    );
    final mutation = await agentActionService.createNote(
      document,
      ownedAnnotation: annotation,
    );
    return {
      'created': true,
      'noteId': noteId,
      'actionId': mutation.action.id,
      'undoAvailableUntil': mutation.action.expiresAt,
    };
  }
}

class ReadingDifficultySaveTool
    extends RepositoryTool<JsonMap, Map<String, dynamic>> {
  ReadingDifficultySaveTool(this._ref)
      : super(
          name: 'reading_difficulty_save',
          description:
              'Save or reopen a source-backed reading difficulty. Set userInitiated true only for an explicit user request; proactive use returns a confirmation preview.',
          inputJsonSchema: const {
            'type': 'object',
            'required': ['userInitiated'],
            'properties': {
              'text': {'type': 'string'},
              'cfi': {'type': 'string'},
              'context': {'type': 'string'},
              'userInitiated': {'type': 'boolean'},
            },
          },
        );

  final WidgetRef _ref;
  @override
  JsonMap parseInput(Map<String, dynamic> json) => json;

  @override
  Future<Map<String, dynamic>> run(JsonMap input) async {
    final reading = _ref.read(currentReadingProvider);
    final book = reading.book;
    if (!reading.isReading || book == null) {
      throw StateError('No active reading session');
    }
    final selection = readingAgentRuntime.state.selection;
    final text = (selection?.text ?? input['text']?.toString() ?? '').trim();
    final cfi = (selection?.cfi ?? input['cfi']?.toString() ?? '').trim();
    if (text.isEmpty || !_isValidCfi(cfi)) {
      throw ArgumentError('A current selection or explicit source is required');
    }
    if (input['userInitiated'] != true) {
      return {
        'requiresConfirmation': true,
        'preview': {
          'text': text,
          'cfi': cfi,
          'context': selection?.surroundingText ?? input['context']?.toString(),
          'chapterTitle': reading.chapterTitle,
          'chapterHref': reading.chapterHref,
        },
      };
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    final mutation = await agentActionService.saveDifficulty(
      ReadingDifficulty(
        id: const Uuid().v4(),
        bookId: book.id,
        cfi: cfi,
        text: text,
        chapterHref: reading.chapterHref,
        chapterTitle: reading.chapterTitle,
        context: selection?.surroundingText ?? input['context']?.toString(),
        createdAt: now,
        updatedAt: now,
      ),
    );
    return {
      'saved': true,
      'difficultyId': mutation.value.id,
      'actionId': mutation.action.id,
      'undoAvailableUntil': mutation.action.expiresAt,
    };
  }
}

class ReadingGoalSetTool extends RepositoryTool<JsonMap, Map<String, dynamic>> {
  ReadingGoalSetTool(this._ref)
      : super(
          name: 'reading_goal_set',
          description:
              'Build a structured reading-goal preview. This tool never writes; the app saves it only when the user presses the confirmation control.',
          inputJsonSchema: const {
            'type': 'object',
            'required': ['title'],
            'properties': {
              'title': {'type': 'string'},
              'template': {
                'type': 'string',
                'enum': ['understandChapter', 'completeRange', 'createOutput'],
              },
              'timeBudgetMinutes': {'type': 'integer'},
              'criteria': {
                'type': 'array',
                'maxItems': 3,
                'items': {'type': 'string'},
              },
            },
          },
        );

  final WidgetRef _ref;
  @override
  JsonMap parseInput(Map<String, dynamic> json) => json;

  @override
  Future<Map<String, dynamic>> run(JsonMap input) async {
    final reading = _ref.read(currentReadingProvider);
    final book = reading.book;
    if (!reading.isReading || book == null) {
      throw StateError('No active reading session');
    }
    final title = input['title']?.toString().trim() ?? '';
    if (title.isEmpty) throw ArgumentError('Goal title is required');
    final criteria = (input['criteria'] as List? ?? const [])
        .take(3)
        .map((value) => {
              'title': value.toString(),
              'completed': false,
              'requiresUserConfirmation': true,
            })
        .toList(growable: false);
    final preview = {
      'title': title,
      'template': input['template']?.toString(),
      'timeBudgetMinutes': input['timeBudgetMinutes'],
      'criteria': criteria,
      'range': {
        'startCfi': reading.cfi,
        'chapterHref': reading.chapterHref,
      },
    };
    return {'requiresConfirmation': true, 'preview': preview};
  }
}

final readerNavigateToolDefinition = AiToolDefinition(
  id: 'reader_navigate',
  displayNameBuilder: (L10n _) => '阅读器导航',
  descriptionBuilder: (L10n _) => '在当前书内跳转，并可返回原位置',
  build: (context) => ReaderNavigateTool(context.ref).tool,
);

final readingNoteCreateToolDefinition = AiToolDefinition(
  id: 'reading_note_create',
  displayNameBuilder: (L10n _) => '创建阅读笔记',
  descriptionBuilder: (L10n _) => '创建有原文来源且可撤销的 AI 笔记',
  build: (context) => ReadingNoteCreateTool(context.ref).tool,
);

final readingDifficultySaveToolDefinition = AiToolDefinition(
  id: 'reading_difficulty_save',
  displayNameBuilder: (L10n _) => '保存阅读难点',
  descriptionBuilder: (L10n _) => '保存或重新打开当前书的难点',
  build: (context) => ReadingDifficultySaveTool(context.ref).tool,
);

final readingGoalSetToolDefinition = AiToolDefinition(
  id: 'reading_goal_set',
  displayNameBuilder: (L10n _) => '设置阅读目标',
  descriptionBuilder: (L10n _) => '先预览，用户确认后保存目标',
  build: (context) => ReadingGoalSetTool(context.ref).tool,
);

bool _isValidCfi(String value) =>
    value.startsWith('epubcfi(') && value.endsWith(')');

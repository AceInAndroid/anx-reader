import 'dart:convert';

import 'package:anx_reader/models/reading_agent.dart';
import 'package:crypto/crypto.dart';

class FictionBackfillChapter {
  const FictionBackfillChapter({
    required this.href,
    required this.title,
    required this.startProgress,
    this.endProgress,
  });

  final String href;
  final String title;
  final double startProgress;
  final double? endProgress;
}

typedef FictionChapterLoader = Future<String> Function(String href);
typedef FictionBackfillGenerator = Future<String> Function(String prompt);
typedef FictionBackfillBatchWriter = Future<void> Function({
  required List<ReadingArtifact> artifacts,
  required List<ReadingArtifact> checkpoints,
  required int completedChapters,
  required int totalChapters,
});

typedef _PreparedChapter = ({
  FictionBackfillChapter chapter,
  String content,
  String hash,
});

class _BackfillBatchResult {
  const _BackfillBatchResult({required this.artifacts, required this.chapters});

  final List<ReadingArtifact> artifacts;
  final List<_PreparedChapter> chapters;
}

class _BackfillBatchAttempt {
  const _BackfillBatchAttempt.success(this.result) : error = null;
  const _BackfillBatchAttempt.failure(this.error) : result = null;

  final _BackfillBatchResult? result;
  final Object? error;
}

/// Explicit, bounded fiction backfill. It never reads a chapter whose start is
/// beyond [safeBoundary], and it does no work until the caller invokes it after
/// user confirmation.
class FictionBackfillService {
  const FictionBackfillService();

  Future<List<ReadingArtifact>> build({
    required int bookId,
    required String moduleId,
    required double safeBoundary,
    required List<FictionBackfillChapter> chapters,
    required FictionChapterLoader loadChapter,
    required FictionBackfillGenerator generate,
    required String sessionId,
    required int ingestedAt,
    double fromProgress = 0,
    int batchSize = 1,
    int maxInputCharacters = 24000,
    int concurrency = 1,
    FictionBackfillBatchWriter? onBatchCompleted,
    Iterable<ReadingArtifact> existingArtifacts = const [],
  }) async {
    final lowerBound = fromProgress.clamp(0, safeBoundary).toDouble();
    final checkpointHashes = <String, String>{
      for (final artifact in existingArtifacts)
        if (artifact.kind == ReadingArtifactKinds.backfillCheckpoint &&
            artifact.chapterHref?.isNotEmpty == true)
          artifact.chapterHref!.split('#').first:
              artifact.payload['contentHash']?.toString() ?? '',
    };
    final eligible = chapters
        .where((chapter) =>
            chapter.startProgress >= lowerBound - .000001 &&
            chapter.startProgress <= safeBoundary + .000001 &&
            (chapter.endProgress ?? chapter.startProgress) <=
                safeBoundary + .000001)
        .toList()
      ..sort((a, b) => a.startProgress.compareTo(b.startProgress));
    final result = <ReadingArtifact>[];
    final existingIds = existingArtifacts.map((item) => item.id).toSet();
    final pending = <_PreparedChapter>[];
    for (final chapter in eligible) {
      final content = (await loadChapter(chapter.href)).trim();
      if (content.isEmpty) continue;
      final hash = _contentHash(content);
      if (checkpointHashes[chapter.href.split('#').first] == hash) continue;
      pending.add((chapter: chapter, content: content, hash: hash));
    }
    final batches = _makeBatches(
      pending,
      batchSize: batchSize.clamp(1, 20),
      maxInputCharacters: maxInputCharacters.clamp(4000, 100000),
    );
    var completed = 0;
    final workerCount = concurrency.clamp(1, 3);
    for (var offset = 0; offset < batches.length; offset += workerCount) {
      final window = batches.skip(offset).take(workerCount);
      // A failed request must not discard successful requests in the same
      // concurrency window: their checkpoints are emitted before the error
      // is rethrown, so a retry resumes from the last completed batch.
      final attempts = await Future.wait([
        for (final batch in window)
          _attemptBatch(
            batch: batch,
            bookId: bookId,
            moduleId: moduleId,
            lowerBound: lowerBound,
            safeBoundary: safeBoundary,
            sessionId: sessionId,
            ingestedAt: ingestedAt,
            generate: generate,
            existingIds: existingIds,
          )
      ]);
      Object? firstError;
      for (final attempt in attempts) {
        if (attempt.error != null) {
          firstError ??= attempt.error;
          continue;
        }
        final completedBatch = attempt.result!;
        result.addAll(completedBatch.artifacts);
        completed += completedBatch.chapters.length;
        if (onBatchCompleted != null) {
          await onBatchCompleted(
            artifacts: completedBatch.artifacts,
            checkpoints: [
              for (final item in completedBatch.chapters)
                _checkpointArtifact(
                  bookId: bookId,
                  moduleId: moduleId,
                  chapter: item.chapter,
                  contentHash: item.hash,
                  sessionId: sessionId,
                  now: ingestedAt,
                ),
            ],
            completedChapters: completed,
            totalChapters: pending.length,
          );
        }
      }
      if (firstError != null) throw firstError;
    }
    return result;
  }

  Future<_BackfillBatchAttempt> _attemptBatch({
    required List<_PreparedChapter> batch,
    required int bookId,
    required String moduleId,
    required double lowerBound,
    required double safeBoundary,
    required String sessionId,
    required int ingestedAt,
    required FictionBackfillGenerator generate,
    required Set<String> existingIds,
  }) async {
    try {
      return _BackfillBatchAttempt.success(await _processBatch(
        batch: batch,
        bookId: bookId,
        moduleId: moduleId,
        lowerBound: lowerBound,
        safeBoundary: safeBoundary,
        sessionId: sessionId,
        ingestedAt: ingestedAt,
        generate: generate,
        existingIds: existingIds,
      ));
    } catch (error) {
      return _BackfillBatchAttempt.failure(error);
    }
  }

  Future<_BackfillBatchResult> _processBatch({
    required List<_PreparedChapter> batch,
    required int bookId,
    required String moduleId,
    required double lowerBound,
    required double safeBoundary,
    required String sessionId,
    required int ingestedAt,
    required FictionBackfillGenerator generate,
    required Set<String> existingIds,
  }) async {
    final response = await generate(_batchPrompt(batch));
    final grouped = _decodeBatch(response, batch);
    final expected =
        batch.map((item) => item.chapter.href.split('#').first).toSet();
    if (!grouped.keys.toSet().containsAll(expected)) {
      throw const FormatException('模型未返回完整的章节批次');
    }
    final artifacts = <ReadingArtifact>[];
    for (final entry in grouped.entries) {
      final chapter = batch.firstWhere(
          (item) => item.chapter.href.split('#').first == entry.key);
      for (final value in entry.value) {
        final kind = _kind(value['kind']?.toString());
        if (kind == null) continue;
        final payload = value['payload'];
        if (payload is! Map || payload.isEmpty) continue;
        final normalizedPayload = Map<String, dynamic>.from(payload);
        if (!_isValid(kind, normalizedPayload)) continue;
        final sourceProgress =
            chapter.chapter.startProgress.clamp(lowerBound, safeBoundary);
        final id =
            _stableId(bookId, chapter.chapter.href, kind, normalizedPayload);
        if (existingIds.contains(id)) continue;
        existingIds.add(id);
        artifacts.add(ReadingArtifact(
          id: id,
          bookId: bookId,
          moduleId: moduleId,
          kind: kind,
          payload: normalizedPayload,
          epistemicStatus: ReadingArtifactEpistemicStatus.agentInference,
          sourceTextSnapshot: chapter.content.length > 500
              ? chapter.content.substring(0, 500)
              : chapter.content,
          chapterHref: chapter.chapter.href,
          chapterTitle: chapter.chapter.title,
          sourceProgress: sourceProgress.toDouble(),
          visibleFromProgress: sourceProgress.toDouble(),
          ingestedAt: ingestedAt,
          ingestionMode: ReadingArtifactIngestionMode.backfill,
          sessionId: sessionId,
          createdBy: 'agent',
          createdAt: ingestedAt,
          updatedAt: ingestedAt,
        ));
      }
    }
    return _BackfillBatchResult(artifacts: artifacts, chapters: batch);
  }

  List<List<_PreparedChapter>> _makeBatches(
    List<_PreparedChapter> chapters, {
    required int batchSize,
    required int maxInputCharacters,
  }) {
    final result = <List<_PreparedChapter>>[];
    var current = <_PreparedChapter>[];
    var characters = 0;
    for (final chapter in chapters) {
      final wouldOverflow = current.isNotEmpty &&
          (current.length >= batchSize ||
              characters + chapter.content.length > maxInputCharacters);
      if (wouldOverflow) {
        result.add(current);
        current = [];
        characters = 0;
      }
      current.add(chapter);
      characters += chapter.content.length;
    }
    if (current.isNotEmpty) result.add(current);
    return result;
  }

  ReadingArtifact _checkpointArtifact({
    required int bookId,
    required String moduleId,
    required FictionBackfillChapter chapter,
    required String contentHash,
    required String sessionId,
    required int now,
  }) {
    final href = chapter.href.split('#').first;
    final idHash = sha256.convert(utf8.encode('$bookId|$href'));
    return ReadingArtifact(
      id: 'fiction-backfill-checkpoint-$idHash',
      bookId: bookId,
      moduleId: moduleId,
      kind: ReadingArtifactKinds.backfillCheckpoint,
      payload: {
        'contentHash': contentHash,
        'extractorVersion': 2,
        'status': 'completed',
      },
      epistemicStatus: ReadingArtifactEpistemicStatus.textFact,
      chapterHref: chapter.href,
      chapterTitle: chapter.title,
      sourceProgress: chapter.startProgress,
      visibleFromProgress: chapter.startProgress,
      ingestedAt: now,
      ingestionMode: ReadingArtifactIngestionMode.backfill,
      sessionId: sessionId,
      createdBy: 'system',
      createdAt: now,
      updatedAt: now,
    );
  }

  String _batchPrompt(List<_PreparedChapter> batch) => '''
你正在为用户已经读过的小说章节建立前情档案。只依据下方正文，不补充常识，不预测后文。
请对每章分别提取，返回严格 JSON 数组，每项格式：
{"chapterHref":"章节 href","items":[{"kind":"character|relationship|event","payload":{...}}]}
人物 payload 使用 entityId（稳定 ID）、name、summary、aliases；关系使用 from、to、relation、summary、state(active|changed|ended)、previousRelation；事件使用 title、summary、eventType（冲突/相遇/转折/揭示/离别/其他）、storyTimeLabel（不确定则空）、participants、importance(normal|major)。
只提取重要事件，不要逐段生成流水账。不要猜测故事内日期。关系人物必须来自本章正文。
${batch.map((item) => '章节 href：${item.chapter.href}\n章节：${item.chapter.title}\n正文：\n${item.content}').join('\n\n---\n\n')}
''';

  Map<String, List<Map<String, dynamic>>> _decodeBatch(
      String raw, List<_PreparedChapter> batch) {
    final start = raw.indexOf('[');
    final end = raw.lastIndexOf(']');
    if (start < 0 || end <= start) return {};
    try {
      final decoded = jsonDecode(raw.substring(start, end + 1));
      if (decoded is! List) return {};
      final result = <String, List<Map<String, dynamic>>>{};
      if (batch.length == 1 &&
          decoded.every((item) => item is Map && item['kind'] != null)) {
        result[batch.single.chapter.href.split('#').first] = decoded
            .whereType<Map>()
            .map((value) => Map<String, dynamic>.from(value))
            .toList();
        return result;
      }
      for (final item in decoded.whereType<Map>()) {
        final href = item['chapterHref']?.toString().split('#').first ?? '';
        final values = item['items'];
        if (href.isEmpty || values is! List) continue;
        result[href] = values
            .whereType<Map>()
            .map((value) => Map<String, dynamic>.from(value))
            .toList();
      }
      return result;
    } catch (_) {
      return {};
    }
  }

  String _contentHash(String content) =>
      sha256.convert(utf8.encode(content)).toString();

  String? _kind(String? value) => switch (value) {
        'character' => ReadingArtifactKinds.character,
        'relationship' => ReadingArtifactKinds.relationship,
        'event' => ReadingArtifactKinds.event,
        'mystery' => ReadingArtifactKinds.mystery,
        'clue' => ReadingArtifactKinds.clue,
        'scene' => ReadingArtifactKinds.scene,
        _ => null,
      };

  bool _isValid(String kind, Map<String, dynamic> payload) => switch (kind) {
        ReadingArtifactKinds.character => _has(payload, 'name'),
        ReadingArtifactKinds.relationship => _has(payload, 'from') &&
            _has(payload, 'to') &&
            _has(payload, 'relation'),
        ReadingArtifactKinds.event => _has(payload, 'title'),
        ReadingArtifactKinds.mystery => _has(payload, 'question'),
        ReadingArtifactKinds.scene => _has(payload, 'summary'),
        ReadingArtifactKinds.clue =>
          _has(payload, 'summary') || _has(payload, 'title'),
        _ => false,
      };

  bool _has(Map<String, dynamic> payload, String key) =>
      payload[key]?.toString().trim().isNotEmpty == true;

  String _stableId(
    int bookId,
    String href,
    String kind,
    Map<String, dynamic> payload,
  ) {
    final signature = jsonEncode(_canonical(payload));
    final digest = sha256.convert(utf8.encode(
      '$bookId|${href.split('#').first.trim()}|$kind|$signature',
    ));
    return 'fiction-backfill-$digest';
  }

  Object? _canonical(Object? value) {
    if (value is Map) {
      final keys = value.keys.map((key) => key.toString()).toList()..sort();
      return {for (final key in keys) key: _canonical(value[key])};
    }
    if (value is List) return value.map(_canonical).toList(growable: false);
    return value;
  }
}

const fictionBackfillService = FictionBackfillService();

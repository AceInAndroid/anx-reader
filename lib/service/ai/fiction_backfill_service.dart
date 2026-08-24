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
    Iterable<ReadingArtifact> existingArtifacts = const [],
  }) async {
    final lowerBound = fromProgress.clamp(0, safeBoundary).toDouble();
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
    for (final chapter in eligible) {
      final content = (await loadChapter(chapter.href)).trim();
      if (content.isEmpty) continue;
      final response = await generate(_prompt(chapter, content));
      final values = _decodeList(response);
      for (final value in values) {
        final kind = _kind(value['kind']?.toString());
        if (kind == null) continue;
        final payload = value['payload'];
        if (payload is! Map || payload.isEmpty) continue;
        final normalizedPayload = Map<String, dynamic>.from(payload);
        if (!_isValid(kind, normalizedPayload)) continue;
        final sourceProgress =
            chapter.startProgress.clamp(lowerBound, safeBoundary);
        final id = _stableId(bookId, chapter.href, kind, normalizedPayload);
        if (existingIds.contains(id)) continue;
        existingIds.add(id);
        result.add(ReadingArtifact(
          id: id,
          bookId: bookId,
          moduleId: moduleId,
          kind: kind,
          payload: normalizedPayload,
          epistemicStatus: ReadingArtifactEpistemicStatus.agentInference,
          sourceTextSnapshot:
              content.length > 500 ? content.substring(0, 500) : content,
          chapterHref: chapter.href,
          chapterTitle: chapter.title,
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
    return result;
  }

  String _prompt(FictionBackfillChapter chapter, String content) => '''
你正在为用户已经读过的小说章节建立前情档案。只依据下方正文，不补充常识，不预测后文。
章节：${chapter.title}
请返回严格 JSON 数组，每项格式：
{"kind":"character|relationship|event|mystery|clue|scene","payload":{...}}
人物 payload 使用 entityId（稳定 ID）、name、summary、aliases；关系使用 from、to、relation、summary、state(active|changed|ended)、previousRelation；事件使用 title、summary、eventType（冲突/相遇/转折/揭示/离别/其他）、storyTimeLabel（不确定则空）、participants、importance(normal|major)；悬念使用 question、currentTheory；场景使用 summary。
只提取重要事件，不要逐段生成流水账。不要猜测故事内日期。关系人物必须来自本章正文。
正文：
$content
''';

  List<Map<String, dynamic>> _decodeList(String raw) {
    final start = raw.indexOf('[');
    final end = raw.lastIndexOf(']');
    if (start < 0 || end <= start) return const [];
    try {
      final decoded = jsonDecode(raw.substring(start, end + 1));
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

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

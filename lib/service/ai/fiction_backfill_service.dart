import 'dart:convert';

import 'package:anx_reader/models/reading_agent.dart';

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
  }) async {
    final eligible = chapters
        .where((chapter) =>
            chapter.startProgress <= safeBoundary + .000001 &&
            (chapter.endProgress ?? chapter.startProgress) <=
                safeBoundary + .000001)
        .toList()
      ..sort((a, b) => a.startProgress.compareTo(b.startProgress));
    final result = <ReadingArtifact>[];
    for (final chapter in eligible) {
      final content = (await loadChapter(chapter.href)).trim();
      if (content.isEmpty) continue;
      final response = await generate(_prompt(chapter, content));
      final values = _decodeList(response);
      for (var index = 0; index < values.length; index++) {
        final value = values[index];
        final kind = _kind(value['kind']?.toString());
        if (kind == null) continue;
        final payload = value['payload'];
        if (payload is! Map || payload.isEmpty) continue;
        final sourceProgress = chapter.startProgress.clamp(0, safeBoundary);
        result.add(ReadingArtifact(
          id: '$bookId-backfill-$ingestedAt-${chapter.href.hashCode}-$index',
          bookId: bookId,
          moduleId: moduleId,
          kind: kind,
          payload: Map<String, dynamic>.from(payload),
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
{"kind":"character|relationship|mystery|clue|scene","payload":{...}}
人物 payload 使用 name、summary、aliases、relationships；悬念使用 question、currentTheory；场景使用 summary。
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
        'mystery' => ReadingArtifactKinds.mystery,
        'clue' => ReadingArtifactKinds.clue,
        'scene' => ReadingArtifactKinds.scene,
        _ => null,
      };
}

const fictionBackfillService = FictionBackfillService();

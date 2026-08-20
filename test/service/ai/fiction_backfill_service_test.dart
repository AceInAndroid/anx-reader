import 'dart:convert';

import 'package:anx_reader/models/reading_agent.dart';
import 'package:anx_reader/service/ai/fiction_backfill_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('backfill never loads chapters beyond safe boundary', () async {
    final loaded = <String>[];
    final artifacts = await fictionBackfillService.build(
      bookId: 1,
      moduleId: 'fiction.immersion',
      safeBoundary: .52,
      chapters: const [
        FictionBackfillChapter(
            href: 'early.xhtml',
            title: '前章',
            startProgress: .18,
            endProgress: .3),
        FictionBackfillChapter(
            href: 'partial.xhtml',
            title: '当前章',
            startProgress: .5,
            endProgress: .6),
        FictionBackfillChapter(
            href: 'future.xhtml',
            title: '后章',
            startProgress: .7,
            endProgress: .8),
      ],
      loadChapter: (href) async {
        loaded.add(href);
        return '林先生走进车站。';
      },
      generate: (_) async => jsonEncode([
        {
          'kind': 'character',
          'payload': {'name': '林先生', 'summary': '出现在车站'}
        }
      ]),
      sessionId: 'session',
      ingestedAt: 1234,
    );

    expect(loaded, ['early.xhtml']);
    expect(artifacts, hasLength(1));
    expect(artifacts.single.sourceProgress, .18);
    expect(artifacts.single.visibleFromProgress, .18);
    expect(artifacts.single.ingestedAt, 1234);
    expect(
        artifacts.single.ingestionMode, ReadingArtifactIngestionMode.backfill);
    expect(artifacts.single.isVisibleAtProgress(.1), isFalse);
    expect(artifacts.single.isVisibleAtProgress(.18), isTrue);
  });
}

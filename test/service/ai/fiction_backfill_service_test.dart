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

  test('event output is validated and uses stable ids for deduplication',
      () async {
    Future<List<ReadingArtifact>> build({
      Iterable<ReadingArtifact> existing = const [],
    }) =>
        fictionBackfillService.build(
          bookId: 1,
          moduleId: 'fiction.immersion',
          safeBoundary: .5,
          chapters: const [
            FictionBackfillChapter(
              href: 'one.xhtml',
              title: '第一章',
              startProgress: .1,
              endProgress: .2,
            ),
          ],
          loadChapter: (_) async => '两人在车站相遇。',
          generate: (_) async => jsonEncode([
            {
              'kind': 'event',
              'payload': {
                'title': '车站相遇',
                'summary': '两人第一次见面',
                'participants': ['甲', '乙'],
              },
            },
            {
              'kind': 'relationship',
              'payload': {'from': '甲'},
            },
          ]),
          sessionId: 'session',
          ingestedAt: 9999,
          existingArtifacts: existing,
        );

    final first = await build();
    final second = await build(existing: first);

    expect(first, hasLength(1));
    expect(first.single.kind, ReadingArtifactKinds.event);
    expect(first.single.id, startsWith('fiction-backfill-'));
    expect(second, isEmpty);
  });

  test('backfill respects the persisted artifact coverage lower bound',
      () async {
    final loaded = <String>[];
    final artifacts = await fictionBackfillService.build(
      bookId: 1,
      moduleId: 'fiction.immersion',
      safeBoundary: .5,
      fromProgress: .3,
      chapters: const [
        FictionBackfillChapter(
          href: 'unseen-prefix.xhtml',
          title: '本机未读前文',
          startProgress: .1,
          endProgress: .2,
        ),
        FictionBackfillChapter(
          href: 'local-range.xhtml',
          title: '本机起点之后',
          startProgress: .35,
          endProgress: .45,
        ),
      ],
      loadChapter: (href) async {
        loaded.add(href);
        return '正文';
      },
      generate: (_) async => jsonEncode([
        {
          'kind': 'event',
          'payload': {'title': '事件'}
        }
      ]),
      sessionId: 'session',
      ingestedAt: 1,
    );

    expect(loaded, ['local-range.xhtml']);
    expect(artifacts, hasLength(1));
    expect(artifacts.single.sourceProgress, .35);
  });
}

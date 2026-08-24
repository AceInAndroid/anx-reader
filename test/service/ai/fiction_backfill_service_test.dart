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

  test('batches chapters and emits resumable checkpoints after success',
      () async {
    var requests = 0;
    final completed = <String>[];
    final savedCheckpoints = <ReadingArtifact>[];
    final artifacts = await fictionBackfillService.build(
      bookId: 1,
      moduleId: 'fiction.immersion',
      safeBoundary: .8,
      batchSize: 2,
      chapters: const [
        FictionBackfillChapter(
            href: 'one.xhtml', title: '一', startProgress: .1, endProgress: .2),
        FictionBackfillChapter(
            href: 'two.xhtml', title: '二', startProgress: .2, endProgress: .3),
      ],
      loadChapter: (_) async => '同一批正文',
      generate: (_) async {
        requests++;
        return jsonEncode([
          {
            'chapterHref': 'one.xhtml',
            'items': [
              {
                'kind': 'event',
                'payload': {'title': '一中的事件'}
              }
            ]
          },
          {
            'chapterHref': 'two.xhtml',
            'items': [
              {
                'kind': 'event',
                'payload': {'title': '二中的事件'}
              }
            ]
          },
        ]);
      },
      sessionId: 'session',
      ingestedAt: 1,
      onBatchCompleted: ({
        required artifacts,
        required checkpoints,
        required completedChapters,
        required totalChapters,
      }) async {
        savedCheckpoints.addAll(checkpoints);
        completed.addAll(checkpoints.map((item) => item.chapterHref!));
        expect(artifacts, hasLength(2));
        expect(completedChapters, 2);
        expect(totalChapters, 2);
      },
    );

    expect(requests, 1);
    expect(artifacts, hasLength(2));
    expect(completed, ['one.xhtml', 'two.xhtml']);

    final resumed = await fictionBackfillService.build(
      bookId: 1,
      moduleId: 'fiction.immersion',
      safeBoundary: .8,
      batchSize: 2,
      chapters: const [
        FictionBackfillChapter(
            href: 'one.xhtml', title: '一', startProgress: .1, endProgress: .2),
        FictionBackfillChapter(
            href: 'two.xhtml', title: '二', startProgress: .2, endProgress: .3),
      ],
      loadChapter: (_) async => '同一批正文',
      generate: (_) async {
        requests++;
        return '[]';
      },
      sessionId: 'session',
      ingestedAt: 2,
      existingArtifacts: savedCheckpoints,
    );
    expect(resumed, isEmpty);
    expect(requests, 1);
  });

  test('persists successful concurrent batches before surfacing a failure',
      () async {
    final savedCheckpoints = <ReadingArtifact>[];
    var requests = 0;
    await expectLater(
      fictionBackfillService.build(
        bookId: 7,
        moduleId: 'fiction.immersion',
        safeBoundary: 1,
        batchSize: 1,
        concurrency: 2,
        chapters: const [
          FictionBackfillChapter(
              href: 'one.xhtml',
              title: '一',
              startProgress: .1,
              endProgress: .2),
          FictionBackfillChapter(
              href: 'two.xhtml',
              title: '二',
              startProgress: .2,
              endProgress: .3),
        ],
        loadChapter: (_) async => '正文',
        generate: (_) async {
          requests++;
          if (requests == 2) throw StateError('temporary failure');
          return jsonEncode([
            {
              'chapterHref': 'one.xhtml',
              'items': [
                {
                  'kind': 'event',
                  'payload': {'title': '已完成'}
                }
              ]
            }
          ]);
        },
        sessionId: 'session',
        ingestedAt: 1,
        onBatchCompleted: ({
          required artifacts,
          required checkpoints,
          required completedChapters,
          required totalChapters,
        }) async {
          savedCheckpoints.addAll(checkpoints);
        },
      ),
      throwsA(isA<StateError>()),
    );
    expect(savedCheckpoints, hasLength(1));
    expect(savedCheckpoints.single.chapterHref, 'one.xhtml');
  });

  test('does not checkpoint an incomplete model batch', () async {
    var callbackCalled = false;
    await expectLater(
      fictionBackfillService.build(
        bookId: 1,
        moduleId: 'fiction.immersion',
        safeBoundary: 1,
        batchSize: 2,
        chapters: const [
          FictionBackfillChapter(
              href: 'one.xhtml',
              title: '一',
              startProgress: .1,
              endProgress: .2),
          FictionBackfillChapter(
              href: 'two.xhtml',
              title: '二',
              startProgress: .2,
              endProgress: .3),
        ],
        loadChapter: (_) async => '正文',
        generate: (_) async => jsonEncode([
          {'chapterHref': 'one.xhtml', 'items': []}
        ]),
        sessionId: 'session',
        ingestedAt: 1,
        onBatchCompleted: ({
          required artifacts,
          required checkpoints,
          required completedChapters,
          required totalChapters,
        }) async {
          callbackCalled = true;
        },
      ),
      throwsFormatException,
    );
    expect(callbackCalled, isFalse);
  });

  test('reprocesses a checkpointed chapter when its content changes', () async {
    final savedCheckpoints = <ReadingArtifact>[];
    var requests = 0;

    Future<void> build(String content,
        {Iterable<ReadingArtifact> existing = const []}) async {
      await fictionBackfillService.build(
        bookId: 1,
        moduleId: 'fiction.immersion',
        safeBoundary: 1,
        chapters: const [
          FictionBackfillChapter(
              href: 'one.xhtml',
              title: '一',
              startProgress: .1,
              endProgress: .2),
        ],
        loadChapter: (_) async => content,
        generate: (_) async {
          requests++;
          return '[]';
        },
        sessionId: 'session',
        ingestedAt: 1,
        existingArtifacts: existing,
        onBatchCompleted: ({
          required artifacts,
          required checkpoints,
          required completedChapters,
          required totalChapters,
        }) async {
          savedCheckpoints.addAll(checkpoints);
        },
      );
    }

    await build('旧正文');
    await build('新正文', existing: savedCheckpoints);
    expect(requests, 2);
  });
}

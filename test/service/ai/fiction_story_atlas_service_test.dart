import 'package:anx_reader/models/reading_agent.dart';
import 'package:anx_reader/service/ai/fiction_story_atlas_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  ReadingArtifact artifact({
    required String id,
    required String kind,
    required double progress,
    required Map<String, dynamic> payload,
    int? createdAt,
  }) {
    final time = createdAt ?? (progress * 1000).round();
    return ReadingArtifact(
      id: id,
      bookId: 1,
      moduleId: 'fiction.immersion',
      kind: kind,
      payload: payload,
      sourceProgress: progress,
      visibleFromProgress: progress,
      chapterHref: 'chapter-$progress.xhtml',
      chapterTitle: '章节 $progress',
      ingestedAt: time,
      createdAt: time,
      updatedAt: time,
    );
  }

  test('filters future artifacts and selects latest visible relationship', () {
    final atlas = fictionStoryAtlasService.fromArtifacts([
      artifact(
        id: 'a',
        kind: ReadingArtifactKinds.character,
        progress: .1,
        payload: {'entityId': 'alice', 'name': '爱丽丝'},
      ),
      artifact(
        id: 'b',
        kind: ReadingArtifactKinds.character,
        progress: .12,
        payload: {'entityId': 'bob', 'name': '鲍勃'},
      ),
      artifact(
        id: 'r1',
        kind: ReadingArtifactKinds.relationship,
        progress: .2,
        payload: {
          'from': 'alice',
          'to': 'bob',
          'relation': '陌生人',
          'state': 'active',
        },
      ),
      artifact(
        id: 'r2',
        kind: ReadingArtifactKinds.relationship,
        progress: .4,
        payload: {
          'from': '爱丽丝',
          'to': '鲍勃',
          'relation': '朋友',
          'state': 'changed',
        },
      ),
      artifact(
        id: 'future',
        kind: ReadingArtifactKinds.character,
        progress: .8,
        payload: {'name': '未来人物'},
      ),
    ], visibleAtProgress: .5);

    expect(atlas.characters.map((item) => item.name), isNot(contains('未来人物')));
    expect(atlas.relationships.single.relation, '朋友');
    expect(atlas.relationships.single.history, hasLength(2));
  });

  test('sorts timeline by source order instead of story time label', () {
    final atlas = fictionStoryAtlasService.fromArtifacts([
      artifact(
        id: 'later-text',
        kind: ReadingArtifactKinds.event,
        progress: .3,
        payload: {'title': '十年前', 'storyTimeLabel': '十年前'},
      ),
      artifact(
        id: 'earlier-text',
        kind: ReadingArtifactKinds.event,
        progress: .1,
        payload: {'title': '今天', 'storyTimeLabel': '今天'},
      ),
      artifact(
        id: 'unknown',
        kind: 'fiction.location',
        progress: .05,
        payload: {'title': '安全忽略'},
      ),
    ], visibleAtProgress: .5);

    expect(atlas.timeline.map((item) => item.title), ['今天', '十年前']);
  });

  test('groups long timeline by chapter and applies density and participant',
      () {
    final atlas = fictionStoryAtlasService.fromArtifacts([
      artifact(
        id: 'major',
        kind: ReadingArtifactKinds.event,
        progress: .1,
        payload: {
          'title': '重大转折',
          'importance': 'major',
          'participants': ['林青'],
        },
      ),
      artifact(
        id: 'normal',
        kind: ReadingArtifactKinds.event,
        progress: .2,
        payload: {
          'title': '普通事件',
          'participants': ['周明']
        },
      ),
      artifact(
        id: 'scene',
        kind: ReadingArtifactKinds.scene,
        progress: .3,
        payload: {
          'title': '场景描写',
          'participants': ['林青']
        },
      ),
    ], visibleAtProgress: .5);

    final compact = fictionStoryAtlasService.timelineChapters(atlas.timeline);
    expect(
        compact.expand((chapter) => chapter.events).map((event) => event.title),
        ['重大转折']);

    final standard = fictionStoryAtlasService.timelineChapters(
      atlas.timeline,
      density: FictionTimelineDensity.standard,
    );
    expect(standard.expand((chapter) => chapter.events), hasLength(2));

    final linQing = fictionStoryAtlasService.timelineChapters(
      atlas.timeline,
      density: FictionTimelineDensity.complete,
      participant: '林青',
    );
    expect(linQing.expand((chapter) => chapter.events), hasLength(2));
  });
}

import 'package:anx_reader/models/book.dart';
import 'package:anx_reader/models/reading_agent.dart';
import 'package:anx_reader/page/fiction_character_graph_page.dart';
import 'package:anx_reader/page/fiction_story_timeline_page.dart';
import 'package:anx_reader/service/ai/fiction_story_atlas_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 8, 24).millisecondsSinceEpoch;
  final book = Book.mock().copyWith(readingPercentage: .5);

  ReadingArtifact artifact(
    String id,
    String kind,
    double progress,
    Map<String, dynamic> payload,
  ) =>
      ReadingArtifact(
        id: id,
        bookId: book.id,
        moduleId: 'fiction.immersion',
        kind: kind,
        payload: payload,
        sourceStartCfi: 'epubcfi(/6/$id)',
        sourceTextSnapshot: '来源正文',
        chapterTitle: '第一章',
        sourceProgress: progress,
        visibleFromProgress: progress,
        ingestedAt: now,
        createdAt: now,
        updatedAt: now,
      );

  final atlas = fictionStoryAtlasService.fromArtifacts([
    artifact('a', ReadingArtifactKinds.character, .1,
        {'entityId': 'a', 'name': '阿青', 'summary': '剑客'}),
    artifact('b', ReadingArtifactKinds.character, .12,
        {'entityId': 'b', 'name': '白公公', 'summary': '对手'}),
    artifact('r', ReadingArtifactKinds.relationship, .2, {
      'from': 'a',
      'to': 'b',
      'relation': '对手',
      'summary': '在宫中交锋',
      'state': 'active',
    }),
    artifact('e', ReadingArtifactKinds.event, .25, {
      'title': '宫中交锋',
      'summary': '两人在宫中第一次正面交锋',
      'participants': ['a', 'b'],
      'importance': 'major',
    }),
  ], visibleAtProgress: .5);

  testWidgets('character graph uses initial avatars and relationship labels',
      (tester) async {
    tester.view.physicalSize = const Size(1024, 768);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      home: FictionCharacterGraphPage(book: book, initialAtlas: atlas),
    ));
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('人物关系图'), findsOneWidget);
    expect(find.text('阿青'), findsOneWidget);
    expect(find.text('白公公'), findsOneWidget);
    expect(find.text('对手'), findsOneWidget);
    expect(find.byType(Image), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('timeline renders narrative order metadata on phone',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      home: FictionStoryTimelinePage(book: book, initialAtlas: atlas),
    ));
    await tester.pumpAndSettle();

    expect(find.text('故事事件时间线'), findsOneWidget);
    expect(find.text('宫中交锋'), findsOneWidget);
    expect(find.text('时间未明'), findsOneWidget);
    expect(find.text('正文顺序 · 安全边界 50%'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

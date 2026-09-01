import 'package:anx_reader/models/book.dart';
import 'package:anx_reader/models/next_reading_action.dart';
import 'package:anx_reader/service/ai/fiction_story_atlas_service.dart';
import 'package:anx_reader/service/ai/reading_closure_policy.dart';
import 'package:anx_reader/service/ai/reading_outcomes_service.dart';
import 'package:anx_reader/widgets/reading_page/reading_book_hub.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final book = Book(
    id: 7,
    title: '测试小说',
    coverPath: '',
    filePath: '',
    lastReadPosition: 'epubcfi(/6/2)',
    readingPercentage: .36,
    author: '作者',
    isDeleted: false,
    rating: 0,
    createTime: DateTime(2026),
    updateTime: DateTime(2026),
  );

  testWidgets('book hub keeps one primary action and converged entries', (
    tester,
  ) async {
    final atlas = fictionStoryAtlasService.fromArtifacts(
      const [],
      visibleAtProgress: .36,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReadingBookHubContent(
            book: book,
            state: ReadingOutcomesSnapshot(loadedAt: DateTime(2026)),
            closure: ReadingClosurePolicyRegistry.fictionImmersion,
            nextAction: const NextReadingAction(
              id: 'next',
              kind: NextReadingActionKinds.resumeContext,
              bookId: 7,
              sourceId: 'resume',
              title: '恢复上次阅读上下文',
              reason: '先回顾近期人物和场景。',
              priority: 0,
              target: NextReadingActionTarget(
                kind: NextReadingActionTargetKinds.resumeContext,
              ),
              completionFingerprint: 'resume:7',
            ),
            atlas: atlas,
            syncing: false,
            syncEnabled: true,
            onNextAction: () async {},
            onOpenOutcomes: () async {},
            onOpenWiki: () async {},
            onOpenStoryArchive: () async {},
            onSync: () async {},
            onOpenReadingSettings: () async {},
          ),
        ),
      ),
    );

    expect(find.text('恢复上次阅读上下文'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '开始'), findsOneWidget);
    expect(find.text('阅读成果'), findsOneWidget);
    expect(find.text('书籍 Wiki'), findsOneWidget);
    expect(find.text('故事档案'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('同步状态'),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('同步状态'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('book hub uses static sync state when animations are disabled', (
    tester,
  ) async {
    final atlas = fictionStoryAtlasService.fromArtifacts(
      const [],
      visibleAtProgress: .36,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Scaffold(
            body: ReadingBookHubContent(
              book: book,
              state: ReadingOutcomesSnapshot(loadedAt: DateTime(2026)),
              closure: ReadingClosurePolicyRegistry.fictionImmersion,
              nextAction: const NextReadingAction(
                id: 'continue',
                kind: NextReadingActionKinds.continueReading,
                bookId: 7,
                sourceId: 'reader',
                title: '继续阅读',
                reason: '保持沉浸。',
                priority: 0,
                target: NextReadingActionTarget(
                  kind: NextReadingActionTargetKinds.reader,
                ),
                completionFingerprint: 'reader:7',
              ),
              atlas: atlas,
              syncing: true,
              syncEnabled: true,
              onNextAction: () async {},
              onOpenOutcomes: () async {},
              onOpenWiki: () async {},
              onOpenStoryArchive: () async {},
              onSync: () async {},
              onOpenReadingSettings: () async {},
            ),
          ),
        ),
      ),
    );

    await tester.scrollUntilVisible(
      find.text('同步状态'),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byIcon(Icons.sync_disabled), findsOneWidget);
  });
}

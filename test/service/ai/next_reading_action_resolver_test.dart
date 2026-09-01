import 'package:anx_reader/models/next_reading_action.dart';
import 'package:anx_reader/models/reading_agent.dart';
import 'package:anx_reader/models/reading_coach.dart';
import 'package:anx_reader/service/ai/next_reading_action_resolver.dart';
import 'package:anx_reader/service/ai/reading_closure_policy.dart';
import 'package:anx_reader/service/ai/reading_outcomes_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const resolver = NextReadingActionResolver();
  final now = DateTime(2026, 8, 31).millisecondsSinceEpoch;

  ReadingOutcomesSnapshot snapshot({
    bool dueCard = false,
    bool checkpoint = false,
    bool difficulty = false,
    bool goal = false,
  }) =>
      ReadingOutcomesSnapshot(
        goals: goal
            ? [
                ReadingGoal(
                  id: 'goal',
                  bookId: 1,
                  title: '理解本章',
                  createdAt: now,
                  updatedAt: now,
                ),
              ]
            : const [],
        pendingCheckpoints: checkpoint
            ? [
                ReadingChapterCheckpoint(
                  id: 'checkpoint',
                  bookId: 1,
                  chapterHref: 'chapter.xhtml',
                  chapterTitle: '第一章',
                  createdAt: now,
                  updatedAt: now,
                ),
              ]
            : const [],
        difficulties: difficulty
            ? [
                ReadingDifficulty(
                  id: 'difficulty',
                  bookId: 1,
                  cfi: 'epubcfi(/6/2)',
                  text: '证据如何支持结论？',
                  createdAt: now,
                  updatedAt: now,
                ),
              ]
            : const [],
        knowledgeCards: dueCard
            ? [
                KnowledgeCard(
                  id: 'card',
                  bookId: 1,
                  front: '问题',
                  back: '答案',
                  dueAt: now - 1,
                  createdAt: now,
                  updatedAt: now,
                ),
              ]
            : const [],
        loadedAt: DateTime.fromMillisecondsSinceEpoch(now),
      );

  test('knowledge closure prioritizes a due card over other candidates', () {
    final action = resolver.resolve(
      bookId: 1,
      outcomes: snapshot(
        dueCard: true,
        checkpoint: true,
        difficulty: true,
        goal: true,
      ),
      closure: ReadingClosurePolicyRegistry.knowledgeArgument,
    );

    expect(action.kind, NextReadingActionKinds.dueReview);
    expect(action.priority, 0);
  });

  test('psychology closure prioritizes checkpoint then difficulty', () {
    final withCheckpoint = resolver.resolve(
      bookId: 1,
      outcomes: snapshot(
        dueCard: true,
        checkpoint: true,
        difficulty: true,
      ),
      closure: ReadingClosurePolicyRegistry.psychologyReflection,
    );
    final withoutCheckpoint = resolver.resolve(
      bookId: 1,
      outcomes: snapshot(dueCard: true, difficulty: true),
      closure: ReadingClosurePolicyRegistry.psychologyReflection,
    );

    expect(withCheckpoint.kind, NextReadingActionKinds.chapterCheckpoint);
    expect(withoutCheckpoint.kind, NextReadingActionKinds.unresolvedDifficulty);
  });

  test('fiction closure keeps resume context ahead of an active goal', () {
    final action = resolver.resolve(
      bookId: 1,
      outcomes: snapshot(goal: true),
      closure: ReadingClosurePolicyRegistry.fictionImmersion,
      resumeContextAvailable: true,
    );

    expect(action.kind, NextReadingActionKinds.resumeContext);
  });

  test('empty outcomes degrade to passive continue reading', () {
    final action = resolver.resolve(
      bookId: 1,
      outcomes: snapshot(),
      closure: ReadingClosurePolicyRegistry.knowledgeArgument,
    );

    expect(action.kind, NextReadingActionKinds.continueReading);
    expect(action.isPassive, isTrue);
  });
}

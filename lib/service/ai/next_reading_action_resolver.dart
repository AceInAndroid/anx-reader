import 'package:anx_reader/models/next_reading_action.dart';
import 'package:anx_reader/models/reading_agent.dart';
import 'package:anx_reader/service/ai/fiction_story_atlas_service.dart';
import 'package:anx_reader/service/ai/reading_closure_policy.dart';
import 'package:anx_reader/service/ai/reading_outcomes_service.dart';

/// Builds one deterministic next step from existing outcomes.
///
/// This resolver owns no persistence and never invokes a model. A source
/// record changing or disappearing is the completion signal.
class NextReadingActionResolver {
  const NextReadingActionResolver();

  NextReadingAction resolve({
    required int bookId,
    required ReadingOutcomesSnapshot outcomes,
    required ReadingClosurePolicyDefinition closure,
    BookReadingCoverage? coverage,
    FictionStoryAtlas? atlas,
    bool resumeContextAvailable = false,
  }) {
    final candidates = <String, NextReadingAction>{};
    final dueCard = outcomes.dueCards.firstOrNull;
    if (dueCard != null && closure.showKnowledgeCards) {
      candidates[NextReadingActionKinds.dueReview] = NextReadingAction(
        id: '${NextReadingActionKinds.dueReview}:$bookId:${dueCard.id}',
        kind: NextReadingActionKinds.dueReview,
        bookId: bookId,
        sourceId: dueCard.id,
        title: '先复习 ${outcomes.dueCards.length} 张到期卡片',
        reason: '先处理已到期的短时回忆，再继续阅读。',
        priority: 0,
        target: NextReadingActionTarget(
          kind: NextReadingActionTargetKinds.reviewCard,
          location: dueCard.chapterHref,
          payload: {'cardId': dueCard.id},
        ),
        completionFingerprint:
            '${dueCard.id}:${dueCard.updatedAt}:${dueCard.dueAt}',
      );
    }

    final checkpoint = outcomes.pendingCheckpoints.firstOrNull;
    if (checkpoint != null && !closure.immersive) {
      candidates[NextReadingActionKinds.chapterCheckpoint] = NextReadingAction(
        id: '${NextReadingActionKinds.chapterCheckpoint}:$bookId:${checkpoint.id}',
        kind: NextReadingActionKinds.chapterCheckpoint,
        bookId: bookId,
        sourceId: checkpoint.id,
        title: '${closure.checkpointAction}“${checkpoint.chapterTitle}”',
        reason: '完成一个已读章节的${closure.checkpointTitle}。',
        priority: 0,
        target: NextReadingActionTarget(
          kind: NextReadingActionTargetKinds.checkpoint,
          location: checkpoint.chapterHref,
          payload: {'checkpointId': checkpoint.id},
        ),
        completionFingerprint:
            '${checkpoint.id}:${checkpoint.updatedAt}:${checkpoint.status.name}',
      );
    }

    final difficulty = outcomes.unresolvedDifficulties.firstOrNull;
    if (difficulty != null) {
      candidates[NextReadingActionKinds.unresolvedDifficulty] =
          NextReadingAction(
        id: '${NextReadingActionKinds.unresolvedDifficulty}:$bookId:${difficulty.id}',
        kind: NextReadingActionKinds.unresolvedDifficulty,
        bookId: bookId,
        sourceId: difficulty.id,
        title:
            closure.immersive ? '查看一个未解悬念' : '处理一个${closure.difficultyTitle}',
        reason: difficulty.text,
        priority: 0,
        target: NextReadingActionTarget(
          kind: NextReadingActionTargetKinds.difficulty,
          location: difficulty.cfi,
          payload: {'difficultyId': difficulty.id},
        ),
        completionFingerprint:
            '${difficulty.id}:${difficulty.updatedAt}:${difficulty.status.name}',
      );
    }

    final goal = outcomes.activeGoal;
    if (goal != null) {
      candidates[NextReadingActionKinds.activeGoal] = NextReadingAction(
        id: '${NextReadingActionKinds.activeGoal}:$bookId:${goal.id}',
        kind: NextReadingActionKinds.activeGoal,
        bookId: bookId,
        sourceId: goal.id,
        title: '继续“${goal.title}”',
        reason: '当前进度 ${(goal.progress * 100).round()}%。',
        priority: 0,
        target: const NextReadingActionTarget(
          kind: NextReadingActionTargetKinds.goal,
        ),
        completionFingerprint:
            '${goal.id}:${goal.updatedAt}:${goal.progress}:${goal.status.name}',
      );
    }

    if (resumeContextAvailable) {
      candidates[NextReadingActionKinds.resumeContext] = NextReadingAction(
        id: '${NextReadingActionKinds.resumeContext}:$bookId',
        kind: NextReadingActionKinds.resumeContext,
        bookId: bookId,
        sourceId: 'resume-context',
        title: '恢复上次阅读上下文',
        reason: '先回顾近期人物、场景和未解悬念。',
        priority: 0,
        target: const NextReadingActionTarget(
          kind: NextReadingActionTargetKinds.resumeContext,
        ),
        completionFingerprint: 'resume-context:$bookId',
      );
    }

    final mysteries =
        atlas?.timeline.where((event) => event.isMystery).toList() ??
            const <FictionTimelineEvent>[];
    if (mysteries.isNotEmpty) {
      final mystery = mysteries.last;
      candidates[NextReadingActionKinds.fictionMystery] = NextReadingAction(
        id: '${NextReadingActionKinds.fictionMystery}:$bookId:${mystery.id}',
        kind: NextReadingActionKinds.fictionMystery,
        bookId: bookId,
        sourceId: mystery.id,
        title: '查看当前未解悬念',
        reason: mystery.title,
        priority: 0,
        target: const NextReadingActionTarget(
          kind: NextReadingActionTargetKinds.storyMysteries,
        ),
        completionFingerprint:
            '${mystery.id}:${mystery.source.updatedAt}:${mystery.source.status.name}',
      );
    }

    final maintainArchive = coverage != null &&
        !coverage.setupPending &&
        coverage.setupStatus != ReadingCoverageSetupStatus.fromHere;
    final coverageGap = maintainArchive &&
        coverage.safeKnowledgeBoundary >
            coverage.artifactCoverageEnd + 0.000001;
    if (coverageGap) {
      candidates[NextReadingActionKinds.archiveCoverage] = NextReadingAction(
        id: '${NextReadingActionKinds.archiveCoverage}:$bookId',
        kind: NextReadingActionKinds.archiveCoverage,
        bookId: bookId,
        sourceId: 'coverage',
        title: '补齐已读故事档案',
        reason:
            '档案到 ${(coverage.artifactCoverageEnd * 100).round()}%，安全边界已到 ${(coverage.safeKnowledgeBoundary * 100).round()}%。',
        priority: 0,
        target: const NextReadingActionTarget(
          kind: NextReadingActionTargetKinds.organizeArchive,
        ),
        completionFingerprint:
            '${coverage.updatedAt}:${coverage.artifactCoverageEnd}:${coverage.safeKnowledgeBoundary}',
      );
    }

    candidates[NextReadingActionKinds.continueReading] = NextReadingAction(
      id: '${NextReadingActionKinds.continueReading}:$bookId',
      kind: NextReadingActionKinds.continueReading,
      bookId: bookId,
      sourceId: 'reader',
      title: '继续阅读',
      reason: closure.immersive ? '保持沉浸，不需要完成测试。' : '从当前位置继续推进。',
      priority: closure.nextActionOrder.length,
      target: const NextReadingActionTarget(
        kind: NextReadingActionTargetKinds.reader,
      ),
      completionFingerprint: 'reader:$bookId',
    );

    for (var index = 0; index < closure.nextActionOrder.length; index++) {
      final kind = closure.nextActionOrder[index];
      final candidate = candidates[kind];
      if (candidate != null) {
        return NextReadingAction(
          id: candidate.id,
          kind: candidate.kind,
          bookId: candidate.bookId,
          sourceId: candidate.sourceId,
          title: candidate.title,
          reason: candidate.reason,
          priority: index,
          target: candidate.target,
          completionFingerprint: candidate.completionFingerprint,
        );
      }
    }
    return candidates[NextReadingActionKinds.continueReading]!;
  }
}

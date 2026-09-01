/// Stable action identifiers projected from existing reading outcomes.
///
/// These values are intentionally strings so closure modules can declare an
/// order without coupling persisted profiles or extension modules to enums.
abstract final class NextReadingActionKinds {
  static const dueReview = 'reading_action.due_review';
  static const chapterCheckpoint = 'reading_action.chapter_checkpoint';
  static const unresolvedDifficulty = 'reading_action.unresolved_difficulty';
  static const activeGoal = 'reading_action.active_goal';
  static const resumeContext = 'reading_action.resume_context';
  static const fictionMystery = 'reading_action.fiction_mystery';
  static const archiveCoverage = 'reading_action.archive_coverage';
  static const continueReading = 'reading_action.continue_reading';
}

abstract final class NextReadingActionTargetKinds {
  static const reviewCard = 'reading_target.review_card';
  static const checkpoint = 'reading_target.checkpoint';
  static const difficulty = 'reading_target.difficulty';
  static const goal = 'reading_target.goal';
  static const resumeContext = 'reading_target.resume_context';
  static const storyMysteries = 'reading_target.story_mysteries';
  static const organizeArchive = 'reading_target.organize_archive';
  static const reader = 'reading_target.reader';
}

class NextReadingActionTarget {
  const NextReadingActionTarget({
    required this.kind,
    this.location,
    this.payload = const {},
  });

  final String kind;
  final String? location;
  final Map<String, Object?> payload;
}

/// A read-only projection. Completion is derived from the source record, so
/// this object is never stored or synchronized.
class NextReadingAction {
  const NextReadingAction({
    required this.id,
    required this.kind,
    required this.bookId,
    required this.sourceId,
    required this.title,
    required this.reason,
    required this.priority,
    required this.target,
    required this.completionFingerprint,
  });

  final String id;
  final String kind;
  final int bookId;
  final String sourceId;
  final String title;
  final String reason;
  final int priority;
  final NextReadingActionTarget target;
  final String completionFingerprint;

  bool get isPassive => kind == NextReadingActionKinds.continueReading;
}

import 'dart:collection';

/// Coarse activity state shared by reading, synchronization and background
/// work. It deliberately carries no book content or persisted state.
enum ReadingActivityState { activeReading, idle, background }

/// Coordinates automatic work so it does not compete with active reading.
///
/// Automatic sync requests are represented by one pending intent. The sync
/// provider remains responsible for direction merging and single-flight
/// execution; this class only answers when automatic work may run.
class ReadingActivityCoordinator {
  ReadingActivityCoordinator();

  static final ReadingActivityCoordinator instance =
      ReadingActivityCoordinator();

  final Set<Object> _readingSessions = HashSet<Object>.identity();
  bool _isBackground = false;
  bool _hasPendingAutomaticSync = false;
  bool _backgroundFlushPermitted = false;

  ReadingActivityState get state {
    if (_isBackground) return ReadingActivityState.background;
    if (_readingSessions.isNotEmpty) {
      return ReadingActivityState.activeReading;
    }
    return ReadingActivityState.idle;
  }

  bool get hasPendingAutomaticSync => _hasPendingAutomaticSync;

  /// Retains one automatic intent when a background check could not run (for
  /// example while offline). The caller stores the desired direction beside
  /// this flag so the next eligible foreground/idle check can execute it.
  void queueAutomaticSync() => _hasPendingAutomaticSync = true;

  void startReading(Object session) {
    _readingSessions.add(session);
    _backgroundFlushPermitted = false;
  }

  void finishReading(Object session) {
    _readingSessions.remove(session);
  }

  void enterBackground() {
    _isBackground = true;
  }

  void enterForeground() {
    _isBackground = false;
    _backgroundFlushPermitted = false;
  }

  /// Called after the reading page has persisted its position and session
  /// state. The following automatic request may flush the coalesced intent.
  void permitBackgroundFlush() {
    _backgroundFlushPermitted = true;
  }

  /// Returns true when the request must be delayed until reading stops or the
  /// application enters the background.
  bool deferAutomaticSyncIfReading() {
    final mustWaitForReadingCheckpoint = _readingSessions.isNotEmpty &&
        (!_isBackground || !_backgroundFlushPermitted);
    if (!mustWaitForReadingCheckpoint) return false;
    _hasPendingAutomaticSync = true;
    return true;
  }

  /// Consumes the coalesced intent immediately before an automatic sync.
  bool consumePendingAutomaticSync() {
    final hadPendingIntent = _hasPendingAutomaticSync;
    _hasPendingAutomaticSync = false;
    _backgroundFlushPermitted = false;
    return hadPendingIntent;
  }
}

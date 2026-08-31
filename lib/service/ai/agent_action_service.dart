import 'package:anx_reader/models/reading_agent.dart';
import 'package:anx_reader/models/reading_evidence.dart';
import 'package:anx_reader/models/reading_coach.dart';
import 'package:anx_reader/models/reading_note.dart';
import 'package:anx_reader/models/book_note.dart';
import 'package:anx_reader/models/book_wiki.dart';
import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:uuid/uuid.dart';
import 'package:anx_reader/service/ai/reading_agent_repository.dart';
import 'package:anx_reader/service/ai/reading_agent_runtime.dart';
import 'package:anx_reader/service/ai/reading_evidence_adapter.dart';
import 'package:anx_reader/service/ai/validated_ai_mutation.dart';
import 'package:anx_reader/utils/log/common.dart';

/// Single mutation boundary used by Reading Agent tools and UI commands.
/// Repository transactions persist both the mutation and its undo journal.
class AgentActionService {
  AgentActionService({
    ReadingAgentRepository? repository,
    ReadingAgentRuntimeController? runtime,
  })  : _repository = repository ?? readingAgentRepository,
        _runtime = runtime ?? readingAgentRuntime;

  final ReadingAgentRepository _repository;
  final ReadingAgentRuntimeController _runtime;

  Future<AgentMutation<T>> applyValidated<T>(
    ValidatedAiMutation<T> mutation,
    Future<AgentMutation<T>> Function() apply,
  ) async {
    _validateMutation(mutation);
    final result = await apply();
    _logAppliedMutation(mutation, result.action.id);
    return result;
  }

  Future<AgentMutation<T>?> applyValidatedNullable<T>(
    ValidatedAiMutation<T> mutation,
    Future<AgentMutation<T>?> Function() apply,
  ) async {
    _validateMutation(mutation);
    final result = await apply();
    if (result != null) _logAppliedMutation(mutation, result.action.id);
    return result;
  }

  void _validateMutation<T>(ValidatedAiMutation<T> mutation) {
    if (!mutation.isAuthorized) {
      throw StateError('Proactive AI suggestions require user confirmation');
    }
    validateEvidenceForMutation(
      evidence: mutation.evidence,
      bookId: mutation.bookId,
      visibleProgress: mutation.visibleProgress,
    );
  }

  void _logAppliedMutation<T>(
    ValidatedAiMutation<T> mutation,
    String actionId,
  ) {
    AnxLog.info(
      'AI mutation applied action=${mutation.actionType} '
      'target=${mutation.targetType} actionId=$actionId '
      'requestId=${mutation.requestId ?? '-'} taskId=${mutation.taskId ?? '-'} '
      'workloadId=${mutation.workloadId ?? '-'}',
    );
  }

  /// Common validation boundary for new AI write commands. Existing typed
  /// methods remain the compatibility facade and continue to own domain
  /// validation and repository transactions.
  void validateEvidenceForMutation({
    required Iterable<EvidenceEnvelope> evidence,
    required int bookId,
    required double visibleProgress,
  }) {
    for (final item in evidence) {
      if (!item.isTraceable) {
        throw ArgumentError('AI mutation contains untraceable evidence');
      }
      if (item.bookId != null && item.bookId != bookId) {
        throw ArgumentError('AI mutation evidence belongs to another book');
      }
      if (!item.isVisibleAtProgress(visibleProgress)) {
        throw ArgumentError('AI mutation evidence exceeds spoiler boundary');
      }
    }
  }

  String get _sessionId {
    final value = _runtime.state.sessionId;
    if (value == null) throw StateError('No active reading session');
    return value;
  }

  Future<AgentMutation<ReadingGoal>> saveGoal(ReadingGoal goal) async {
    final mutation = await applyValidated(
      ValidatedAiMutation<ReadingGoal>(
        actionType: 'reading_goal_save',
        targetType: 'reading_goal',
        targetId: goal.id,
        bookId: goal.bookId,
        value: goal,
        authorization: AiMutationAuthorization.confirmedTask,
        visibleProgress: _runtime.state.totalProgress,
      ),
      () => _repository.saveGoal(goal, sessionId: _sessionId),
    );
    _runtime.goalChanged(goal.status == ReadingGoalStatus.active ? goal : null);
    _runtime.actionApplied(mutation.action);
    return mutation;
  }

  Future<AgentMutation<ReadingNoteDocument>> createNote(
    ReadingNoteDocument document, {
    int? ownedAnnotationId,
    BookNote? ownedAnnotation,
  }) async {
    final mutation = await applyValidated(
      ValidatedAiMutation<ReadingNoteDocument>(
        actionType: 'reading_note_create',
        targetType: 'reading_note',
        targetId: document.note.id,
        bookId: document.note.bookId,
        value: document,
        authorization: AiMutationAuthorization.confirmedTask,
        evidence: [
          for (final source in document.sources)
            if (ReadingEvidenceAdapter.fromNoteSource(
              source,
              bookId: document.note.bookId,
              visibleFromProgress: _runtime.state.totalProgress,
            )
                case final item?)
              item,
        ],
        visibleProgress: _runtime.state.totalProgress,
      ),
      () => _repository.createNote(
        document,
        sessionId: _sessionId,
        ownedAnnotationId: ownedAnnotationId,
        ownedAnnotation: ownedAnnotation,
      ),
    );
    if (ownedAnnotation != null) {
      ReaderCommandGateway.instance.showAnnotation(ownedAnnotation);
    }
    _runtime.actionApplied(mutation.action);
    return mutation;
  }

  Future<AgentMutation<ReadingNoteDocument>> createSourcedNote({
    required int bookId,
    required String sourceText,
    required String cfi,
    required String chapterTitle,
    String? chapterHref,
    required String body,
    String title = '',
    String model = 'unknown',
  }) async {
    if (sourceText.trim().isEmpty ||
        !cfi.startsWith('epubcfi(') ||
        !cfi.endsWith(')') ||
        body.trim().isEmpty) {
      throw ArgumentError('A valid source, CFI, and note body are required');
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    final noteId = const Uuid().v4();
    final document = ReadingNoteDocument(
      note: ReadingNote(
        id: noteId,
        bookId: bookId,
        title: title.trim(),
        status: ReadingNoteStatus.active,
        captureKind: ReadingNoteCaptureKind.manual,
        isFavorite: false,
        createdAt: now,
        updatedAt: now,
      ),
      blocks: [
        ReadingNoteBlock(
          id: const Uuid().v4(),
          noteId: noteId,
          type: ReadingNoteBlockType.quote,
          content: sourceText.trim(),
          sortOrder: 0,
          origin: ReadingNoteBlockOrigin.source,
          createdAt: now,
          updatedAt: now,
        ),
        ReadingNoteBlock(
          id: const Uuid().v4(),
          noteId: noteId,
          type: ReadingNoteBlockType.ai,
          content: body.trim(),
          sortOrder: 1,
          origin: ReadingNoteBlockOrigin.ai,
          metadata: {'model': model, 'sessionId': _sessionId},
          createdAt: now,
          updatedAt: now,
        ),
      ],
      sources: [
        ReadingNoteSource(
          noteId: noteId,
          type: ReadingNoteSourceType.aiSession,
          sourceRef: _sessionId,
          chapterHref: chapterHref,
          chapterTitle: chapterTitle,
          cfi: cfi,
          textSnapshot: sourceText.trim(),
          metadata: {'model': model},
          createdAt: now,
        ),
      ],
    );
    return createNote(
      document,
      ownedAnnotation: BookNote(
        bookId: bookId,
        content: sourceText.trim(),
        cfi: cfi,
        chapter: chapterTitle,
        type: 'highlight',
        color: Prefs().annotationColor,
        readerNote: body.trim(),
        createTime: DateTime.fromMillisecondsSinceEpoch(now),
        updateTime: DateTime.fromMillisecondsSinceEpoch(now),
      ),
    );
  }

  Future<AgentMutation<ReadingDifficulty>> saveDifficulty(
    ReadingDifficulty difficulty,
  ) async {
    final mutation = await applyValidated(
      ValidatedAiMutation<ReadingDifficulty>(
        actionType: 'reading_difficulty_save',
        targetType: 'reading_difficulty',
        targetId: difficulty.id,
        bookId: difficulty.bookId,
        value: difficulty,
        authorization: AiMutationAuthorization.confirmedTask,
        visibleProgress: _runtime.state.totalProgress,
      ),
      () => _repository.saveDifficulty(difficulty, sessionId: _sessionId),
    );
    ReaderCommandGateway.instance.showDifficulty(
      id: mutation.value.id,
      cfi: mutation.value.cfi,
    );
    _runtime.actionApplied(mutation.action);
    return mutation;
  }

  Future<AgentMutation<ReadingMemoryDocument>> appendMemory(
      ReadingMemoryDocument document) async {
    final mutation = await applyValidated(
      ValidatedAiMutation<ReadingMemoryDocument>(
        actionType: 'reading_memory_append',
        targetType: 'reading_memory',
        targetId: document.id,
        bookId: document.bookId,
        value: document,
        authorization: AiMutationAuthorization.confirmedTask,
        visibleProgress: _runtime.state.totalProgress,
      ),
      () => _repository.appendMemory(document, sessionId: _sessionId),
    );
    _runtime.memoryAdded(document.title);
    _runtime.actionApplied(mutation.action);
    return mutation;
  }

  Future<AgentMutation<ReadingArtifact>> saveArtifact(
      ReadingArtifact artifact) async {
    final source = ReadingEvidenceAdapter.fromArtifact(artifact);
    final mutation = await applyValidated(
      ValidatedAiMutation<ReadingArtifact>(
        actionType: 'reading_artifact_save',
        targetType: 'reading_artifact',
        targetId: artifact.id,
        bookId: artifact.bookId,
        value: artifact,
        authorization: AiMutationAuthorization.confirmedTask,
        evidence: source == null ? const [] : [source],
        visibleProgress: _runtime.state.totalProgress,
      ),
      () => _repository.saveArtifact(artifact, sessionId: _sessionId),
    );
    _runtime.actionApplied(mutation.action);
    return mutation;
  }

  Future<AgentMutation<BookWikiEntry>> saveWikiEntry(
    BookWikiEntry entry, {
    BookWiki? wiki,
    BookWikiRevision? revision,
    String? sessionId,
  }) async {
    final evidence = [
      for (final source in entry.sources)
        if (ReadingEvidenceAdapter.fromWikiSource(
          source,
          visibleFromProgress: entry.visibleFromProgress,
          epistemicStatus: entry.epistemicStatus,
        )
            case final resolved?)
          resolved,
    ];
    final mutation = await applyValidated(
      ValidatedAiMutation<BookWikiEntry>(
        actionType: 'book_wiki_entry_save',
        targetType: 'book_wiki_entry',
        targetId: entry.id,
        bookId: entry.bookId,
        value: entry,
        authorization: AiMutationAuthorization.confirmedTask,
        evidence: evidence,
        // Full-book Wiki generation is explicitly confirmed and may persist
        // future entries while keeping them hidden by visibleFromProgress.
        visibleProgress: 1,
      ),
      () => _repository.saveWikiEntry(
        entry,
        wiki: wiki,
        revision: revision,
        sessionId: sessionId ??
            _runtime.state.sessionId ??
            'wiki-${entry.bookId}-${DateTime.now().millisecondsSinceEpoch}',
      ),
    );
    if (_runtime.state.sessionId != null) {
      _runtime.actionApplied(mutation.action);
    }
    return mutation;
  }

  Future<AgentMutation<ReaderProfileItem>?> recordProfileEvidence({
    required String key,
    required Map<String, dynamic> value,
    bool explicit = false,
  }) async {
    final mutation = await applyValidatedNullable(
      ValidatedAiMutation<ReaderProfileItem>(
        actionType: 'reader_profile_evidence',
        targetType: 'reader_profile',
        targetId: key,
        bookId: _runtime.state.bookId ?? 0,
        value: ReaderProfileItem(
          key: key,
          value: value,
          createdAt: DateTime.now().millisecondsSinceEpoch,
          updatedAt: DateTime.now().millisecondsSinceEpoch,
        ),
        authorization: explicit
            ? AiMutationAuthorization.explicitUserRequest
            : AiMutationAuthorization.confirmedTask,
      ),
      () => _repository.recordProfileEvidence(
        key: key,
        value: value,
        sessionId: _sessionId,
        explicit: explicit,
      ),
    );
    if (mutation != null) _runtime.actionApplied(mutation.action);
    return mutation;
  }

  Future<AgentMutation<ReaderProfileItem>> setProfileStatus({
    required String key,
    required ReaderProfileStatus status,
  }) async {
    final mutation = await applyValidated(
      ValidatedAiMutation<ReaderProfileItem>(
        actionType: 'reader_profile_status',
        targetType: 'reader_profile',
        targetId: key,
        bookId: _runtime.state.bookId ?? 0,
        value: ReaderProfileItem(
          key: key,
          status: status,
          createdAt: DateTime.now().millisecondsSinceEpoch,
          updatedAt: DateTime.now().millisecondsSinceEpoch,
        ),
        authorization: AiMutationAuthorization.explicitUserRequest,
      ),
      () => _repository.setProfileStatus(
        key: key,
        status: status,
        sessionId: _sessionId,
      ),
    );
    _runtime.actionApplied(mutation.action);
    return mutation;
  }

  Future<UndoResult> undo(AgentAction action) async {
    final result = await _repository.undo(action.id);
    if (result == UndoResult.undone) {
      if (action.type == AgentActionType.note) {
        final sources = action.afterSnapshot?['sources'];
        if (sources is List && sources.isNotEmpty && sources.first is Map) {
          final cfi = (sources.first as Map)['cfi']?.toString();
          if (cfi?.isNotEmpty == true) {
            ReaderCommandGateway.instance.hideAnnotation(cfi!);
          }
        }
      } else if (action.type == AgentActionType.difficulty) {
        ReaderCommandGateway.instance.hideAnnotation(
          'difficulty:${action.targetId}',
        );
      } else if (action.type == AgentActionType.memory) {
        _runtime
            .memoryRemoved(action.afterSnapshot?['title']?.toString() ?? '');
      }
      _runtime.actionUndone(action);
      if (action.type == AgentActionType.goal && action.bookId != null) {
        _runtime.goalChanged(await _repository.activeGoal(action.bookId!));
      }
    }
    return result;
  }
}

final agentActionService = AgentActionService();

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/providers/ai_history.dart';
import 'package:anx_reader/providers/current_reading.dart';
import 'package:anx_reader/service/ai/ai_history.dart';
import 'package:anx_reader/service/ai/index.dart';
import 'package:anx_reader/service/ai/reading_agent_orchestrator.dart';
import 'package:anx_reader/service/ai/reading_ai_models.dart';
import 'package:anx_reader/utils/ai_reasoning_parser.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:langchain_core/chat_models.dart';

part 'ai_chat.g.dart';

@Riverpod(keepAlive: true)
class AiChat extends _$AiChat {
  String? _currentSessionId;
  ReadingAiMode? _readingModeOverride;
  ReadingAnalysisRequest? _analysisRequestOverride;

  @override
  FutureOr<List<ChatMessage>> build() async {
    _currentSessionId = null;
    _readingModeOverride = null;
    _analysisRequestOverride = null;
    return List<ChatMessage>.empty();
  }

  Future<void> sendMessage(String message) async {
    state = AsyncData([
      ...state.whenOrNull(data: (data) => data) ?? [],
      ChatMessage.humanText(message),
    ]);
  }

  void restore(List<ChatMessage> history, {String? sessionId}) {
    if (sessionId != null) {
      _currentSessionId = sessionId;
    }
    state = AsyncData(history);
  }

  Stream<List<ChatMessage>> sendMessageStream(
    String message,
    WidgetRef widgetRef,
    bool isRegenerate,
  ) async* {
    final sessionId = _ensureSessionId();
    final serviceId = Prefs().selectedAiService;
    final config = Prefs().getAiConfig(serviceId);
    final model = (config['model'])?.trim() ?? '';
    final historyNotifier = widgetRef.read(aiHistoryProvider.notifier);
    final initialHistoryState = widgetRef
        .read(aiHistoryProvider)
        .maybeWhen(data: (value) => value, orElse: () => const []);
    AiChatHistoryEntry? entry;
    for (final item in initialHistoryState) {
      if (item.id == sessionId) {
        entry = item;
        break;
      }
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    final reading = widgetRef.read(currentReadingProvider);
    final book = reading.book;
    final readingMode = _readingModeOverride ??
        (book == null
            ? ReadingAiMode.general
            : Prefs().readingAiModeForBook(book.id));
    final analysisRequest = _analysisRequestOverride;
    _analysisRequestOverride = null;

    List<ChatMessage> messages = [
      ...state.whenOrNull(data: (data) => data) ?? [],
      ChatMessage.humanText(message),
    ];

    state = AsyncData(messages);

    List<ChatMessage> updatedMessages = [
      ...messages,
      ChatMessage.ai(''),
    ];

    final draftEntry = (entry ??
            AiChatHistoryEntry(
              id: sessionId,
              serviceId: serviceId,
              model: model,
              createdAt: entry?.createdAt ?? now,
              updatedAt: now,
              messages: List<ChatMessage>.from(updatedMessages),
              completed: false,
              title: message.split('\n').first.trim(),
              bookId: book?.id,
              bookTitle: book?.title,
              chapterTitle: reading.chapterTitle,
              chapterHref: reading.chapterHref,
              readingMode: readingMode.name,
              analysisDepth: analysisRequest?.depth.name,
              frameworks: analysisRequest?.frameworks
                      .map((framework) => framework.name)
                      .toList(growable: false) ??
                  const <String>[],
              outputTemplate: analysisRequest?.outputTemplate.name,
              readingGoal: analysisRequest?.readingGoal,
              contextSnapshot: book == null
                  ? null
                  : ReadingContextSnapshot(
                      bookId: book.id.toString(),
                      bookTitle: book.title,
                      author: book.author,
                      chapterTitle: reading.chapterTitle,
                      chapterHref: reading.chapterHref,
                      progress: reading.percentage,
                      capturedAt: now,
                      metadata: {'cfi': reading.cfi},
                    ).toJson(),
            ))
        .copyWith(
      messages: List<ChatMessage>.from(updatedMessages),
      updatedAt: now,
      completed: false,
      model: model,
      analysisDepth: analysisRequest?.depth.name,
      frameworks: analysisRequest?.frameworks
          .map((framework) => framework.name)
          .toList(growable: false),
      outputTemplate: analysisRequest?.outputTemplate.name,
      readingGoal: analysisRequest?.readingGoal,
      clearAnalysisResult: analysisRequest != null,
    );

    await historyNotifier.upsert(draftEntry);

    yield updatedMessages;

    String assistantResponse = "";
    var agentTraces = const <AgentRunTrace>[];
    var citations = const <Map<String, dynamic>>[];
    try {
      final turn = reading.isReading
          ? await const ReadingAgentOrchestrator().prepare(
              messages: messages,
              mode: readingMode,
              ref: widgetRef,
              analysisRequest: analysisRequest,
            )
          : ReadingAgentTurn(messages: messages);
      agentTraces = turn.traces;
      citations = turn.citations;
      await for (final chunk in aiGenerateStream(
        turn.messages,
        regenerate: isRegenerate,
        useAgent: true,
        ref: widgetRef,
        readingMode: readingMode,
      )) {
        assistantResponse = chunk;

        final updatedMessagesWithResponse =
            List<ChatMessage>.from(updatedMessages);
        updatedMessagesWithResponse[updatedMessagesWithResponse.length - 1] =
            assistantMessageFromDisplayContent(assistantResponse);

        yield updatedMessagesWithResponse;

        state = AsyncData(updatedMessagesWithResponse);
      }
      final completedEntry = draftEntry.copyWith(
        messages: List<ChatMessage>.from(state.value ?? updatedMessages),
        updatedAt: DateTime.now().millisecondsSinceEpoch,
        completed: true,
        model: model,
        readingMode: readingMode.name,
        agentTraces: agentTraces.map((trace) => trace.toJson()).toList(),
        citations: citations,
        analysisResult: analysisRequest == null
            ? null
            : ReadingAnalysisResult(
                request: analysisRequest,
                generatedAt: DateTime.now().millisecondsSinceEpoch,
                summary: assistantResponse,
                citations: citations,
              ).toJson(),
      );
      await historyNotifier.upsert(completedEntry);
    } catch (_) {
      final failedEntry = draftEntry.copyWith(
        messages: List<ChatMessage>.from(state.value ?? updatedMessages),
        updatedAt: DateTime.now().millisecondsSinceEpoch,
        completed: false,
        model: model,
        readingMode: readingMode.name,
        agentTraces: agentTraces.map((trace) => trace.toJson()).toList(),
        citations: citations,
      );
      await historyNotifier.upsert(failedEntry);
      rethrow;
    }
  }

  void clear() {
    state = AsyncData(List<ChatMessage>.empty());
    _currentSessionId = null;
    _readingModeOverride = null;
    _analysisRequestOverride = null;
  }

  void loadHistoryEntry(AiChatHistoryEntry entry) {
    _currentSessionId = entry.id;
    _readingModeOverride = ReadingAiMode.fromJson(entry.readingMode);
    _analysisRequestOverride = null;
    state = AsyncData(List<ChatMessage>.from(entry.messages));
  }

  void setReadingModeOverride(ReadingAiMode mode) {
    _readingModeOverride = mode;
  }

  void setReadingAnalysisRequest(ReadingAnalysisRequest request) {
    _analysisRequestOverride = request;
  }

  String? get currentSessionId => _currentSessionId;

  String _ensureSessionId() {
    return _currentSessionId ??= _generateSessionId();
  }

  String _generateSessionId() {
    return DateTime.now().microsecondsSinceEpoch.toString();
  }
}

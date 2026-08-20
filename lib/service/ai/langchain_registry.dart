import 'dart:io';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/models/ai_provider.dart';
import 'package:anx_reader/providers/current_reading.dart';
import 'package:anx_reader/service/ai/timeout_http_client.dart';
import 'package:anx_reader/service/ai/reading_ai_models.dart';
import 'package:anx_reader/service/ai/reading_agent_runtime.dart';
import 'package:anx_reader/service/ai/reading_closure_policy.dart';
import 'package:anx_reader/service/ai/reading_experience_profile_service.dart';
import 'package:anx_reader/service/ai/reading_skills.dart';
import 'package:anx_reader/service/ai/tools/reading_agent_tools.dart';
import 'package:anx_reader/service/ai/tools/ai_tool_registry.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:langchain_anthropic/langchain_anthropic.dart';
import 'package:langchain_core/chat_models.dart';
import 'package:langchain_core/tools.dart';
import 'package:langchain_google/langchain_google.dart';
import 'package:langchain_openai/langchain_openai.dart';

import 'langchain_ai_config.dart';

/// Factory responsible for building chat models based on user preferences.
class LangchainAiRegistry {
  const LangchainAiRegistry(
    this.ref, {
    this.readingModeOverride,
    this.readingSkillOverride,
  });
  final WidgetRef? ref;
  final ReadingAiMode? readingModeOverride;
  final ReadingSkillSelection? readingSkillOverride;

  LangchainPipeline resolve(
    LangchainAiConfig config, {
    bool useAgent = false,
  }) {
    switch (config.identifier) {
      case 'claude':
        return _buildPipeline(
          config,
          _buildAnthropic(config),
          useAgent: useAgent,
        );
      case 'gemini':
        return _buildPipeline(
          config,
          _buildGoogle(config),
          useAgent: useAgent,
        );
      case 'deepseek':
      case 'openrouter':
      case 'openai':
      default:
        return _buildPipeline(
          config,
          _buildOpenAi(config),
          useAgent: useAgent,
        );
    }
  }

  /// Resolve pipeline based on AiProtocol enum (for new provider system)
  LangchainPipeline resolveByProtocol(
    AiProtocol protocol,
    LangchainAiConfig config, {
    bool useAgent = false,
  }) {
    switch (protocol) {
      case AiProtocol.claude:
        return _buildPipeline(
          config,
          _buildAnthropic(config),
          useAgent: useAgent,
        );
      case AiProtocol.gemini:
        return _buildPipeline(
          config,
          _buildGoogle(config),
          useAgent: useAgent,
        );
      case AiProtocol.openai:
        return _buildPipeline(
          config,
          _buildOpenAi(config),
          useAgent: useAgent,
        );
    }
  }

  BaseChatModel _buildOpenAi(LangchainAiConfig config) {
    final httpClient = config.requestTimeoutSeconds > 0
        ? TimeoutHttpClient(
            http.Client(),
            timeout: Duration(seconds: config.requestTimeoutSeconds),
          )
        : null;

    return ChatOpenAI(
      apiKey: config.apiKey.isEmpty ? null : config.apiKey,
      baseUrl: config.baseUrl ?? 'https://api.openai.com/v1',
      headers: config.headers.isEmpty ? null : config.headers,
      defaultOptions: config.toOpenAIOptions(),
      client: httpClient,
    );
  }

  BaseChatModel _buildAnthropic(LangchainAiConfig config) {
    return ChatAnthropic(
      apiKey: config.apiKey.isEmpty ? null : config.apiKey,
      baseUrl: config.baseUrl ?? 'https://api.anthropic.com/v1',
      headers: config.headers.isEmpty ? null : config.headers,
      defaultOptions: config.toAnthropicOptions(),
    );
  }

  BaseChatModel _buildGoogle(LangchainAiConfig config) {
    return ChatGoogleGenerativeAI(
      apiKey: config.apiKey.isEmpty ? null : config.apiKey,
      baseUrl: config.baseUrl,
      headers: config.headers.isEmpty ? null : config.headers,
      defaultOptions: config.toGoogleOptions(),
    );
  }

  LangchainPipeline _buildPipeline(
    LangchainAiConfig config,
    BaseChatModel model, {
    required bool useAgent,
  }) {
    if (useAgent) {
      assert(ref != null, 'ref must be provided when useAgent is true');
    }

    final isReading =
        useAgent && ref != null && ref!.read(currentReadingProvider).isReading;

    var tools = const <Tool>[];
    ChatMessage? systemMessage;

    if (useAgent) {
      final enabledIds = Prefs().enabledAiToolIds;
      final toolContext = AiToolContext(ref: ref!);
      tools = AiToolRegistry.buildTools(toolContext, enabledIds);
      final enabledDefs = AiToolRegistry.definitions
          .where((def) => enabledIds.contains(def.id))
          .where((def) =>
              Prefs().readingAgentBetaEnabled ||
              !readingAgentToolIds.contains(def.id))
          .toList(growable: false);
      final currentBook =
          isReading ? ref!.read(currentReadingProvider).book : null;
      final resolvedMode = readingModeOverride ??
          (currentBook == null
              ? ReadingAiMode.general
              : Prefs().readingAiModeForBook(currentBook.id));
      final closurePolicy = currentBook == null
          ? null
          : const ReadingClosurePolicyMatcher().match(
              mode: resolvedMode,
              title: currentBook.title,
              author: currentBook.author,
              description: currentBook.description ?? '',
              pinnedId: readingExperienceProfileService
                  .pinnedModuleId(currentBook.id),
            );
      systemMessage = _buildAgentSystemMessage(
        isReading: isReading,
        enabledTools: enabledDefs,
        readingMode: resolvedMode,
        readingSkill: readingSkillOverride,
        closurePolicy: closurePolicy,
      );
    }

    return LangchainPipeline(
      model: model,
      tools: tools,
      systemMessage: systemMessage,
    );
  }

  ChatMessage _buildAgentSystemMessage({
    required bool isReading,
    required List<AiToolDefinition> enabledTools,
    required ReadingAiMode readingMode,
    ReadingSkillSelection? readingSkill,
    ReadingClosurePolicyDefinition? closurePolicy,
  }) {
    final currentLanguageCode =
        Prefs().locale?.languageCode ?? Platform.localeName;

    // Map language code to language name
    final languageMap = {
      'zh': '简体中文',
      'zh-CN': '简体中文',
      'zh-Hans': '简体中文',
      'zh-TW': '繁體中文',
      'zh-Hant': '繁體中文',
      'en': 'English',
      'ja': '日本語',
      'ko': '한국어',
      'fr': 'Français',
      'de': 'Deutsch',
      'es': 'Español',
      'ru': 'Русский',
      'ar': 'العربية',
      'tr': 'Türkçe',
    };

    final languageName = languageMap[currentLanguageCode] ??
        languageMap[currentLanguageCode.split('_').first] ??
        currentLanguageCode;

    final readingStateContext = isReading
        ? '📖 User is currently reading - You are a focused reading companion, providing instant comprehension help, translation, and note-taking assistance.'
        : '📚 User is browsing the library - You are a wise librarian, helping organize books and plan reading strategies.';

    final profile = readingMode.agentProfile;
    final readingAgentContext = Prefs().readingAgentBetaEnabled && isReading
        ? _formatReadingAgentContext(readingAgentRuntime.state)
        : '';
    final readingSkillContext = readingSkill == null
        ? ''
        : '\n## Active Reading Method\n${readingSkill.promptContext()}';
    final closureContext = closurePolicy == null
        ? ''
        : '\n## Reading Closure Policy\n'
            'Closure: ${closurePolicy.title}\n'
            'Closure guidance: ${closurePolicy.systemGuidance}';
    final guidance =
        '''You are "Anx Reader AI", an intelligent reading assistant integrated into the Anx Reader app.

## Your Role
A knowledgeable reading companion who helps users understand, organize, and enjoy their reading experience through intelligent tool usage and thoughtful insights.

## Current Context
$readingStateContext
Reading mode: ${readingMode.name}
Mode guidance: ${profile.systemPrompt}
Safety boundary: ${profile.safetyPrompt}
$readingAgentContext
$readingSkillContext
$closureContext

Use layered context. Start from the selection, adjacent paragraphs, chapter and book metadata. Read chapter text, table of contents, notes or other chapters only when needed through tools; never imply that the entire book or all notes were uploaded.

## Tool Usage Principles
1. **Gather context first** - Use tools to understand the situation before responding
2. **Combine tools efficiently** - Use multiple tools in parallel or sequence when needed
3. **Prioritize specific tools** - When user is reading, prefer current_* series tools over general search
4. **Be transparent** - Briefly explain your reasoning when using complex tool combinations

## Available Tools & Usage Scenarios
${_formatToolCatalog(enabledTools)}

## Response Strategy

### When answering user queries:
1. **Understand intent** - What does the user really want?
2. **Gather data** - Use tools to collect relevant information
3. **Synthesize** - Connect information pieces into coherent insights
4. **Deliver value** - Provide actionable suggestions or clear answers

### Communication Style:
- **Concise yet complete** - No unnecessary elaboration
- **Evidence-based** - Reference specific content from tool results
- **Context-adaptive** - Adjust tone based on reading state
- **Reasonable defaults** - When ambiguous, proactively ask for clarification
- **Language consistency** - Unless the user explicitly uses another language, always respond in **$languageName**, regardless of the language used in their question

### Markdown Example

You can use Markdown to format text easily. Here are some examples:

- **Bold Text**: **This text is bold**
- *Italic Text*: *This text is italicized*
- [Link](https://www.example.com): [This is a link](https://www.example.com)
- Lists:
  1. Item 1
  2. Item 2
  3. Item 3

### LaTeX Example

You can also use LaTeX for mathematical expressions. Here's an example:

- **Equation**: \\( f(x) = x^2 + 2x + 1 \\)
- **Integral**: \\( \\int_{0}^{1} x^2 \\, dx \\)
- **Matrix**:

\\[
\\begin{bmatrix}
1 & 2 & 3 \\\\
4 & 5 & 6 \\\\
7 & 8 & 9
\\end{bmatrix}
\\]


## Error Handling
- **No results** → Suggest alternative search strategies or verify book/chapter context
- **Tool failure** → Acknowledge the issue and try alternative approaches
- **Out of scope** → Clearly state limitations and suggest manual alternatives

## Important Constraints
- Respect user privacy - only access data through provided tools
- Stay focused on reading-related assistance
- Don't make assumptions about unavailable data
- Use the user's language for responses
- Reader page turns, dwell time, rereading and chapter changes never authorize a model request or a persistent write
- Execute persistent writes directly only when the user explicitly asked to save/create/mark; proactive ideas must return a confirmation preview
- Never treat profile candidates or model inferences as confirmed user facts

## Remember
You are not just a tool executor, but the user's reading companion. Your mission is to make every reading session more insightful and enjoyable.''';

    return ChatMessage.system(guidance);
  }

  String _formatReadingAgentContext(ReadingWorldState state) {
    if (!state.isUsableForAgent) return '';
    final selection = state.selection;
    return '''

## Reading World State (local snapshot)
- Book: ${state.bookTitle ?? ''} (id: ${state.bookId})
- Chapter: ${state.chapterTitle ?? ''} (${state.chapterHref ?? ''})
- CFI: ${state.cfi ?? ''}
- Total progress: ${(state.totalProgress * 100).toStringAsFixed(1)}%
- Chapter progress: ${(state.chapterProgress * 100).toStringAsFixed(1)}%
- Active goal: ${state.activeGoal?.title ?? 'none'}
- Unresolved difficulties: ${state.unresolvedDifficultyCount}
- Pending chapter checks: ${state.pendingCheckpointCount}
- Due knowledge cards: ${state.dueKnowledgeCardCount}
- Mastery: ${state.masterySummary}
- Markdown memory documents: ${state.markdownMemorySummary}
- Confirmed reader profile: ${state.confirmedProfileSummary}
${selection == null ? '- Selection: none' : '- Selection: active at ${selection.cfi} (${selection.text.length} characters)'}
Only confirmed profile values above are user context. Pending profile candidates are intentionally excluded.
''';
  }

  String _formatToolCatalog(List<AiToolDefinition> enabledTools) {
    if (enabledTools.isEmpty) {
      return '_No tools are currently enabled by the user._';
    }
    return enabledTools
        .map(
          (tool) =>
              '- **${tool.displayNameOrDefault()}** → ${tool.descriptionOrDefault()}',
        )
        .join('\n');
  }
}

class LangchainPipeline {
  const LangchainPipeline({
    required this.model,
    required this.tools,
    this.systemMessage,
  });

  final BaseChatModel model;
  final List<Tool> tools;
  final ChatMessage? systemMessage;
}

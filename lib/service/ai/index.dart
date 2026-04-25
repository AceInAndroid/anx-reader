import 'dart:async';
import 'dart:io';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/main.dart';
import 'package:anx_reader/models/ai_provider.dart';
import 'package:anx_reader/providers/ai_providers.dart';
import 'package:anx_reader/service/ai/ai_key_rotator.dart';
import 'package:anx_reader/service/ai/langchain_ai_config.dart';
import 'package:anx_reader/service/ai/langchain_registry.dart';
import 'package:anx_reader/service/ai/langchain_runner.dart';
import 'package:anx_reader/service/ai/request_queue.dart';
import 'package:anx_reader/utils/ai_reasoning_parser.dart';
import 'package:anx_reader/utils/log/common.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:langchain_core/chat_models.dart';
import 'package:langchain_core/prompts.dart';

final CancelableLangchainRunner _runner = CancelableLangchainRunner();

// Global request timestamps list for RPM throttling
final List<DateTime> _aiRequestTimestamps = [];

/// Throttle AI requests if RPM limit is configured (sliding 1-minute window).
Future<void> _throttleIfNeeded() async {
  final rpm = Prefs().aiRpm;
  if (rpm <= 0) return;

  // Apply minimum interval between requests
  final minInterval = Duration(milliseconds: (60000 / rpm).round());
  await Future.delayed(minInterval);

  final now = DateTime.now();
  final windowStart = now.subtract(const Duration(minutes: 1));
  _aiRequestTimestamps.removeWhere((ts) => ts.isBefore(windowStart));

  if (_aiRequestTimestamps.length >= rpm) {
    final oldest = _aiRequestTimestamps.first;
    final waitUntil = oldest.add(const Duration(minutes: 1));
    final waitDuration = waitUntil.difference(DateTime.now());
    if (waitDuration > Duration.zero) {
      AnxLog.info('Rate limit reached, waiting ${waitDuration.inSeconds}s');
      await Future.delayed(waitDuration);
    }
    final newNow = DateTime.now();
    _aiRequestTimestamps.removeWhere(
        (ts) => ts.isBefore(newNow.subtract(const Duration(minutes: 1))));
  }
  _aiRequestTimestamps.add(DateTime.now());
}

Stream<String> aiGenerateStream(
  List<ChatMessage> messages, {
  String? identifier,
  Map<String, String>? config,
  bool regenerate = false,
  bool useAgent = false,
  WidgetRef? ref,
}) async* {
  if (useAgent) {
    assert(ref != null, 'ref must be provided when useAgent is true');
  }
  LangchainAiRegistry registry = LangchainAiRegistry(ref);

  // Try primary provider
  bool primaryFailed = false;
  String? lastOutput;
  await for (final chunk in _generateStream(
    messages: messages,
    identifier: identifier,
    overrideConfig: config,
    regenerate: regenerate,
    useAgent: useAgent,
    registry: registry,
  )) {
    lastOutput = chunk;
    yield chunk;
  }

  // Detect if primary failed
  if (lastOutput != null) {
    final lower = lastOutput.toLowerCase();
    primaryFailed = lower.startsWith('error:') || lower.startsWith('translation error');
  }

  // Try fallback if primary failed
  if (primaryFailed) {
    final fallbackId = Prefs().aiFallbackProvider;
    if (fallbackId != null && fallbackId != identifier) {
      AnxLog.info('Trying fallback provider: $fallbackId');
      yield '\n[Falling back to backup provider...]';
      await for (final chunk in _generateStream(
        messages: messages,
        identifier: fallbackId,
        overrideConfig: config,
        regenerate: regenerate,
        useAgent: useAgent,
        registry: registry,
      )) {
        yield chunk;
      }
    }
  }
}

void cancelActiveAiRequest() {
  _runner.cancel();
}

Stream<String> _generateStream({
  required List<ChatMessage> messages,
  String? identifier,
  Map<String, String>? overrideConfig,
  required bool regenerate,
  required bool useAgent,
  required LangchainAiRegistry registry,
}) async* {
  AnxLog.info('aiGenerateStream called identifier: $identifier');
  final sanitizedMessages = _sanitizeMessagesForPrompt(messages);

  LangchainAiConfig config;

  // Try to use new provider system first if ref is available
  if (registry.ref != null && overrideConfig == null) {
    try {
      final notifier = registry.ref!.read(aiProvidersProvider.notifier);
      // If a specific provider id was passed, use it; otherwise use the default
      final AiProvider? provider = identifier != null
          ? notifier.getProviderById(identifier)
          : notifier.getSelectedProvider();
      if (provider != null &&
          provider.enabled &&
          AiKeyRotator.hasValidKey(provider)) {
        final apiKey = AiKeyRotator.getNextKey(provider);
        if (apiKey != null) {
          config = LangchainAiConfig.fromProvider(
            providerId: provider.id,
            model: provider.model,
            apiKey: apiKey,
            url: provider.url,
            reasoningEffort: provider.reasoningEffort,
            enableThinking: provider.enableThinking,
          );

          AnxLog.info(
              'aiGenerateStream (new): ${provider.id}, model: ${config.model}, baseUrl: ${config.baseUrl}');

          final pipeline = registry.resolveByProtocol(provider.protocol, config,
              useAgent: useAgent);
          final model = pipeline.model;

          await _throttleIfNeeded();
          yield* _executeStream(
            model: model,
            pipeline: pipeline,
            sanitizedMessages: sanitizedMessages,
            useAgent: useAgent,
            registry: registry,
            config: config,
          );

          // Advance key index for round-robin rotation after successful call
          registry.ref!
              .read(aiProvidersProvider.notifier)
              .advanceKeyIndex(provider.id);
          return;
        }
      }
    } catch (e) {
      AnxLog.warning(
          'Failed to use new provider system, falling back to legacy: $e');
    }
  }

  // Try new provider system without ref (reads directly from Prefs storage)
  if (overrideConfig == null) {
    try {
      final rawProviders = Prefs().getAiProviders();
      if (rawProviders.isNotEmpty) {
        final providers = rawProviders
            .map((json) => AiProvider.fromJson(json as Map<String, dynamic>))
            .toList();

        AiProvider? provider;
        if (identifier != null) {
          try {
            provider = providers.firstWhere((p) => p.id == identifier);
          } catch (_) {
            provider = null;
          }
        } else {
          final selectedId = Prefs().selectedAiService;
          try {
            provider = providers.firstWhere((p) => p.id == selectedId);
          } catch (_) {}
          provider ??= providers.where((p) => p.enabled).firstOrNull;
        }

        if (provider != null &&
            provider.enabled &&
            AiKeyRotator.hasValidKey(provider)) {
          final apiKey = AiKeyRotator.getNextKey(provider);
          if (apiKey != null) {
            config = LangchainAiConfig.fromProvider(
              providerId: provider.id,
              model: provider.model,
              apiKey: apiKey,
              url: provider.url,
              reasoningEffort: provider.reasoningEffort,
              enableThinking: provider.enableThinking,
            );

            AnxLog.info(
                'aiGenerateStream (no-ref new): ${provider.id}, model: ${config.model}, baseUrl: ${config.baseUrl}');

            final pipeline = registry.resolveByProtocol(
                provider.protocol, config,
                useAgent: useAgent);
            final model = pipeline.model;

            await _throttleIfNeeded();
            yield* _executeStream(
              model: model,
              pipeline: pipeline,
              sanitizedMessages: sanitizedMessages,
              useAgent: useAgent,
              registry: registry,
              config: config,
            );

            // Advance key index in persistent storage for round-robin rotation
            final updatedProviders = providers.map((p) {
              if (p.id == provider!.id) {
                return p.copyWith(
                    keyIndex: p.keyIndex + 1, updatedAt: DateTime.now());
              }
              return p;
            }).toList();
            Prefs().saveAiProviders(updatedProviders);
            return;
          }
        }
      }
    } catch (e) {
      AnxLog.warning(
          'Failed to use no-ref new provider system, falling back to legacy: $e');
    }
  }

  // Fall back to legacy system
  final selectedIdentifier = identifier ?? Prefs().selectedAiService;
  final savedConfig = Prefs().getAiConfig(selectedIdentifier);
  if (savedConfig.isEmpty &&
      (overrideConfig == null || overrideConfig.isEmpty)) {
    final context = navigatorKey.currentContext;
    if (context != null) {
      yield L10n.of(context).aiServiceNotConfigured;
    } else {
      yield 'AI service not configured';
    }
    return;
  }

  config = LangchainAiConfig.fromPrefs(selectedIdentifier, savedConfig);
  if (overrideConfig != null && overrideConfig.isNotEmpty) {
    final override =
        LangchainAiConfig.fromPrefs(selectedIdentifier, overrideConfig);
    config = mergeConfigs(config, override);
  }

  AnxLog.info(
      'aiGenerateStream (legacy): $selectedIdentifier, model: ${config.model}, baseUrl: ${config.baseUrl}');

  final pipeline = registry.resolve(config, useAgent: useAgent);
  final model = pipeline.model;

  await _throttleIfNeeded();
  yield* _executeStream(
    model: model,
    pipeline: pipeline,
    sanitizedMessages: sanitizedMessages,
    useAgent: useAgent,
    registry: registry,
    config: config,
  );
}

/// Execute the AI stream with the given model and pipeline
/// Pass registry and config to allow creating fresh model on retry
Stream<String> _executeStream({
  required BaseChatModel model,
  required LangchainPipeline pipeline,
  required List<ChatMessage> sanitizedMessages,
  required bool useAgent,
  required LangchainAiRegistry registry,
  required LangchainAiConfig config,
}) async* {
  var buffer = '';
  int retryCount = 0;
  const maxRetries = 3;
  BaseChatModel currentModel = model;

  try {
    Stream<String> stream = _createStream(
      model: currentModel,
      pipeline: pipeline,
      sanitizedMessages: sanitizedMessages,
      useAgent: useAgent,
    );

    await for (final chunk in stream) {
      buffer = chunk;
      yield buffer;
    }
  } catch (error, stack) {
    final errorType = parseRateLimitError(error);

    // Check if we should retry
    if (errorType != RateLimitErrorType.unknown && retryCount < maxRetries) {
      retryCount++;
      final delay = calculateRetryDelay(errorType, retryCount);

      AnxLog.info(
        'AI request failed, retry $retryCount/$maxRetries after ${delay.inSeconds}s: $error',
      );

      yield 'Retrying... ($retryCount/$maxRetries)';

      await Future.delayed(delay);

      // Close the old model if needed
      try {
        currentModel.close();
      } catch (_) {}

      // Create a fresh pipeline and model for retry
      final freshPipeline = registry.resolve(config, useAgent: useAgent);
      currentModel = freshPipeline.model;

      // Retry the stream
      try {
        final retryStream = _createStream(
          model: currentModel,
          pipeline: freshPipeline,
          sanitizedMessages: sanitizedMessages,
          useAgent: useAgent,
        );

        await for (final chunk in retryStream) {
          buffer = chunk;
          yield buffer;
        }
      } catch (retryError, retryStack) {
        final mapped = _mapError(retryError);
        AnxLog.severe('AI retry error: $mapped\n$retryStack');
        yield mapped;
      }
    } else {
      final mapped = _mapError(error);
      AnxLog.severe('AI error: $mapped\n$stack');
      yield mapped;
    }
  } finally {
    try {
      currentModel.close();
    } catch (_) {}
  }
}

/// Create stream based on useAgent flag
Stream<String> _createStream({
  required BaseChatModel model,
  required LangchainPipeline pipeline,
  required List<ChatMessage> sanitizedMessages,
  required bool useAgent,
}) {
  if (useAgent) {
    final inputMessage = _latestUserMessage(sanitizedMessages);
    if (inputMessage == null) {
      return Stream.value('No user input provided');
    }

    final tools = pipeline.tools;
    if (tools.isEmpty) {
      return Stream.value('Agent mode not supported for this provider.');
    }

    final historyMessages = sanitizedMessages
        .sublist(0, sanitizedMessages.length - 1)
        .toList(growable: false);

    return _runner.streamAgent(
      model: model,
      tools: tools,
      history: historyMessages,
      input: inputMessage,
      systemMessage: pipeline.systemMessage,
    );
  } else {
    final prompt = PromptValue.chat(sanitizedMessages);
    return _runner.stream(model: model, prompt: prompt);
  }
}

String _mapError(Object error) {
  final base = 'Error: ';

  if (error is TimeoutException) {
    return '${base}Request timed out';
  }

  if (error is SocketException) {
    return '${base}Network error: ${error.message}';
  }

  final message = error.toString().toLowerCase();

  if (message.contains('401') ||
      message.contains('unauthorized') ||
      message.contains('invalid api key')) {
    return '${base}Authentication failed. Please verify API key.';
  }

  if (message.contains('429') || message.contains('rate limit')) {
    return '${base}Rate limit reached. Try again later.';
  }

  if (message.contains('timeout')) {
    return '${base}Request timed out';
  }

  if (message.contains('network') ||
      message.contains('socket') ||
      message.contains('failed host lookup')) {
    return '${base}Network error: ${error.toString()}';
  }

  return '$base${error.toString()}';
}

List<ChatMessage> _sanitizeMessagesForPrompt(List<ChatMessage> messages) {
  return messages.map((message) {
    if (message is AIChatMessage) {
      if (message.reasoningContent.isNotEmpty) {
        return AIChatMessage(
          content: message.content,
          toolCalls: message.toolCalls,
        );
      }
      final plainText = reasoningContentToPlainText(message.content);
      if (plainText == message.content) {
        return message;
      }
      return AIChatMessage(
        content: plainText,
        toolCalls: message.toolCalls,
      );
    }
    return message;
  }).toList(growable: false);
}

String? _latestUserMessage(List<ChatMessage> messages) {
  for (var i = messages.length - 1; i >= 0; i--) {
    final message = messages[i];
    if (message is HumanChatMessage) {
      return message.contentAsString;
    }
  }
  return null;
}

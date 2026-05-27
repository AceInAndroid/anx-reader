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

class _AiExecutionResult {
  const _AiExecutionResult({
    required this.stream,
    required this.providerId,
    required this.isError,
  });

  final Stream<String> stream;
  final String? providerId;
  final bool isError;
}

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
  final registry = LangchainAiRegistry(ref);

  final primary = await _generateStream(
    messages: messages,
    identifier: identifier,
    overrideConfig: config,
    regenerate: regenerate,
    useAgent: useAgent,
    registry: registry,
  );

  await for (final chunk in primary.stream) {
    yield chunk;
  }

  if (!primary.isError) return;

  final fallbackId = _resolveRunnableFallbackId(
    registry: registry,
    primaryIdentifier: primary.providerId ?? identifier,
  );
  if (fallbackId == null) return;

  AnxLog.info('Trying fallback provider: $fallbackId');
  yield '\n[Falling back to backup provider...]';

  final fallback = await _generateStream(
    messages: messages,
    identifier: fallbackId,
    overrideConfig: config,
    regenerate: regenerate,
    useAgent: useAgent,
    registry: registry,
  );

  await for (final chunk in fallback.stream) {
    yield chunk;
  }
}

Future<String> aiGenerateText(
  List<ChatMessage> messages, {
  String? identifier,
  Map<String, String>? config,
  bool regenerate = false,
  bool useAgent = false,
  WidgetRef? ref,
}) async {
  String? lastResult;
  await for (final chunk in aiGenerateStream(
    messages,
    identifier: identifier,
    config: config,
    regenerate: regenerate,
    useAgent: useAgent,
    ref: ref,
  )) {
    lastResult = chunk;
  }
  return lastResult ?? '';
}

Future<String?> resolveRunnableAiFallbackProviderId({
  String? primaryIdentifier,
  WidgetRef? ref,
}) async {
  return _resolveRunnableFallbackId(
    registry: LangchainAiRegistry(ref),
    primaryIdentifier: primaryIdentifier,
  );
}

void cancelActiveAiRequest() {
  _runner.cancel();
}

String? _resolveRunnableFallbackId({
  required LangchainAiRegistry registry,
  required String? primaryIdentifier,
}) {
  final fallbackId = Prefs().aiFallbackProvider;
  if (fallbackId == null || fallbackId == primaryIdentifier) {
    return null;
  }

  if (registry.ref != null) {
    final notifier = registry.ref!.read(aiProvidersProvider.notifier);
    final fallback = notifier.getRunnableProviderById(fallbackId);
    if (fallback != null) return fallback.id;
    Prefs().aiFallbackProvider = null;
    return null;
  }

  try {
    final providers = Prefs()
        .getAiProviders()
        .map((json) => AiProvider.fromJson(json as Map<String, dynamic>))
        .toList();
    final fallback = providers
        .where((p) => p.id == fallbackId)
        .where((p) => p.enabled && AiKeyRotator.hasValidKey(p))
        .firstOrNull;
    if (fallback != null) return fallback.id;
  } catch (_) {}

  Prefs().aiFallbackProvider = null;
  return null;
}

Future<_AiExecutionResult> _generateStream({
  required List<ChatMessage> messages,
  String? identifier,
  Map<String, String>? overrideConfig,
  required bool regenerate,
  required bool useAgent,
  required LangchainAiRegistry registry,
}) async {
  AnxLog.info('aiGenerateStream called identifier: $identifier');
  final sanitizedMessages = _sanitizeMessagesForPrompt(messages);

  LangchainAiConfig config;
  String? resolvedProviderId;

  // Try to use new provider system first if ref is available
  if (registry.ref != null && overrideConfig == null) {
    try {
      final notifier = registry.ref!.read(aiProvidersProvider.notifier);
      // If a specific provider id was passed, use it; otherwise use the default
      final AiProvider? provider = identifier != null
          ? notifier.getRunnableProviderById(identifier)
          : notifier.getRunnableSelectedProvider();
      if (provider != null) {
        final apiKey = AiKeyRotator.getNextKey(provider);
        if (apiKey != null) {
          resolvedProviderId = provider.id;
          config = LangchainAiConfig.fromProvider(
            providerId: provider.id,
            model: provider.model,
            apiKey: apiKey,
            url: provider.url,
            reasoningEffort: provider.reasoningEffort,
            requestTimeoutSeconds: provider.requestTimeoutSeconds,
          );

          AnxLog.info(
              'aiGenerateStream (new): ${provider.id}, model: ${config.model}, baseUrl: ${config.baseUrl}');

          final pipeline = registry.resolveByProtocol(provider.protocol, config,
              useAgent: useAgent);
          final model = pipeline.model;

          await _throttleIfNeeded();
          final result = await _executeStream(
            model: model,
            pipeline: pipeline,
            sanitizedMessages: sanitizedMessages,
            useAgent: useAgent,
            registry: registry,
            config: config,
          );

          // Advance key index for round-robin rotation after successful call
          if (!result.isError) {
            registry.ref!
                .read(aiProvidersProvider.notifier)
                .advanceKeyIndex(provider.id);
          }
          return _AiExecutionResult(
            stream: result.stream,
            providerId: resolvedProviderId,
            isError: result.isError,
          );
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
            provider = providers.firstWhere((p) =>
                p.id == identifier && p.enabled && AiKeyRotator.hasValidKey(p));
          } catch (_) {
            provider = null;
          }
        } else {
          final selectedId = Prefs().selectedAiService;
          try {
            provider = providers.firstWhere((p) =>
                p.id == selectedId && p.enabled && AiKeyRotator.hasValidKey(p));
          } catch (_) {}
          provider ??= providers
              .where((p) => p.enabled && AiKeyRotator.hasValidKey(p))
              .firstOrNull;
        }

        if (provider != null) {
          final apiKey = AiKeyRotator.getNextKey(provider);
          if (apiKey != null) {
            resolvedProviderId = provider.id;
            config = LangchainAiConfig.fromProvider(
              providerId: provider.id,
              model: provider.model,
              apiKey: apiKey,
              url: provider.url,
              reasoningEffort: provider.reasoningEffort,
              requestTimeoutSeconds: provider.requestTimeoutSeconds,
            );

            AnxLog.info(
                'aiGenerateStream (no-ref new): ${provider.id}, model: ${config.model}, baseUrl: ${config.baseUrl}');

            final pipeline = registry.resolveByProtocol(
                provider.protocol, config,
                useAgent: useAgent);
            final model = pipeline.model;

            await _throttleIfNeeded();
            final result = await _executeStream(
              model: model,
              pipeline: pipeline,
              sanitizedMessages: sanitizedMessages,
              useAgent: useAgent,
              registry: registry,
              config: config,
            );

            // Advance key index in persistent storage for round-robin rotation
            if (!result.isError) {
              final updatedProviders = providers.map((p) {
                if (p.id == provider!.id) {
                  return p.copyWith(
                      keyIndex: p.keyIndex + 1, updatedAt: DateTime.now());
                }
                return p;
              }).toList();
              Prefs().saveAiProviders(updatedProviders);
            }
            return _AiExecutionResult(
              stream: result.stream,
              providerId: resolvedProviderId,
              isError: result.isError,
            );
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
      return _AiExecutionResult(
        stream: Stream.value(L10n.of(context).aiServiceNotConfigured),
        providerId: resolvedProviderId ?? selectedIdentifier,
        isError: true,
      );
    } else {
      return _AiExecutionResult(
        stream: Stream.value('AI service not configured'),
        providerId: null,
        isError: true,
      );
    }
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
  final result = await _executeStream(
    model: model,
    pipeline: pipeline,
    sanitizedMessages: sanitizedMessages,
    useAgent: useAgent,
    registry: registry,
    config: config,
  );
  return _AiExecutionResult(
    stream: result.stream,
    providerId: resolvedProviderId ?? selectedIdentifier,
    isError: result.isError,
  );
}

/// Execute the AI stream with the given model and pipeline
/// Pass registry and config to allow creating fresh model on retry
Future<_AiExecutionResult> _executeStream({
  required BaseChatModel model,
  required LangchainPipeline pipeline,
  required List<ChatMessage> sanitizedMessages,
  required bool useAgent,
  required LangchainAiRegistry registry,
  required LangchainAiConfig config,
}) async {
  int retryCount = 0;
  const maxRetries = 3;
  BaseChatModel currentModel = model;
  final chunks = <String>[];

  void emit(String value) {
    chunks.add(value);
  }

  _AiExecutionResult finish(bool isError) {
    return _AiExecutionResult(
      stream: Stream<String>.fromIterable(chunks),
      providerId: config.identifier,
      isError: isError,
    );
  }

  try {
    Stream<String> stream = _createStream(
      model: currentModel,
      pipeline: pipeline,
      sanitizedMessages: sanitizedMessages,
      useAgent: useAgent,
    );

    await for (final chunk in stream) {
      emit(chunk);
    }
    return finish(false);
  } catch (error, stack) {
    final errorType = parseRateLimitError(error);

    // Check if we should retry
    if (errorType != RateLimitErrorType.unknown && retryCount < maxRetries) {
      retryCount++;
      final delay = calculateRetryDelay(errorType, retryCount);

      AnxLog.info(
        'AI request failed, retry $retryCount/$maxRetries after ${delay.inSeconds}s: $error',
      );

      emit('Retrying... ($retryCount/$maxRetries)');

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
          emit(chunk);
        }
        return finish(false);
      } catch (retryError, retryStack) {
        final mapped = _mapError(retryError);
        AnxLog.severe('AI retry error: $mapped\n$retryStack');
        emit(mapped);
        return finish(true);
      }
    } else {
      final mapped = _mapError(error);
      AnxLog.severe('AI error: $mapped\n$stack');
      emit(mapped);
      return finish(true);
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

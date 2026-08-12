import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/dao/book_note.dart';
import 'package:anx_reader/enums/hint_key.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/models/ai_quick_prompt_chip.dart';
import 'package:anx_reader/models/book_note.dart';
import 'package:anx_reader/page/settings_page/ai.dart';
import 'package:anx_reader/providers/ai_history.dart';
import 'package:anx_reader/providers/ai_chat.dart';
import 'package:anx_reader/providers/ai_workspace.dart';
import 'package:anx_reader/service/ai/ai_history.dart';
import 'package:anx_reader/service/ai/index.dart';
import 'package:anx_reader/service/ai/reading_ai_models.dart';
import 'package:anx_reader/service/ai/reading_frameworks.dart';
import 'package:anx_reader/utils/toast/common.dart';
import 'package:anx_reader/utils/env_var.dart';
import 'package:anx_reader/widgets/ai/ai_chat_stream.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:langchain_core/chat_models.dart';
import 'package:url_launcher/url_launcher.dart';

class AiReadingWorkspace extends ConsumerStatefulWidget {
  const AiReadingWorkspace({
    super.key,
    required this.controller,
    required this.chatKey,
    required this.quickPromptChips,
    required this.bookTitle,
    required this.bookAuthor,
    this.bookDescription,
    this.trailing,
    this.onOpenBookSession,
    this.onRestoreReadingContext,
    this.sendImmediate = false,
  });

  final AiWorkspaceController controller;
  final GlobalKey<AiChatStreamState> chatKey;
  final List<AiQuickPromptChip> quickPromptChips;
  final String bookTitle;
  final String bookAuthor;
  final String? bookDescription;
  final List<Widget>? trailing;
  final Future<void> Function(AiChatHistoryEntry entry)? onOpenBookSession;
  final Future<void> Function(AiChatHistoryEntry entry)?
      onRestoreReadingContext;
  final bool sendImmediate;

  @override
  ConsumerState<AiReadingWorkspace> createState() => _AiReadingWorkspaceState();
}

class _AiReadingWorkspaceState extends ConsumerState<AiReadingWorkspace> {
  bool _requestedModeSuggestion = false;
  bool _showAnalysisConfig = false;
  bool _analysisAutoRecommend = true;
  late ReadingAnalysisDepth _analysisDepth;
  late ReadingOutputTemplate _analysisOutput;
  final Set<ReadingFramework> _analysisFrameworks = {};
  final TextEditingController _readingGoalController = TextEditingController();

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
    _analysisDepth = widget.controller.analysisDepth;
    _analysisOutput = widget.controller.outputTemplate;
    _analysisAutoRecommend = Prefs().readingAnalysisAutoRecommend;
    if (!Prefs().hasReadingAiModeForBook(widget.controller.bookId)) {
      widget.controller.suggestMode(
        title: widget.bookTitle,
        description: widget.bookDescription,
      );
    }
  }

  Future<void> _suggestModeWithAi() async {
    if (_requestedModeSuggestion ||
        Prefs().hasReadingAiModeForBook(widget.controller.bookId)) {
      return;
    }
    if (EnvVar.isAppStore &&
        Prefs().shouldShowHint(HintKey.aiDataSharingConsent)) {
      return;
    }
    _requestedModeSuggestion = true;
    setState(() {});
    final selection = widget.controller.pendingSelection;
    final result = await aiGenerateText(
      [
        ChatMessage.humanText('''只输出 general、history、psychology、finance 之一，不要解释。
根据少量书籍元数据建议 AI 阅读模式：
书名：${widget.bookTitle}
作者：${widget.bookAuthor}
简介：${widget.bookDescription ?? ''}
当前章节：${selection?.chapterTitle ?? ''}
少量正文：${selection?.surroundingText ?? selection?.selectedText ?? ''}'''),
      ],
      useAgent: false,
      ref: ref,
    );
    if (!mounted) return;
    final normalized = result.trim().toLowerCase();
    for (final mode in ReadingAiMode.values) {
      if (normalized == mode.name || normalized.contains(mode.name)) {
        widget.controller.setSuggestedMode(mode);
        return;
      }
    }
  }

  @override
  void didUpdateWidget(covariant AiReadingWorkspace oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_changed);
      widget.controller.addListener(_changed);
      _analysisDepth = widget.controller.analysisDepth;
      _analysisOutput = widget.controller.outputTemplate;
      _showAnalysisConfig = false;
      _analysisFrameworks.clear();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    _readingGoalController.dispose();
    super.dispose();
  }

  void _changed() {
    if (!mounted) return;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: IndexedStack(
        index: controller.view.index,
        children: [
          _buildChat(),
          _buildHistory(),
          _buildSessionDetail(),
          _buildAgentsAndSources(),
        ],
      ),
    );
  }

  Widget _buildChat() {
    final pending = widget.controller.pendingSelection;
    return Column(
      children: [
        if (widget.controller.suggestedMode != null) _buildModeSuggestion(),
        _buildCurrentAgentTrace(),
        if (pending != null) _buildSelectionCard(pending),
        Expanded(
          child: AiChatStream(
            key: widget.chatKey,
            initialMessage: widget.controller.draft,
            sendImmediate: widget.sendImmediate,
            onDraftChanged: widget.controller.setDraft,
            initialScrollOffset: widget.controller.chatScrollOffset,
            onScrollOffsetChanged: widget.controller.setChatScrollOffset,
            onSaveAnswer: _saveAnswerAsNote,
            quickPromptChips: widget.quickPromptChips,
            title: _modeLabel(widget.controller.mode),
            onOpenHistory: widget.controller.showHistory,
            onOpenAgents: widget.controller.showAgentsAndSources,
            trailing: widget.trailing,
          ),
        ),
      ],
    );
  }

  Widget _buildCurrentAgentTrace() {
    final sessionId = ref.read(aiChatProvider.notifier).currentSessionId;
    if (sessionId == null) return const SizedBox.shrink();
    final history = ref.watch(aiHistoryProvider).asData?.value ?? const [];
    AiChatHistoryEntry? current;
    for (final entry in history) {
      if (entry.id == sessionId) {
        current = entry;
        break;
      }
    }
    if (current == null ||
        (current.agentTraces.isEmpty &&
            current.citations.isEmpty &&
            current.analysisDepth == null)) {
      return const SizedBox.shrink();
    }
    final frameworkLabels = current.frameworks.map((value) {
      final framework = ReadingFramework.fromJson(value);
      return framework == null
          ? value
          : const ReadingFrameworkRegistry().get(framework).label;
    }).join('、');
    return ExpansionTile(
      initiallyExpanded: false,
      leading: const Icon(Icons.hub_outlined, size: 18),
      title: Text(
        current.analysisDepth == null
            ? '专家任务 ${current.agentTraces.length}'
            : '${_analysisDepthLabel(ReadingAnalysisDepth.fromJson(current.analysisDepth))}分析 · $frameworkLabels',
      ),
      subtitle: Text(
        '专家 ${current.agentTraces.length} · 来源 ${current.citations.length} · 点击查看详情',
      ),
      children: [
        if (current.analysisDepth != null)
          ListTile(
            dense: true,
            leading: const Icon(Icons.auto_awesome, size: 18),
            title: Text(
              _analysisOutputLabel(
                ReadingOutputTemplate.fromJson(current.outputTemplate),
              ),
            ),
            subtitle: Text(
              current.readingGoal?.isNotEmpty == true
                  ? '目标：${current.readingGoal}'
                  : '目标：理解当前内容及其在本书中的作用',
            ),
          ),
        for (final trace in current.agentTraces)
          ListTile(
            dense: true,
            leading: Icon(
              trace['status'] == 'completed'
                  ? Icons.check_circle_outline
                  : Icons.info_outline,
              size: 18,
            ),
            title: Text(trace['agentId']?.toString() ?? 'agent'),
            subtitle: Text(
              trace['detail']?.toString().isNotEmpty == true
                  ? trace['detail'].toString()
                  : trace['status']?.toString() ?? '',
            ),
          ),
        for (final citation in current.citations)
          ListTile(
            dense: true,
            leading: const Icon(Icons.link, size: 18),
            title: Text(
              citation['title']?.toString() ??
                  citation['url']?.toString() ??
                  'Source',
            ),
            subtitle: Text(
              [
                citation['url']?.toString() ?? '',
                if (citation['publishedAt'] != null)
                  '发布：${citation['publishedAt']}',
                if (citation['accessedAt'] != null)
                  '访问：${citation['accessedAt']}',
              ].where((value) => value.isNotEmpty).join('\n'),
            ),
            onTap: () {
              final uri = Uri.tryParse(citation['url']?.toString() ?? '');
              if (uri != null) launchUrl(uri);
            },
          ),
      ],
    );
  }

  Widget _buildModeSuggestion() {
    final suggested = widget.controller.suggestedMode!;
    return MaterialBanner(
      content: Text('建议使用“${_modeLabel(suggested)}”模式，确认后仅对本书生效。'),
      actions: [
        TextButton(
          onPressed: _requestedModeSuggestion ? null : _suggestModeWithAi,
          child: const Text('AI 识别'),
        ),
        TextButton(
          onPressed: () => _setMode(suggested),
          child: Text(L10n.of(context).commonConfirm),
        ),
        TextButton(
          onPressed: () => _setMode(ReadingAiMode.general),
          child: Text(L10n.of(context).commonCancel),
        ),
      ],
    );
  }

  Widget _buildSelectionCard(ReadingContextSnapshot snapshot) {
    final actions = widget.controller.mode.agentProfile.actionOrder.take(4);
    return Card(
      margin: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      elevation: 0,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.format_quote, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    snapshot.selectedText ?? '',
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: widget.controller.clearPendingSelection,
                  icon: const Icon(Icons.close, size: 18),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final action in actions)
                  ActionChip(
                    label: Text(_actionLabel(action)),
                    onPressed: () {
                      if (action == SelectionAiAction.addNote) {
                        _saveSelectionAsNote(snapshot);
                        return;
                      }
                      final prompt = widget.controller.buildActionPrompt(
                        action,
                      );
                      final started =
                          widget.chatKey.currentState?.sendPrompt(prompt) ??
                              false;
                      if (started) {
                        widget.controller.clearPendingSelection();
                      }
                    },
                  ),
                ActionChip(
                  avatar: const Icon(Icons.auto_awesome, size: 16),
                  label: const Text('深度分析'),
                  onPressed: () => _openAnalysisConfig(snapshot),
                ),
              ],
            ),
            if (_showAnalysisConfig) ...[
              const Divider(height: 24),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * 0.55,
                ),
                child: SingleChildScrollView(
                  child: _buildAnalysisConfig(snapshot),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildAnalysisConfig(ReadingContextSnapshot snapshot) {
    const registry = ReadingFrameworkRegistry();
    final maxFrameworks = Prefs().readingAnalysisMaxFrameworks;
    final researchEnabled = Prefs().readingResearchWebSearch &&
        Prefs().readingWebSearchConfig.enabled;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('深度阅读', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<ReadingAnalysisDepth>(
                initialValue: _analysisDepth,
                decoration: const InputDecoration(
                  labelText: '分析深度',
                  isDense: true,
                ),
                items: ReadingAnalysisDepth.values
                    .map(
                      (depth) => DropdownMenuItem(
                        value: depth,
                        child: Text(_analysisDepthLabel(depth)),
                      ),
                    )
                    .toList(growable: false),
                onChanged: (depth) {
                  if (depth == null) return;
                  setState(() {
                    _analysisDepth = depth;
                    if (_analysisAutoRecommend) {
                      _recommendFrameworks(snapshot);
                    }
                  });
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: DropdownButtonFormField<ReadingOutputTemplate>(
                initialValue: _analysisOutput,
                decoration: const InputDecoration(
                  labelText: '输出形式',
                  isDense: true,
                ),
                items: ReadingOutputTemplate.values
                    .map(
                      (output) => DropdownMenuItem(
                        value: output,
                        child: Text(_analysisOutputLabel(output)),
                      ),
                    )
                    .toList(growable: false),
                onChanged: (output) {
                  if (output != null) setState(() => _analysisOutput = output);
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _readingGoalController,
          maxLines: 2,
          minLines: 1,
          decoration: const InputDecoration(
            labelText: '本次阅读目标（可选）',
            hintText: '例如：判断作者的论证是否成立',
            isDense: true,
          ),
          onChanged: (_) {
            if (_analysisAutoRecommend) {
              setState(() => _recommendFrameworks(snapshot));
            }
          },
        ),
        SwitchListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          value: _analysisAutoRecommend,
          title: const Text('自动推荐主要框架'),
          subtitle: Text('本地推荐，不调用模型；最多 $maxFrameworks 个'),
          onChanged: (value) {
            setState(() {
              _analysisAutoRecommend = value;
              if (value) _recommendFrameworks(snapshot);
            });
          },
        ),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final framework in ReadingFramework.values)
              ChoiceChip(
                label: Text(registry.get(framework).label),
                selected: _analysisFrameworks.contains(framework),
                onSelected: (selected) {
                  setState(() {
                    _analysisAutoRecommend = false;
                    if (selected) {
                      if (_analysisFrameworks.length >= maxFrameworks) {
                        _analysisFrameworks.remove(_analysisFrameworks.first);
                      }
                      _analysisFrameworks.add(framework);
                    } else if (_analysisFrameworks.length > 1) {
                      _analysisFrameworks.remove(framework);
                    }
                  });
                },
              ),
          ],
        ),
        const SizedBox(height: 6),
        for (final framework in _analysisFrameworks)
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Text(
              '${registry.get(framework).label}：${registry.get(framework).description}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        if (_analysisDepth == ReadingAnalysisDepth.research)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              researchEnabled
                  ? '研究档将使用已配置的可信网络来源。'
                  : '研究档未获得联网条件，将仅使用本书并列出待核查问题。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: () => setState(() => _showAnalysisConfig = false),
              child: Text(L10n.of(context).commonCancel),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: _analysisFrameworks.isEmpty
                  ? null
                  : () => _startDeepAnalysis(snapshot),
              icon: const Icon(Icons.play_arrow, size: 18),
              label: const Text('开始分析'),
            ),
          ],
        ),
      ],
    );
  }

  void _openAnalysisConfig(ReadingContextSnapshot snapshot) {
    _analysisDepth = widget.controller.analysisDepth;
    _analysisOutput = widget.controller.outputTemplate;
    _analysisAutoRecommend = Prefs().readingAnalysisAutoRecommend;
    _readingGoalController.clear();
    _recommendFrameworks(snapshot);
    if (!Prefs().readingAnalysisConfirmBeforeSend) {
      _startDeepAnalysis(snapshot);
      return;
    }
    setState(() => _showAnalysisConfig = true);
  }

  void _recommendFrameworks(ReadingContextSnapshot snapshot) {
    final frameworks = const ReadingFrameworkRecommender().recommend(
      depth: _analysisDepth,
      mode: widget.controller.mode,
      readingGoal: _readingGoalController.text,
      text: snapshot.selectedText,
      maxFrameworks: Prefs().readingAnalysisMaxFrameworks,
    );
    _analysisFrameworks
      ..clear()
      ..addAll(frameworks);
  }

  void _startDeepAnalysis(ReadingContextSnapshot snapshot) {
    if (_analysisFrameworks.isEmpty) _recommendFrameworks(snapshot);
    final request = widget.controller.buildAnalysisRequest(
      depth: _analysisDepth,
      output: _analysisOutput,
      frameworks: _analysisFrameworks.toList(growable: false),
      readingGoal: _readingGoalController.text,
      recommendedAutomatically: _analysisAutoRecommend,
    );
    widget.controller.setAnalysisDefaults(
      depth: _analysisDepth,
      output: _analysisOutput,
    );
    ref.read(aiChatProvider.notifier).setReadingAnalysisRequest(request);
    final prompt = widget.controller.buildDeepAnalysisPrompt(request);
    final started = widget.chatKey.currentState?.sendPrompt(prompt) ?? false;
    if (started) {
      widget.controller.clearPendingSelection();
      setState(() => _showAnalysisConfig = false);
    }
  }

  Widget _buildHistory() {
    final state = ref.watch(aiHistoryProvider);
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leadingWidth: 96,
        leading: TextButton.icon(
          key: const ValueKey('ai-history-back'),
          onPressed: widget.controller.showChat,
          icon: const Icon(Icons.arrow_back, size: 20),
          label: const Text('返回'),
        ),
        title: Text(L10n.of(context).conversationHistory),
        actions: [
          TextButton(
            onPressed: () => widget.controller.setHistoryScope(
              !widget.controller.showAllHistory,
            ),
            child: Text(widget.controller.showAllHistory ? '当前书' : '全部会话'),
          ),
        ],
      ),
      body: state.when(
        loading: () => Center(
          child: Prefs().reduceMotion
              ? const Text('Loading...')
              : const CircularProgressIndicator(),
        ),
        error: (_, __) =>
            Center(child: Text(L10n.of(context).failedToLoadHistoryTip)),
        data: (entries) {
          final visible = widget.controller.showAllHistory
              ? entries
              : entries
                  .where((entry) => entry.bookId == widget.controller.bookId)
                  .toList(growable: false);
          if (visible.isEmpty) {
            return Center(child: Text(L10n.of(context).noConversationTip));
          }
          if (widget.controller.showAllHistory) {
            final groups = <String, List<AiChatHistoryEntry>>{};
            for (final entry in visible) {
              final label = entry.bookTitle ?? '未关联书籍';
              groups.putIfAbsent(label, () => []).add(entry);
            }
            return ListView(
              key: const PageStorageKey('ai-history-all'),
              children: [
                for (final group in groups.entries) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                    child: Text(
                      group.key,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  for (final entry in group.value) _buildHistoryTile(entry),
                ],
              ],
            );
          }
          return ListView.builder(
            key: PageStorageKey('ai-history-${widget.controller.bookId}'),
            itemCount: visible.length,
            itemBuilder: (context, index) {
              final entry = visible[index];
              return _buildHistoryTile(entry);
            },
          );
        },
      ),
    );
  }

  Widget _buildHistoryTile(AiChatHistoryEntry entry) {
    return ListTile(
      leading: const Icon(Icons.chat_bubble_outline),
      title: Text(entry.title ?? _historyTitle(entry)),
      subtitle: Text(
        '${entry.bookTitle ?? '未关联书籍'} · ${entry.chapterTitle ?? entry.model}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => widget.controller.showSessionDetail(entry),
    );
  }

  Widget _buildSessionDetail() {
    final entry = widget.controller.selectedSession;
    if (entry == null) return const SizedBox.shrink();
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leadingWidth: 96,
        leading: TextButton.icon(
          key: const ValueKey('ai-session-back'),
          onPressed: widget.controller.showHistory,
          icon: const Icon(Icons.arrow_back, size: 20),
          label: const Text('返回'),
        ),
        title: Text(entry.title ?? _historyTitle(entry)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            entry.bookTitle ?? '未关联书籍',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          if (entry.chapterTitle != null) Text(entry.chapterTitle!),
          const SizedBox(height: 12),
          Text('模式：${entry.readingMode ?? 'general'}'),
          if (entry.analysisDepth != null)
            Text(
              '深度：${_analysisDepthLabel(ReadingAnalysisDepth.fromJson(entry.analysisDepth))}',
            ),
          if (entry.frameworks.isNotEmpty)
            Text(
              '框架：${entry.frameworks.map((value) {
                final framework = ReadingFramework.fromJson(value);
                return framework == null
                    ? value
                    : const ReadingFrameworkRegistry().get(framework).label;
              }).join('、')}',
            ),
          if (entry.outputTemplate != null)
            Text(
              '输出：${_analysisOutputLabel(ReadingOutputTemplate.fromJson(entry.outputTemplate))}',
            ),
          Text('模型：${entry.serviceId} · ${entry.model}'),
          Text('消息：${entry.messages.length}'),
          Text('专家任务：${entry.agentTraces.length}'),
          Text('引用：${entry.citations.length}'),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () => _restoreSession(entry),
            icon: const Icon(Icons.restore),
            label: const Text('恢复并继续对话'),
          ),
        ],
      ),
    );
  }

  Widget _buildAgentsAndSources() {
    final profile = widget.controller.mode.agentProfile;
    final search = Prefs().readingWebSearchConfig;
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leadingWidth: 96,
        leading: TextButton.icon(
          key: const ValueKey('ai-agents-back'),
          onPressed: widget.controller.showChat,
          icon: const Icon(Icons.arrow_back, size: 20),
          label: const Text('返回'),
        ),
        title: const Text('专家与来源'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          DropdownButtonFormField<ReadingAiMode>(
            initialValue: widget.controller.mode,
            decoration: const InputDecoration(labelText: '阅读模式'),
            items: ReadingAiMode.values
                .map(
                  (mode) => DropdownMenuItem(
                    value: mode,
                    child: Text(_modeLabel(mode)),
                  ),
                )
                .toList(growable: false),
            onChanged: (mode) {
              if (mode != null) _setMode(mode);
            },
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<ReadingAnalysisDepth>(
            initialValue: widget.controller.analysisDepth,
            decoration: const InputDecoration(
              labelText: '本书默认分析深度',
              helperText: '仅影响之后发起的深度分析',
            ),
            items: ReadingAnalysisDepth.values
                .map(
                  (depth) => DropdownMenuItem(
                    value: depth,
                    child: Text(_analysisDepthLabel(depth)),
                  ),
                )
                .toList(growable: false),
            onChanged: (depth) {
              if (depth == null) return;
              widget.controller.setAnalysisDefaults(
                depth: depth,
                output: widget.controller.outputTemplate,
              );
            },
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<ReadingOutputTemplate>(
            initialValue: widget.controller.outputTemplate,
            decoration: const InputDecoration(labelText: '本书默认输出形式'),
            items: ReadingOutputTemplate.values
                .map(
                  (output) => DropdownMenuItem(
                    value: output,
                    child: Text(_analysisOutputLabel(output)),
                  ),
                )
                .toList(growable: false),
            onChanged: (output) {
              if (output == null) return;
              widget.controller.setAnalysisDefaults(
                depth: widget.controller.analysisDepth,
                output: output,
              );
            },
          ),
          if (Prefs().hasReadingAnalysisConfigForBook(widget.controller.bookId))
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: widget.controller.resetAnalysisDefaults,
                child: const Text('恢复全局默认'),
              ),
            ),
          const SizedBox(height: 20),
          Text('主助手', style: Theme.of(context).textTheme.titleMedium),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.account_tree_outlined),
            value: Prefs().readingMultiAgentEnabled,
            title: const Text('主助手调度专家'),
            subtitle: const Text('简单问题直接回答；复杂问题最多并行调用两个专家'),
            onChanged: (value) {
              Prefs().readingMultiAgentEnabled = value;
              setState(() {});
            },
          ),
          ListTile(
            enabled: Prefs().readingMultiAgentEnabled,
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.psychology_outlined),
            title: Text(profile.displayName),
            subtitle: Text('当前模式专家 · 可使用 ${profile.allowedTools.length} 个阅读工具'),
          ),
          ListTile(
            enabled: Prefs().readingMultiAgentEnabled,
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.fact_check_outlined),
            title: const Text('来源研究员与事实核查员'),
            subtitle: const Text('负责出处、时间、数字、证据冲突和不确定性'),
          ),
          const Divider(),
          Text('网络检索', style: Theme.of(context).textTheme.titleMedium),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(search.enabled ? Icons.cloud_done : Icons.cloud_off),
            title: Text(search.enabled ? '已启用' : '默认关闭'),
            subtitle: Text(search.enabled ? '仅保留可信域名中的结果' : '将使用本书、笔记、书架和内置词典'),
          ),
          const Divider(),
          Text('可信来源', style: Theme.of(context).textTheme.titleMedium),
          for (final domain in Prefs()
              .readingTrustedSourcePack(widget.controller.mode)
              .domains)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.verified_outlined, size: 18),
              title: Text(domain),
            ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: _openGlobalAiSettings,
            icon: const Icon(Icons.tune),
            label: const Text('打开完整 AI 设置'),
          ),
        ],
      ),
    );
  }

  void _openGlobalAiSettings() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => Scaffold(
          appBar: AppBar(title: Text(L10n.of(context).settingsAi)),
          body: const AISettings(),
        ),
      ),
    );
  }

  Future<void> _restoreSession(AiChatHistoryEntry entry) async {
    if (entry.bookId != null && entry.bookId != widget.controller.bookId) {
      final openBook = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('这是另一本书的会话'),
          content: Text(
            widget.onOpenBookSession == null
                ? '会话属于《${entry.bookTitle ?? ''}》。当前版本需先从书架打开该书，才能恢复当时的阅读位置；也可以只恢复对话。'
                : '是否打开《${entry.bookTitle ?? ''}》并恢复当时的阅读上下文？',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('仅恢复对话'),
            ),
            if (widget.onOpenBookSession != null)
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('打开该书'),
              ),
          ],
        ),
      );
      if (openBook == true && widget.onOpenBookSession != null) {
        await widget.onOpenBookSession!(entry);
        return;
      }
    }
    await widget.chatKey.currentState?.restoreSession(entry);
    await widget.onRestoreReadingContext?.call(entry);
    final restoredMode = ReadingAiMode.fromJson(entry.readingMode);
    widget.controller.setMode(restoredMode, persist: false);
    if (entry.analysisDepth != null) {
      widget.controller.setAnalysisDefaults(
        depth: ReadingAnalysisDepth.fromJson(entry.analysisDepth),
        output: ReadingOutputTemplate.fromJson(entry.outputTemplate),
        persist: false,
      );
    }
    ref.read(aiChatProvider.notifier).setReadingModeOverride(restoredMode);
    widget.controller.showChat();
    await widget.chatKey.currentState?.scrollToBottom(waitForLayout: true);
  }

  void _setMode(ReadingAiMode mode) {
    widget.controller.setMode(mode);
    ref.read(aiChatProvider.notifier).setReadingModeOverride(mode);
  }

  Future<void> _saveSelectionAsNote(ReadingContextSnapshot snapshot) async {
    final cfi = snapshot.metadata['cfi']?.toString() ?? '';
    final now = DateTime.now();
    await bookNoteDao.save(
      BookNote(
        bookId: widget.controller.bookId,
        content: snapshot.selectedText ?? '',
        cfi: cfi,
        chapter: snapshot.chapterTitle ?? '',
        type: 'highlight',
        color: Prefs().annotationColor,
        readerNote: 'AI 阅读工作台待处理划线',
        createTime: now,
        updateTime: now,
      ),
    );
    widget.controller.clearPendingSelection();
    if (mounted) AnxToast.show(L10n.of(context).commonSaveSuccess);
  }

  Future<void> _saveAnswerAsNote(String answer) async {
    final snapshot = widget.controller.lastSelection;
    if (snapshot == null) {
      AnxToast.show('请先从阅读页选择一段内容');
      return;
    }
    final sessionId = ref.read(aiChatProvider.notifier).currentSessionId;
    final entry = ref
        .read(aiHistoryProvider)
        .asData
        ?.value
        .where((item) => item.id == sessionId)
        .firstOrNull;
    final sourceLines = entry?.citations
            .map((source) => source['url']?.toString())
            .whereType<String>()
            .take(3)
            .join('\n') ??
        '';
    final analysisLine = entry?.analysisDepth == null
        ? ''
        : '深度分析：${_analysisDepthLabel(ReadingAnalysisDepth.fromJson(entry!.analysisDepth))} · ${entry.frameworks.map((value) {
            final framework = ReadingFramework.fromJson(value);
            return framework == null
                ? value
                : const ReadingFrameworkRegistry().get(framework).label;
          }).join('、')}\n';
    final normalized = answer.replaceAll(RegExp(r'\s+'), ' ').trim();
    final summary = normalized.length <= 480
        ? normalized
        : '${normalized.substring(0, 480)}...';
    final now = DateTime.now();
    await bookNoteDao.save(
      BookNote(
        bookId: widget.controller.bookId,
        content: snapshot.selectedText ?? '',
        cfi: snapshot.metadata['cfi']?.toString() ?? '',
        chapter: snapshot.chapterTitle ?? '',
        type: 'highlight',
        color: Prefs().annotationColor,
        readerNote: 'AI 摘要：$summary\n'
            '$analysisLine'
            '${sourceLines.isEmpty ? '' : '来源：\n$sourceLines\n'}'
            '会话：anx-ai-session://${sessionId ?? ''}',
        createTime: now,
        updateTime: now,
      ),
    );
    if (mounted) AnxToast.show(L10n.of(context).commonSaveSuccess);
  }

  String _historyTitle(AiChatHistoryEntry entry) {
    for (final message in entry.messages) {
      final text = message.contentAsString.trim();
      if (text.isNotEmpty) return text.split('\n').first;
    }
    return 'Conversation';
  }

  String _modeLabel(ReadingAiMode mode) => switch (mode) {
        ReadingAiMode.general => '通用陪读',
        ReadingAiMode.history => '历史陪读',
        ReadingAiMode.psychology => '心理陪读',
        ReadingAiMode.finance => '理财陪读',
      };

  String _actionLabel(SelectionAiAction action) => switch (action) {
        SelectionAiAction.explain => '解释',
        SelectionAiAction.summarize => '总结',
        SelectionAiAction.contextualize =>
          widget.controller.mode == ReadingAiMode.history ? '时间线/背景' : '联系全书',
        SelectionAiAction.factCheck =>
          widget.controller.mode == ReadingAiMode.history ? '史料核查' : '事实核查',
        SelectionAiAction.analyze =>
          widget.controller.mode == ReadingAiMode.psychology
              ? '反思对话'
              : widget.controller.mode == ReadingAiMode.finance
                  ? '验证假设/风险'
                  : '分析',
        SelectionAiAction.translate => '翻译',
        SelectionAiAction.connectToBook => '联系全书',
        SelectionAiAction.addNote => '加入笔记',
        SelectionAiAction.sourceLookup => '查典籍',
        SelectionAiAction.timeline => '时间线',
        SelectionAiAction.reflection => '反思对话',
        SelectionAiAction.exercise => '生成练习',
        SelectionAiAction.validateAssumption => '验证假设',
        SelectionAiAction.calculate => '计算',
        SelectionAiAction.riskCheck => '风险检查',
        SelectionAiAction.deepAnalyze => '深度分析',
      };

  String _analysisDepthLabel(ReadingAnalysisDepth depth) => switch (depth) {
        ReadingAnalysisDepth.quick => '快读',
        ReadingAnalysisDepth.standard => '精读',
        ReadingAnalysisDepth.deep => '深读',
        ReadingAnalysisDepth.research => '研究',
      };

  String _analysisOutputLabel(ReadingOutputTemplate output) => switch (output) {
        ReadingOutputTemplate.learningNote => '学习笔记',
        ReadingOutputTemplate.argumentAnalysis => '论证分析',
        ReadingOutputTemplate.conceptMap => '概念图',
        ReadingOutputTemplate.practicePlan => '实践计划',
      };
}

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/enums/ai_prompts.dart';
import 'package:anx_reader/enums/ai_chat_display_mode.dart';
import 'package:anx_reader/enums/ai_panel_position.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/page/settings_page/ai_provider_list_page.dart';
import 'package:anx_reader/providers/ai_cache_count.dart';
import 'package:anx_reader/providers/ai_providers.dart';
import 'package:anx_reader/providers/user_prompts.dart';
import 'package:anx_reader/service/ai/tools/ai_tool_registry.dart';
import 'package:anx_reader/service/ai/reading_ai_models.dart';
import 'package:anx_reader/service/ai/web_search.dart';
import 'package:anx_reader/widgets/common/anx_button.dart';
import 'package:anx_reader/widgets/common/anx_segmented_button.dart';
import 'package:anx_reader/widgets/delete_confirm.dart';
import 'package:anx_reader/widgets/settings/settings_section.dart';
import 'package:anx_reader/widgets/settings/settings_tile.dart';
import 'package:anx_reader/widgets/settings/settings_title.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:anx_reader/utils/toast/common.dart';

class AISettings extends ConsumerStatefulWidget {
  const AISettings({super.key});

  @override
  ConsumerState<AISettings> createState() => _AISettingsState();
}

class _AISettingsState extends ConsumerState<AISettings> {
  // User prompts state
  String? _expandedUserPromptId;
  final Map<String, TextEditingController> _userPromptNameControllers = {};
  final Map<String, TextEditingController> _userPromptContentControllers = {};

  @override
  void dispose() {
    // Clean up user prompt controllers
    for (var controller in _userPromptNameControllers.values) {
      controller.dispose();
    }
    for (var controller in _userPromptContentControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);

    List<Map<String, dynamic>> prompts = [
      {
        "identifier": AiPrompts.test,
        "title": l10n.settingsAiPromptTest,
        "variables": ["language_locale"],
      },
      {
        "identifier": AiPrompts.summaryTheChapter,
        "title": l10n.settingsAiPromptSummaryTheChapter,
        "variables": [],
      },
      {
        "identifier": AiPrompts.summaryTheBook,
        "title": l10n.settingsAiPromptSummaryTheBook,
        "variables": [],
      },
      {
        "identifier": AiPrompts.summaryThePreviousContent,
        "title": l10n.settingsAiPromptSummaryThePreviousContent,
        "variables": ["previous_content"],
      },
      {
        "identifier": AiPrompts.translate,
        "title": l10n.settingsAiPromptTranslateAndDictionary,
        "variables": ["text", "to_locale", "from_locale", "contextText"],
      },
      {
        "identifier": AiPrompts.fullTextTranslate,
        "title": l10n.settingsAiPromptFullTextTranslate,
        "variables": ["text", "to_locale", "from_locale"],
      },
      {
        "identifier": AiPrompts.mindmap,
        "title": l10n.settingsAiPromptMindmap,
        "variables": [],
      }
    ];

    var promptTile = CustomSettingsTile(
      child: ListView.builder(
        physics: const NeverScrollableScrollPhysics(),
        shrinkWrap: true,
        itemCount: prompts.length,
        itemBuilder: (context, index) {
          return SettingsTile.navigation(
            title: Text(prompts[index]["title"]),
            onPressed: (context) {
              SmartDialog.show(builder: (context) {
                final controller = TextEditingController(
                  text: Prefs().getAiPrompt(
                    AiPrompts.values[index],
                  ),
                );

                return AlertDialog(
                  title: Text(L10n.of(context).commonEdit),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        maxLines: 10,
                        controller: controller,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                        ),
                      ),
                      Wrap(
                        children: [
                          for (var variable in prompts[index]["variables"])
                            TextButton(
                              onPressed: () {
                                // insert the variables at the cursor
                                if (controller.selection.start == -1 ||
                                    controller.selection.end == -1) {
                                  return;
                                }

                                TextSelection.fromPosition(
                                  TextPosition(
                                    offset: controller.selection.start,
                                  ),
                                );

                                controller.text = controller.text.replaceRange(
                                  controller.selection.start,
                                  controller.selection.end,
                                  '{{$variable}}',
                                );
                              },
                              child: Text(
                                '{{$variable}}',
                              ),
                            ),
                        ],
                      )
                    ],
                  ),
                  actions: [
                    TextButton(
                      onPressed: () {
                        Prefs().deleteAiPrompt(AiPrompts.values[index]);
                        controller.text = Prefs().getAiPrompt(
                          AiPrompts.values[index],
                        );
                      },
                      child: Text(L10n.of(context).commonReset),
                    ),
                    TextButton(
                      onPressed: () {
                        Prefs().saveAiPrompt(
                          AiPrompts.values[index],
                          controller.text,
                        );
                      },
                      child: Text(L10n.of(context).commonSave),
                    ),
                  ],
                );
              });
            },
          );
        },
      ),
    );

    final toolDefs = AiToolRegistry.definitions;
    final enabledToolIds = Prefs().enabledAiToolIds;

    final toolsTile = CustomSettingsTile(
      child: Column(
        children: [
          for (final tool in toolDefs)
            SettingsTile.switchTile(
              initialValue: enabledToolIds.contains(tool.id),
              onToggle: (value) {
                final next = Set<String>.from(enabledToolIds);
                if (value) {
                  next.add(tool.id);
                } else {
                  next.remove(tool.id);
                }
                Prefs().enabledAiToolIds = next.toList();
                setState(() {});
              },
              title: Text(tool.displayName(l10n)),
              description: Text(tool.description(l10n)),
            ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () {
                Prefs().resetEnabledAiTools();
                setState(() {});
              },
              child: Text(l10n.commonReset),
            ),
          ),
        ],
      ),
    );

    return settingsSections(sections: [
      SettingsSection(
        title: Text(L10n.of(context).settingsAiServices),
        tiles: [
          SettingsTile.navigation(
            title: Text(l10n.settingsAiProviders),
            description: _buildProviderDescription(),
            onPressed: (context) {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const AiProviderCenterPage(),
                ),
              );
            },
          ),
          CustomSettingsTile(
              child: _AiRpmTile(setState: () => setState(() {}))),
          // SettingsTile.navigation(
          //   leading: const Icon(Icons.chat),
          //   title: Text(L10n.of(context).aiChat),
          //   onPressed: (context) {
          //     Navigator.push(
          //       context,
          //       CupertinoPageRoute(
          //         builder: (context) => const AiChatPage(),
          //       ),
          //     );
          //   },
          // ),
        ],
      ),
      SettingsSection(
        title: Text(L10n.of(context).settingsAiChatDisplay),
        tiles: [
          aiChatDisplayModeTile(),
          if (Prefs().aiChatDisplayMode != AiChatDisplayMode.popup)
            aiPanelPositionTile(),
        ],
      ),
      SettingsSection(
        title: const Text('阅读模式'),
        tiles: [
          _readingModeTile(),
        ],
      ),
      SettingsSection(
        title: const Text('深度阅读'),
        tiles: [
          _deepReadingTile(),
        ],
      ),
      SettingsSection(
        title: const Text('专家'),
        tiles: [
          SettingsTile.switchTile(
            initialValue: Prefs().readingMultiAgentEnabled,
            onToggle: (value) {
              Prefs().readingMultiAgentEnabled = value;
              setState(() {});
            },
            title: const Text('主助手调度专家'),
            description: const Text('复杂问题最多并行调用两个专家；简单问题直接回答'),
          ),
        ],
      ),
      SettingsSection(
        title: const Text('网络检索'),
        tiles: [
          _webSearchTile(),
        ],
      ),
      SettingsSection(
        title: const Text('可信来源'),
        tiles: [
          SettingsTile.navigation(
            title: const Text('查看模式来源包'),
            description: const Text('联网结果必须匹配对应模式的可信域名'),
            onPressed: (_) => _showTrustedSources(),
          ),
        ],
      ),
      SettingsSection(
        title: Text(L10n.of(context).settingsAiPrompt),
        tiles: [
          promptTile,
        ],
      ),
      SettingsSection(
        title: Text(L10n.of(context).settingsAiUserPrompts),
        tiles: [
          userPromptsTile(),
        ],
      ),
      SettingsSection(
        title: Text(l10n.settingsAiTools),
        tiles: [
          toolsTile,
        ],
      ),
      SettingsSection(
        title: Text(L10n.of(context).settingsAiCache),
        tiles: [
          CustomSettingsTile(
            child: ListTile(
              title: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(L10n.of(context).settingsAiCacheSize),
                  Text(
                    L10n.of(context).settingsAiCacheCurrentSize(ref
                        .watch(aiCacheCountProvider)
                        .when(
                            data: (value) => value,
                            loading: () => 0,
                            error: (error, stack) => 0)),
                  ),
                ],
              ),
              subtitle: Row(
                children: [
                  Text(Prefs().maxAiCacheCount.toString()),
                  Expanded(
                    child: Slider(
                      value: Prefs().maxAiCacheCount.toDouble(),
                      min: 0,
                      max: 1000,
                      divisions: 100,
                      label: Prefs().maxAiCacheCount.toString(),
                      onChanged: (value) {
                        Prefs().maxAiCacheCount = value.toInt();
                        setState(() {});
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
          SettingsTile.navigation(
              title: Text(L10n.of(context).settingsAiCacheClear),
              onPressed: (context) {
                SmartDialog.show(
                  builder: (context) => AlertDialog(
                    title: Text(L10n.of(context).commonConfirm),
                    actions: [
                      TextButton(
                        onPressed: () {
                          SmartDialog.dismiss();
                        },
                        child: Text(L10n.of(context).commonCancel),
                      ),
                      TextButton(
                        onPressed: () {
                          ref.read(aiCacheCountProvider.notifier).clearCache();
                          SmartDialog.dismiss();
                        },
                        child: Text(L10n.of(context).commonConfirm),
                      ),
                    ],
                  ),
                );
              }),
        ],
      ),
    ]);
  }

  AbstractSettingsTile _readingModeTile() {
    return CustomSettingsTile(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: DropdownButtonFormField<ReadingAiMode>(
          initialValue: Prefs().defaultReadingAiMode,
          decoration: const InputDecoration(
            labelText: '默认阅读模式',
            helperText: '每本书可在 AI 阅读工作台中单独覆盖',
          ),
          items: ReadingAiMode.values
              .map((mode) => DropdownMenuItem(
                    value: mode,
                    child: Text(_readingModeLabel(mode)),
                  ))
              .toList(growable: false),
          onChanged: (mode) {
            if (mode == null) return;
            Prefs().defaultReadingAiMode = mode;
            setState(() {});
          },
        ),
      ),
    );
  }

  AbstractSettingsTile _deepReadingTile() {
    return CustomSettingsTile(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DropdownButtonFormField<ReadingAnalysisDepth>(
              initialValue: Prefs().defaultReadingAnalysisDepth,
              decoration: const InputDecoration(
                labelText: '默认分析深度',
                helperText: '快读不调用专家；精读 1 个；深读与研究最多 2 个',
              ),
              items: ReadingAnalysisDepth.values
                  .map((depth) => DropdownMenuItem(
                        value: depth,
                        child: Text(_analysisDepthLabel(depth)),
                      ))
                  .toList(growable: false),
              onChanged: (depth) {
                if (depth == null) return;
                Prefs().defaultReadingAnalysisDepth = depth;
                setState(() {});
              },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<ReadingOutputTemplate>(
              initialValue: Prefs().defaultReadingOutputTemplate,
              decoration: const InputDecoration(labelText: '默认输出形式'),
              items: ReadingOutputTemplate.values
                  .map((output) => DropdownMenuItem(
                        value: output,
                        child: Text(_analysisOutputLabel(output)),
                      ))
                  .toList(growable: false),
              onChanged: (output) {
                if (output == null) return;
                Prefs().defaultReadingOutputTemplate = output;
                setState(() {});
              },
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: Prefs().readingAnalysisAutoRecommend,
              title: const Text('本地自动推荐框架'),
              subtitle: const Text('根据深度、阅读模式和目标推荐，不调用 AI'),
              onChanged: (value) {
                Prefs().readingAnalysisAutoRecommend = value;
                setState(() {});
              },
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: Prefs().readingAnalysisConfirmBeforeSend,
              title: const Text('发送前确认'),
              subtitle: const Text('在划线动作卡中确认深度、框架和输出形式'),
              onChanged: (value) {
                Prefs().readingAnalysisConfirmBeforeSend = value;
                setState(() {});
              },
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: Prefs().readingResearchWebSearch,
              title: const Text('研究档允许联网'),
              subtitle: const Text('仅研究档生效，且仍需启用并配置下方网络检索'),
              onChanged: (value) {
                Prefs().readingResearchWebSearch = value;
                setState(() {});
              },
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('主要框架数量'),
              subtitle: Slider(
                value: Prefs().readingAnalysisMaxFrameworks.toDouble(),
                min: 1,
                max: 2,
                divisions: 1,
                label: '${Prefs().readingAnalysisMaxFrameworks}',
                onChanged: (value) {
                  Prefs().readingAnalysisMaxFrameworks = value.round();
                  setState(() {});
                },
              ),
              trailing: Text('${Prefs().readingAnalysisMaxFrameworks}'),
            ),
          ],
        ),
      ),
    );
  }

  AbstractSettingsTile _webSearchTile() {
    final config = Prefs().readingWebSearchConfig;
    return CustomSettingsTile(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: config.enabled,
              title: const Text('允许联网核查'),
              subtitle: const Text('默认关闭；失败时自动退化到本书、笔记和内置词典'),
              onChanged: (enabled) {
                Prefs().readingWebSearchConfig = _copySearchConfig(
                  config,
                  enabled: enabled,
                );
                setState(() {});
              },
            ),
            DropdownButtonFormField<WebSearchProvider>(
              initialValue: config.provider,
              decoration: const InputDecoration(labelText: '搜索供应商'),
              items: WebSearchProvider.values
                  .map((provider) => DropdownMenuItem(
                        value: provider,
                        child: Text(switch (provider) {
                          WebSearchProvider.tavily => 'Tavily',
                          WebSearchProvider.brave => 'Brave Search',
                          WebSearchProvider.custom => '自定义兼容接口',
                        }),
                      ))
                  .toList(growable: false),
              onChanged: (provider) {
                if (provider == null) return;
                Prefs().readingWebSearchConfig = switch (provider) {
                  WebSearchProvider.tavily => WebSearchProviderConfig.tavily(
                      enabled: config.enabled,
                      apiKey: config.apiKey,
                      trustedSources: config.trustedSources,
                    ),
                  WebSearchProvider.brave => WebSearchProviderConfig.brave(
                      enabled: config.enabled,
                      apiKey: config.apiKey,
                      trustedSources: config.trustedSources,
                    ),
                  WebSearchProvider.custom => WebSearchProviderConfig.custom(
                      enabled: config.enabled,
                      apiKey: config.apiKey,
                      endpoint: config.provider == WebSearchProvider.custom
                          ? config.endpoint
                          : null,
                      trustedSources: config.trustedSources,
                    ),
                };
                setState(() {});
              },
            ),
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Key 与接口'),
              subtitle: Text(config.apiKey?.isNotEmpty == true
                  ? '${config.endpoint ?? config.effectiveEndpoint} · Key 已配置'
                  : '${config.endpoint ?? config.effectiveEndpoint} · 未配置 Key'),
              trailing: const Icon(Icons.edit_outlined),
              onTap: () => _editSearchCredentials(config),
            ),
          ],
        ),
      ),
    );
  }

  WebSearchProviderConfig _copySearchConfig(
    WebSearchProviderConfig config, {
    WebSearchProvider? provider,
    bool? enabled,
    String? apiKey,
    Uri? endpoint,
  }) {
    return WebSearchProviderConfig(
      provider: provider ?? config.provider,
      enabled: enabled ?? config.enabled,
      apiKey: apiKey ?? config.apiKey,
      endpoint: endpoint ?? config.endpoint,
      headers: config.headers,
      queryParameter: config.queryParameter,
      maxResults: config.maxResults,
      timeout: config.timeout,
      trustedSources: config.trustedSources,
    );
  }

  Future<void> _editSearchCredentials(WebSearchProviderConfig config) async {
    final keyController = TextEditingController(text: config.apiKey ?? '');
    final endpointController = TextEditingController(
      text: config.endpoint?.toString() ?? '',
    );
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('网络检索配置'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: keyController,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'API Key'),
            ),
            if (config.provider == WebSearchProvider.custom)
              TextField(
                controller: endpointController,
                decoration: const InputDecoration(labelText: 'HTTPS 接口地址'),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(L10n.of(context).commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(L10n.of(context).commonSave),
          ),
        ],
      ),
    );
    if (saved == true) {
      final endpointText = endpointController.text.trim();
      Prefs().readingWebSearchConfig = WebSearchProviderConfig(
        provider: config.provider,
        enabled: config.enabled,
        apiKey: keyController.text.trim(),
        endpoint: endpointText.isEmpty ? null : Uri.tryParse(endpointText),
        headers: config.headers,
        queryParameter: config.queryParameter,
        maxResults: config.maxResults,
        timeout: config.timeout,
        trustedSources: config.trustedSources,
      );
      if (mounted) setState(() {});
    }
    keyController.dispose();
    endpointController.dispose();
  }

  Future<void> _showTrustedSources() async {
    var selectedMode = ReadingAiMode.general;
    final domains = {
      for (final mode in ReadingAiMode.values)
        mode: List<String>.from(Prefs().readingTrustedSourcePack(mode).domains),
    };
    final domainController = TextEditingController();
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('可信来源包'),
          content: SizedBox(
            width: 520,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<ReadingAiMode>(
                  initialValue: selectedMode,
                  items: ReadingAiMode.values
                      .map((mode) => DropdownMenuItem(
                            value: mode,
                            child: Text(_readingModeLabel(mode)),
                          ))
                      .toList(growable: false),
                  onChanged: (mode) {
                    if (mode != null) {
                      setDialogState(() => selectedMode = mode);
                    }
                  },
                ),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: domainController,
                        decoration: const InputDecoration(
                          labelText: '域名，例如 who.int',
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.add),
                      onPressed: () {
                        final value = _normalizeTrustedDomain(
                          domainController.text,
                        );
                        if (value == null ||
                            domains[selectedMode]!.contains(value)) {
                          return;
                        }
                        setDialogState(() {
                          domains[selectedMode]!.add(value);
                          domainController.clear();
                        });
                      },
                    ),
                  ],
                ),
                SizedBox(
                  height: 300,
                  child: ListView(
                    shrinkWrap: true,
                    children: domains[selectedMode]!
                        .map((domain) => ListTile(
                              dense: true,
                              title: Text(domain),
                              trailing: IconButton(
                                icon: const Icon(Icons.delete_outline),
                                onPressed: () => setDialogState(
                                  () => domains[selectedMode]!.remove(domain),
                                ),
                              ),
                            ))
                        .toList(growable: false),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(L10n.of(context).commonCancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(L10n.of(context).commonSave),
            ),
          ],
        ),
      ),
    );
    domainController.dispose();
    if (saved == true) {
      for (final mode in ReadingAiMode.values) {
        Prefs().setReadingTrustedSourceDomains(mode, domains[mode]!);
      }
      if (mounted) setState(() {});
    }
  }

  String? _normalizeTrustedDomain(String input) {
    final trimmed = input.trim().toLowerCase();
    if (trimmed.isEmpty) return null;
    final uri = Uri.tryParse(
      trimmed.contains('://') ? trimmed : 'https://$trimmed',
    );
    if (uri == null || uri.host.isEmpty) return null;
    return uri.host.replaceFirst(RegExp(r'^www\.'), '');
  }

  String _readingModeLabel(ReadingAiMode mode) => switch (mode) {
        ReadingAiMode.general => '通用',
        ReadingAiMode.history => '历史',
        ReadingAiMode.psychology => '心理',
        ReadingAiMode.finance => '理财',
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

  // Build description showing current selected provider
  Widget? _buildProviderDescription() {
    final provider =
        ref.read(aiProvidersProvider.notifier).getSelectedProvider();
    if (provider == null) {
      return null;
    }
    return Text(provider.title);
  }

  // AI chat display mode configuration
  AbstractSettingsTile aiChatDisplayModeTile() {
    final l10n = L10n.of(context);
    return CustomSettingsTile(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.settingsAiChatDisplayMode,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: AnxSegmentedButton<AiChatDisplayMode>(
                    segments: [
                      SegmentButtonItem(
                        value: AiChatDisplayMode.adaptive,
                        label: l10n.settingsAiChatDisplayModeAdaptive,
                        icon: const Icon(Icons.auto_awesome, size: 18),
                      ),
                      SegmentButtonItem(
                        value: AiChatDisplayMode.split,
                        label: l10n.settingsAiChatDisplayModeSplit,
                        icon: const Icon(Icons.splitscreen, size: 18),
                      ),
                      SegmentButtonItem(
                        value: AiChatDisplayMode.popup,
                        label: l10n.settingsAiChatDisplayModePopup,
                        icon: const Icon(Icons.open_in_new, size: 18),
                      ),
                    ],
                    selected: {Prefs().aiChatDisplayMode},
                    onSelectionChanged: (Set<AiChatDisplayMode> selected) {
                      if (selected.isNotEmpty) {
                        Prefs().aiChatDisplayMode = selected.first;
                        setState(() {});
                      }
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // AI panel position configuration (only shown when not in popup mode)
  AbstractSettingsTile aiPanelPositionTile() {
    final l10n = L10n.of(context);
    return CustomSettingsTile(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.settingsAiPanelPosition,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: AnxSegmentedButton<AiPanelPositionEnum>(
                    segments: [
                      SegmentButtonItem(
                        value: AiPanelPositionEnum.bottom,
                        label: l10n.settingsAiPanelPositionBottom,
                        icon: const Icon(Icons.vertical_align_bottom, size: 18),
                      ),
                      SegmentButtonItem(
                        value: AiPanelPositionEnum.right,
                        label: l10n.settingsAiPanelPositionRight,
                        icon: const Icon(Icons.border_right, size: 18),
                      ),
                    ],
                    selected: {Prefs().aiPanelPosition},
                    onSelectionChanged: (Set<AiPanelPositionEnum> selected) {
                      if (selected.isNotEmpty) {
                        Prefs().aiPanelPosition = selected.first;
                        setState(() {});
                      }
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // User prompts management methods
  AbstractSettingsTile userPromptsTile() {
    final userPrompts = ref.watch(userPromptsProvider);
    ref.read(userPromptsProvider.notifier);

    return CustomSettingsTile(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top button and hint
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AnxButton(
                  onPressed: _showAddPromptDialog,
                  child: Text(L10n.of(context).settingsAiUserPromptsAdd),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.info_outline,
                        size: 16, color: Colors.grey),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        L10n.of(context).settingsAiUserPromptsHint,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Prompts list
          if (userPrompts.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Center(
                child: Text(
                  L10n.of(context).settingsAiUserPromptsEmpty,
                  style: TextStyle(color: Colors.grey[600]),
                ),
              ),
            )
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: userPrompts.length,
              itemBuilder: (context, index) {
                final prompt = userPrompts[index];
                final isExpanded = _expandedUserPromptId == prompt.id;

                return _buildUserPromptItem(
                  prompt,
                  isExpanded,
                  index,
                  userPrompts.length,
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildUserPromptItem(
    prompt,
    bool isExpanded,
    int index,
    int totalCount,
  ) {
    final notifier = ref.read(userPromptsProvider.notifier);

    // Initialize controllers
    _userPromptNameControllers.putIfAbsent(
      prompt.id,
      () => TextEditingController(text: prompt.name),
    );
    _userPromptContentControllers.putIfAbsent(
      prompt.id,
      () => TextEditingController(text: prompt.content),
    );

    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeInOut,
      alignment: Alignment.topCenter,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.withAlpha(100)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title row: Switch + Name + Action buttons
            Row(
              children: [
                Switch(
                  value: prompt.enabled,
                  onChanged: (_) {
                    notifier.toggleEnabled(prompt.id);
                  },
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    prompt.name,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),

                // Edit button
                IconButton(
                  icon: Icon(isExpanded ? Icons.expand_less : Icons.edit),
                  onPressed: () {
                    setState(() {
                      _expandedUserPromptId = isExpanded ? null : prompt.id;
                    });
                  },
                  tooltip: L10n.of(context).commonEdit,
                ),

                // Move up button
                IconButton(
                  icon: const Icon(Icons.arrow_upward, size: 20),
                  onPressed: index > 0
                      ? () => notifier.movePrompt(prompt.id, true)
                      : null,
                ),

                // Move down button
                IconButton(
                  icon: const Icon(Icons.arrow_downward, size: 20),
                  onPressed: index < totalCount - 1
                      ? () => notifier.movePrompt(prompt.id, false)
                      : null,
                ),
              ],
            ),

            // Expanded edit area
            if (isExpanded) ...[
              const Divider(height: 16),
              _buildEditForm(prompt),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildEditForm(prompt) {
    final notifier = ref.read(userPromptsProvider.notifier);
    final nameController = _userPromptNameControllers[prompt.id]!;
    final contentController = _userPromptContentControllers[prompt.id]!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Name input
        TextField(
          controller: nameController,
          decoration: InputDecoration(
            labelText: L10n.of(context).settingsAiUserPromptsName,
            border: const OutlineInputBorder(),
          ),
          maxLength: 50,
        ),
        const SizedBox(height: 12),

        // Content input
        TextField(
          controller: contentController,
          decoration: InputDecoration(
            labelText: L10n.of(context).settingsAiUserPromptsContent,
            border: const OutlineInputBorder(),
            alignLabelWithHint: true,
          ),
          maxLines: 8,
          minLines: 5,
          maxLength: 2000,
        ),
        const SizedBox(height: 12),

        // Action buttons
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            // Delete button (uses default L10n text)
            DeleteConfirm(
              delete: () {
                notifier.deletePrompt(prompt.id);
                _userPromptNameControllers.remove(prompt.id)?.dispose();
                _userPromptContentControllers.remove(prompt.id)?.dispose();
                setState(() {
                  _expandedUserPromptId = null;
                });
              },
              useTextButton: true,
            ),

            // Save button
            TextButton(
              onPressed: () {
                final name = nameController.text.trim();
                final content = contentController.text.trim();

                if (name.isEmpty || content.isEmpty) {
                  AnxToast.show(L10n.of(context).commonInputCannotBeEmpty);
                  return;
                }

                final updatedPrompt = prompt.copyWith(
                  name: name,
                  content: content,
                );
                notifier.updatePrompt(updatedPrompt);

                setState(() {
                  _expandedUserPromptId = null;
                });

                AnxToast.show(L10n.of(context).commonSaveSuccess);
              },
              child: Text(L10n.of(context).commonSave),
            ),
          ],
        ),
      ],
    );
  }

  void _showAddPromptDialog() {
    final notifier = ref.read(userPromptsProvider.notifier);
    final nameController = TextEditingController();
    final contentController = TextEditingController();

    SmartDialog.show(
      builder: (context) => AlertDialog(
        title: Text(L10n.of(context).settingsAiUserPromptsAdd),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: InputDecoration(
                  labelText: L10n.of(context).settingsAiUserPromptsName,
                  border: const OutlineInputBorder(),
                ),
                maxLength: 50,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: contentController,
                decoration: InputDecoration(
                  labelText: L10n.of(context).settingsAiUserPromptsContent,
                  border: const OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
                maxLines: 8,
                minLines: 5,
                maxLength: 2000,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              SmartDialog.dismiss();
              nameController.dispose();
              contentController.dispose();
            },
            child: Text(L10n.of(context).commonCancel),
          ),
          TextButton(
            onPressed: () {
              final name = nameController.text.trim();
              final content = contentController.text.trim();

              if (name.isEmpty || content.isEmpty) {
                AnxToast.show(L10n.of(context).commonInputCannotBeEmpty);
                return;
              }

              notifier.addPrompt(name: name, content: content);

              SmartDialog.dismiss();
              nameController.dispose();
              contentController.dispose();

              AnxToast.show(L10n.of(context).commonAddSuccess);
            },
            child: Text(L10n.of(context).commonConfirm),
          ),
        ],
      ),
    );
  }
}

class _AiRpmTile extends StatefulWidget {
  const _AiRpmTile({required this.setState});

  final VoidCallback setState;

  @override
  State<_AiRpmTile> createState() => _AiRpmTileState();
}

class _AiRpmTileState extends State<_AiRpmTile> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    final rpm = Prefs().aiRpm;
    _controller = TextEditingController(text: rpm == 0 ? '' : rpm.toString());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return ListTile(
      title: Text(l10n.settingsAiRpm),
      subtitle: Text(
        l10n.settingsAiRpmTip,
        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
      ),
      trailing: SizedBox(
        width: 80,
        child: TextField(
          controller: _controller,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          textAlign: TextAlign.center,
          decoration: const InputDecoration(
            hintText: '0',
            border: OutlineInputBorder(),
            contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            isDense: true,
          ),
          onChanged: (value) {
            Prefs().aiRpm = int.tryParse(value) ?? 0;
            widget.setState();
          },
        ),
      ),
    );
  }
}

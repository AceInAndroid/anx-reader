import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/enums/lang_list.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/page/settings_page/ai_provider_detail_page.dart';
import 'package:anx_reader/providers/ai_providers.dart';
import 'package:anx_reader/service/translate/index.dart';
import 'package:anx_reader/utils/env_var.dart';
import 'package:anx_reader/utils/toast/common.dart';
import 'package:anx_reader/widgets/common/container/filled_container.dart';
import 'package:anx_reader/widgets/settings/service_config_form.dart';
import 'package:anx_reader/widgets/settings/settings_section.dart';
import 'package:anx_reader/widgets/settings/settings_tile.dart';
import 'package:anx_reader/widgets/settings/settings_title.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';

class TranslateSetting extends ConsumerStatefulWidget {
  const TranslateSetting({super.key});

  @override
  ConsumerState<TranslateSetting> createState() => _TranslateSettingState();
}

class _TranslateSettingState extends ConsumerState<TranslateSetting> {
  Widget autoTranslateSelection() {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      trailing: Switch(
        value: Prefs().autoTranslateSelection,
        onChanged: (bool value) => setState(() {
          Prefs().autoTranslateSelection = value;
        }),
      ),
      title: Text(L10n.of(context).readingPageAutoTranslateSelection),
    );
  }

  @override
  Widget build(BuildContext context) {
    return settingsSections(
      sections: [
        SettingsSection(
          title: Text(L10n.of(context).underlineTranslation),
          tiles: [
            CustomSettingsTile(
              child: FilledContainer(
                margin: const EdgeInsets.all(2.0),
                color: Theme.of(context).cardColor,
                radius: 28,
                child: Padding(
                  padding: EdgeInsets.all(8.0),
                  child: Column(
                    children: [
                      TranslationConfig(setState: () => setState(() {})),
                      Row(
                        children: [
                          Icon(Icons.info_outline, color: Colors.blue),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              L10n.of(context).underlineTranslationTip,
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
              ),
            ),
            CustomSettingsTile(
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: autoTranslateSelection(),
              ),
            ),
          ],
        ),
        SettingsSection(
          title: Text(L10n.of(context).fullTextTranslation),
          tiles: [
            CustomSettingsTile(
              child: FilledContainer(
                margin: const EdgeInsets.all(2.0),
                color: Theme.of(context).cardColor,
                radius: 28,
                child: Padding(
                  padding: EdgeInsets.all(8.0),
                  child: Column(
                    children: [
                      FullTextTranslationConfig(
                        setState: () => setState(() {}),
                      ),
                      const Divider(),
                      // Translation margin setting
                      Row(
                        children: [
                          Icon(Icons.panorama, size: 20),
                          const SizedBox(width: 8),
                          Text(
                            L10n.of(context).translationMargin,
                            style: const TextStyle(fontSize: 14),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<int>(
                        initialValue: Prefs().translationMargin,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                        ),
                        items: [
                          DropdownMenuItem(
                            value: 800,
                            child: Text(
                              L10n.of(context).translationMargin1Page,
                            ),
                          ),
                          DropdownMenuItem(
                            value: 1600,
                            child: Text(
                              L10n.of(context).translationMargin2Pages,
                            ),
                          ),
                          DropdownMenuItem(
                            value: 2400,
                            child: Text(
                              L10n.of(context).translationMargin3Pages,
                            ),
                          ),
                          DropdownMenuItem(
                            value: 3200,
                            child: Text(
                              L10n.of(context).translationMargin5Pages,
                            ),
                          ),
                        ],
                        onChanged: (value) {
                          if (value != null) {
                            Prefs().translationMargin = value;
                          }
                        },
                      ),
                      const SizedBox(height: 8),
                      Text(
                        L10n.of(context).translationMarginTip,
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                      const Divider(),
                      Row(
                        children: [
                          Icon(Icons.info_outline, color: Colors.orange),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              L10n.of(context).fullTextTranslationTip,
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
              ),
            ),
          ],
        ),
        if (EnvVar.enableAIFeature)
          SettingsSection(
            title: Text(L10n.of(context).aiTranslationProvider),
            tiles: [
              CustomSettingsTile(
                child: _AiTranslationProviderSelector(
                  enabled: Prefs().translateService == TranslateService.ai ||
                      Prefs().fullTextTranslateService == TranslateService.ai,
                  setState: () => setState(() {}),
                ),
              ),
            ],
          ),
        SettingsSection(
          title: Text(L10n.of(context).translationServiceConfiguration),
          tiles: [
            for (var service in TranslateService.activeValues)
              CustomSettingsTile(child: TranslateSettingItem(service: service)),
          ],
        ),
      ],
    );
  }
}

class _AiTranslationProviderSelector extends ConsumerWidget {
  const _AiTranslationProviderSelector({
    required this.enabled,
    required this.setState,
  });

  final bool enabled;
  final VoidCallback setState;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    final providers = ref.watch(aiProvidersProvider);
    final runnableProviders = providers.where(
      (provider) => provider.enabled && provider.hasValidKey,
    );
    final selectedProvider =
        ref.watch(aiProvidersProvider.notifier).getRunnableSelectedProvider();
    final translationId = Prefs().translationAiProvider;
    final validTranslationId =
        runnableProviders.any((provider) => provider.id == translationId)
            ? translationId
            : null;
    final effectiveName = validTranslationId == null
        ? selectedProvider?.title
        : providers
            .firstWhere((provider) => provider.id == validTranslationId)
            .title;

    return FilledContainer(
      margin: const EdgeInsets.all(2.0),
      color: Theme.of(context).cardColor,
      radius: 28,
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.translate_rounded,
                  size: 20,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  l10n.aiTranslationProvider,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String?>(
              initialValue: validTranslationId,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
              ),
              items: [
                DropdownMenuItem<String?>(
                  value: null,
                  child: Text(l10n.aiTranslationProviderDefault),
                ),
                for (final provider in runnableProviders)
                  DropdownMenuItem<String?>(
                    value: provider.id,
                    child: Text(provider.title),
                  ),
              ],
              onChanged: enabled
                  ? (value) {
                      Prefs().translationAiProvider = value;
                      setState();
                    }
                  : null,
            ),
            const SizedBox(height: 8),
            Text(
              enabled
                  ? (effectiveName == null
                      ? l10n.aiTranslationProviderTip
                      : l10n.aiTranslationProviderUsing(effectiveName))
                  : l10n.aiTranslationProviderDisabledTip,
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) =>
                          const AiProviderDetailPage(providerId: null),
                    ),
                  ).then((_) {
                    ref.read(aiProvidersProvider.notifier).refresh();
                    setState();
                  });
                },
                icon: const Icon(Icons.add),
                label: Text(l10n.settingsAiProvidersAdd),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class TranslationConfig extends StatelessWidget {
  const TranslationConfig({super.key, required this.setState});

  final VoidCallback setState;

  static const currentServiceTextStyle = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.bold,
  );

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            TextButton(
              onPressed: () {
                showModalBottomSheet(
                  context: context,
                  builder: (context) => const TranslateServicePicker(),
                ).then((value) {
                  setState();
                });
              },
              child: Text(
                Prefs().translateService.getLabel(context),
                style: currentServiceTextStyle,
              ),
            ),
            Text(L10n.of(context).settingsTranslateCurrentService),
          ],
        ),
        const Divider(),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: TextButton(
                onPressed: () {
                  showModalBottomSheet(
                    context: context,
                    builder: (context) => const TranslateLangPicker(
                      isFrom: true,
                      isWebView: false,
                    ),
                  ).then((value) {
                    setState();
                  });
                },
                child: Text(Prefs().translateFrom.getNative(context)),
              ),
            ),
            const Icon(Icons.arrow_forward_ios),
            Expanded(
              child: TextButton(
                onPressed: () {
                  showModalBottomSheet(
                    context: context,
                    builder: (context) => const TranslateLangPicker(
                      isFrom: false,
                      isWebView: false,
                    ),
                  ).then((value) {
                    setState();
                  });
                },
                child: Text(
                  Prefs().translateTo.getNative(context),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class FullTextTranslationConfig extends StatelessWidget {
  const FullTextTranslationConfig({super.key, required this.setState});

  final VoidCallback setState;

  static const currentServiceTextStyle = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.bold,
  );

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            TextButton(
              onPressed: () {
                showModalBottomSheet(
                  context: context,
                  builder: (context) => const FullTextTranslateServicePicker(),
                ).then((value) {
                  setState();
                });
              },
              child: Text(
                Prefs().fullTextTranslateService.getLabel(context),
                style: currentServiceTextStyle,
              ),
            ),
            Text(L10n.of(context).settingsTranslateCurrentService),
          ],
        ),
        const Divider(),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: TextButton(
                onPressed: () {
                  showModalBottomSheet(
                    context: context,
                    builder: (context) => const TranslateLangPicker(
                      isFrom: true,
                      isWebView: true,
                    ),
                  ).then((value) {
                    setState();
                  });
                },
                child: Text(Prefs().fullTextTranslateFrom.getNative(context)),
              ),
            ),
            const Icon(Icons.arrow_forward_ios),
            Expanded(
              child: TextButton(
                onPressed: () {
                  showModalBottomSheet(
                    context: context,
                    builder: (context) => const TranslateLangPicker(
                      isFrom: false,
                      isWebView: true,
                    ),
                  ).then((value) {
                    setState();
                  });
                },
                child: Text(
                  Prefs().fullTextTranslateTo.getNative(context),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class TranslateServicePicker extends StatelessWidget {
  const TranslateServicePicker({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: TranslateService.activeValues.length,
      itemBuilder: (context, index) {
        final service = TranslateService.activeValues.elementAt(index);
        return ListTile(
          title: Text(service.getLabel(context)),
          onTap: () {
            Prefs().translateService = service;
            Navigator.pop(context);
          },
        );
      },
    );
  }
}

class FullTextTranslateServicePicker extends StatelessWidget {
  const FullTextTranslateServicePicker({super.key});

  @override
  Widget build(BuildContext context) {
    final services =
        TranslateService.activeValues.where((s) => !s.isWebView).toList();

    return ListView.builder(
      itemCount: services.length,
      itemBuilder: (context, index) => ListTile(
        title: Text(services[index].getLabel(context)),
        onTap: () {
          Prefs().fullTextTranslateService = services[index];
          Navigator.pop(context);
        },
      ),
    );
  }
}

class TranslateLangPicker extends StatelessWidget {
  const TranslateLangPicker({
    super.key,
    required this.isFrom,
    this.isWebView = false,
  });

  final bool isFrom;
  final bool isWebView;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: LangListEnum.values.length,
      itemBuilder: (context, index) => ListTile(
        title: Text(LangListEnum.values[index].getNative(context)),
        subtitle: Text(
          LangListEnum.values[index].name[0].toUpperCase() +
              LangListEnum.values[index].name.substring(1),
        ),
        onTap: () {
          if (isWebView) {
            if (isFrom) {
              Prefs().fullTextTranslateFrom = LangListEnum.values[index];
            } else {
              Prefs().fullTextTranslateTo = LangListEnum.values[index];
            }
          } else {
            if (isFrom) {
              Prefs().translateFrom = LangListEnum.values[index];
            } else {
              Prefs().translateTo = LangListEnum.values[index];
            }
          }
          Navigator.pop(context);
        },
      ),
    );
  }
}

class TranslateSettingItem extends StatefulWidget {
  const TranslateSettingItem({super.key, required this.service});

  final TranslateService service;

  @override
  State<TranslateSettingItem> createState() => _TranslateSettingItemState();
}

class _TranslateSettingItemState extends State<TranslateSettingItem> {
  bool isExpanded = false;
  static const testText = "Hello, world!";
  static const languageTextStyle = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.bold,
  );

  Map<String, dynamic> _currentConfig = {};

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  void _loadConfig() {
    _currentConfig = getTranslateServiceConfig(widget.service);
    setState(() {});
  }

  Widget languageText(String text) {
    return Expanded(
      child: Text(text, style: languageTextStyle, textAlign: TextAlign.center),
    );
  }

  void _saveConfig() {
    try {
      saveTranslateServiceConfig(widget.service, _currentConfig);
      AnxToast.show(L10n.of(context).commonSaved);
    } catch (e) {
      AnxToast.show(L10n.of(context).commonFailed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final configItems = getTranslateServiceConfigItems(context, widget.service);

    return Card(
      margin: const EdgeInsets.all(10),
      color: isExpanded
          ? Theme.of(context).colorScheme.secondaryContainer
          : Colors.transparent,
      shadowColor: Colors.transparent,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.translate_outlined),
            title: Text(widget.service.getLabel(context)),
            onTap: () {
              setState(() {
                isExpanded = !isExpanded;
              });
            },
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.bounceInOut,
            alignment: Alignment.topCenter,
            child: isExpanded
                ? Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ServiceConfigForm(
                          configItems: configItems,
                          initialConfig: _currentConfig,
                          onConfigChanged: (newConfig) {
                            _currentConfig = newConfig;
                          },
                        ),
                        const Divider(),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton(
                              onPressed: () {
                                _saveConfig();
                                SmartDialog.show(
                                  useSystem: true,
                                  animationType:
                                      SmartAnimationType.centerFade_otherSlide,
                                  builder: (context) => AlertDialog(
                                    title: const Center(
                                      child: Icon(Icons.check_circle),
                                    ),
                                    content: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            languageText(
                                              Prefs().translateFrom.getNative(
                                                    context,
                                                  ),
                                            ),
                                            const Icon(Icons.arrow_forward_ios),
                                            languageText(
                                              Prefs().translateTo.getNative(
                                                    context,
                                                  ),
                                            ),
                                          ],
                                        ),
                                        const Divider(),
                                        const Text(testText),
                                        const Icon(Icons.arrow_downward),
                                        translateText(
                                          testText,
                                          service: widget.service,
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                              child: Text(L10n.of(context).commonTest),
                            ),
                            TextButton(
                              onPressed: () {
                                _saveConfig();
                                setState(() {
                                  isExpanded = !isExpanded;
                                });
                              },
                              child: Text(L10n.of(context).commonSave),
                            ),
                          ],
                        ),
                      ],
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/models/ai_provider.dart';
import 'package:anx_reader/page/settings_page/ai_provider_detail_page.dart';
import 'package:anx_reader/providers/ai_providers.dart';
import 'package:anx_reader/widgets/common/container/filled_container.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';

enum AiProviderListMode { general, translation }

class AiProviderListPage extends ConsumerWidget {
  const AiProviderListPage({
    super.key,
    this.mode = AiProviderListMode.general,
  });

  final AiProviderListMode mode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    final providers = ref.watch(aiProvidersProvider);
    final notifier = ref.read(aiProvidersProvider.notifier);
    final selectedId = mode == AiProviderListMode.general
        ? notifier.getSelectedProvider()?.id
        : notifier.getDedicatedTranslationProvider()?.id;
    final generalProvider = notifier.getRunnableSelectedProvider();

    return Scaffold(
      appBar: AppBar(
        title: Text(
          mode == AiProviderListMode.translation
              ? l10n.settingsAiTranslationProviders
              : l10n.settingsAiGeneralProviders,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => _addProvider(context),
            tooltip: l10n.settingsAiProvidersAdd,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(top: 8, bottom: 24),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
            child: Text(
              mode == AiProviderListMode.translation
                  ? l10n.settingsAiTranslationProvidersTip
                  : l10n.settingsAiGeneralProvidersTip,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
          if (mode == AiProviderListMode.translation)
            _FollowGeneralProviderTile(
              selected: selectedId == null,
              generalProvider: generalProvider,
              onSelected: () => notifier.setTranslationProvider(null),
            ),
          for (final provider in providers)
            _ProviderTile(
              provider: provider,
              selected: provider.id == selectedId,
              selectedLabel: mode == AiProviderListMode.general
                  ? l10n.settingsAiProviderDefault
                  : l10n.aiTranslationProviderSelected,
              runnable: notifier.isRunnableProvider(provider),
              onSelected: () {
                if (mode == AiProviderListMode.translation) {
                  notifier.setTranslationProvider(provider.id);
                } else {
                  notifier.setSelectedProvider(provider.id);
                }
              },
              onEnabledChanged: (value) {
                notifier.toggleProvider(provider.id, value);
              },
              onEdit: () => _editProvider(context, provider.id),
              onDelete: provider.isBuiltin
                  ? null
                  : () => _deleteProvider(context, ref, provider),
            ),
        ],
      ),
    );
  }

  Future<void> _addProvider(BuildContext context) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const AiProviderDetailPage(providerId: null),
      ),
    );
  }

  Future<void> _editProvider(BuildContext context, String providerId) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AiProviderDetailPage(providerId: providerId),
      ),
    );
  }

  Future<void> _deleteProvider(
    BuildContext context,
    WidgetRef ref,
    AiProvider provider,
  ) async {
    final l10n = L10n.of(context);
    var confirmed = false;

    await SmartDialog.show(
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.commonConfirm),
        content: Text(l10n.settingsAiProviderDeleteConfirm),
        actions: [
          TextButton(
            onPressed: SmartDialog.dismiss,
            child: Text(l10n.commonCancel),
          ),
          TextButton(
            onPressed: () {
              confirmed = true;
              SmartDialog.dismiss();
            },
            child: Text(l10n.commonConfirm),
          ),
        ],
      ),
    );

    if (confirmed && context.mounted) {
      ref.read(aiProvidersProvider.notifier).deleteProvider(provider.id);
    }
  }
}

class _FollowGeneralProviderTile extends StatelessWidget {
  const _FollowGeneralProviderTile({
    required this.selected,
    required this.generalProvider,
    required this.onSelected,
  });

  final bool selected;
  final AiProvider? generalProvider;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final model = generalProvider?.model.trim();

    return FilledContainer(
      radius: 20,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: ListTile(
        minVerticalPadding: 12,
        leading: _SelectionButton(
          selected: selected,
          enabled: true,
          onPressed: onSelected,
        ),
        title: Text(l10n.aiTranslationProviderDefault),
        subtitle: Text(
          generalProvider == null
              ? l10n.aiProviderNoRunnable
              : [
                  generalProvider!.title,
                  if (model != null && model.isNotEmpty) model,
                ].join(' · '),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        onTap: onSelected,
      ),
    );
  }
}

class _ProviderTile extends StatelessWidget {
  const _ProviderTile({
    required this.provider,
    required this.selected,
    required this.selectedLabel,
    required this.runnable,
    required this.onSelected,
    required this.onEnabledChanged,
    required this.onEdit,
    required this.onDelete,
  });

  final AiProvider provider;
  final bool selected;
  final String selectedLabel;
  final bool runnable;
  final VoidCallback onSelected;
  final ValueChanged<bool> onEnabledChanged;
  final VoidCallback onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final theme = Theme.of(context);
    final model = provider.model.trim();

    return FilledContainer(
      radius: 20,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: InkWell(
        onTap: onEdit,
        onLongPress: onDelete,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 12, 8),
          child: Row(
            children: [
              _SelectionButton(
                selected: selected,
                enabled: runnable,
                onPressed: onSelected,
              ),
              _ProviderLogo(provider: provider),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            provider.title,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight:
                                  selected ? FontWeight.w700 : FontWeight.w500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (selected) ...[
                          const SizedBox(width: 8),
                          Text(
                            selectedLabel,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      model.isEmpty ? provider.url : model,
                      style: theme.textTheme.bodySmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (!runnable)
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Text(
                          !provider.enabled
                              ? l10n.settingsAiProviderDisabled
                              : !provider.hasValidKey
                                  ? l10n.settingsAiProviderNoValidKeys
                                  : l10n.configurationInformationIsIncomplete,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.error,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (onDelete != null)
                SizedBox.square(
                  dimension: 48,
                  child: IconButton(
                    tooltip: l10n.commonDelete,
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete_outline),
                  ),
                ),
              Switch(
                value: provider.enabled,
                onChanged: onEnabledChanged,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SelectionButton extends StatelessWidget {
  const _SelectionButton({
    required this.selected,
    required this.enabled,
    required this.onPressed,
  });

  final bool selected;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 48,
      child: IconButton(
        onPressed: enabled ? onPressed : null,
        icon: Icon(
          selected ? Icons.check_circle : Icons.radio_button_unchecked,
        ),
      ),
    );
  }
}

class _ProviderLogo extends StatelessWidget {
  const _ProviderLogo({required this.provider});

  final AiProvider provider;

  @override
  Widget build(BuildContext context) {
    if (provider.logoAsset != null) {
      return Image.asset(
        provider.logoAsset!,
        width: 32,
        height: 32,
        errorBuilder: (context, error, stackTrace) => _fallbackAvatar(),
      );
    }
    return _fallbackAvatar();
  }

  Widget _fallbackAvatar() {
    return CircleAvatar(
      radius: 16,
      child: Text(
        provider.title.isEmpty ? '?' : provider.title[0].toUpperCase(),
      ),
    );
  }
}

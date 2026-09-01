import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/page/settings_page/developer/vibration_test_page.dart';
import 'package:anx_reader/page/settings_page/developer/reading_experience_diagnostics_page.dart';
import 'package:anx_reader/page/settings_page/subpage/log_page.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

class DeveloperOptionsPage extends StatelessWidget {
  const DeveloperOptionsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(L10n.of(context).developerOptions)),
      body: AnimatedBuilder(
        animation: Prefs(),
        builder: (context, _) {
          final enabled = Prefs().developerOptionsEnabled;
          return ListView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
              SwitchListTile(
                title: Text(L10n.of(context).developerOptionsEnabled),
                subtitle: Text(L10n.of(context).developerOptionsEnabledTip),
                value: enabled,
                onChanged: (value) {
                  Prefs().developerOptionsEnabled = value;
                  if (!value && Navigator.of(context).canPop()) {
                    Navigator.of(context).pop();
                  }
                },
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.article_outlined),
                title: Text(L10n.of(context).developerLogViewer),
                subtitle: Text(L10n.of(context).developerLogViewerTip),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  CupertinoPageRoute(builder: (context) => const LogPage()),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.monitor_heart_outlined),
                title: const Text('阅读体验诊断'),
                subtitle: const Text('查看连续阅读、同步合并、AI 任务与耗电趋势'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  CupertinoPageRoute(
                    builder: (context) =>
                        const ReadingExperienceDiagnosticsPage(),
                  ),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.vibration_outlined),
                title: const Text('Vibration Test'),
                subtitle: const Text(
                  'Inspect device support and trigger presets',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.of(context).push(
                    CupertinoPageRoute(
                      builder: (context) => const VibrationTestPage(),
                    ),
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }
}

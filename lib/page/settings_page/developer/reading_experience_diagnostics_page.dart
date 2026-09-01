import 'package:anx_reader/service/reading_experience_diagnostics.dart';
import 'package:flutter/material.dart';

class ReadingExperienceDiagnosticsPage extends StatefulWidget {
  const ReadingExperienceDiagnosticsPage({super.key});

  @override
  State<ReadingExperienceDiagnosticsPage> createState() =>
      _ReadingExperienceDiagnosticsPageState();
}

class _ReadingExperienceDiagnosticsPageState
    extends State<ReadingExperienceDiagnosticsPage> {
  late Future<ReadingExperienceDiagnosticsSummary> _summary;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _summary = readingExperienceDiagnostics.summary();
  }

  Future<void> _clear() async {
    await readingExperienceDiagnostics.clear();
    if (!mounted) return;
    setState(_reload);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('阅读体验诊断'),
        actions: [
          IconButton(
            tooltip: '清空诊断',
            onPressed: _clear,
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      body: FutureBuilder<ReadingExperienceDiagnosticsSummary>(
        future: _summary,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final summary = snapshot.requireData;
          if (summary.sessions.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  '还没有阅读会话诊断。数据只保存在本机，不包含正文、选区、密钥或模型输出。',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: [
              Text(
                '最近 30 天 / 最多 100 次会话',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _Metric(label: '会话', value: '${summary.sessionCount}'),
                  _Metric(
                    label: '阅读时长',
                    value: _duration(summary.readingSeconds),
                  ),
                  _Metric(label: '累计耗电', value: '${summary.batteryDelta}%'),
                  _Metric(
                    label: '自动同步请求',
                    value: '${summary.automaticSyncRequests}',
                  ),
                  _Metric(label: '实际同步', value: '${summary.syncExecutions}'),
                  _Metric(
                    label: '合并 / 延后',
                    value: '${summary.syncMerged} / ${summary.syncDeferred}',
                  ),
                  _Metric(
                    label: '模型请求 / 重试',
                    value: '${summary.modelRequests} / ${summary.modelRetries}',
                  ),
                  _Metric(
                    label: '证据拒绝',
                    value: '${summary.validationRejections}',
                  ),
                  _Metric(
                    label: '行动显示 / 执行',
                    value:
                        '${summary.nextActionShown} / ${summary.nextActionExecuted}',
                  ),
                  _Metric(
                    label: '来源跳转 / 返回',
                    value: '${summary.sourceJumps} / ${summary.sourceReturns}',
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Text('最近会话', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              for (final session in summary.sessions.reversed.take(20))
                Card.outlined(
                  child: ListTile(
                    title: Text(
                      '${_date(session.startedAt)} · ${_duration(session.durationSeconds)}',
                    ),
                    subtitle: Text(
                      '同步 ${session.syncExecutions}/${session.automaticSyncRequests}，'
                      '模型 ${session.modelRequests}，任务 ${session.taskExecutions}，'
                      '行动 ${session.nextActionExecuted}/${session.nextActionShown}',
                    ),
                    trailing: Text(
                      session.batteryDelta == null
                          ? '电量 —'
                          : '电量 -${session.batteryDelta!.clamp(0, 100)}%',
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              const Text(
                '这些数据不会参与偏好备份、WebDAV、CloudBase 或遥测上传。电量只在阅读会话开始和结束时各读取一次。',
              ),
            ],
          );
        },
      ),
    );
  }

  static String _duration(int seconds) {
    final minutes = seconds ~/ 60;
    if (minutes < 60) return '$minutes 分钟';
    return '${minutes ~/ 60}小时${minutes % 60}分';
  }

  static String _date(int milliseconds) {
    final date = DateTime.fromMillisecondsSinceEpoch(milliseconds).toLocal();
    return '${date.month}月${date.day}日 ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minWidth: 132),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value, style: Theme.of(context).textTheme.titleMedium),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    ),
  );
}

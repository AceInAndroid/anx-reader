import 'package:anx_reader/models/book.dart';
import 'package:anx_reader/models/reading_agent.dart';
import 'package:anx_reader/service/ai/fiction_story_atlas_service.dart';
import 'package:flutter/material.dart';

class FictionStoryTimelinePage extends StatefulWidget {
  const FictionStoryTimelinePage({
    super.key,
    required this.book,
    this.onOpenLocation,
    this.onRequestOrganize,
    this.initialAtlas,
  });

  final Book book;
  final Future<void> Function(String cfi)? onOpenLocation;
  final VoidCallback? onRequestOrganize;
  final FictionStoryAtlas? initialAtlas;

  @override
  State<FictionStoryTimelinePage> createState() =>
      _FictionStoryTimelinePageState();
}

class _FictionStoryTimelinePageState extends State<FictionStoryTimelinePage> {
  late Future<FictionStoryAtlas> _future;
  FictionStoryAtlas? _atlas;

  @override
  void initState() {
    super.initState();
    _future = widget.initialAtlas != null
        ? Future.value(widget.initialAtlas)
        : fictionStoryAtlasService.load(
            bookId: widget.book.id,
            visibleAtProgress: widget.book.readingPercentage,
          );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('故事事件时间线')),
        body: FutureBuilder<FictionStoryAtlas>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(child: Text('无法读取故事档案：${snapshot.error}'));
            }
            final atlas = snapshot.requireData;
            _atlas = atlas;
            if (atlas.timeline.isEmpty) return _emptyState(atlas);
            return LayoutBuilder(builder: (context, constraints) {
              final header = _boundaryBanner(atlas);
              if (constraints.maxWidth >= 840) {
                return Column(children: [
                  header,
                  Expanded(child: _horizontalTimeline(atlas.timeline)),
                ]);
              }
              return Column(children: [
                header,
                Expanded(child: _verticalTimeline(atlas.timeline)),
              ]);
            });
          },
        ),
      );

  Widget _emptyState(FictionStoryAtlas atlas) => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.timeline,
                  size: 52, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 14),
              Text('还没有故事事件', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(
                '时间线按正文中遇到事件的顺序展示，不会猜测绝对日期，也不会读取后文。',
                textAlign: TextAlign.center,
              ),
              if (widget.onRequestOrganize != null) ...[
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: widget.onRequestOrganize,
                  icon: const Icon(Icons.auto_awesome_outlined),
                  label: const Text('整理已读部分'),
                ),
              ],
            ],
          ),
        ),
      );

  Widget _boundaryBanner(FictionStoryAtlas atlas) => Material(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(children: [
            const Icon(Icons.shield_outlined, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '正文顺序 · 安全边界 ${(atlas.visibleProgress * 100).round()}%',
              ),
            ),
          ]),
        ),
      );

  Widget _verticalTimeline(List<FictionTimelineEvent> events) =>
      ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 40),
        itemCount: events.length,
        itemBuilder: (context, index) {
          final event = events[index];
          return IntrinsicHeight(
            child:
                Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              SizedBox(
                width: 42,
                child: Column(children: [
                  _TimelineDot(event: event),
                  if (index != events.length - 1)
                    Expanded(
                      child: Container(
                        width: 2,
                        color: Theme.of(context).colorScheme.outlineVariant,
                      ),
                    ),
                ]),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: _eventCard(event),
                ),
              ),
            ]),
          );
        },
      );

  Widget _horizontalTimeline(List<FictionTimelineEvent> events) =>
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(28, 32, 28, 32),
        child: SizedBox(
          width: events.length * 290.0,
          child: Stack(children: [
            Positioned(
              left: 40,
              right: 40,
              top: 250,
              child: Container(
                height: 3,
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var index = 0; index < events.length; index++)
                  SizedBox(
                    width: 290,
                    child: Column(children: [
                      if (index.isOdd) const SizedBox(height: 266),
                      if (index.isEven) _eventCard(events[index]),
                      if (index.isEven) const SizedBox(height: 12),
                      _TimelineDot(event: events[index]),
                      if (index.isOdd) const SizedBox(height: 12),
                      if (index.isOdd) _eventCard(events[index]),
                    ]),
                  ),
              ],
            ),
          ]),
        ),
      );

  Widget _eventCard(FictionTimelineEvent event) {
    final color = _eventColor(context, event);
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 6),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _showEvent(event),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                width: 5,
                height: 28,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(event.title,
                    style: Theme.of(context).textTheme.titleMedium),
              ),
            ]),
            if (event.summary.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(event.summary, maxLines: 3, overflow: TextOverflow.ellipsis),
            ],
            const SizedBox(height: 10),
            Wrap(spacing: 6, runSpacing: 6, children: [
              _tag(event.storyTimeLabel ?? '时间未明'),
              _tag('${(event.source.sourceProgress * 100).round()}%'),
              _tag(event.source.epistemicStatus ==
                      ReadingArtifactEpistemicStatus.agentInference
                  ? 'AI 推测'
                  : '文本事实'),
            ]),
          ]),
        ),
      ),
    );
  }

  Widget _tag(String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(text, style: Theme.of(context).textTheme.labelSmall),
      );

  Future<void> _showEvent(FictionTimelineEvent event) async {
    final source = event.source;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: ListView(shrinkWrap: true, children: [
            Text(event.title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(event.summary.isEmpty ? '当前位置没有更多摘要。' : event.summary),
            if (event.participants.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('参与人物：${event.participants.join('、')}'),
            ],
            const SizedBox(height: 12),
            Text('故事内时间：${event.storyTimeLabel ?? '时间未明'}'),
            Text(
                '来源：${source.chapterTitle ?? '未知章节'} · ${(source.sourceProgress * 100).round()}%'),
            if (source.sourceTextSnapshot.isNotEmpty) ...[
              const Divider(height: 28),
              Text('原文快照', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 6),
              Text(source.sourceTextSnapshot),
            ],
            ..._relatedEvents(event),
            const SizedBox(height: 16),
            FilledButton.tonalIcon(
              onPressed: _sourceTarget(source).isEmpty
                  ? null
                  : () async {
                      Navigator.pop(sheetContext);
                      await widget.onOpenLocation?.call(_sourceTarget(source));
                    },
              icon: const Icon(Icons.short_text),
              label: const Text('返回来源'),
            ),
          ]),
        ),
      ),
    );
  }

  List<Widget> _relatedEvents(FictionTimelineEvent event) {
    final events = _atlas?.timeline;
    if (events == null || events.length < 2) return const [];
    final index = events.indexWhere((item) => item.id == event.id);
    if (index < 0) return const [];
    final previous = index > 0 ? events[index - 1] : null;
    final next = index < events.length - 1 ? events[index + 1] : null;
    if (previous == null && next == null) return const [];
    return [
      const Divider(height: 28),
      Text('前后相关事件', style: Theme.of(context).textTheme.titleMedium),
      if (previous != null)
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.arrow_back),
          title: Text(previous.title),
          subtitle: const Text('上一个正文事件'),
        ),
      if (next != null)
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.arrow_forward),
          title: Text(next.title),
          subtitle: const Text('下一个正文事件'),
        ),
    ];
  }

  String _sourceTarget(ReadingArtifact source) =>
      source.sourceStartCfi ??
      source.discoveredAtCfi ??
      source.chapterHref ??
      '';
}

class _TimelineDot extends StatelessWidget {
  const _TimelineDot({required this.event});
  final FictionTimelineEvent event;

  @override
  Widget build(BuildContext context) {
    final color = _eventColor(context, event);
    return Semantics(
      label: '${event.title}时间线节点',
      child: Container(
        width: event.isMajor ? 22 : 16,
        height: event.isMajor ? 22 : 16,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
          border: Border.all(
              color: Theme.of(context).colorScheme.surface, width: 3),
          boxShadow: [BoxShadow(color: color.withAlpha(70), blurRadius: 8)],
        ),
      ),
    );
  }
}

Color _eventColor(BuildContext context, FictionTimelineEvent event) {
  final scheme = Theme.of(context).colorScheme;
  if (event.isMystery) return scheme.tertiary;
  if (event.isClue) return scheme.secondary;
  if (event.isMajor) return scheme.error;
  return scheme.primary;
}

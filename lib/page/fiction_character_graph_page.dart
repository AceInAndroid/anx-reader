import 'package:anx_reader/models/book.dart';
import 'package:anx_reader/models/reading_agent.dart';
import 'package:anx_reader/service/ai/fiction_story_atlas_service.dart';
import 'package:flutter/material.dart';
import 'package:graphview/GraphView.dart';

class FictionCharacterGraphPage extends StatefulWidget {
  const FictionCharacterGraphPage({
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
  State<FictionCharacterGraphPage> createState() =>
      _FictionCharacterGraphPageState();
}

class _FictionCharacterGraphPageState extends State<FictionCharacterGraphPage> {
  late Future<FictionStoryAtlas> _future;
  FictionCharacterNode? _selected;
  FictionStoryAtlas? _atlas;
  final _controller = GraphViewController();

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

  void _select(FictionCharacterNode node, {bool sheet = true}) {
    setState(() => _selected = node);
    if (sheet && MediaQuery.sizeOf(context).width < 840) {
      showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (_) => SafeArea(child: _details(node)),
      );
    }
  }

  Future<void> _openSource(ReadingArtifactSource source) async {
    final cfi = source.cfi;
    if (cfi.isEmpty) return;
    await widget.onOpenLocation?.call(cfi);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('人物关系图')),
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
            if (atlas.characters.isEmpty || atlas.relationships.isEmpty) {
              return _emptyState(atlas);
            }
            return LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 840;
                final graph = _graph(atlas, constraints.maxWidth);
                if (!wide) return graph;
                return Row(
                  children: [
                    Expanded(child: graph),
                    SizedBox(width: 320, child: _details(_selected)),
                  ],
                );
              },
            );
          },
        ),
      );

  Widget _emptyState(FictionStoryAtlas atlas) => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.hub_outlined,
                  size: 52, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 14),
              Text(
                atlas.characters.isEmpty ? '还没有人物档案' : '还没有人物关系',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text('这里只显示当前阅读进度以内的内容，不会自动读取后文。', textAlign: TextAlign.center),
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

  Widget _graph(FictionStoryAtlas atlas, double width) {
    final graph = Graph();
    final nodes = <String, Node>{};
    for (final character in atlas.characters) {
      nodes[character.id] = Node.Id(character.id);
      graph.addNode(nodes[character.id]!);
    }
    for (var index = 0; index < atlas.relationships.length; index++) {
      final relationship = atlas.relationships[index];
      final relationId = '@relation:$index';
      final relationNode = Node.Id(relationId);
      nodes[relationId] = relationNode;
      graph.addNode(relationNode);
      final paint = Paint()
        ..color = relationship.isChanged
            ? Theme.of(context).colorScheme.outline
            : Theme.of(context).colorScheme.primary
        ..strokeWidth = relationship.isChanged ? 1.2 : 2.4;
      graph.addEdge(
        nodes[relationship.from]!,
        relationNode,
        paint: paint,
      );
      graph.addEdge(relationNode, nodes[relationship.to]!, paint: paint);
    }
    final algorithm = FruchtermanReingoldAlgorithm(
      FruchtermanReingoldConfiguration(
        iterations: 300,
        repulsionRate: 0.8,
        attractionRate: 0.15,
      ),
    );
    return Column(
      children: [
        _boundaryBanner(atlas),
        Expanded(
          // GraphView.builder already owns an InteractiveViewer. Wrapping it
          // in a second viewer makes the graph's render and hit-test
          // coordinate spaces diverge on slow/partial-refresh displays (most
          // visible on E-INK: edges remain while nodes and taps disappear).
          child: SizedBox(
            width: width < 840 ? width * 1.4 : width,
            height: 620,
            child: GraphView.builder(
              graph: graph,
              algorithm: algorithm,
              controller: _controller,
              autoZoomToFit: true,
              // Keep positions and hit targets stable, especially while an
              // E-INK display performs a partial refresh.
              animated: false,
              paint: Paint()
                ..color = Theme.of(context).colorScheme.outline
                ..strokeWidth = 1.4,
              builder: (node) {
                final id = node.key?.value?.toString() ?? '';
                if (id.startsWith('@relation:')) {
                  final index = int.parse(id.split(':').last);
                  final relationship = atlas.relationships[index];
                  return ActionChip(
                    onPressed: () => _showRelationship(relationship),
                    avatar: Icon(
                      relationship.isChanged ? Icons.history : Icons.swap_horiz,
                      size: 16,
                    ),
                    label: Text(relationship.relation),
                  );
                }
                final character = atlas.characters.firstWhere(
                  (item) => item.id == id,
                  orElse: () => atlas.characters.first,
                );
                return Semantics(
                  button: true,
                  label: '查看${character.name}的人物详情',
                  child: InkWell(
                    key: ValueKey('fiction-character-${character.id}'),
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => _select(character),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: _CharacterNode(
                        character: character,
                        selected: _selected?.id == character.id,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        if (_selected != null && width >= 840)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text('点击人物查看摘要与来源；关系变化以来源章节为准。',
                style: Theme.of(context).textTheme.bodySmall),
          ),
      ],
    );
  }

  Widget _boundaryBanner(FictionStoryAtlas atlas) => Material(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              const Icon(Icons.shield_outlined, size: 18),
              const SizedBox(width: 8),
              Expanded(
                  child: Text(
                      '安全边界 ${(atlas.visibleProgress * 100).round()}% · 仅展示已读内容')),
            ],
          ),
        ),
      );

  Widget _details(FictionCharacterNode? node) {
    if (node == null) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Text('选择一个人物查看详情。'),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      child: ListView(
        shrinkWrap: true,
        children: [
          Row(children: [
            _InitialAvatar(name: node.name, large: true),
            const SizedBox(width: 12),
            Expanded(
                child: Text(node.name,
                    style: Theme.of(context).textTheme.titleLarge)),
          ]),
          if (node.summary.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(node.summary),
          ],
          if (node.aliases.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('别名：${node.aliases.join('、')}'),
          ],
          const SizedBox(height: 12),
          _sourceStatus(node.source),
          const SizedBox(height: 16),
          Text('已知关系', style: Theme.of(context).textTheme.titleMedium),
          for (final edge in _relationshipsFor(node))
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('${_otherName(edge, node)} · ${edge.relation}'),
              subtitle: Text(edge.summary.isEmpty ? edge.state : edge.summary),
              trailing: edge.isChanged ? const Icon(Icons.history) : null,
              onTap: () => _showRelationship(edge),
            ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () =>
                _openSource(ReadingArtifactSource.fromArtifact(node.source)),
            icon: const Icon(Icons.short_text),
            label: const Text('返回来源'),
          ),
        ],
      ),
    );
  }

  List<FictionRelationshipEdge> _relationshipsFor(FictionCharacterNode node) {
    final atlas = _atlas;
    if (atlas == null) return const [];
    return atlas.relationships
        .where((edge) => edge.from == node.id || edge.to == node.id)
        .toList(growable: false);
  }

  String _otherName(FictionRelationshipEdge edge, FictionCharacterNode node) {
    final id = edge.from == node.id ? edge.to : edge.from;
    final atlas = _atlas;
    if (atlas == null) return id;
    for (final character in atlas.characters) {
      if (character.id == id) return character.name;
    }
    return id;
  }

  void _showRelationship(FictionRelationshipEdge edge) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('${edge.relation}关系'),
        content: SizedBox(
          width: 420,
          child: ListView(
            shrinkWrap: true,
            children: [
              Text(edge.summary.isEmpty ? '当前位置没有更多描述。' : edge.summary),
              const SizedBox(height: 8),
              _sourceStatus(edge.source),
              const Divider(height: 28),
              Text('关系变化记录', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 6),
              for (final artifact in edge.history)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(
                    '${artifact.payload['relation'] ?? '其他'} · ${artifact.payload['state'] ?? 'active'}',
                  ),
                  subtitle: Text(
                    '${artifact.chapterTitle ?? '未知章节'} · ${(artifact.sourceProgress * 100).round()}%',
                  ),
                  trailing: const Icon(Icons.short_text, size: 20),
                  onTap: _sourceTarget(artifact).isEmpty
                      ? null
                      : () async {
                          Navigator.pop(dialogContext);
                          await widget.onOpenLocation
                              ?.call(_sourceTarget(artifact));
                        },
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('关闭'))
        ],
      ),
    );
  }

  Widget _sourceStatus(ReadingArtifact artifact) => Align(
        alignment: Alignment.centerLeft,
        child: Chip(
          visualDensity: VisualDensity.compact,
          avatar: Icon(
            artifact.epistemicStatus ==
                    ReadingArtifactEpistemicStatus.agentInference
                ? Icons.auto_awesome_outlined
                : Icons.menu_book_outlined,
            size: 16,
          ),
          label: Text(
            artifact.epistemicStatus ==
                    ReadingArtifactEpistemicStatus.agentInference
                ? 'AI 推测'
                : '文本事实',
          ),
        ),
      );

  String _sourceTarget(ReadingArtifact source) =>
      source.sourceStartCfi ??
      source.discoveredAtCfi ??
      source.chapterHref ??
      '';
}

class _CharacterNode extends StatelessWidget {
  const _CharacterNode({required this.character, required this.selected});
  final FictionCharacterNode character;
  final bool selected;

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _InitialAvatar(name: character.name, selected: selected),
          const SizedBox(height: 4),
          Container(
            constraints: const BoxConstraints(maxWidth: 120),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: Theme.of(context).colorScheme.onSurface,
                width: 1.2,
              ),
            ),
            child: Text(character.name, overflow: TextOverflow.ellipsis),
          ),
        ],
      );
}

class _InitialAvatar extends StatelessWidget {
  const _InitialAvatar(
      {required this.name, this.large = false, this.selected = false});
  final String name;
  final bool large;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final diameter = (large ? 28.0 : 24.0) * 2;
    return Container(
      width: diameter,
      height: diameter,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? colors.primary : colors.surface,
        border: Border.all(
          color: selected ? colors.primary : colors.onSurface,
          width: selected ? 3 : 2,
        ),
      ),
      child: Text(
        _avatarInitial(name),
        style: TextStyle(
          color: selected ? colors.onPrimary : colors.onSurface,
          fontSize: large ? 24 : 18,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// Returns the first character of a person's given name rather than the
/// family name. This keeps Chinese character avatars useful: 张三 -> 三,
/// 王小明 -> 小, 诸葛亮 -> 亮. For non-Chinese names we use the initial of
/// the final whitespace-delimited name part (John Doe -> D).
String _avatarInitial(String rawName) {
  final name = rawName.trim();
  if (name.isEmpty) return '?';

  final parts = name.split(RegExp(r'\s+')).where((part) => part.isNotEmpty);
  final lastPart = parts.isEmpty ? name : parts.last;
  final runes = lastPart.runes.toList(growable: false);
  if (runes.isEmpty) return '?';

  final isChineseName = runes.every((rune) =>
      (rune >= 0x3400 && rune <= 0x4DBF) || (rune >= 0x4E00 && rune <= 0x9FFF));
  if (!isChineseName || runes.length == 1) {
    return String.fromCharCode(runes.first);
  }

  // The common compound surnames need two characters skipped. Unknown
  // surnames default to a one-character surname, which covers the vast
  // majority of Chinese names without maintaining a large surname database.
  const compoundSurnames = {
    '欧阳',
    '司马',
    '上官',
    '诸葛',
    '东方',
    '独孤',
    '南宫',
    '夏侯',
    '皇甫',
    '尉迟',
    '公孙',
    '慕容',
    '令狐',
    '长孙',
    '宇文',
    '闻人',
    '赫连',
    '澹台',
    '端木',
    '拓跋',
    '百里',
    '钟离',
    '完颜',
    '呼延',
    '鲜于',
    '第五',
  };
  final surnameLength = runes.length >= 3 &&
          compoundSurnames.contains(String.fromCharCodes(runes.take(2)))
      ? 2
      : 1;
  return String.fromCharCode(
      runes[surnameLength < runes.length ? surnameLength : 0]);
}

class ReadingArtifactSource {
  const ReadingArtifactSource({required this.cfi});
  final String cfi;
  factory ReadingArtifactSource.fromArtifact(ReadingArtifact artifact) =>
      ReadingArtifactSource(
        cfi: artifact.sourceStartCfi ??
            artifact.discoveredAtCfi ??
            artifact.chapterHref ??
            '',
      );
}

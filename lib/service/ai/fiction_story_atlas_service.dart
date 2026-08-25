import 'package:anx_reader/models/reading_agent.dart';
import 'package:anx_reader/service/ai/reading_agent_repository.dart';

/// A page-independent projection of fiction Artifacts. The database remains
/// the source of truth; this service only applies the reader's current spoiler
/// boundary and normalizes legacy payloads for the visual surfaces.
class FictionStoryAtlas {
  const FictionStoryAtlas({
    required this.characters,
    required this.relationships,
    required this.timeline,
    required this.visibleProgress,
    required this.coverageStart,
    required this.coverageEnd,
    this.lastIngestedAt,
  });

  final List<FictionCharacterNode> characters;
  final List<FictionRelationshipEdge> relationships;
  final List<FictionTimelineEvent> timeline;
  final double visibleProgress;
  final double? coverageStart;
  final double? coverageEnd;
  final int? lastIngestedAt;

  bool get isEmpty => characters.isEmpty && timeline.isEmpty;
}

class FictionCharacterNode {
  const FictionCharacterNode({
    required this.id,
    required this.name,
    required this.summary,
    required this.aliases,
    required this.source,
  });

  final String id;
  final String name;
  final String summary;
  final List<String> aliases;
  final ReadingArtifact source;

  String get initial => name.trim().isEmpty ? '?' : name.trim()[0];
}

class FictionRelationshipEdge {
  const FictionRelationshipEdge({
    required this.from,
    required this.to,
    required this.relation,
    required this.summary,
    required this.state,
    required this.history,
    required this.source,
  });

  final String from;
  final String to;
  final String relation;
  final String summary;
  final String state;
  final List<ReadingArtifact> history;
  final ReadingArtifact source;

  bool get isChanged => state == 'changed' || state == 'ended';
}

class FictionTimelineEvent {
  const FictionTimelineEvent({
    required this.id,
    required this.title,
    required this.summary,
    required this.kind,
    required this.participants,
    required this.storyTimeLabel,
    required this.source,
  });

  final String id;
  final String title;
  final String summary;
  final String kind;
  final List<String> participants;
  final String? storyTimeLabel;
  final ReadingArtifact source;

  bool get isMajor => source.payload['importance']?.toString() == 'major';
  bool get isMystery => kind == ReadingArtifactKinds.mystery;
  bool get isClue => kind == ReadingArtifactKinds.clue;
}

enum FictionTimelineDensity { compact, standard, complete }

class FictionTimelineChapter {
  const FictionTimelineChapter({
    required this.id,
    required this.title,
    required this.startProgress,
    required this.events,
  });

  final String id;
  final String title;
  final double startProgress;
  final List<FictionTimelineEvent> events;

  int get majorEventCount => events.where((event) => event.isMajor).length;
}

class FictionStoryAtlasService {
  const FictionStoryAtlasService({ReadingAgentRepository? repository})
      : _repository = repository;

  final ReadingAgentRepository? _repository;

  Future<FictionStoryAtlas> load({
    required int bookId,
    required double visibleAtProgress,
  }) async {
    final artifacts = await (_repository ?? readingAgentRepository).artifacts(
      bookId,
      status: ReadingArtifactStatus.active,
      visibleAtProgress: visibleAtProgress,
    );
    return fromArtifacts(artifacts, visibleAtProgress: visibleAtProgress);
  }

  /// Produces the chapter-level projection used by long timelines. Filtering
  /// happens before grouping so the page can render one bounded chapter page
  /// without building every event widget in the book.
  List<FictionTimelineChapter> timelineChapters(
    Iterable<FictionTimelineEvent> input, {
    FictionTimelineDensity density = FictionTimelineDensity.compact,
    Set<String> kinds = const {},
    String? participant,
  }) {
    final normalizedParticipant = participant?.trim();
    final filtered = input.where((event) {
      if (!_includedAtDensity(event, density)) return false;
      if (kinds.isNotEmpty && !kinds.contains(event.kind)) return false;
      if (normalizedParticipant != null &&
          normalizedParticipant.isNotEmpty &&
          !event.participants.contains(normalizedParticipant)) {
        return false;
      }
      return true;
    });
    final grouped = <String, List<FictionTimelineEvent>>{};
    final titles = <String, String>{};
    for (final event in filtered) {
      final href = event.source.chapterHref?.trim() ?? '';
      final title = event.source.chapterTitle?.trim() ?? '';
      final key = href.isNotEmpty
          ? href
          : title.isNotEmpty
              ? 'title:$title'
              : 'progress:${(event.source.sourceProgress * 1000).floor()}';
      grouped.putIfAbsent(key, () => []).add(event);
      titles[key] = title.isEmpty ? '未知章节' : title;
    }
    return grouped.entries.map((entry) {
      final events = entry.value
        ..sort((a, b) => _artifactOrder(a.source, b.source));
      return FictionTimelineChapter(
        id: entry.key,
        title: titles[entry.key]!,
        startProgress: events.first.source.sourceProgress,
        events: List.unmodifiable(events),
      );
    }).toList(growable: false)
      ..sort((a, b) => a.startProgress.compareTo(b.startProgress));
  }

  bool _includedAtDensity(
    FictionTimelineEvent event,
    FictionTimelineDensity density,
  ) =>
      switch (density) {
        FictionTimelineDensity.compact =>
          event.isMajor || event.isMystery || event.isClue,
        FictionTimelineDensity.standard =>
          event.kind != ReadingArtifactKinds.scene,
        FictionTimelineDensity.complete => true,
      };

  FictionStoryAtlas fromArtifacts(
    Iterable<ReadingArtifact> input, {
    required double visibleAtProgress,
  }) {
    final artifacts = input
        .where((item) =>
            item.isVisibleAtProgress(visibleAtProgress) &&
            item.status == ReadingArtifactStatus.active)
        .toList(growable: false);
    final characters = <String, FictionCharacterNode>{};
    final aliases = <String, String>{};
    for (final artifact in artifacts
        .where((item) => item.kind == ReadingArtifactKinds.character)) {
      final name = _text(artifact.payload['name']);
      if (name.isEmpty) continue;
      final id = _id(artifact.payload['entityId'], name);
      final node = FictionCharacterNode(
        id: id,
        name: name,
        summary: _text(artifact.payload['summary']),
        aliases: _list(artifact.payload['aliases']),
        source: artifact,
      );
      characters[id] = node;
      aliases[_normalize(name)] = id;
      for (final alias in node.aliases) {
        aliases[_normalize(alias)] = id;
      }
    }

    final relationshipArtifacts = artifacts
        .where((item) => item.kind == ReadingArtifactKinds.relationship)
        .toList()
      ..sort(_artifactOrder);
    final grouped = <String, List<ReadingArtifact>>{};
    for (final artifact in relationshipArtifacts) {
      final from = _resolve(
        _text(artifact.payload['from']),
        characters,
        aliases,
      );
      final to = _resolve(
        _text(artifact.payload['to']),
        characters,
        aliases,
      );
      if (from.isEmpty || to.isEmpty || from == to) continue;
      characters.putIfAbsent(from, () => _placeholder(from, artifact));
      characters.putIfAbsent(to, () => _placeholder(to, artifact));
      final key = [from, to]..sort();
      grouped.putIfAbsent(key.join('|'), () => []).add(artifact);
    }
    final relationships = <FictionRelationshipEdge>[];
    for (final history in grouped.values) {
      history.sort(_artifactOrder);
      final latest = history.last;
      final from = _resolve(_text(latest.payload['from']), characters, aliases);
      final to = _resolve(_text(latest.payload['to']), characters, aliases);
      relationships.add(FictionRelationshipEdge(
        from: from,
        to: to,
        relation: _text(latest.payload['relation'], fallback: '其他'),
        summary: _text(latest.payload['summary']),
        state: _text(latest.payload['state'], fallback: 'active'),
        history: List.unmodifiable(history),
        source: latest,
      ));
    }

    final timelineKinds = {
      ReadingArtifactKinds.event,
      ReadingArtifactKinds.scene,
      ReadingArtifactKinds.clue,
      ReadingArtifactKinds.mystery,
    };
    final timeline = artifacts
        .where((item) => timelineKinds.contains(item.kind))
        .map((artifact) => _timelineEvent(artifact, aliases, characters))
        .toList()
      ..sort((a, b) => _artifactOrder(a.source, b.source));
    final ingested = artifacts.map((item) => item.ingestedAt).toList();
    final progress = artifacts.map((item) => item.sourceProgress).toList();
    return FictionStoryAtlas(
      characters: List.unmodifiable(characters.values),
      relationships: List.unmodifiable(relationships),
      timeline: List.unmodifiable(timeline),
      visibleProgress: visibleAtProgress.clamp(0, 1).toDouble(),
      coverageStart: progress.isEmpty ? null : progress.reduce(_min),
      coverageEnd: progress.isEmpty ? null : progress.reduce(_max),
      lastIngestedAt: ingested.isEmpty ? null : ingested.reduce(_maxInt),
    );
  }

  FictionTimelineEvent _timelineEvent(
    ReadingArtifact artifact,
    Map<String, String> aliases,
    Map<String, FictionCharacterNode> characters,
  ) {
    final payload = artifact.payload;
    final title = _text(
      payload['title'],
      fallback: artifact.kind == ReadingArtifactKinds.scene
          ? '场景'
          : artifact.kind == ReadingArtifactKinds.mystery
              ? '未解悬念'
              : artifact.kind == ReadingArtifactKinds.clue
                  ? '线索'
                  : '故事事件',
    );
    final participants = _list(payload['participants']).map((value) {
      final id = _resolve(value, characters, aliases);
      return characters[id]?.name ?? value;
    }).toList(growable: false);
    return FictionTimelineEvent(
      id: artifact.id,
      title: title,
      summary: _text(
        payload['summary'],
        fallback: _text(payload['question']),
      ),
      kind: artifact.kind,
      participants: participants,
      storyTimeLabel: _nullableText(payload['storyTimeLabel']),
      source: artifact,
    );
  }

  FictionCharacterNode _placeholder(String id, ReadingArtifact source) =>
      FictionCharacterNode(
        id: id,
        name: id,
        summary: '',
        aliases: const [],
        source: source,
      );

  String _resolve(String value, Map<String, FictionCharacterNode> characters,
      Map<String, String> aliases) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return '';
    if (characters.containsKey(trimmed)) return trimmed;
    return aliases[_normalize(trimmed)] ?? _normalize(trimmed);
  }

  String _id(Object? raw, String fallback) =>
      _text(raw).isEmpty ? _normalize(fallback) : _text(raw);

  String _normalize(String value) =>
      value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  String _text(Object? value, {String fallback = ''}) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? fallback : text;
  }

  String? _nullableText(Object? value) {
    final text = _text(value);
    return text.isEmpty ? null : text;
  }

  List<String> _list(Object? value) => value is List
      ? value
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .toList()
      : const [];

  int _artifactOrder(ReadingArtifact a, ReadingArtifact b) {
    final progress = a.sourceProgress.compareTo(b.sourceProgress);
    if (progress != 0) return progress;
    final href = (a.chapterHref ?? '').compareTo(b.chapterHref ?? '');
    if (href != 0) return href;
    final cfi = (a.sourceStartCfi ?? a.discoveredAtCfi ?? '')
        .compareTo(b.sourceStartCfi ?? b.discoveredAtCfi ?? '');
    if (cfi != 0) return cfi;
    return a.createdAt.compareTo(b.createdAt);
  }

  double _min(double a, double b) => a < b ? a : b;
  double _max(double a, double b) => a > b ? a : b;
  int _maxInt(int a, int b) => a > b ? a : b;
}

const fictionStoryAtlasService = FictionStoryAtlasService();

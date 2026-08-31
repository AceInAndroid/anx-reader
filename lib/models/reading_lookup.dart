import 'package:anx_reader/models/selection_snapshot.dart';

enum ReadingLookupCandidateKind {
  chineseCharacter,
  chinesePhrase,
  englishWord,
  passage,
  unsupported;

  bool get isDictionaryLookup =>
      this == chineseCharacter || this == chinesePhrase || this == englishWord;
}

enum NetworkPolicy {
  offlineOnly,
  cacheFirst,
  networkAllowed;

  bool get allowsNetwork => this != offlineOnly;
}

enum ReadingLookupSource {
  localMdx,
  bundledChinese,
  englishDictionary,
  none,
}

class ReadingLookupCandidate {
  const ReadingLookupCandidate({
    required this.text,
    required this.kind,
    required this.trigger,
    required this.allowContextExpansion,
  });

  final String text;
  final ReadingLookupCandidateKind kind;
  final SelectionTrigger trigger;
  final bool allowContextExpansion;

  bool get isDictionaryLookup => kind.isDictionaryLookup;
}

class ReadingLookupSense {
  const ReadingLookupSense({required this.definition, this.example});

  final String definition;
  final String? example;
}

class ReadingLookupResult {
  const ReadingLookupResult({
    required this.query,
    required this.source,
    this.matchedWord,
    this.dictionaryName,
    this.html,
    this.senses = const [],
    this.pronunciation,
    this.partOfSpeech,
    this.definition,
    this.example,
    this.audioUrl,
  });

  factory ReadingLookupResult.empty(String query) => ReadingLookupResult(
        query: query,
        source: ReadingLookupSource.none,
      );

  final String query;
  final ReadingLookupSource source;
  final String? matchedWord;
  final String? dictionaryName;
  final String? html;
  final List<ReadingLookupSense> senses;
  final String? pronunciation;
  final String? partOfSpeech;
  final String? definition;
  final String? example;
  final String? audioUrl;

  bool get found => source != ReadingLookupSource.none;
}

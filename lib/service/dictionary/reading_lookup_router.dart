import 'package:anx_reader/models/reading_lookup.dart';
import 'package:anx_reader/service/dictionary/chinese_dictionary.dart';
import 'package:anx_reader/service/dictionary/english_dictionary.dart';
import 'package:anx_reader/service/dictionary/local_dictionary.dart';

class ReadingLookupRouter {
  const ReadingLookupRouter._();

  static Future<ReadingLookupResult> lookup({
    required ReadingLookupCandidate candidate,
    required NetworkPolicy networkPolicy,
    String? contextText,
  }) async {
    if (!candidate.isDictionaryLookup) {
      return ReadingLookupResult.empty(candidate.text);
    }

    final local = await LocalDictionaryService.lookup(candidate.text);
    if (local != null) {
      return ReadingLookupResult(
        query: candidate.text,
        source: ReadingLookupSource.localMdx,
        matchedWord: local.word,
        dictionaryName: local.dictionaryName,
        html: local.html,
      );
    }

    if (candidate.kind == ReadingLookupCandidateKind.chineseCharacter ||
        candidate.kind == ReadingLookupCandidateKind.chinesePhrase) {
      final entry = await ChineseDictionaryService.lookup(
        candidate.text,
        contextText: contextText,
        allowContextExpansion: candidate.allowContextExpansion,
      );
      if (entry == null) return ReadingLookupResult.empty(candidate.text);
      return ReadingLookupResult(
        query: candidate.text,
        source: ReadingLookupSource.bundledChinese,
        matchedWord: entry.word,
        pronunciation: entry.pinyin,
        senses: entry.senses
            .map(
              (sense) => ReadingLookupSense(
                definition: sense.definition,
                example: sense.example,
              ),
            )
            .toList(growable: false),
      );
    }

    final entry = await EnglishDictionaryService.lookup(
      candidate.text,
      networkPolicy: networkPolicy,
    );
    if (entry == null) return ReadingLookupResult.empty(candidate.text);
    return ReadingLookupResult(
      query: candidate.text,
      source: ReadingLookupSource.englishDictionary,
      matchedWord: entry.lemma ?? candidate.text,
      pronunciation: entry.phonetic,
      partOfSpeech: entry.partOfSpeech,
      definition: entry.definitionEn,
      example: entry.exampleSentence,
      audioUrl: entry.audioUrl,
    );
  }
}

import 'package:anx_reader/models/reading_lookup.dart';
import 'package:anx_reader/models/selection_snapshot.dart';
import 'package:anx_reader/service/dictionary/chinese_dictionary.dart';
import 'package:anx_reader/service/dictionary/english_dictionary.dart';

class ReadingLookupCandidateResolver {
  const ReadingLookupCandidateResolver._();

  static ReadingLookupCandidate resolve(
    String text, {
    SelectionSnapshot? selection,
    bool offline = false,
  }) {
    final value = text.trim();
    final trigger = selection?.trigger ?? SelectionTrigger.manual;
    if (value.isEmpty) {
      return ReadingLookupCandidate(
        text: value,
        kind: ReadingLookupCandidateKind.unsupported,
        trigger: trigger,
        allowContextExpansion: false,
      );
    }

    if (EnglishDictionaryService.isEnglishWord(value)) {
      return ReadingLookupCandidate(
        text: value,
        kind: ReadingLookupCandidateKind.englishWord,
        trigger: trigger,
        allowContextExpansion: false,
      );
    }

    if (ChineseDictionaryService.isLookupCandidate(value)) {
      final singleCharacter = value.runes.length == 1;
      final automaticTouch = trigger == SelectionTrigger.longPress ||
          trigger == SelectionTrigger.doubleTap;
      return ReadingLookupCandidate(
        text: value,
        kind: singleCharacter
            ? ReadingLookupCandidateKind.chineseCharacter
            : ReadingLookupCandidateKind.chinesePhrase,
        trigger: trigger,
        // Offline lookup means exactly what the user touched. Explicitly
        // selected phrases and range-button selections are never expanded.
        allowContextExpansion: singleCharacter && automaticTouch && !offline,
      );
    }

    return ReadingLookupCandidate(
      text: value,
      kind: ReadingLookupCandidateKind.passage,
      trigger: trigger,
      allowContextExpansion: false,
    );
  }
}

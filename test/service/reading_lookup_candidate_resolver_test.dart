import 'package:anx_reader/models/reading_lookup.dart';
import 'package:anx_reader/models/selection_snapshot.dart';
import 'package:anx_reader/service/dictionary/reading_lookup_candidate_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

SelectionSnapshot _selection({
  required String text,
  required SelectionRangeType rangeType,
  required SelectionTrigger trigger,
}) =>
    SelectionSnapshot(
      sessionId: 1,
      rangeType: rangeType,
      trigger: trigger,
      text: text,
      cfi: 'epubcfi(/6/2)',
      contextText: '他是一位著名作家。',
      chapterIndex: 0,
      canMovePrevious: true,
      canMoveNext: true,
      supportsRangeSelection: true,
    );

void main() {
  test('offline Chinese long press keeps exact character', () {
    final candidate = ReadingLookupCandidateResolver.resolve(
      '家',
      selection: _selection(
        text: '家',
        rangeType: SelectionRangeType.character,
        trigger: SelectionTrigger.longPress,
      ),
      offline: true,
    );

    expect(candidate.kind, ReadingLookupCandidateKind.chineseCharacter);
    expect(candidate.allowContextExpansion, isFalse);
  });

  test('online Chinese touch may use context expansion', () {
    final candidate = ReadingLookupCandidateResolver.resolve(
      '家',
      selection: _selection(
        text: '家',
        rangeType: SelectionRangeType.character,
        trigger: SelectionTrigger.longPress,
      ),
    );

    expect(candidate.allowContextExpansion, isTrue);
  });

  test('explicit Chinese phrase and English word are stable candidates', () {
    final phrase = ReadingLookupCandidateResolver.resolve(
      '阅读方法',
      selection: _selection(
        text: '阅读方法',
        rangeType: SelectionRangeType.word,
        trigger: SelectionTrigger.rangeButton,
      ),
    );
    final english = ReadingLookupCandidateResolver.resolve('reading');

    expect(phrase.kind, ReadingLookupCandidateKind.chinesePhrase);
    expect(phrase.allowContextExpansion, isFalse);
    expect(english.kind, ReadingLookupCandidateKind.englishWord);
  });
}

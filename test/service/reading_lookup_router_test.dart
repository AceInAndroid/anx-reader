import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/models/reading_lookup.dart';
import 'package:anx_reader/models/selection_snapshot.dart';
import 'package:anx_reader/service/dictionary/reading_lookup_candidate_resolver.dart';
import 'package:anx_reader/service/dictionary/reading_lookup_router.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    Prefs().prefs = await SharedPreferences.getInstance();
  });

  test('offline Chinese character cannot expand from context', () async {
    final snapshot = SelectionSnapshot(
      sessionId: 1,
      rangeType: SelectionRangeType.character,
      trigger: SelectionTrigger.longPress,
      text: '家',
      cfi: 'epubcfi(/6/2)',
      contextText: '他是一位著名作家。',
      chapterIndex: 0,
      canMovePrevious: true,
      canMoveNext: true,
      supportsRangeSelection: true,
    );
    final candidate = ReadingLookupCandidateResolver.resolve(
      '家',
      selection: snapshot,
      offline: true,
    );
    final result = await ReadingLookupRouter.lookup(
      candidate: candidate,
      networkPolicy: NetworkPolicy.offlineOnly,
      contextText: snapshot.contextText,
    );

    expect(result.source, ReadingLookupSource.bundledChinese);
    expect(result.matchedWord, '家');
  });

  test('offline English lookup does not require a network result', () async {
    final candidate = ReadingLookupCandidateResolver.resolve(
      'anxuncachedword',
      offline: true,
    );
    final result = await ReadingLookupRouter.lookup(
      candidate: candidate,
      networkPolicy: NetworkPolicy.offlineOnly,
    );

    expect(result.found, isFalse);
  });
}

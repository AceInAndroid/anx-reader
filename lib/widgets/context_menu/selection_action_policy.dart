import 'package:anx_reader/service/dictionary/chinese_dictionary.dart';
import 'package:anx_reader/service/dictionary/english_dictionary.dart';

enum SelectionMenuAction {
  lookupOrTranslate,
  addToVocabulary,
  ai,
  copy,
  more,
  webSearch,
  paragraphTranslate,
  narrate,
  saveDifficulty,
  note,
  share,
}

class SelectionActionPolicy {
  const SelectionActionPolicy._({
    required this.isDictionaryLookup,
    required this.primaryActions,
    required this.moreActions,
  });

  final bool isDictionaryLookup;
  final List<SelectionMenuAction> primaryActions;
  final List<SelectionMenuAction> moreActions;

  factory SelectionActionPolicy.forSelection(
    String text, {
    required bool aiEnabled,
    required bool vocabularyEnabled,
    required bool footnote,
  }) {
    final isDictionaryLookup = EnglishDictionaryService.isEnglishWord(text) ||
        ChineseDictionaryService.isLookupCandidate(text);
    final primary = <SelectionMenuAction>[
      SelectionMenuAction.lookupOrTranslate,
      if (isDictionaryLookup && vocabularyEnabled)
        SelectionMenuAction.addToVocabulary,
      if (aiEnabled) SelectionMenuAction.ai,
      if (!isDictionaryLookup) SelectionMenuAction.copy,
      SelectionMenuAction.more,
    ];
    final more = <SelectionMenuAction>[
      if (isDictionaryLookup) SelectionMenuAction.copy,
      SelectionMenuAction.webSearch,
      SelectionMenuAction.paragraphTranslate,
      SelectionMenuAction.narrate,
      if (!footnote) SelectionMenuAction.saveDifficulty,
      if (!footnote) SelectionMenuAction.note,
      SelectionMenuAction.share,
    ];
    return SelectionActionPolicy._(
      isDictionaryLookup: isDictionaryLookup,
      primaryActions: List.unmodifiable(primary),
      moreActions: List.unmodifiable(more),
    );
  }
}

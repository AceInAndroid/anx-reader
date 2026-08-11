import 'package:anx_reader/widgets/context_menu/selection_action_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('word selection prioritizes lookup, vocabulary, and AI', () {
    final policy = SelectionActionPolicy.forSelection(
      'reading',
      aiEnabled: true,
      vocabularyEnabled: true,
      footnote: false,
    );

    expect(policy.isDictionaryLookup, isTrue);
    expect(policy.primaryActions, [
      SelectionMenuAction.lookupOrTranslate,
      SelectionMenuAction.addToVocabulary,
      SelectionMenuAction.ai,
      SelectionMenuAction.more,
    ]);
    expect(policy.moreActions, contains(SelectionMenuAction.copy));
  });

  test('passage selection prioritizes translation, AI, and copy', () {
    final policy = SelectionActionPolicy.forSelection(
      'A selected sentence with several words.',
      aiEnabled: true,
      vocabularyEnabled: true,
      footnote: false,
    );

    expect(policy.isDictionaryLookup, isFalse);
    expect(policy.primaryActions, [
      SelectionMenuAction.lookupOrTranslate,
      SelectionMenuAction.ai,
      SelectionMenuAction.copy,
      SelectionMenuAction.more,
    ]);
  });

  test('disabled capabilities and footnotes remove unavailable actions', () {
    final policy = SelectionActionPolicy.forSelection(
      '词语',
      aiEnabled: false,
      vocabularyEnabled: false,
      footnote: true,
    );

    expect(policy.primaryActions, isNot(contains(SelectionMenuAction.ai)));
    expect(
      policy.primaryActions,
      isNot(contains(SelectionMenuAction.addToVocabulary)),
    );
    expect(policy.moreActions, isNot(contains(SelectionMenuAction.note)));
  });
}

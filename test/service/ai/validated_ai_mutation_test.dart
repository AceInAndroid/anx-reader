import 'package:anx_reader/models/reading_evidence.dart';
import 'package:anx_reader/service/ai/agent_action_service.dart';
import 'package:anx_reader/service/ai/validated_ai_mutation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final service = AgentActionService();

  test('proactive suggestions are not authorized writes', () {
    const mutation = ValidatedAiMutation<String>(
      actionType: 'save',
      targetType: 'artifact',
      targetId: 'target',
      bookId: 1,
      value: 'value',
      authorization: AiMutationAuthorization.proactiveSuggestion,
    );

    expect(mutation.isAuthorized, isFalse);
  });

  test('mutation evidence must belong to the same book', () {
    const evidence = EvidenceEnvelope(
      id: 'evidence',
      sourceKind: EvidenceSourceKind.bookText,
      bookId: 2,
      chapterHref: 'chapter.xhtml',
      exactText: '证据',
      producer: 'test',
    );

    expect(
      () => service.validateEvidenceForMutation(
        evidence: const [evidence],
        bookId: 1,
        visibleProgress: 1,
      ),
      throwsArgumentError,
    );
  });

  test('mutation evidence cannot cross the visible spoiler boundary', () {
    const evidence = EvidenceEnvelope(
      id: 'evidence',
      sourceKind: EvidenceSourceKind.bookText,
      bookId: 1,
      chapterHref: 'chapter.xhtml',
      exactText: '证据',
      visibleFromProgress: .7,
      producer: 'test',
    );

    expect(
      () => service.validateEvidenceForMutation(
        evidence: const [evidence],
        bookId: 1,
        visibleProgress: .6,
      ),
      throwsArgumentError,
    );
  });
}

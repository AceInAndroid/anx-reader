import 'package:anx_reader/service/ai/ai_context_assembler.dart';
import 'package:anx_reader/service/ai/ai_request.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:langchain_core/chat_models.dart';

void main() {
  test('request derives stable workload and a unique trace id', () {
    final first = AiRequest(
      messages: [ChatMessage.humanText('hello')],
      contextTask: AiContextTask.translation,
    );
    final second = AiRequest(
      messages: [ChatMessage.humanText('hello')],
      contextTask: AiContextTask.translation,
    );

    expect(first.workloadId, 'translation.selection');
    expect(first.trace.workloadId, first.workloadId);
    expect(first.trace.requestId, isNotEmpty);
    expect(first.trace.requestId, isNot(second.trace.requestId));
  });

  test('workload descriptors lock structured task defaults', () {
    final fiction = AiWorkloadDescriptorRegistry.find('fiction.story_atlas');
    final summary =
        AiWorkloadDescriptorRegistry.find('context.rolling_summary');

    expect(fiction?.contextTask, AiContextTask.fictionBackfill);
    expect(fiction?.outputContract.kind, AiOutputKind.json);
    expect(
      fiction?.fallbackPolicy,
      AiFallbackPolicy.confirmBeforeFullTextCloud,
    );
    expect(summary?.fallbackPolicy, AiFallbackPolicy.none);
    expect(summary?.providerRole, AiProviderRole.localExtraction);
  });
}

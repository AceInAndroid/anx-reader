import 'package:anx_reader/service/ai/langchain_runner.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:langchain/langchain.dart';

void main() {
  test('runner estimates input and output when provider omits usage', () async {
    int? receivedInput;
    int? receivedOutput;
    bool? receivedEstimated;
    final runner = CancelableLangchainRunner(
      onTokenUsage: ({
        required inputTokens,
        required outputTokens,
        required estimated,
      }) {
        receivedInput = inputTokens;
        receivedOutput = outputTokens;
        receivedEstimated = estimated;
      },
    );

    final chunks = await runner
        .stream(
          model: FakeChatModel(responses: const ['回答']),
          prompt: PromptValue.chat([ChatMessage.humanText('问题')]),
        )
        .toList();

    expect(chunks.last, '回答');
    expect(receivedInput, 2);
    expect(receivedOutput, 2);
    expect(receivedEstimated, isTrue);
  });
}

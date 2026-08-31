import 'package:anx_reader/service/ai/ai_request.dart';
import 'package:anx_reader/service/ai/index.dart';

/// Compatibility gateway for new AI workloads.
///
/// Existing callers may continue using aiGenerate*; new code should construct
/// an AiRequest so workload, source scope, output contract and trace metadata
/// travel together.
class AiRequestGateway {
  const AiRequestGateway();

  AiStreamResult execute(AiRequest request) => executeAiRequest(request);

  Stream<String> executeStream(AiRequest request) =>
      executeAiRequestStream(request);

  Future<String> executeText(AiRequest request) =>
      executeAiRequestText(request);

  Future<AiGenerationResult<String>> executeTextWithMetadata(
    AiRequest request,
  ) =>
      executeAiRequestTextWithMetadata(request);
}

const aiRequestGateway = AiRequestGateway();

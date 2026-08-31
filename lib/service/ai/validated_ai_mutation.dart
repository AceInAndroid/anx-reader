import 'package:anx_reader/models/reading_evidence.dart';

enum AiMutationAuthorization {
  explicitUserRequest,
  confirmedTask,
  systemMaintenance,
  proactiveSuggestion,
}

class ValidatedAiMutation<T> {
  const ValidatedAiMutation({
    required this.actionType,
    required this.targetType,
    required this.targetId,
    required this.bookId,
    required this.value,
    required this.authorization,
    this.evidence = const [],
    this.visibleProgress = 1,
    this.requestId,
    this.taskId,
    this.workloadId,
  });

  final String actionType;
  final String targetType;
  final String targetId;
  final int bookId;
  final T value;
  final AiMutationAuthorization authorization;
  final List<EvidenceEnvelope> evidence;
  final double visibleProgress;
  final String? requestId;
  final String? taskId;
  final String? workloadId;

  bool get isAuthorized =>
      authorization != AiMutationAuthorization.proactiveSuggestion;
}

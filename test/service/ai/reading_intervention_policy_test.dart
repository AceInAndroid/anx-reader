import 'package:anx_reader/service/ai/reading_agent_runtime.dart';
import 'package:anx_reader/service/ai/reading_intervention_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('policy only exposes a passive capsule when state is present', () {
    const policy = ReadingInterventionPolicy();
    expect(
        policy.decide(
          state: const ReadingWorldState(unresolvedDifficultyCount: 1),
          controlsVisible: true,
          dismissedForSession: false,
        ),
        ReadingIntervention.passiveCapsule);
    expect(
        policy.decide(
          state: const ReadingWorldState(unresolvedDifficultyCount: 1),
          controlsVisible: false,
          dismissedForSession: false,
        ),
        ReadingIntervention.none);
    expect(
        policy.decide(
          state: const ReadingWorldState(pendingCheckpointCount: 1),
          controlsVisible: true,
          dismissedForSession: true,
        ),
        ReadingIntervention.none);
  });
}

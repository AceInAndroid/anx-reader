import 'package:anx_reader/service/ai/reading_agent_runtime.dart';

enum ReadingIntervention { none, passiveCapsule }

/// Pure local policy. It can expose a capsule, but it can never authorize a
/// model request, modal, banner, notification, or persistent Agent write.
class ReadingInterventionPolicy {
  const ReadingInterventionPolicy();

  ReadingIntervention decide({
    required ReadingWorldState state,
    required bool controlsVisible,
    required bool dismissedForSession,
  }) {
    if (!controlsVisible || dismissedForSession || !state.hasCapsuleState) {
      return ReadingIntervention.none;
    }
    return ReadingIntervention.passiveCapsule;
  }
}

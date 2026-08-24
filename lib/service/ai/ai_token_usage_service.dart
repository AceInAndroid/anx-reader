import 'dart:convert';

import 'package:anx_reader/config/shared_preference_provider.dart';

class AiTokenUsageSnapshot {
  const AiTokenUsageSnapshot({
    required this.month,
    required this.inputTokens,
    required this.outputTokens,
    required this.requests,
    required this.estimatedRequests,
    required this.startedAt,
  });

  factory AiTokenUsageSnapshot.empty(DateTime now) => AiTokenUsageSnapshot(
        month: _monthKey(now),
        inputTokens: 0,
        outputTokens: 0,
        requests: 0,
        estimatedRequests: 0,
        startedAt: now.millisecondsSinceEpoch,
      );

  factory AiTokenUsageSnapshot.fromJson(
    Map<String, dynamic> json,
    DateTime now,
  ) {
    if (json['month'] != _monthKey(now)) {
      return AiTokenUsageSnapshot.empty(now);
    }
    return AiTokenUsageSnapshot(
      month: json['month']?.toString() ?? _monthKey(now),
      inputTokens: _nonNegativeInt(json['inputTokens']),
      outputTokens: _nonNegativeInt(json['outputTokens']),
      requests: _nonNegativeInt(json['requests']),
      estimatedRequests: _nonNegativeInt(json['estimatedRequests']),
      startedAt: _nonNegativeInt(json['startedAt']) == 0
          ? now.millisecondsSinceEpoch
          : _nonNegativeInt(json['startedAt']),
    );
  }

  final String month;
  final int inputTokens;
  final int outputTokens;
  final int requests;
  final int estimatedRequests;
  final int startedAt;

  int get totalTokens => inputTokens + outputTokens;
  bool get containsEstimates => estimatedRequests > 0;

  AiTokenUsageSnapshot add({
    required int inputTokens,
    required int outputTokens,
    required bool estimated,
  }) =>
      AiTokenUsageSnapshot(
        month: month,
        inputTokens: this.inputTokens + inputTokens.clamp(0, 1 << 62),
        outputTokens: this.outputTokens + outputTokens.clamp(0, 1 << 62),
        requests: requests + 1,
        estimatedRequests: estimatedRequests + (estimated ? 1 : 0),
        startedAt: startedAt,
      );

  Map<String, dynamic> toJson() => {
        'month': month,
        'inputTokens': inputTokens,
        'outputTokens': outputTokens,
        'requests': requests,
        'estimatedRequests': estimatedRequests,
        'startedAt': startedAt,
      };

  static int _nonNegativeInt(Object? value) =>
      value is num ? value.toInt().clamp(0, 1 << 62) : 0;
}

class AiTokenUsageService {
  AiTokenUsageService({DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  static const storageKey = 'aiTokenUsageMonthly';
  final DateTime Function() _clock;

  AiTokenUsageSnapshot snapshot() {
    final now = _clock();
    final raw = Prefs().prefs.getString(storageKey);
    if (raw == null || raw.isEmpty) return AiTokenUsageSnapshot.empty(now);
    try {
      return AiTokenUsageSnapshot.fromJson(
        Map<String, dynamic>.from(jsonDecode(raw) as Map),
        now,
      );
    } catch (_) {
      return AiTokenUsageSnapshot.empty(now);
    }
  }

  void record({
    required int inputTokens,
    required int outputTokens,
    required bool estimated,
  }) {
    if (inputTokens <= 0 && outputTokens <= 0) return;
    final updated = snapshot().add(
      inputTokens: inputTokens,
      outputTokens: outputTokens,
      estimated: estimated,
    );
    Prefs().prefs.setString(storageKey, jsonEncode(updated.toJson()));
  }

  void reset() {
    final empty = AiTokenUsageSnapshot.empty(_clock());
    Prefs().prefs.setString(storageKey, jsonEncode(empty.toJson()));
  }
}

String _monthKey(DateTime value) =>
    '${value.year}-${value.month.toString().padLeft(2, '0')}';

final aiTokenUsageService = AiTokenUsageService();

import 'package:anx_reader/models/reading_agent.dart';
import 'package:anx_reader/service/ai/fiction_hybrid_extraction_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('cloud verification stays within twenty percent of baseline', () {
    expect(
      FictionHybridExtractionService.withinCloudVerificationBudget(
        baselineInputTokens: 1000,
        usedCloudInputTokens: 120,
        nextCloudInputTokens: 80,
      ),
      isTrue,
    );
    expect(
      FictionHybridExtractionService.withinCloudVerificationBudget(
        baselineInputTokens: 1000,
        usedCloudInputTokens: 120,
        nextCloudInputTokens: 81,
      ),
      isFalse,
    );
  });

  const validator = FictionCandidateRuleValidator();

  test('requires an exact evidence substring', () {
    final verdict = validator.validate(
      kind: ReadingArtifactKinds.character,
      payload: const {'name': '第五伦', 'evidence': '第五伦走进城内'},
      chapterContent: '第五伦走进屋内。',
    );
    expect(verdict.status, FictionCandidateRuleStatus.rejected);
  });

  test('accepts EPUB whitespace and punctuation normalization only', () {
    final verdict = validator.validate(
      kind: ReadingArtifactKinds.character,
      payload: const {'name': '第五伦', 'evidence': '“第五伦，进屋。”'},
      chapterContent: '“第五伦，\n进屋。”',
    );
    expect(verdict.status, FictionCandidateRuleStatus.accepted);
  });

  test('rejects generic roles and background historical references', () {
    expect(
      validator
          .validate(
            kind: ReadingArtifactKinds.character,
            payload: const {'name': '县宰', 'evidence': '县宰走进屋内'},
            chapterContent: '县宰走进屋内。',
          )
          .status,
      FictionCandidateRuleStatus.rejected,
    );
    expect(
      validator
          .validate(
            kind: ReadingArtifactKinds.character,
            payload: const {'name': '刘邦', 'evidence': '两百年前刘邦建立汉朝'},
            chapterContent: '两百年前刘邦建立汉朝。',
          )
          .status,
      FictionCandidateRuleStatus.rejected,
    );
  });

  test('preserves numeric surnames and explicit durable relations', () {
    final verdict = validator.validate(
      kind: ReadingArtifactKinds.relationship,
      payload: const {
        'from': '第五伦',
        'to': '第八矫',
        'relation': '同宗兄弟',
        'evidence': '而排名第二的，正是同宗兄弟第八矫',
      },
      chapterContent: '而排名第二的，正是同宗兄弟第八矫。',
    );
    expect(verdict.status, FictionCandidateRuleStatus.accepted);
    expect(verdict.payload['from'], '第五伦');
    expect(verdict.payload['to'], '第八矫');
  });

  test('rejects transient actions and routes implicit durable relations', () {
    final transient = validator.validate(
      kind: ReadingArtifactKinds.relationship,
      payload: const {
        'from': '甲',
        'to': '乙',
        'relation': '对话',
        'evidence': '甲与乙对话',
      },
      chapterContent: '甲与乙对话。',
    );
    expect(transient.status, FictionCandidateRuleStatus.rejected);

    final implicit = validator.validate(
      kind: ReadingArtifactKinds.relationship,
      payload: const {
        'from': '甲',
        'to': '乙',
        'relation': '盟友',
        'evidence': '甲与乙约定共同进退',
      },
      chapterContent: '甲与乙约定共同进退。',
    );
    expect(implicit.status, FictionCandidateRuleStatus.ambiguous);
  });

  test('normalizes narrator and assigns stable relation type', () {
    final narrator = FictionCandidateRuleValidator.normalizePayload(
      ReadingArtifactKinds.character,
      {
        'name': '我',
        'aliases': ['我'],
      },
    );
    expect(narrator['name'], '叙述者');
    expect(narrator['entityId'], 'narrator.primary');
    expect(narrator['role'], 'protagonist');

    final relation = FictionCandidateRuleValidator.normalizePayload(
      ReadingArtifactKinds.relationship,
      {
        'from': '圣兵哥',
        'to': '泽胜',
        'relation': '搭档',
      },
    );
    expect(relation['relationType'], 'partner');
  });

  test('normalizes event track and stage', () {
    final event = FictionCandidateRuleValidator.normalizePayload(
      ReadingArtifactKinds.event,
      {'eventType': '揭示'},
    );
    expect(event['track'], 'case');
    expect(event['stage'], 'revelation');
  });
}

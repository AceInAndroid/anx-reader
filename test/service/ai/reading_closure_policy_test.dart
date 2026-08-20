import 'package:anx_reader/service/ai/reading_ai_models.dart';
import 'package:anx_reader/service/ai/reading_closure_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const matcher = ReadingClosurePolicyMatcher();

  test('matches fiction, knowledge and psychology closures locally', () {
    expect(
      matcher
          .match(
            mode: ReadingAiMode.general,
            title: '长篇悬疑小说',
            description: '人物关系与故事',
          )
          .id,
      ReadingClosureIds.fictionImmersion,
    );
    expect(
      matcher
          .match(
            mode: ReadingAiMode.general,
            title: '经济学原理',
          )
          .id,
      ReadingClosureIds.knowledgeArgument,
    );
    expect(
      matcher
          .match(
            mode: ReadingAiMode.psychology,
            title: '心理学',
          )
          .id,
      ReadingClosureIds.psychologyReflection,
    );
  });

  test('pinned closure overrides metadata and exposes distinct behavior', () {
    final closure = matcher.match(
      mode: ReadingAiMode.general,
      title: '一部小说',
      pinnedId: ReadingClosureIds.knowledgeArgument,
    );
    expect(closure.id, ReadingClosureIds.knowledgeArgument);
    expect(closure.showMastery, isTrue);
    expect(closure.showKnowledgeCards, isTrue);
    expect(closure.defaultCreateKnowledgeCard, isFalse);

    expect(
      ReadingClosurePolicyRegistry.fictionImmersion.checkpointTriggersCapsule,
      isFalse,
    );
    expect(
      ReadingClosurePolicyRegistry.fictionImmersion.showMastery,
      isFalse,
    );
  });

  test('legacy enum and preference names map to stable ids', () {
    // ignore: deprecated_member_use_from_same_package
    expect(ReadingClosureType.fictionImmersion.stableId,
        ReadingClosureIds.fictionImmersion);
    expect(ReadingClosureIds.normalize('psychologyReflection'),
        ReadingClosureIds.psychologyReflection);
  });

  test('registry accepts a fourth module without changing matcher code', () {
    const fourth = ReadingClosurePolicyDefinition(
      id: 'history.evidence',
      title: '历史证据闭环',
      description: '测试扩展模块',
      goalLabel: '史料目标',
      goalTemplateSpecs: [
        ReadingGoalTemplateSpec(id: 'source', title: '核查一条史料'),
      ],
      checkpoint: ReadingCheckpointSpec(
        title: '史料检查',
        actionLabel: '核查',
        emptyText: '暂无',
        reflectionLabel: '争议',
        reflectionHelperText: '区分事实与解释',
        memoryTitleSuffix: '史料',
      ),
      outcomeSections: [
        ReadingOutcomeSectionSpec(
          id: 'goals',
          source: ReadingOutcomeSource.goals,
          title: '史料目标',
          emptyText: '暂无史料目标',
        ),
      ],
      quickPrompts: [
        ReadingQuickPromptSpec(
          id: 'source-check',
          label: '核查史料',
          prompt: '区分原始史料与解释。',
        ),
      ],
      systemGuidance: 'Separate sources from interpretations.',
    );
    const registry =
        ReadingClosurePolicyRegistry(additionalDefinitions: [fourth]);
    final matched = ReadingClosurePolicyMatcher(registry: registry).match(
      mode: ReadingAiMode.history,
      pinnedId: 'history.evidence',
    );
    expect(matched.id, 'history.evidence');
    expect(matched.goalTemplateSpecs.single.title, '核查一条史料');
    expect(matched.quickPrompts.single.label, '核查史料');
  });
}

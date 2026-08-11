import 'package:anx_reader/service/ai/reading_agent_orchestrator.dart';
import 'package:anx_reader/service/ai/reading_ai_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const orchestrator = ReadingAgentOrchestrator();

  test('simple questions stay with the primary assistant', () {
    final plan = orchestrator.plan('这句话是什么意思？', ReadingAiMode.general);
    expect(plan.usesExperts, isFalse);
  });

  test(
    'long selection explanations do not dispatch experts by length alone',
    () {
      final selection = List.filled(80, '这是一段需要结合上下文解释的划线内容。').join();
      final plan = orchestrator.plan(
        '解释这段内容中的关键概念和论证。\n\n选中文本：\n$selection',
        ReadingAiMode.history,
      );
      expect(plan.usesExperts, isFalse);
    },
  );

  test('complex mode tasks dispatch no more than two specialists', () {
    final plan = orchestrator.plan(
      '请核查这段历史叙述的典籍出处、证据冲突、数字和事件时间线。',
      ReadingAiMode.history,
    );
    expect(plan.agentIds, contains('history-specialist'));
    expect(plan.agentIds, contains('source-researcher'));
    expect(plan.agentIds.length, lessThanOrEqualTo(2));
  });

  test('analysis depth controls experts and research source task', () {
    const quick = ReadingAnalysisRequest(
      depth: ReadingAnalysisDepth.quick,
      frameworks: <ReadingFramework>[
        ReadingFramework.scqa,
        ReadingFramework.fiveWTwoH,
      ],
      outputTemplate: ReadingOutputTemplate.learningNote,
    );
    const research = ReadingAnalysisRequest(
      depth: ReadingAnalysisDepth.research,
      frameworks: <ReadingFramework>[
        ReadingFramework.criticalThinking,
        ReadingFramework.systemsThinking,
      ],
      outputTemplate: ReadingOutputTemplate.argumentAnalysis,
      allowWebSearch: true,
    );

    expect(
      orchestrator
          .plan('分析划线', ReadingAiMode.general, analysisRequest: quick)
          .agentIds,
      isEmpty,
    );
    final plan = orchestrator.plan(
      '研究这段内容',
      ReadingAiMode.history,
      analysisRequest: research,
    );
    expect(plan.agentIds.first, 'source-researcher');
    expect(plan.agentIds.length, 2);
  });
}

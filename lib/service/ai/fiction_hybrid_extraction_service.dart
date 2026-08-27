import 'dart:convert';

import 'package:anx_reader/models/ai_provider.dart';
import 'package:anx_reader/models/reading_agent.dart';
import 'package:anx_reader/service/ai/ai_context_assembler.dart';
import 'package:anx_reader/service/ai/ai_extraction_engine.dart';
import 'package:anx_reader/service/ai/ai_token_usage_service.dart';
import 'package:anx_reader/service/ai/index.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:langchain_core/chat_models.dart';

class FictionHybridExtractionService {
  FictionHybridExtractionService({required this.ref});

  final WidgetRef ref;
  int _baselineInputTokens = 0;
  int _cloudVerificationInputTokens = 0;
  final Set<String> _baselineFingerprints = {};

  static const maxCloudVerificationRatio = .20;

  static bool withinCloudVerificationBudget({
    required int baselineInputTokens,
    required int usedCloudInputTokens,
    required int nextCloudInputTokens,
  }) =>
      usedCloudInputTokens + nextCloudInputTokens <=
      (baselineInputTokens * maxCloudVerificationRatio).floor();

  AiProvider? get provider => aiExtractionEngine.resolveProvider(ref);

  Map<String, dynamic> get artifactMetadata => {
        'pipelineVersion': AiExtractionEngine.pipelineVersion,
        if (provider case final value?) ...{
          'extractorProvider': value.id,
          'extractorModel': value.model,
          'extractorDeployment': value.deployment.name,
        },
      };

  Future<String> generate(String prompt) async {
    final baseline = aiContextAssembler.estimateTokens(prompt);
    final fingerprint = sha256.convert(utf8.encode(prompt)).toString();
    if (_baselineFingerprints.add(fingerprint)) {
      _baselineInputTokens += baseline;
      aiTokenUsageService.recordStorySavings(
        baselineInputTokens: baseline,
        cloudInputTokens: 0,
      );
    }
    final result = await aiExtractionEngine.extract(
      taskId: AiExtractionTaskIds.fictionStoryAtlas,
      prompt: prompt,
      ref: ref,
    );
    if (!result.isValid) {
      throw FormatException(result.validationErrors.join('；'));
    }
    return result.raw;
  }

  Future<Map<String, dynamic>?> validate({
    required String kind,
    required Map<String, dynamic> payload,
    required String chapterContent,
  }) async {
    final verdict = const FictionCandidateRuleValidator().validate(
      kind: kind,
      payload: payload,
      chapterContent: chapterContent,
    );
    if (verdict.status == FictionCandidateRuleStatus.rejected) return null;
    if (verdict.status == FictionCandidateRuleStatus.accepted) {
      return verdict.payload;
    }
    return _verifyAmbiguous(
      verdict.payload,
      verdict.payload['evidence']?.toString() ?? '',
    );
  }

  Future<Map<String, dynamic>?> _verifyAmbiguous(
    Map<String, dynamic> payload,
    String evidence,
  ) async {
    final prompt = '''你只复核一条小说人物关系候选，不得使用证据之外的知识。
候选：${jsonEncode(payload)}
原文证据：${jsonEncode(evidence)}
只返回 JSON：{"decision":"accept|reject|normalize","relation":"必要时的简短中文关系"}。
不得新增人物、证据或关系事实。''';
    try {
      final cloudInput = aiContextAssembler.estimateTokens(prompt);
      if (!withinCloudVerificationBudget(
        baselineInputTokens: _baselineInputTokens,
        usedCloudInputTokens: _cloudVerificationInputTokens,
        nextCloudInputTokens: cloudInput,
      )) {
        return null;
      }
      _cloudVerificationInputTokens += cloudInput;
      aiTokenUsageService.recordStorySavings(
        baselineInputTokens: 0,
        cloudInputTokens: cloudInput,
      );
      final generated = await aiTokenUsageService.runWithRole(
        AiTokenUsageRole.cloudVerification,
        () => aiGenerateTextWithMetadata(
          [ChatMessage.humanText(prompt)],
          ref: ref,
          task: AiContextTask.cloudVerification,
        ),
      );
      final decoded = _decodeObject(generated.value);
      final decision = decoded['decision']?.toString();
      if (decision == 'reject') return null;
      if (decision != 'accept' && decision != 'normalize') return null;
      final normalized = decoded['relation']?.toString().trim() ?? '';
      return {
        ...payload,
        if (decision == 'normalize' && normalized.isNotEmpty)
          'relation': normalized,
        'confidenceSource': 'cloudVerified',
        'reviewStatus': decision,
        if (generated.providerId != null)
          'reviewProvider': generated.providerId,
        if (generated.model != null) 'reviewModel': generated.model,
      };
    } catch (_) {
      // Keep an ambiguous item pending instead of weakening privacy or
      // silently accepting it after the verifier failed.
      return null;
    }
  }

  Map<String, dynamic> _decodeObject(String raw) {
    final start = raw.indexOf('{');
    final end = raw.lastIndexOf('}');
    if (start < 0 || end <= start) throw const FormatException('Invalid JSON');
    return Map<String, dynamic>.from(
      jsonDecode(raw.substring(start, end + 1)) as Map,
    );
  }
}

enum FictionCandidateRuleStatus { accepted, ambiguous, rejected }

class FictionCandidateRuleVerdict {
  const FictionCandidateRuleVerdict(this.status, this.payload);
  final FictionCandidateRuleStatus status;
  final Map<String, dynamic> payload;
}

class FictionCandidateRuleValidator {
  const FictionCandidateRuleValidator();

  FictionCandidateRuleVerdict validate({
    required String kind,
    required Map<String, dynamic> payload,
    required String chapterContent,
  }) {
    FictionCandidateRuleVerdict reject() => FictionCandidateRuleVerdict(
        FictionCandidateRuleStatus.rejected, payload);
    final evidence = payload['evidence']?.toString().trim() ?? '';
    if (evidence.isEmpty ||
        evidence.length > 80 ||
        !chapterContent.contains(evidence)) {
      return reject();
    }
    if (kind == ReadingArtifactKinds.character) {
      final name = payload['name']?.toString().trim() ?? '';
      if (_genericNames.contains(name) || name.length < 2) return reject();
      if (_looksLikeBackgroundReference(evidence)) return reject();
      return FictionCandidateRuleVerdict(
        FictionCandidateRuleStatus.accepted,
        {...payload, 'confidenceSource': 'evidenceValidated'},
      );
    }
    if (kind == ReadingArtifactKinds.event) {
      return FictionCandidateRuleVerdict(
        FictionCandidateRuleStatus.accepted,
        {...payload, 'confidenceSource': 'evidenceValidated'},
      );
    }
    if (kind != ReadingArtifactKinds.relationship) return reject();
    final relation = payload['relation']?.toString().trim() ?? '';
    if (_transientRelations.any(relation.contains) ||
        !_durableRelations.any(relation.contains)) {
      return reject();
    }
    if (_explicitRelationTerms.any(evidence.contains)) {
      return FictionCandidateRuleVerdict(
        FictionCandidateRuleStatus.accepted,
        {
          ...payload,
          'confidenceSource': 'explicitText',
          'reviewStatus': 'ruleAccepted',
        },
      );
    }
    return FictionCandidateRuleVerdict(
      FictionCandidateRuleStatus.ambiguous,
      payload,
    );
  }

  bool _looksLikeBackgroundReference(String evidence) => const [
        '曾言',
        '两百年前',
        '之后',
        '被称为',
        '典故',
        '书中记载',
      ].any(evidence.contains);

  static const _genericNames = {
    '县宰',
    '长平县宰',
    '诸生',
    '吏卒',
    '士卒',
    '百姓',
    '少年',
    '侍从',
    '众人',
  };
  static const _transientRelations = ['对话', '问', '看', '同行', '点头', '相遇'];
  static const _durableRelations = [
    '父',
    '母',
    '子',
    '女',
    '兄',
    '弟',
    '姐',
    '妹',
    '祖',
    '孙',
    '夫妻',
    '婚',
    '亲属',
    '同宗',
    '师生',
    '师徒',
    '主从',
    '君臣',
    '同僚',
    '朋友',
    '盟友',
    '对手',
    '敌对',
    '雇佣',
    '上下级',
  ];
  static const _explicitRelationTerms = [
    '父亲',
    '母亲',
    '儿子',
    '女儿',
    '兄长',
    '兄弟',
    '姐妹',
    '祖父',
    '孙儿',
    '夫妻',
    '妻子',
    '丈夫',
    '同宗',
    '师父',
    '弟子',
    '同僚',
    '盟友',
    '敌人',
    '对手',
    '仇人',
    '上司',
    '下属',
    '主人',
    '仆从',
  ];
}

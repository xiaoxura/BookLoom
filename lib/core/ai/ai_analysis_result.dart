import 'dart:convert';

import 'package:bookloom/core/ai/ai_chapter_split_decoder.dart';
import 'package:bookloom/core/ai/ai_context.dart';
import 'package:bookloom/core/ai/ai_json.dart';
import 'package:bookloom/core/editing/ai_chapter_split_proposal.dart';
import 'package:bookloom/core/editing/ai_text_proposal.dart';
import 'package:bookloom/core/editing/proofreading_finding.dart';
import 'package:bookloom/core/editing/proofreading_rule.dart';
import 'package:bookloom/core/errors/app_failure.dart';

final class AiRuleRequest {
  AiRuleRequest({
    required this.kind,
    required List<String> positiveExamples,
    required List<String> negativeExamples,
  }) : positiveExamples = List<String>.unmodifiable(positiveExamples),
       negativeExamples = List<String>.unmodifiable(negativeExamples);

  final ProofreadingRuleKind kind;
  final List<String> positiveExamples;
  final List<String> negativeExamples;

  void validate({AiContextChunk? context}) {
    if (positiveExamples.isEmpty ||
        positiveExamples.length > ProofreadingRule.maxExamplesPerPolarity ||
        negativeExamples.length > ProofreadingRule.maxExamplesPerPolarity ||
        positiveExamples.toSet().length != positiveExamples.length ||
        negativeExamples.toSet().length != negativeExamples.length ||
        positiveExamples.any(negativeExamples.contains)) {
      throw const ValidationFailure('AI 规则正反例数量无效、重复或相互冲突。');
    }
    var characters = 0;
    for (final sample in [...positiveExamples, ...negativeExamples]) {
      characters += sample.length;
      if (sample.trim().isEmpty ||
          sample.length > ProofreadingRule.maxExampleUtf16 ||
          RegExp(r'[\r\n\u2028\u2029]').hasMatch(sample) ||
          characters > ProofreadingRule.maxPatternAndExamplesUtf16) {
        throw const ValidationFailure('AI 规则样例无效或超出请求预算。');
      }
      for (var index = 0; index < sample.length; index++) {
        final code = sample.codeUnitAt(index);
        if (code >= 0xd800 && code <= 0xdbff) {
          if (++index >= sample.length) {
            throw const ValidationFailure('AI 规则样例包含无效字符。');
          }
          final next = sample.codeUnitAt(index);
          if (next < 0xdc00 || next > 0xdfff) {
            throw const ValidationFailure('AI 规则样例包含无效字符。');
          }
        } else if (code >= 0xdc00 && code <= 0xdfff) {
          throw const ValidationFailure('AI 规则样例包含无效字符。');
        }
      }
    }
    if (context != null && !isCoveredBy(context)) {
      throw const ValidationFailure('所有正例必须完整位于同一发送片段的正文核心中。');
    }
  }

  bool isCoveredBy(AiContextChunk context) => positiveExamples.every(
    (sample) => context.slices.any((slice) => slice.text.contains(sample)),
  );

  Map<String, Object> toJson() => {
    'kind': kind.name,
    'positive_examples': positiveExamples,
    'negative_examples': negativeExamples,
  };
}

final class AiAnalysisResult {
  AiAnalysisResult._({
    required this.responseId,
    required this.context,
    required List<Finding> findings,
    required this.textChanges,
    required Map<String, String> findingIdByTextProposalId,
    required List<AiChapterSplitProposal> chapterSplits,
    required Map<String, String> findingIdBySplitProposalId,
    required List<RuleProposal> ruleProposals,
  }) : findings = List<Finding>.unmodifiable(findings),
       findingIdByTextProposalId = Map<String, String>.unmodifiable(
         findingIdByTextProposalId,
       ),
       chapterSplits = List<AiChapterSplitProposal>.unmodifiable(chapterSplits),
       findingIdBySplitProposalId = Map<String, String>.unmodifiable(
         findingIdBySplitProposalId,
       ),
       ruleProposals = List<RuleProposal>.unmodifiable(ruleProposals);

  final String responseId;
  final AiContextChunk context;
  final List<Finding> findings;
  final AiTextProposalResult textChanges;
  final Map<String, String> findingIdByTextProposalId;
  final List<AiChapterSplitProposal> chapterSplits;
  final Map<String, String> findingIdBySplitProposalId;
  final List<RuleProposal> ruleProposals;
}

abstract final class AiAnalysisResultDecoder {
  static AiAnalysisResult decode(
    String response, {
    required AiContextChunk context,
    required String responseId,
    AiRuleRequest? ruleRequest,
  }) {
    ruleRequest?.validate(context: context);
    if (response.length > 65536 ||
        !RegExp(r'^[a-zA-Z0-9_-]{1,64}$').hasMatch(responseId)) {
      _invalidResult();
    }
    final Object? decoded;
    try {
      decoded = decodeStrictAiJson(response);
    } on FormatException {
      _invalidResult();
    }
    const keys = {'schema_version', 'findings', 'proposals', 'rule_proposals'};
    if (decoded is! Map<String, dynamic> ||
        decoded.length != keys.length ||
        !keys.every(decoded.containsKey) ||
        decoded['schema_version'] is! int ||
        decoded['schema_version'] != 1 ||
        decoded['findings'] is! List ||
        decoded['proposals'] is! List ||
        decoded['rule_proposals'] is! List) {
      _invalidResult();
    }
    final findingValues = decoded['findings'] as List;
    final proposalValues = decoded['proposals'] as List;
    final ruleValues = decoded['rule_proposals'] as List;
    if (findingValues.length + proposalValues.length + ruleValues.length >
            100 ||
        ruleValues.length > 4 ||
        ruleValues.isNotEmpty && ruleRequest == null) {
      _invalidResult();
    }
    final findings = AiFindingDecoder.decode(
      jsonEncode({'schema_version': 1, 'findings': findingValues}),
      context: context,
    );
    final normalizedTextValues = <Map<String, dynamic>>[];
    final textFindingIds = <String>[];
    final normalizedSplitValues = <Map<String, dynamic>>[];
    final splitFindingIds = <String>[];
    for (final value in proposalValues) {
      if (value is! Map<String, dynamic> ||
          value['finding_id'] is! String ||
          value['action'] is! String) {
        _invalidResult();
      }
      final normalized = Map<String, dynamic>.of(value)..remove('finding_id');
      switch (value['action']) {
        case 'delete_text' ||
            'replace_text' ||
            'remove_block' ||
            'rename_chapter':
          textFindingIds.add(value['finding_id'] as String);
          normalizedTextValues.add(normalized);
          break;
        case 'split_chapter':
          splitFindingIds.add(value['finding_id'] as String);
          normalizedSplitValues.add(normalized);
          break;
        default:
          _invalidResult();
      }
    }
    final textChanges = AiTextProposalDecoder.decode(
      jsonEncode({'schema_version': 1, 'proposals': normalizedTextValues}),
      context: context,
    );
    final chapterSplits = AiChapterSplitDecoder.decode(
      jsonEncode({'schema_version': 1, 'proposals': normalizedSplitValues}),
      context: context,
    );
    final ids = findings.map((finding) => finding.id).toSet();
    final findingsById = {for (final finding in findings) finding.id: finding};
    final findingIdByTextProposalId = <String, String>{};
    for (final (index, change) in textChanges.proposals.indexed) {
      if (!ids.add(change.id)) _invalidResult();
      final finding = findingsById[textFindingIds[index]];
      if (finding == null ||
          finding.chapterId != change.target.chapterId ||
          finding.blockId != change.target.blockId ||
          finding.range!.start > change.range.start ||
          finding.range!.end < change.range.end ||
          !(change.action == AiTextProposalAction.renameChapter
              ? change.originalTitle != null &&
                    finding.kind == FindingKind.missingChapter &&
                    finding.assessment == FindingAssessment.missedHeading
              : finding.kind == FindingKind.advertisement &&
                        finding.assessment == FindingAssessment.advertisement ||
                    change.action != AiTextProposalAction.removeBlock &&
                        finding.kind == FindingKind.other &&
                        finding.assessment == FindingAssessment.observed)) {
        _invalidResult();
      }
      findingIdByTextProposalId[change.id] = finding.id;
      for (final finding in findings) {
        if (finding.chapterId == change.target.chapterId &&
            finding.blockId == change.target.blockId &&
            finding.range!.overlaps(change.range) &&
            const {
              FindingAssessment.undetermined,
              FindingAssessment.suspectedMissing,
              FindingAssessment.numberingSuspect,
              FindingAssessment.authorNote,
              FindingAssessment.storyQuote,
              FindingAssessment.notAdvertisement,
            }.contains(finding.assessment)) {
          _invalidResult();
        }
      }
    }
    final findingIdBySplitProposalId = <String, String>{};
    for (final (index, split) in chapterSplits.indexed) {
      if (!ids.add(split.id)) _invalidResult();
      final finding = findingsById[splitFindingIds[index]];
      if (finding == null ||
          finding.chapterId != split.target.chapterId ||
          finding.blockId != split.target.blockId ||
          finding.range!.start > split.range.start ||
          finding.range!.end < split.range.end ||
          !(finding.assessment == FindingAssessment.missedHeading ||
              finding.assessment == FindingAssessment.mergedContent) ||
          !(finding.kind == FindingKind.missingChapter ||
              finding.kind == FindingKind.missedHeading)) {
        _invalidResult();
      }
      findingIdBySplitProposalId[split.id] = finding.id;
      final slice = context.slices.singleWhere(
        (slice) => slice.block.blockId == split.target.blockId,
      );
      final titleLine = split.titleLineIn(slice.block.text, split.range);
      for (final evidence in findings) {
        if (evidence.chapterId == split.target.chapterId &&
            evidence.blockId == split.target.blockId &&
            evidence.range!.overlaps(titleLine) &&
            const {
              FindingAssessment.undetermined,
              FindingAssessment.suspectedMissing,
              FindingAssessment.numberingSuspect,
              FindingAssessment.authorNote,
              FindingAssessment.storyQuote,
              FindingAssessment.notAdvertisement,
            }.contains(evidence.assessment)) {
          _invalidResult();
        }
      }
    }
    final rules = <RuleProposal>[];
    if (ruleValues.isNotEmpty) {
      final request = ruleRequest!;
      for (final (index, value) in ruleValues.indexed) {
        final proposal = RuleProposalDecoder.decode(
          jsonEncode(value),
          proposalId: '$responseId-rule-$index',
          ruleId: '$responseId-candidate-$index',
          bookId: context.bookId,
          source: ProofreadingRuleSource.ai,
          requiredPositiveExamples: request.positiveExamples,
          requiredNegativeExamples: request.negativeExamples,
        );
        if (proposal.rule.kind != request.kind ||
            !ids.add(proposal.proposalId) ||
            !ids.add(proposal.rule.id)) {
          _invalidResult();
        }
        rules.add(proposal);
      }
    }
    return AiAnalysisResult._(
      responseId: responseId,
      context: context,
      findings: findings,
      textChanges: textChanges,
      findingIdByTextProposalId: findingIdByTextProposalId,
      chapterSplits: chapterSplits,
      findingIdBySplitProposalId: findingIdBySplitProposalId,
      ruleProposals: rules,
    );
  }
}

Never _invalidResult() =>
    throw const ValidationFailure('AI 校对结果验证失败，未修改书稿；请重新分析或缩小范围。');

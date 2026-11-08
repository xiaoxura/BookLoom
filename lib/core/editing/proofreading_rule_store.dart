import 'dart:convert';

import 'proofreading_rule.dart';

final class RuleMergeResult {
  const RuleMergeResult({required this.addedIds, required this.skippedIds});

  final List<String> addedIds;
  final List<String> skippedIds;
}

abstract class ProofreadingRuleStore {
  Future<List<ProofreadingRule>> loadForBook(String bookId);

  /// Adds rules whose IDs are absent and never overwrites existing rules.
  ///
  /// Used by backup restore: definitions are preserved, but nothing is
  /// selected, enabled or run implicitly.
  Future<RuleMergeResult> mergeMissing(
    List<ProofreadingRule> rules, {
    bool Function()? isCurrent,
  });

  Future<void> save(
    ProofreadingRule rule, {
    bool Function()? isCurrent,
    Map<String, ProofreadingRule?>? expectedRules,
  });

  Future<void> delete(
    String ruleId, {
    bool Function()? isCurrent,
    Map<String, ProofreadingRule?>? expectedRules,
  });

  /// Runs a synchronous action only while the expected rules are current.
  Future<void> runIfCurrent(
    Map<String, ProofreadingRule?> expectedRules,
    void Function() action, {
    bool Function()? isCurrent,
  });
}

String proofreadingRuleFingerprint(ProofreadingRule rule) => jsonEncode([
  rule.id,
  rule.name,
  rule.kind.name,
  rule.enabled,
  rule.source.name,
  rule.scope.name,
  rule.bookId,
  rule.target.name,
  rule.mode.name,
  rule.pattern,
  if (rule.excludePattern != null) {'exclude': rule.excludePattern},
  if (rule.wholeLineOnly) {'whole_line': true},
  rule.caseSensitive,
  rule.action.name,
  rule.priority,
  rule.positiveExamples,
  rule.negativeExamples,
  if (rule.titleCaptureGroup != null) rule.titleCaptureGroup,
  if (rule.headingLevel != 2) {'heading_level': rule.headingLevel},
  if (rule.numberCaptureGroup != null)
    {'number_capture_group': rule.numberCaptureGroup},
]);

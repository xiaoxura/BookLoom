import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../core/editing/proofreading_rule.dart';
import '../core/editing/proofreading_rule_store.dart';
import '../features/editor/application/editor_session.dart';
import '../features/editor/application/rule_workbench_task.dart';
import '../features/editor/data/proofreading_rule_store.dart';
import 'providers.dart';

final proofreadingRuleStoreProvider = Provider<ProofreadingRuleStore>(
  (ref) => SettingsProofreadingRuleStore(ref.watch(databaseProvider)),
  name: 'proofreadingRuleStore',
);

final ruleWorkbenchTaskProvider = ChangeNotifierProvider.autoDispose
    .family<RuleWorkbenchTask, EditorSession>((ref, session) {
      return RuleWorkbenchTask(
        session: session,
        store: _DeferredRuleStore(
          () => ref.read(proofreadingRuleStoreProvider),
        ),
      );
    }, name: 'ruleWorkbenchTask');

class _DeferredRuleStore implements ProofreadingRuleStore {
  const _DeferredRuleStore(this._resolve);

  final ProofreadingRuleStore Function() _resolve;

  @override
  Future<List<ProofreadingRule>> loadForBook(String bookId) =>
      _resolve().loadForBook(bookId);

  @override
  Future<RuleMergeResult> mergeMissing(
    List<ProofreadingRule> rules, {
    bool Function()? isCurrent,
  }) => _resolve().mergeMissing(rules, isCurrent: isCurrent);

  @override
  Future<void> save(
    ProofreadingRule rule, {
    bool Function()? isCurrent,
    Map<String, ProofreadingRule?>? expectedRules,
  }) =>
      _resolve().save(rule, isCurrent: isCurrent, expectedRules: expectedRules);

  @override
  Future<void> delete(
    String ruleId, {
    bool Function()? isCurrent,
    Map<String, ProofreadingRule?>? expectedRules,
  }) => _resolve().delete(
    ruleId,
    isCurrent: isCurrent,
    expectedRules: expectedRules,
  );

  @override
  Future<void> runIfCurrent(
    Map<String, ProofreadingRule?> expectedRules,
    void Function() action, {
    bool Function()? isCurrent,
  }) => _resolve().runIfCurrent(expectedRules, action, isCurrent: isCurrent);
}

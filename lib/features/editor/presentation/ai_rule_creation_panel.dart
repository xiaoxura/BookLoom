import 'dart:async';

import 'package:bookloom/app/ai_rule_providers.dart';
import 'package:bookloom/core/ai/ai_endpoint.dart';
import 'package:bookloom/core/editing/proofreading_rule.dart';
import 'package:bookloom/design/tokens/app_metrics.dart';
import 'package:bookloom/features/editor/application/ai_rule_creation_task.dart';
import 'package:bookloom/features/editor/application/editor_session.dart';
import 'package:bookloom/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AiRuleCreationPanel extends ConsumerStatefulWidget {
  const AiRuleCreationPanel({
    super.key,
    required this.session,
    required this.selection,
    required this.initialKind,
    required this.onUseRule,
  });

  final EditorSession session;
  final AiRuleSelection selection;
  final ProofreadingRuleKind initialKind;
  final ValueChanged<ProofreadingRule> onUseRule;

  @override
  ConsumerState<AiRuleCreationPanel> createState() =>
      _AiRuleCreationPanelState();
}

class _AiRuleCreationPanelState extends ConsumerState<AiRuleCreationPanel> {
  final _intent = TextEditingController();
  final _negative = TextEditingController();
  late ProofreadingRuleKind _kind;
  AiRuleCreationTask? _task;

  @override
  void initState() {
    super.initState();
    _kind = widget.initialKind;
  }

  @override
  void didUpdateWidget(covariant AiRuleCreationPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session != widget.session ||
        !_sameSelection(oldWidget.selection, widget.selection) ||
        oldWidget.initialKind != widget.initialKind) {
      _task?.cancel();
      _task = null;
      _kind = widget.initialKind;
      _intent.clear();
      _negative.clear();
    }
  }

  @override
  void dispose() {
    final task = _task;
    if (task != null && task.isBusy) scheduleMicrotask(task.cancel);
    _intent.dispose();
    _negative.dispose();
    super.dispose();
  }

  void _inputChanged(AiRuleCreationTask task) {
    if (task.phase != AiRuleCreationPhase.idle) task.cancel();
    setState(() {});
  }

  List<String> get _negativeExamples => _negative.text
      .split(RegExp(r'\r\n|\n|\r'))
      .where((example) => example.trim().isNotEmpty)
      .toList();

  Future<void> _prepare(AiRuleCreationTask task) => task.prepare(
    selection: widget.selection,
    kind: _kind,
    intent: _intent.text,
    negativeExamples: _negativeExamples,
    relatedRules: const [],
  );

  void _use(AiRuleCreationTask task, RuleProposal proposal) {
    final consent = task.consent;
    if (!identical(_task, task) ||
        !task.canUseProposals ||
        consent == null ||
        !task.proposals.any((current) => identical(current, proposal)) ||
        consent.chunk.sessionId != widget.session.sessionId ||
        consent.chunk.sessionRevision != widget.session.saveSeq ||
        consent.chunk.bookId != widget.session.book?.id) {
      return;
    }
    widget.onUseRule(proposal.rule);
  }

  @override
  Widget build(BuildContext context) {
    final task = ref.watch(aiRuleCreationTaskProvider(widget.session));
    _task = task;
    final consent = task.phase == AiRuleCreationPhase.awaitingConsent
        ? task.consent
        : null;
    final canPrepare =
        !task.isBusy &&
        _intent.text.trim().isNotEmpty &&
        _intent.text.length <= 1024;
    final proposals = task.phase == AiRuleCreationPhase.completed
        ? task.proposals
        : const <RuleProposal>[];

    return ListView.builder(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.xl,
        AppSpacing.xl,
        AppSpacing.xl + MediaQuery.viewInsetsOf(context).bottom,
      ),
      itemCount: 1 + proposals.length,
      itemBuilder: (context, index) {
        if (index == 0) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _controls(context, task, canPrepare),
              if (consent != null) _review(context, task, consent),
            ],
          );
        }
        return _proposal(context, task, proposals[index - 1]);
      },
    );
  }

  Widget _controls(
    BuildContext context,
    AiRuleCreationTask task,
    bool canPrepare,
  ) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.aiRuleTitle, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: AppSpacing.md),
        Text(l10n.aiRuleSelected),
        SelectableText(widget.selection.original),
        const SizedBox(height: AppSpacing.md),
        DropdownButtonFormField<ProofreadingRuleKind>(
          key: const ValueKey('ai-rule-kind'),
          initialValue: _kind,
          isExpanded: true,
          decoration: InputDecoration(labelText: l10n.ruleWorkbenchKind),
          items: [
            DropdownMenuItem(
              value: ProofreadingRuleKind.chapter,
              child: Text(l10n.ruleWorkbenchChapter),
            ),
            DropdownMenuItem(
              value: ProofreadingRuleKind.advertisement,
              child: Text(l10n.ruleWorkbenchAdvertisement),
            ),
          ],
          onChanged: task.isBusy
              ? null
              : (value) {
                  if (value == null || value == _kind) return;
                  _kind = value;
                  _inputChanged(task);
                },
        ),
        TextField(
          key: const ValueKey('ai-rule-intent'),
          controller: _intent,
          maxLength: 1024,
          maxLines: 3,
          decoration: InputDecoration(labelText: l10n.aiRuleIntent),
          onChanged: (_) => _inputChanged(task),
        ),
        TextField(
          key: const ValueKey('ai-rule-negative'),
          controller: _negative,
          maxLines: 4,
          decoration: InputDecoration(
            labelText: l10n.aiRuleNegative,
            helperText: l10n.ruleWorkbenchOnePerLine,
          ),
          onChanged: (_) => _inputChanged(task),
        ),
        FilledButton.tonalIcon(
          key: const ValueKey('ai-rule-prepare'),
          onPressed: canPrepare ? () => unawaited(_prepare(task)) : null,
          icon: const Icon(Icons.visibility_outlined),
          label: Text(l10n.aiProofreadingPrepare),
        ),
        if (task.phase != AiRuleCreationPhase.idle) ...[
          const SizedBox(height: AppSpacing.md),
          Text('${l10n.aiProofreadingPhase}: ${_phaseLabel(l10n, task.phase)}'),
        ],
        if (task.isBusy) ...[
          const LinearProgressIndicator(),
          TextButton.icon(
            key: const ValueKey('ai-rule-cancel'),
            onPressed: task.cancel,
            icon: const Icon(Icons.close),
            label: Text(l10n.editorWorkbenchCancelTask),
          ),
        ],
        if (task.failure case final failure?)
          Text(
            [
              failure.message,
              if (failure.hint != null) failure.hint!,
            ].join(' '),
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        if (task.phase == AiRuleCreationPhase.completed &&
            task.proposals.isEmpty)
          Text(l10n.aiRuleNoProposals),
      ],
    );
  }

  Widget _review(
    BuildContext context,
    AiRuleCreationTask task,
    AiRuleCreationConsent consent,
  ) {
    final l10n = AppLocalizations.of(context);
    final slice = consent.chunk.slices.single;
    final config = consent.configuration;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: AppSpacing.xxl),
        Text(
          l10n.aiProofreadingReview,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        _detail(l10n.aiRequestAddress, config.endpoint.requestUri.toString()),
        _detail(l10n.aiFormat, _formatLabel(config.format)),
        _detail(l10n.aiModel, config.model),
        _detail(l10n.aiRuleIntent, consent.intent),
        _detail(l10n.aiRuleChapterTitle, slice.block.chapterTitle),
        _detail(l10n.aiRuleBefore, slice.before),
        _detail(l10n.aiRuleSelected, slice.text),
        _detail(l10n.aiRuleAfter, slice.after),
        Text(l10n.ruleWorkbenchPositive),
        for (final example in consent.request.positiveExamples)
          SelectableText(example),
        Text(l10n.ruleWorkbenchNegative),
        for (final example in consent.request.negativeExamples)
          SelectableText(example),
        Text('${l10n.aiRuleRelated}: ${consent.relatedRules.length}'),
        for (final rule in consent.relatedRules)
          _detail(
            rule.name,
            '${rule.kind.name} · ${rule.target.name} · ${rule.mode.name} · ${rule.pattern} · ${rule.action.name}',
          ),
        const SizedBox(height: AppSpacing.sm),
        FilledButton.icon(
          key: const ValueKey('ai-rule-send'),
          onPressed: task.isBusy ? null : () => unawaited(task.run(consent)),
          icon: const Icon(Icons.send_outlined),
          label: Text(l10n.aiProofreadingStart),
        ),
        Text(l10n.aiProofreadingCancelCost),
      ],
    );
  }

  Widget _proposal(
    BuildContext context,
    AiRuleCreationTask task,
    RuleProposal proposal,
  ) {
    final l10n = AppLocalizations.of(context);
    final rule = proposal.rule;
    return ExpansionTile(
      key: ValueKey('ai-rule-proposal-${proposal.proposalId}'),
      title: Text(rule.name),
      subtitle: Text(
        '${l10n.ruleWorkbenchAiSource} · ${l10n.ruleWorkbenchBookScope}',
      ),
      children: [
        Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _detail(l10n.aiProofreadingReason, proposal.reason),
              _detail(l10n.ruleWorkbenchName, rule.name),
              _detail(l10n.ruleWorkbenchKind, rule.kind.name),
              _detail(l10n.ruleWorkbenchTarget, rule.target.name),
              _detail(l10n.ruleWorkbenchMode, rule.mode.name),
              _detail(l10n.ruleWorkbenchPattern, rule.pattern),
              _detail(l10n.ruleWorkbenchAction, rule.action.name),
              Text(l10n.ruleWorkbenchPositive),
              for (final example in rule.positiveExamples)
                SelectableText(example),
              Text(l10n.ruleWorkbenchNegative),
              for (final example in rule.negativeExamples)
                SelectableText(example),
              FilledButton.tonalIcon(
                key: ValueKey('ai-rule-use-${proposal.proposalId}'),
                onPressed: task.canUseProposals
                    ? () => _use(task, proposal)
                    : null,
                icon: const Icon(Icons.rule),
                label: Text(l10n.aiRuleCheckAndTrial),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _detail(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [Text(label), SelectableText(value)],
    ),
  );
}

String _formatLabel(AiEndpointFormat format) => switch (format) {
  AiEndpointFormat.openAiChatCompletions => 'OpenAI Chat Completions',
  AiEndpointFormat.openAiResponses => 'OpenAI Responses',
  AiEndpointFormat.claudeMessages => 'Claude Messages',
};

bool _sameSelection(AiRuleSelection left, AiRuleSelection right) =>
    left.chapterId == right.chapterId &&
    left.blockId == right.blockId &&
    left.startUtf16 == right.startUtf16 &&
    left.endUtf16 == right.endUtf16 &&
    left.original == right.original;

String _phaseLabel(AppLocalizations l10n, AiRuleCreationPhase phase) =>
    switch (phase) {
      AiRuleCreationPhase.idle => l10n.aiProofreadingIdle,
      AiRuleCreationPhase.preparing => l10n.aiProofreadingPreparing,
      AiRuleCreationPhase.awaitingConsent => l10n.aiProofreadingAwaitingConsent,
      AiRuleCreationPhase.running => l10n.aiRuleRunning,
      AiRuleCreationPhase.completed => l10n.aiRuleCompleted,
      AiRuleCreationPhase.cancelled => l10n.aiProofreadingCancelled,
      AiRuleCreationPhase.stale => l10n.aiProofreadingStale,
      AiRuleCreationPhase.failed => l10n.aiProofreadingFailed,
    };

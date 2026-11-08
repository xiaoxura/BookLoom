import 'dart:async';

import 'package:bookloom/app/ai_providers.dart';
import 'package:bookloom/core/ai/ai_analysis_result.dart';
import 'package:bookloom/core/ai/ai_proofreading_prompt.dart';
import 'package:bookloom/core/editing/ai_text_proposal.dart';
import 'package:bookloom/core/editing/proofreading_finding.dart';
import 'package:bookloom/core/editing/proofreading_rule.dart';
import 'package:bookloom/core/model/block.dart';
import 'package:bookloom/core/model/chapter.dart';
import 'package:bookloom/design/tokens/app_metrics.dart';
import 'package:bookloom/features/editor/application/ai_advertisement_request.dart';
import 'package:bookloom/features/editor/application/ai_audit_gap_request.dart';
import 'package:bookloom/features/editor/application/ai_proofreading_task.dart';
import 'package:bookloom/features/editor/application/editor_session.dart';
import 'package:bookloom/l10n/app_localizations.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AiProofreadingPanel extends ConsumerStatefulWidget {
  const AiProofreadingPanel({
    super.key,
    required this.session,
    required this.onLocate,
    this.initialAuditGap,
    this.initialAdvertisementSelection,
    this.onUseRule,
  });

  final EditorSession session;
  final Future<void> Function(String chapterId, String? blockId) onLocate;
  final AiAuditGapRequest? initialAuditGap;
  final AiAdvertisementRequest? initialAdvertisementSelection;
  final ValueChanged<ProofreadingRule>? onUseRule;

  @override
  ConsumerState<AiProofreadingPanel> createState() =>
      _AiProofreadingPanelState();
}

class _AiProofreadingPanelState extends ConsumerState<AiProofreadingPanel> {
  final _positiveExamples = TextEditingController();
  final _negativeExamples = TextEditingController();
  bool _requestRules = false;
  AiRuleRequest? _preparedRuleRequest;

  List<String> _examples(TextEditingController controller) => controller.text
      .split(RegExp(r'\r\n|\n|\r'))
      .where((example) => example.trim().isNotEmpty)
      .toList();

  bool get _validRuleExamples {
    final positive = _examples(_positiveExamples);
    final negative = _examples(_negativeExamples);
    return positive.isNotEmpty &&
        positive.length <= 12 &&
        negative.length <= 12 &&
        [...positive, ...negative].every((example) => example.length <= 2048) &&
        [
              ...positive,
              ...negative,
            ].fold<int>(0, (sum, example) => sum + example.length) <=
            8192;
  }

  void _ruleInputChanged(AiProofreadingTask task, VoidCallback update) {
    if (!identical(_task, task)) return;
    task.cancel();
    setState(() {
      update();
      _preparedRuleRequest = null;
      _preparedIntent = null;
      _preparedChapterIds = const {};
      _selectedChanges.clear();
    });
  }

  void _useRule(AiProofreadingTask task, RuleProposal proposal) {
    final consent = task.consent;
    if (!mounted ||
        !identical(_task, task) ||
        !task.canUseRuleProposals ||
        consent == null ||
        !identical(consent.ruleRequest, _preparedRuleRequest) ||
        !task.ruleProposals.any((current) => identical(current, proposal)) ||
        consent.plan.chunks.any(
          (chunk) =>
              chunk.bookId != widget.session.book?.id ||
              chunk.sessionId != widget.session.sessionId ||
              chunk.sessionRevision != widget.session.saveSeq,
        )) {
      return;
    }
    widget.onUseRule?.call(proposal.rule);
  }

  AiProofreadingIntent _intent = AiProofreadingIntent.advertisement;
  late Set<String> _chapterIds;
  Set<String> _preparedChapterIds = const <String>{};
  AiProofreadingIntent? _preparedIntent;
  final Set<String> _selectedChanges = <String>{};
  final Map<AiProofreadingSplitChange, int> _splitBeforeVisible = {};
  final Map<AiProofreadingSplitChange, int> _splitAfterVisible = {};
  AiProofreadingTask? _splitPreviewTask;
  List<Finding>? _splitPreviewFindings;
  String? _locateError;
  AiProofreadingTask? _task;
  AiAuditGapRequest? _auditGap;
  bool _auditGapExpired = false;
  AiAdvertisementRequest? _advertisementSelection;
  bool _advertisementSelectionExpired = false;

  bool get _initialExpired =>
      _auditGapExpired || _advertisementSelectionExpired;

  bool _validAdvertisementSelection(AiAdvertisementRequest request) {
    final book = widget.session.book;
    final sessionId = widget.session.sessionId;
    if (book == null ||
        sessionId == null ||
        request.bookId != book.id ||
        request.sessionId != sessionId ||
        request.sessionRevision != widget.session.saveSeq ||
        !book.chapters.any(
          (chapter) => chapter.id == request.chapterId && !chapter.isVolume,
        )) {
      return false;
    }
    if (widget.session.activeChapterId != request.chapterId) return true;
    try {
      request.validate(
        book: book,
        sessionId: sessionId,
        sessionRevision: widget.session.saveSeq,
      );
      return true;
    } on Object {
      return false;
    }
  }

  bool _validAuditGap(AiAuditGapRequest request) {
    final book = widget.session.book;
    final sessionId = widget.session.sessionId;
    if (book == null || sessionId == null) return false;
    try {
      request.validate(
        book: book,
        sessionId: sessionId,
        sessionRevision: widget.session.saveSeq,
      );
      return true;
    } on Object {
      return false;
    }
  }

  void _sessionChanged() {
    if (!mounted ||
        (_auditGap == null || _validAuditGap(_auditGap!)) &&
            (_advertisementSelection == null ||
                _validAdvertisementSelection(_advertisementSelection!))) {
      return;
    }
    _task?.cancel();
    setState(() {
      if (_auditGap != null) {
        _auditGap = null;
        _auditGapExpired = true;
      }
      if (_advertisementSelection != null) {
        _advertisementSelection = null;
        _advertisementSelectionExpired = true;
      }
      _preparedChapterIds = const <String>{};
      _preparedIntent = null;
      _selectedChanges.clear();
    });
  }

  void _resetSelection() {
    _requestRules = false;
    _preparedRuleRequest = null;
    _positiveExamples.clear();
    _negativeExamples.clear();
    final gap = widget.initialAuditGap;
    final selection = widget.initialAdvertisementSelection;
    _auditGap = gap != null && _validAuditGap(gap) ? gap : null;
    _auditGapExpired = gap != null && _auditGap == null;
    _advertisementSelection =
        selection != null &&
            gap == null &&
            _validAdvertisementSelection(selection)
        ? selection
        : null;
    _advertisementSelectionExpired =
        selection != null && _advertisementSelection == null;
    _intent = _auditGap != null
        ? AiProofreadingIntent.missingChapter
        : AiProofreadingIntent.advertisement;
    final activeChapterId = widget.session.activeChapterId;
    _chapterIds =
        _auditGap?.chapterIds.toSet() ??
        (_advertisementSelection == null
            ? null
            : <String>{_advertisementSelection!.chapterId}) ??
        (activeChapterId == null ? <String>{} : <String>{activeChapterId});
    _preparedChapterIds = const <String>{};
    _preparedIntent = null;
    _selectedChanges.clear();
  }

  @override
  void initState() {
    super.initState();
    _resetSelection();
    widget.session.addListener(_sessionChanged);
  }

  @override
  void didUpdateWidget(covariant AiProofreadingPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session != widget.session ||
        !identical(oldWidget.initialAuditGap, widget.initialAuditGap) ||
        !identical(
          oldWidget.initialAdvertisementSelection,
          widget.initialAdvertisementSelection,
        )) {
      if (oldWidget.session != widget.session) {
        oldWidget.session.removeListener(_sessionChanged);
        widget.session.addListener(_sessionChanged);
      }
      final oldTask = _task;
      if (oldTask != null &&
          (oldTask.isBusy ||
              oldTask.consent?.auditGap != null ||
              oldTask.consent?.advertisementSelection != null)) {
        scheduleMicrotask(oldTask.cancel);
      }
      _task = null;
      _resetSelection();
    }
  }

  @override
  void dispose() {
    widget.session.removeListener(_sessionChanged);
    final task = _task;
    if (task != null &&
        (task.isBusy ||
            task.consent?.auditGap != null ||
            task.consent?.advertisementSelection != null)) {
      scheduleMicrotask(task.cancel);
    }
    _positiveExamples.dispose();
    _negativeExamples.dispose();
    super.dispose();
  }

  List<String> get _orderedChapterIds => [
    for (final chapter in widget.session.book?.chapters ?? const <Chapter>[])
      if (!chapter.isVolume && _chapterIds.contains(chapter.id)) chapter.id,
  ];

  void _changeScope(AiProofreadingTask task, VoidCallback update) {
    if (_initialExpired || !identical(_task, task)) return;
    if (task.isBusy ||
        task.phase == AiProofreadingPhase.awaitingConsent ||
        task.phase == AiProofreadingPhase.completed ||
        task.findings.isNotEmpty ||
        task.changes.isNotEmpty ||
        task.splitChanges.isNotEmpty) {
      task.cancel();
    }
    setState(() {
      _requestRules = false;
      _preparedRuleRequest = null;
      _positiveExamples.clear();
      _negativeExamples.clear();
      _auditGap = null;
      _auditGapExpired = false;
      _advertisementSelection = null;
      _advertisementSelectionExpired = false;
      _preparedChapterIds = const <String>{};
      _preparedIntent = null;
      _selectedChanges.clear();
      update();
    });
  }

  void _selectIntent(AiProofreadingTask task, AiProofreadingIntent intent) {
    if (_initialExpired || _intent == intent) return;
    final chapters =
        widget.session.book?.chapters
            .where((chapter) => !chapter.isVolume)
            .toList() ??
        <Chapter>[];
    final activeIndex = chapters.indexWhere(
      (chapter) => chapter.id == widget.session.activeChapterId,
    );
    _changeScope(task, () {
      _intent = intent;
      if (intent == AiProofreadingIntent.advertisement) {
        final activeChapterId = widget.session.activeChapterId;
        _chapterIds = activeChapterId == null
            ? <String>{}
            : <String>{activeChapterId};
      } else if (chapters.length >= 2) {
        final first = activeIndex < 0
            ? 0
            : activeIndex.clamp(0, chapters.length - 2);
        _chapterIds = {chapters[first].id, chapters[first + 1].id};
      } else {
        _chapterIds = {for (final chapter in chapters) chapter.id};
      }
    });
  }

  bool _isPrepared(AiProofreadingTask task) =>
      task.consent != null &&
      task.phase == AiProofreadingPhase.awaitingConsent &&
      identical(task.consent!.auditGap, _auditGap) &&
      identical(task.consent!.ruleRequest, _preparedRuleRequest) &&
      identical(
        task.consent!.advertisementSelection,
        _advertisementSelection,
      ) &&
      !_initialExpired &&
      _preparedIntent == _intent &&
      setEquals(_preparedChapterIds, _chapterIds);

  Future<void> _prepare(AiProofreadingTask task) async {
    final request = _auditGap;
    final selection = _advertisementSelection;
    if (_initialExpired || _requestRules && !_validRuleExamples) return;
    if (request != null && !_validAuditGap(request)) {
      _sessionChanged();
      return;
    }
    if (selection != null && !_validAdvertisementSelection(selection)) {
      _sessionChanged();
      return;
    }
    final ids = _orderedChapterIds;
    setState(() {
      _preparedRuleRequest = _requestRules
          ? AiRuleRequest(
              kind: _intent == AiProofreadingIntent.advertisement
                  ? ProofreadingRuleKind.advertisement
                  : ProofreadingRuleKind.chapter,
              positiveExamples: _examples(_positiveExamples),
              negativeExamples: _examples(_negativeExamples),
            )
          : null;
      _preparedChapterIds = ids.toSet();
      _preparedIntent = _intent;
      _selectedChanges.clear();
    });
    await task.prepare(
      intent: _intent,
      chapterIds: ids,
      auditGap: request,
      advertisementSelection: selection,
      ruleRequest: _preparedRuleRequest,
    );
  }

  void _runPrepared(AiProofreadingTask task, AiProofreadingConsent consent) {
    if (!_isPrepared(task) || !identical(task.consent, consent)) return;
    if (_auditGap case final request? when !_validAuditGap(request)) {
      _sessionChanged();
      return;
    }
    if (_advertisementSelection case final selection?
        when !_validAdvertisementSelection(selection)) {
      _sessionChanged();
      return;
    }
    task.run(consent);
  }

  Future<void> _locate(String chapterId, String? blockId) async {
    try {
      await widget.onLocate(chapterId, blockId);
    } on Object {
      if (mounted) {
        setState(
          () =>
              _locateError = AppLocalizations.of(context)
                  .editorWorkbenchToolFailed,
        );
      }
    }
  }

  bool _hasChange(
    Finding finding,
    List<AiProofreadingChange> changes,
    List<AiProofreadingSplitChange> splits,
  ) =>
      changes.any((change) => change.finding.id == finding.id) ||
      splits.any((change) => change.finding.id == finding.id);

  bool _canEditResult(AiProofreadingTask task, List<Finding> findings) =>
      mounted &&
      identical(_task, task) &&
      identical(task.findings, findings) &&
      task.canApply;

  void _ignoreFinding(
    AiProofreadingTask task,
    List<Finding> findings,
    String findingId,
  ) {
    if (!_canEditResult(task, findings)) return;
    task.ignoreFinding(findingId);
    final visibleIds = {
      ...task.visibleChanges.map((change) => change.id),
      ...task.visibleSplitChanges.map((change) => change.id),
    };
    setState(() => _selectedChanges.retainAll(visibleIds));
  }

  @override
  Widget build(BuildContext context) {
    final task = ref.watch(aiProofreadingTaskProvider(widget.session));
    if (!identical(_task, task)) {
      _task = task;
      if ((_auditGap != null || _advertisementSelection != null) &&
          (task.isBusy || task.consent != null) &&
          (!identical(task.consent?.auditGap, _auditGap) ||
              !identical(
                task.consent?.advertisementSelection,
                _advertisementSelection,
              ))) {
        scheduleMicrotask(task.cancel);
      }
      if (task.consent case final consent?
          when task.phase == AiProofreadingPhase.awaitingConsent ||
              task.phase == AiProofreadingPhase.completed && task.canApply) {
        if (identical(consent.auditGap, _auditGap) &&
            identical(
              consent.advertisementSelection,
              _advertisementSelection,
            ) &&
            !_initialExpired) {
          _intent = consent.intent;
          _chapterIds = consent.chapterTitles.keys.toSet();
          _preparedChapterIds = _chapterIds.toSet();
          _preparedIntent = consent.intent;
          _preparedRuleRequest = consent.ruleRequest;
          _requestRules = consent.ruleRequest != null;
          _positiveExamples.text =
              consent.ruleRequest?.positiveExamples.join('\n') ?? '';
          _negativeExamples.text =
              consent.ruleRequest?.negativeExamples.join('\n') ?? '';
        }
      }
    }
    final l10n = AppLocalizations.of(context);
    final consent = task.consent;
    final showConsent = _isPrepared(task);
    final resultFindings = task.findings;
    if (!identical(_splitPreviewTask, task) ||
        !identical(_splitPreviewFindings, resultFindings) ||
        task.phase != AiProofreadingPhase.completed) {
      _splitBeforeVisible.clear();
      _splitAfterVisible.clear();
      _splitPreviewTask = task;
      _splitPreviewFindings = task.phase == AiProofreadingPhase.completed
          ? resultFindings
          : null;
    }
    final changes = task.visibleChanges;
    final splits = task.visibleSplitChanges;
    final pending = task.visibleFindings
        .where((finding) => !_hasChange(finding, changes, splits))
        .toList();
    _selectedChanges.retainAll({
      ...changes.map((change) => change.id),
      ...splits.map((change) => change.id),
    });
    final selected = Set<String>.of(_selectedChanges);
    final hasConflict = task.conflicts.any(
      (conflict) =>
          selected.contains(conflict.firstId) &&
          selected.contains(conflict.secondId),
    );
    final chunkCount = showConsent ? consent!.plan.chunks.length : 0;
    final resultCount = changes.length + splits.length + pending.length;
    final showResults =
        task.phase == AiProofreadingPhase.completed && resultCount > 0;

    return ListView.builder(
      padding: const EdgeInsets.all(AppSpacing.xl),
      itemCount: 1 + chunkCount + (showResults ? 1 + resultCount : 0),
      itemBuilder: (context, index) {
        if (index == 0) {
          return _buildControls(
            context,
            task,
            showConsent ? consent : null,
            selected,
            hasConflict,
            changes.length + splits.length,
            pending.length,
            resultFindings,
          );
        }
        index--;
        if (index < chunkCount) {
          final chunk = consent!.plan.chunks[index];
          return ExpansionTile(
            key: ValueKey('ai-chunk-${chunk.index}'),
            title: Text('${l10n.aiProofreadingChunk} ${index + 1}'),
            children: [
              Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: SelectableText(
                  AiProofreadingPrompt.userContext(
                    consent.intent,
                    chunk,
                    auditGap: consent.auditGap?.toJson(),
                    advertisementSelection: consent.advertisementSelection
                        ?.toJson(),
                    ruleRequest: consent.ruleChunkIndex == chunk.index
                        ? consent.ruleRequest
                        : null,
                  ),
                ),
              ),
            ],
          );
        }
        index -= chunkCount;
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xl),
            child: Text(
              l10n.aiProofreadingApplicableChanges,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          );
        }
        index--;
        if (index < changes.length) {
          return _buildChange(context, task, resultFindings, changes[index]);
        }
        index -= changes.length;
        if (index < splits.length) {
          return _buildSplitChange(
            context,
            task,
            resultFindings,
            splits[index],
          );
        }
        index -= splits.length;
        if (index < pending.length) {
          return _buildFinding(
            context,
            task,
            resultFindings,
            pending[index],
            index == 0,
          );
        }
        return const SizedBox.shrink();
      },
    );
  }

  Widget _buildControls(
    BuildContext context,
    AiProofreadingTask task,
    AiProofreadingConsent? consent,
    Set<String> selected,
    bool hasConflict,
    int changeCount,
    int pendingCount,
    List<Finding> resultFindings,
  ) {
    final l10n = AppLocalizations.of(context);
    final chapters =
        widget.session.book?.chapters
            .where((chapter) => !chapter.isVolume)
            .toList() ??
        <Chapter>[];
    final canPrepare =
        !_initialExpired &&
        !task.isBusy &&
        (_auditGap == null || _validAuditGap(_auditGap!)) &&
        (_advertisementSelection == null ||
            _validAdvertisementSelection(_advertisementSelection!)) &&
        _orderedChapterIds.length >=
            (_intent == AiProofreadingIntent.missingChapter &&
                    !(_auditGap != null && _validAuditGap(_auditGap!))
                ? 2
                : 1);
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.aiProofreadingIntro),
        if (_auditGap case final gap?) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            l10n.aiAuditGapSource,
            key: const ValueKey('ai-audit-gap-source'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          Text(l10n.aiAuditGapRange(gap.gap.firstMissing, gap.gap.lastMissing)),
          Text(
            gap.beforeTitle == null
                ? l10n.aiAuditGapNoBefore
                : l10n.aiAuditGapBefore(gap.beforeTitle!),
          ),
          Text(l10n.aiAuditGapAfter(gap.afterTitle)),
          Text(l10n.aiAuditGapNoAutoSend),
        ],
        if (_auditGapExpired)
          Text(l10n.aiAuditGapExpired, style: TextStyle(color: colors.error)),
        if (_advertisementSelection case final selection?) ...[
          const SizedBox(height: AppSpacing.sm),
          if (selection.ruleName case final name?)
            Text(l10n.aiAdvertisementSource(name)),
          Text(
            l10n.aiAdvertisementSelectedText,
            key: const ValueKey('ai-advertisement-selection-source'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          Text('${selection.startUtf16}-${selection.endUtf16} UTF-16'),
          SelectableText(
            selection.original,
            key: const ValueKey('ai-advertisement-selection-text'),
          ),
          Text(l10n.aiAdvertisementSelectionScope),
          Text(l10n.aiAuditGapNoAutoSend),
        ],
        if (_advertisementSelectionExpired)
          Text(
            l10n.aiAdvertisementSelectionExpired,
            style: TextStyle(color: colors.error),
          ),
        const SizedBox(height: AppSpacing.md),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            for (final intent in AiProofreadingIntent.values)
              ChoiceChip(
                key: ValueKey('ai-intent-${intent.name}'),
                label: Text(
                  intent == AiProofreadingIntent.advertisement
                      ? l10n.aiProofreadingAdvertisement
                      : l10n.aiProofreadingMissingChapter,
                ),
                selected: _intent == intent,
                showCheckmark: false,
                onSelected: task.isBusy || _initialExpired
                    ? null
                    : (_) => _selectIntent(task, intent),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          l10n.aiProofreadingChapters,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        Text(
          _advertisementSelection != null
              ? l10n.aiAdvertisementSelectionScope
              : _intent == AiProofreadingIntent.missingChapter
              ? l10n.aiProofreadingMissingScope
              : l10n.aiProofreadingScope,
        ),
        TextButton.icon(
          onPressed:
              task.isBusy ||
                  _initialExpired ||
                  widget.session.activeChapterId == null
              ? null
              : () {
                  final activeChapterId = widget.session.activeChapterId!;
                  if (_auditGap == null &&
                      _advertisementSelection == null &&
                      setEquals(_chapterIds, <String>{activeChapterId})) {
                    return;
                  }
                  _changeScope(task, () => _chapterIds = {activeChapterId});
                },
          icon: const Icon(Icons.my_location),
          label: Text(l10n.aiProofreadingCurrentChapter),
        ),
        ConstrainedBox(
          constraints: const BoxConstraints(
            maxHeight: AppLayout.aiChapterSelectionMaxHeight,
          ),
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: chapters.length,
            itemBuilder: (context, index) {
              final chapter = chapters[index];
              return CheckboxListTile(
                key: ValueKey('ai-chapter-${chapter.id}'),
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(chapter.title),
                value: _chapterIds.contains(chapter.id),
                onChanged: task.isBusy || _initialExpired
                    ? null
                    : (value) => _changeScope(task, () {
                        if (value == true) {
                          _chapterIds.add(chapter.id);
                        } else {
                          _chapterIds.remove(chapter.id);
                        }
                      }),
              );
            },
          ),
        ),
        Text(
          '${l10n.aiProofreadingSelectedChapters}: ${_orderedChapterIds.length}',
        ),
        Row(
          children: [
            Checkbox(
              key: const ValueKey('ai-request-rules'),
              value: _requestRules,
              onChanged: _initialExpired
                  ? null
                  : (value) => _ruleInputChanged(task, () {
                      _requestRules = value == true;
                      final original = _advertisementSelection?.original;
                      if (_requestRules &&
                          _positiveExamples.text.isEmpty &&
                          original != null &&
                          original.length <= 2048 &&
                          !original.contains(RegExp(r'[\r\n]'))) {
                        _positiveExamples.text = original;
                      }
                    }),
            ),
            Expanded(child: Text(l10n.aiJointRuleRequest)),
          ],
        ),
        if (_requestRules) ...[
          Text(l10n.aiJointRuleHelp),
          TextField(
            key: const ValueKey('ai-rule-positive'),
            controller: _positiveExamples,
            minLines: 2,
            maxLines: 4,
            decoration: InputDecoration(labelText: l10n.ruleWorkbenchPositive),
            onChanged: (_) => _ruleInputChanged(task, () {}),
          ),
          TextField(
            key: const ValueKey('ai-rule-negative'),
            controller: _negativeExamples,
            minLines: 2,
            maxLines: 4,
            decoration: InputDecoration(labelText: l10n.ruleWorkbenchNegative),
            onChanged: (_) => _ruleInputChanged(task, () {}),
          ),
          Text(l10n.aiJointRuleLimits),
        ],
        const SizedBox(height: AppSpacing.md),
        FilledButton.tonal(
          key: const ValueKey('ai-prepare'),
          onPressed: canPrepare && (!_requestRules || _validRuleExamples)
              ? () => _prepare(task)
              : null,
          child: Text(l10n.aiProofreadingPrepare),
        ),
        if (task.failure case final failure?) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            [
              failure.message,
              if (failure.hint != null) failure.hint!,
            ].join(' '),
            style: TextStyle(color: colors.error),
          ),
        ],
        if (_locateError case final error?)
          Text(error, style: TextStyle(color: colors.error)),
        if (task.phase != AiProofreadingPhase.idle) ...[
          const SizedBox(height: AppSpacing.md),
          Text('${l10n.aiProofreadingPhase}: ${_phaseLabel(l10n, task.phase)}'),
          if (task.phase == AiProofreadingPhase.running ||
              task.phase == AiProofreadingPhase.completed)
            Text(
              '${l10n.aiProofreadingCompletedChunks}: '
              '${task.completedChunks}/${task.totalChunks}',
            ),
          if (task.phase == AiProofreadingPhase.preparing ||
              task.phase == AiProofreadingPhase.running ||
              task.phase == AiProofreadingPhase.applying)
            TextButton.icon(
              key: const ValueKey('ai-cancel'),
              onPressed: task.cancel,
              icon: const Icon(Icons.close),
              label: Text(l10n.editorWorkbenchCancelTask),
            ),
        ],
        if (consent != null) ...[
          const Divider(height: AppSpacing.xxl),
          Text(
            l10n.aiProofreadingReview,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          SelectableText(
            '${l10n.aiRequestAddress}: ${consent.configuration.endpoint.requestUri}',
          ),
          SelectableText('${l10n.aiModel}: ${consent.configuration.model}'),
          Text(
            '${l10n.aiProofreadingChapters}: '
            '${consent.chapterTitles.values.join(', ')}',
          ),
          Text(
            '${l10n.aiProofreadingCharacters}: '
            '${consent.plan.inputCharacters}',
          ),
          Text('${l10n.aiProofreadingBlocks}: ${consent.plan.blockCount}'),
          Text('${l10n.aiProofreadingChunks}: ${consent.plan.chunks.length}'),
          if (consent.ruleRequest case final request?) ...[
            Text(l10n.aiJointRuleAuthorization),
            Text('${l10n.ruleWorkbenchKind}: ${request.kind.name}'),
            Text(l10n.ruleWorkbenchPositive),
            for (final example in request.positiveExamples)
              SelectableText(example),
            Text(l10n.ruleWorkbenchNegative),
            for (final example in request.negativeExamples)
              SelectableText(example),
            Text(l10n.aiJointRuleChunk((consent.ruleChunkIndex ?? -1) + 1)),
          ],
          if (consent.advertisementSelection case final selection?) ...[
            Text(
              l10n.aiAdvertisementReadOnlyContext,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            for (final slice in consent.plan.chunks.single.slices)
              if (slice.block.blockId == selection.blockId) ...[
                if (slice.before.isNotEmpty) SelectableText(slice.before),
                if (slice.after.isNotEmpty) SelectableText(slice.after),
              ] else
                SelectableText(slice.text),
          ],
          ExpansionTile(
            title: Text(l10n.aiProofreadingSystemPrompt),
            children: [
              for (final chunk in consent.plan.chunks)
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${l10n.aiProofreadingChunk} ${chunk.index + 1}'),
                      SelectableText(
                        AiProofreadingPrompt.system(
                          consent.intent,
                          auditGap: consent.auditGap != null,
                          advertisementSelection:
                              consent.advertisementSelection != null,
                          ruleRequest: consent.ruleChunkIndex == chunk.index
                              ? consent.ruleRequest
                              : null,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          Text(l10n.aiProofreadingCompleteScope),
          Text(l10n.aiProofreadingCancelCost),
          const SizedBox(height: AppSpacing.sm),
          FilledButton(
            key: const ValueKey('ai-run'),
            onPressed: task.isBusy ? null : () => _runPrepared(task, consent),
            child: Text(l10n.aiProofreadingStart),
          ),
        ],
        if (task.phase == AiProofreadingPhase.running ||
            task.phase == AiProofreadingPhase.cancelled)
          Text(l10n.aiProofreadingCancelCost),
        if (task.phase == AiProofreadingPhase.applied)
          Text('${l10n.aiProofreadingAppliedCount}: ${task.lastAppliedCount}'),
        if (task.phase == AiProofreadingPhase.completed) ...[
          const Divider(height: AppSpacing.xxl),
          if (task.ignoredFindingCount > 0) ...[
            Text(l10n.aiProofreadingIgnoredCount(task.ignoredFindingCount)),
            TextButton.icon(
              key: const ValueKey('ai-restore-ignored'),
              onPressed: task.canApply
                  ? () {
                      if (_canEditResult(task, resultFindings)) {
                        task.restoreIgnoredFindings();
                      }
                    }
                  : null,
              icon: const Icon(Icons.restore),
              label: Text(l10n.aiProofreadingRestoreIgnored),
            ),
          ],
          if (task.changes.isEmpty &&
              task.splitChanges.isEmpty &&
              task.findings.isEmpty &&
              task.ruleProposals.isEmpty)
            Text(l10n.aiProofreadingNoFindings),
          Text(
            '${l10n.aiProofreadingApplicableChanges}: '
            '$changeCount',
          ),
          Text(
            '${l10n.aiProofreadingPending}: '
            '$pendingCount',
          ),
          if (task.consent?.ruleRequest == null)
            Text(l10n.aiJointRuleNotRequested)
          else ...[
            Text(
              l10n.aiJointRuleCount(task.ruleProposals.length),
              key: const ValueKey('ai-rule-results'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (task.ruleProposals.isEmpty) Text(l10n.aiRuleNoProposals),
            for (final proposal in task.ruleProposals)
              _buildRule(context, task, proposal),
          ],
          if (hasConflict)
            Text(
              l10n.aiProofreadingConflict,
              style: TextStyle(color: colors.error),
            ),
          if (changeCount > 0)
            FilledButton(
              key: const ValueKey('ai-apply-selected'),
              onPressed:
                  task.canApply &&
                      selected.isNotEmpty &&
                      selected.length <= 100 &&
                      !hasConflict
                  ? () => task.applySelected(selected)
                  : null,
              child: Text(l10n.aiProofreadingApplySelected),
            ),
        ],
      ],
    );
  }

  Widget _buildRule(
    BuildContext context,
    AiProofreadingTask task,
    RuleProposal proposal,
  ) {
    final l10n = AppLocalizations.of(context);
    final rule = proposal.rule;
    return ExpansionTile(
      key: ValueKey('ai-rule-tile-${proposal.proposalId}'),
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
              Text(l10n.aiProofreadingReason),
              SelectableText(proposal.reason),
              Text('${l10n.ruleWorkbenchKind}: ${rule.kind.name}'),
              Text('${l10n.ruleWorkbenchTarget}: ${rule.target.name}'),
              Text('${l10n.ruleWorkbenchMode}: ${rule.mode.name}'),
              Text(l10n.ruleWorkbenchPattern),
              SelectableText(rule.pattern),
              Text('${l10n.ruleWorkbenchAction}: ${rule.action.name}'),
              Text(l10n.ruleWorkbenchPositive),
              for (final example in rule.positiveExamples)
                SelectableText(example),
              Text(l10n.ruleWorkbenchNegative),
              for (final example in rule.negativeExamples)
                SelectableText(example),
              Text(l10n.aiJointRuleHelp),
              if (widget.onUseRule != null)
                FilledButton.tonalIcon(
                  key: ValueKey('ai-use-rule-${proposal.proposalId}'),
                  onPressed: task.canUseRuleProposals
                      ? () => _useRule(task, proposal)
                      : null,
                  icon: const Icon(Icons.fact_check_outlined),
                  label: Text(l10n.aiRuleCheckAndTrial),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildChange(
    BuildContext context,
    AiProofreadingTask task,
    List<Finding> resultFindings,
    AiProofreadingChange change,
  ) {
    final l10n = AppLocalizations.of(context);
    final proposal = change.proposal;
    final actionLabel = switch (proposal.action) {
      AiTextProposalAction.replaceText => l10n.aiProofreadingReplace,
      AiTextProposalAction.deleteText => l10n.aiProofreadingDelete,
      AiTextProposalAction.removeBlock => l10n.aiProofreadingRemoveBlock,
      AiTextProposalAction.renameChapter => l10n.aiProofreadingRenameChapter,
    };
    final title =
        task.consent?.chapterTitles[proposal.target.chapterId] ??
        proposal.target.chapterId;
    return ExpansionTile(
      key: ValueKey('ai-change-tile-${change.id}'),
      title: Row(
        children: [
          Checkbox(
            key: ValueKey('ai-change-${change.id}'),
            value: _selectedChanges.contains(change.id),
            onChanged: task.canApply
                ? (value) => setState(() {
                    if (value == true) {
                      _selectedChanges.add(change.id);
                    } else {
                      _selectedChanges.remove(change.id);
                    }
                  })
                : null,
          ),
          Expanded(
            child: Text(
              '$title · $actionLabel',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      children: [
        Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                proposal.action == AiTextProposalAction.renameChapter
                    ? l10n.aiProofreadingOriginalEvidence
                    : l10n.aiProofreadingOriginal,
              ),
              SelectableText(proposal.target.originalText),
              const SizedBox(height: AppSpacing.sm),
              switch (proposal.action) {
                AiTextProposalAction.renameChapter => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l10n.aiProofreadingOriginalChapterTitle),
                    SelectableText(proposal.originalTitle!),
                    const SizedBox(height: AppSpacing.sm),
                    Text(l10n.aiProofreadingNewChapterTitle),
                    SelectableText(proposal.replacement),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      l10n.aiProofreadingRenameChapterImpact,
                      key: ValueKey('ai-rename-chapter-impact-${change.id}'),
                    ),
                  ],
                ),
                AiTextProposalAction.removeBlock => Text(
                  l10n.aiProofreadingRemoveBlockImpact,
                  key: ValueKey('ai-remove-block-impact-${change.id}'),
                ),
                AiTextProposalAction.deleteText => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l10n.aiProofreadingReplacement),
                    Text(l10n.aiProofreadingDelete),
                  ],
                ),
                AiTextProposalAction.replaceText => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l10n.aiProofreadingReplacement),
                    SelectableText(proposal.replacement),
                  ],
                ),
              },
              const SizedBox(height: AppSpacing.sm),
              Text(l10n.aiProofreadingReason),
              SelectableText(proposal.reason),
              Wrap(
                spacing: AppSpacing.sm,
                children: [
                  TextButton.icon(
                    key: ValueKey('ai-locate-${change.id}'),
                    onPressed: () => _locate(
                      proposal.target.chapterId,
                      proposal.target.blockId,
                    ),
                    icon: const Icon(Icons.my_location),
                    label: Text(l10n.aiProofreadingLocate),
                  ),
                  TextButton.icon(
                    onPressed: task.canApply
                        ? () => task.applySelected({change.id})
                        : null,
                    icon: const Icon(Icons.check),
                    label: Text(l10n.aiProofreadingApplyOne),
                  ),
                  TextButton.icon(
                    key: ValueKey('ai-ignore-${change.finding.id}'),
                    onPressed: task.canApply
                        ? () => _ignoreFinding(
                            task,
                            resultFindings,
                            change.finding.id,
                          )
                        : null,
                    icon: const Icon(Icons.visibility_off_outlined),
                    label: Text(l10n.aiProofreadingIgnoreFinding),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSplitChange(
    BuildContext context,
    AiProofreadingTask task,
    List<Finding> resultFindings,
    AiProofreadingSplitChange change,
  ) {
    final l10n = AppLocalizations.of(context);
    final proposal = change.proposal;
    final line = proposal.titleLineIn(change.sourceBlock.text, proposal.range);
    final beforeVisible = _splitBeforeVisible[change] ?? 100;
    final afterVisible = _splitAfterVisible[change] ?? 100;
    return ExpansionTile(
      key: ValueKey('ai-change-tile-${change.id}'),
      title: Row(
        children: [
          Checkbox(
            key: ValueKey('ai-change-${change.id}'),
            value: _selectedChanges.contains(change.id),
            onChanged: task.canApply
                ? (value) => setState(() {
                    if (value == true) {
                      _selectedChanges.add(change.id);
                    } else {
                      _selectedChanges.remove(change.id);
                    }
                  })
                : null,
          ),
          Expanded(
            child: Text('${l10n.aiProofreadingSplit}: ${proposal.title}'),
          ),
        ],
      ),
      children: [
        Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.aiProofreadingOriginal),
              SelectableText(change.sourceBlock.text),
              const SizedBox(height: AppSpacing.sm),
              Text(
                '${l10n.aiProofreadingSplitSource}: ${change.sourceChapter.title}',
              ),
              Text(
                change.parentTitle == null
                    ? l10n.aiProofreadingSplitTopLevel
                    : '${l10n.aiProofreadingSplitParent}: ${change.parentTitle}',
              ),
              ExpansionTile(
                key: ValueKey('ai-split-before-${change.id}'),
                enabled: change.precedingBlockCount > 0,
                title: Text(
                  l10n.aiProofreadingSplitBeforeCount(
                    change.precedingBlockCount,
                  ),
                ),
                children: [
                  for (final block in change.precedingBlocks.take(
                    beforeVisible,
                  ))
                    _splitBlock(context, block),
                  if (beforeVisible < change.precedingBlockCount)
                    TextButton.icon(
                      key: ValueKey('ai-split-more-before-${change.id}'),
                      onPressed: () => _showMoreSplitBlocks(
                        task,
                        resultFindings,
                        change,
                        before: true,
                      ),
                      icon: const Icon(Icons.expand_more),
                      label: Text(l10n.aiProofreadingSplitMore),
                    ),
                ],
              ),
              SelectableText(change.sourceBlock.text.substring(0, line.start)),
              const SizedBox(height: AppSpacing.sm),
              Text('${l10n.aiProofreadingSplitNew}: ${proposal.title}'),
              Text(
                proposal.removeTitleLine
                    ? l10n.aiProofreadingSplitRemoveTitle
                    : l10n.aiProofreadingSplitKeepTitle,
              ),
              SelectableText(
                change.sourceBlock.text.substring(
                  proposal.removeTitleLine ? line.end : line.start,
                ),
              ),
              ExpansionTile(
                key: ValueKey('ai-split-after-${change.id}'),
                enabled: change.followingBlockCount > 0,
                title: Text(
                  l10n.aiProofreadingSplitAfterCount(
                    change.followingBlockCount,
                  ),
                ),
                children: [
                  for (final block in change.followingBlocks.take(afterVisible))
                    _splitBlock(context, block),
                  if (afterVisible < change.followingBlockCount)
                    TextButton.icon(
                      key: ValueKey('ai-split-more-after-${change.id}'),
                      onPressed: () => _showMoreSplitBlocks(
                        task,
                        resultFindings,
                        change,
                        before: false,
                      ),
                      icon: const Icon(Icons.expand_more),
                      label: Text(l10n.aiProofreadingSplitMore),
                    ),
                ],
              ),
              Text(l10n.aiProofreadingSplitResources),
              const SizedBox(height: AppSpacing.sm),
              Text(l10n.aiProofreadingReason),
              SelectableText(proposal.reason),
              Wrap(
                spacing: AppSpacing.sm,
                children: [
                  TextButton.icon(
                    key: ValueKey('ai-locate-${change.id}'),
                    onPressed: () => _locate(
                      proposal.target.chapterId,
                      proposal.target.blockId,
                    ),
                    icon: const Icon(Icons.my_location),
                    label: Text(l10n.aiProofreadingLocate),
                  ),
                  TextButton.icon(
                    onPressed: task.canApply
                        ? () => task.applySelected({change.id})
                        : null,
                    icon: const Icon(Icons.check),
                    label: Text(l10n.aiProofreadingApplyOne),
                  ),
                  TextButton.icon(
                    key: ValueKey('ai-ignore-${change.finding.id}'),
                    onPressed: task.canApply
                        ? () => _ignoreFinding(
                            task,
                            resultFindings,
                            change.finding.id,
                          )
                        : null,
                    icon: const Icon(Icons.visibility_off_outlined),
                    label: Text(l10n.aiProofreadingIgnoreFinding),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _showMoreSplitBlocks(
    AiProofreadingTask task,
    List<Finding> resultFindings,
    AiProofreadingSplitChange change, {
    required bool before,
  }) {
    if (!mounted ||
        !identical(_task, task) ||
        !identical(task.findings, resultFindings) ||
        task.phase != AiProofreadingPhase.completed ||
        !task.visibleSplitChanges.any(
          (current) => identical(current, change),
        )) {
      return;
    }
    final visible = before ? _splitBeforeVisible : _splitAfterVisible;
    final count = before
        ? change.precedingBlockCount
        : change.followingBlockCount;
    setState(
      () => visible[change] = ((visible[change] ?? 100) + 100).clamp(0, count),
    );
  }

  Widget _splitBlock(BuildContext context, Block block) {
    final l10n = AppLocalizations.of(context);
    return SizedBox(
      width: double.infinity,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${switch (block) {
                TextBlock() => l10n.ruleWorkbenchTextBlock,
                ImageBlock() => l10n.ruleWorkbenchImageBlock,
                FootnoteBlock() => l10n.ruleWorkbenchFootnoteBlock,
                DividerBlock() => l10n.ruleWorkbenchDividerBlock,
              }} · ${block.id}',
            ),
            if (block case TextBlock(:final text)) SelectableText(text),
            if (block case ImageBlock(
              :final assetId,
              :final caption,
              :final alt,
            )) ...[
              SelectableText('${l10n.ruleWorkbenchAssetId}: $assetId'),
              if (caption != null)
                SelectableText('${l10n.aiProofreadingSplitCaption}: $caption'),
              if (alt.isNotEmpty)
                SelectableText('${l10n.aiProofreadingSplitAlt}: $alt'),
            ],
            if (block case FootnoteBlock(:final text, :final marker)) ...[
              if (marker != null)
                SelectableText('${l10n.aiProofreadingSplitMarker}: $marker'),
              SelectableText(text),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildFinding(
    BuildContext context,
    AiProofreadingTask task,
    List<Finding> resultFindings,
    Finding finding,
    bool first,
  ) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (first)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xl),
            child: Text(
              l10n.aiProofreadingPending,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
        ExpansionTile(
          key: ValueKey('ai-finding-${finding.id}'),
          title: Text(_assessmentLabel(l10n, finding.assessment)),
          subtitle: Text(
            _chapterTitle(finding.chapterId, widget.session) ??
                finding.chapterId,
          ),
          children: [
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.aiProofreadingOriginal),
                  SelectableText(finding.evidence),
                  const SizedBox(height: AppSpacing.sm),
                  Text(l10n.aiProofreadingReason),
                  SelectableText(finding.reason),
                  TextButton.icon(
                    onPressed: () =>
                        _locate(finding.chapterId, finding.blockId),
                    icon: const Icon(Icons.my_location),
                    label: Text(l10n.aiProofreadingLocate),
                  ),
                  TextButton.icon(
                    key: ValueKey('ai-ignore-${finding.id}'),
                    onPressed: task.canApply
                        ? () => _ignoreFinding(task, resultFindings, finding.id)
                        : null,
                    icon: const Icon(Icons.visibility_off_outlined),
                    label: Text(l10n.aiProofreadingIgnoreFinding),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

String? _chapterTitle(String chapterId, EditorSession session) {
  for (final chapter in session.book?.chapters ?? const <Chapter>[]) {
    if (chapter.id == chapterId) return chapter.title;
  }
  return null;
}

String _phaseLabel(AppLocalizations l10n, AiProofreadingPhase phase) =>
    switch (phase) {
      AiProofreadingPhase.idle => l10n.aiProofreadingIdle,
      AiProofreadingPhase.preparing => l10n.aiProofreadingPreparing,
      AiProofreadingPhase.awaitingConsent => l10n.aiProofreadingAwaitingConsent,
      AiProofreadingPhase.running => l10n.aiProofreadingRunning,
      AiProofreadingPhase.completed => l10n.aiProofreadingCompleted,
      AiProofreadingPhase.applying => l10n.aiProofreadingApplying,
      AiProofreadingPhase.applied => l10n.aiProofreadingApplied,
      AiProofreadingPhase.cancelled => l10n.aiProofreadingCancelled,
      AiProofreadingPhase.stale => l10n.aiProofreadingStale,
      AiProofreadingPhase.failed => l10n.aiProofreadingFailed,
    };

String _assessmentLabel(AppLocalizations l10n, FindingAssessment assessment) =>
    switch (assessment) {
      FindingAssessment.undetermined => l10n.aiProofreadingUndetermined,
      FindingAssessment.suspectedMissing => l10n.aiProofreadingSuspectedMissing,
      FindingAssessment.missedHeading => l10n.aiProofreadingMissedHeading,
      FindingAssessment.mergedContent => l10n.aiProofreadingMergedContent,
      FindingAssessment.numberingSuspect => l10n.aiProofreadingNumberingSuspect,
      FindingAssessment.advertisement => l10n.aiProofreadingAdvertisement,
      FindingAssessment.authorNote => l10n.aiProofreadingAuthorNote,
      FindingAssessment.storyQuote => l10n.aiProofreadingStoryQuote,
      FindingAssessment.notAdvertisement => l10n.aiProofreadingNotAdvertisement,
      FindingAssessment.observed => l10n.aiProofreadingObserved,
    };

import 'package:bookloom/app/offline_dictionaries.dart';
import 'package:bookloom/core/editing/proofreading.dart';
import 'package:bookloom/core/editing/proofreading_rule.dart';
import 'package:bookloom/core/errors/app_failure.dart';
import 'package:bookloom/core/model/parse_options.dart';
import 'package:bookloom/design/tokens/app_metrics.dart';
import 'package:bookloom/features/editor/application/ai_advertisement_request.dart';
import 'package:bookloom/features/editor/application/ai_audit_gap_request.dart';
import 'package:bookloom/features/editor/application/editor_session.dart';
import 'package:bookloom/features/editor/presentation/ai_proofreading_panel.dart';
import 'package:bookloom/features/editor/presentation/rule_workbench_panel.dart';
import 'package:bookloom/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

enum _ProofreadingTool { audit, missed, replace, renumber, convert, rules, ai }

/// Book-wide checks and previewed edits. The session owns the background job,
/// revision check and the single undo entry for each applied preview.
class ProofreadingPanel extends StatefulWidget {
  const ProofreadingPanel({
    super.key,
    required this.session,
    required this.onLocate,
    this.onUseRule,
    this.embedded = false,
  });

  final EditorSession session;
  final Future<void> Function(String chapterId, String? blockId) onLocate;
  final ValueChanged<ProofreadingRule>? onUseRule;

  /// True when hosted inside the docked editor pane. The host paints its own
  /// header, so the panel skips its duplicate page title and tightens its
  /// paddings for the narrower column.
  final bool embedded;

  @override
  State<ProofreadingPanel> createState() => _ProofreadingPanelState();
}

class _ProofreadingPanelState extends State<ProofreadingPanel> {
  final _find = TextEditingController();
  final _replacement = TextEditingController();
  AuditReport? _audit;
  EditorSession? _auditSession;
  String? _auditBookId;
  String? _auditSessionId;
  int? _auditRevision;
  AiAuditGapRequest? _auditGap;
  AiAdvertisementRequest? _advertisementSelection;
  List<MissedChapterCandidate>? _missed;
  ToolPreview? _preview;
  String? _previewLabel;
  String? _error;
  bool _working = false;
  bool _regex = false;
  bool _caseSensitive = false;
  ReplaceScope _scope = ReplaceScope.all;
  ConvertMode _convertMode = ConvertMode.simplified;
  _ProofreadingTool _selectedTool = _ProofreadingTool.audit;

  @override
  void initState() {
    super.initState();
    widget.session.addListener(_sessionChanged);
  }

  @override
  void dispose() {
    widget.session.removeListener(_sessionChanged);
    _find.dispose();
    _replacement.dispose();
    super.dispose();
  }

  void _sessionChanged() {
    if (!mounted) return;
    if (!_auditCurrent) {
      _clearAudit(clearGap: _selectedTool != _ProofreadingTool.ai);
    }
    if (_preview?.baseRevision != null &&
        _preview!.baseRevision != widget.session.saveSeq) {
      _preview = null;
      _previewLabel = null;
    }
    setState(() {});
  }

  bool get _auditCurrent =>
      _audit != null &&
      identical(_auditSession, widget.session) &&
      widget.session.book?.id == _auditBookId &&
      widget.session.sessionId == _auditSessionId &&
      widget.session.saveSeq == _auditRevision;

  void _clearAudit({bool clearGap = true}) {
    _audit = null;
    _auditSession = null;
    _auditBookId = null;
    _auditSessionId = null;
    _auditRevision = null;
    if (clearGap) _auditGap = null;
  }

  @override
  void didUpdateWidget(covariant ProofreadingPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session == widget.session) return;
    oldWidget.session.removeListener(_sessionChanged);
    widget.session.addListener(_sessionChanged);
    _clearAudit();
    _advertisementSelection = null;
    _selectedTool = _ProofreadingTool.audit;
    _missed = null;
    _preview = null;
    _previewLabel = null;
    _error = null;
  }

  Future<void> _auditBook() => _run(() async {
    final session = widget.session;
    final bookId = session.book?.id;
    final sessionId = session.sessionId;
    final revision = session.saveSeq;
    setState(_clearAudit);
    final report = await session.auditBook();
    if (!mounted ||
        !identical(widget.session, session) ||
        session.book?.id != bookId ||
        session.sessionId != sessionId ||
        session.saveSeq != revision) {
      return;
    }
    setState(() {
      _audit = report;
      _auditSession = session;
      _auditBookId = bookId;
      _auditSessionId = sessionId;
      _auditRevision = revision;
    });
  });

  void _analyzeGap(AuditReport report, AuditIssue issue) {
    if (!_auditCurrent ||
        !identical(_audit, report) ||
        !report.issues.contains(issue) ||
        _working ||
        widget.session.isToolRunning) {
      return;
    }
    try {
      final request = AiAuditGapRequest.fromIssue(
        issue: issue,
        book: widget.session.book!,
        sessionId: _auditSessionId!,
        sessionRevision: _auditRevision!,
      );
      setState(() {
        _auditGap = request;
        _selectedTool = _ProofreadingTool.ai;
        _preview = null;
        _previewLabel = null;
        _missed = null;
        _error = null;
      });
    } on Object catch (error) {
      setState(() {
        _clearAudit();
        _error = _failure(error);
      });
    }
  }

  void _dropPreview() {
    if (_preview != null) {
      setState(() {
        _preview = null;
        _previewLabel = null;
      });
    }
  }

  void _selectTool(_ProofreadingTool tool) {
    if (tool == _selectedTool || _working || widget.session.isToolRunning) {
      return;
    }
    setState(() {
      _selectedTool = tool;
      _preview = null;
      _previewLabel = null;
      _clearAudit();
      _advertisementSelection = null;
      _missed = null;
      _error = null;
    });
  }

  Future<void> _analyzeAdvertisement(AiAdvertisementRequest request) async {
    if (!mounted || _working || widget.session.isToolRunning) return;
    setState(() {
      _advertisementSelection = request;
      _auditGap = null;
      _selectedTool = _ProofreadingTool.ai;
      _preview = null;
      _previewLabel = null;
      _missed = null;
      _error = null;
    });
  }

  String _failure(Object error) {
    if (error is AppFailure) {
      return [error.message, if (error.hint != null) error.hint!].join(' ');
    }
    return AppLocalizations.of(context).editorWorkbenchToolFailed;
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_working) return;
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      await action();
    } on TaskCancelled {
      // The user asked to stop the active background job.
    } on Object catch (error) {
      if (mounted) setState(() => _error = _failure(error));
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _locate(String chapterId, String? blockId) async {
    try {
      await widget.onLocate(chapterId, blockId);
    } on Object catch (error) {
      if (mounted) setState(() => _error = _failure(error));
    }
  }

  Future<void> _applyPreview() => _run(() async {
    final preview = _preview;
    if (preview == null) return;
    await widget.session.applyToolPreview(preview);
    if (mounted) {
      setState(() {
        _preview = null;
        _clearAudit();
        _missed = null;
      });
    }
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final progress = widget.session.toolProgress;
    final toolChoices = [
      for (final tool in _ProofreadingTool.values)
        if (tool == _ProofreadingTool.ai || tool == _ProofreadingTool.rules)
          FilterChip(
            label: Text(_toolLabel(l10n, tool)),
            selected: _selectedTool == tool,
            showCheckmark: false,
            onSelected: _working || widget.session.isToolRunning
                ? null
                : (_) => _selectTool(tool),
          )
        else
          ChoiceChip(
            label: Text(_toolLabel(l10n, tool)),
            selected: _selectedTool == tool,
            showCheckmark: false,
            onSelected: _working || widget.session.isToolRunning
                ? null
                : (_) => _selectTool(tool),
          ),
    ];
    if (_selectedTool == _ProofreadingTool.ai ||
        _selectedTool == _ProofreadingTool.rules) {
      final EdgeInsets titlePadding = widget.embedded
          ? const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md, AppSpacing.md, 0)
          : const EdgeInsets.fromLTRB(AppSpacing.xl, AppSpacing.xl, AppSpacing.xl, 0);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!widget.embedded) ...[
            Padding(
              padding: titlePadding,
              child: Text(
                l10n.editorWorkbenchTools,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          SizedBox(
            height: 56,
            child: ListView.separated(
              padding: EdgeInsets.symmetric(
                horizontal: widget.embedded ? AppSpacing.md : AppSpacing.xl,
              ),
              scrollDirection: Axis.horizontal,
              itemCount: toolChoices.length,
              itemBuilder: (context, index) => toolChoices[index],
              separatorBuilder: (context, index) =>
                  const SizedBox(width: AppSpacing.sm),
            ),
          ),
          const Divider(height: AppSpacing.md),
          Expanded(
            child: _selectedTool == _ProofreadingTool.ai
                ? AiProofreadingPanel(
                    key: ValueKey((_auditGap, _advertisementSelection)),
                    session: widget.session,
                    onLocate: widget.onLocate,
                    initialAuditGap: _auditGap,
                    initialAdvertisementSelection: _advertisementSelection,
                    onUseRule: widget.onUseRule,
                  )
                : RuleWorkbenchPanel(
                    session: widget.session,
                    onLocate: widget.onLocate,
                    onAnalyzeAdvertisement: _analyzeAdvertisement,
                  ),
          ),
        ],
      );
    }
    return ListView(
      padding: EdgeInsets.all(widget.embedded ? AppSpacing.md : AppSpacing.xl),
      children: [
        if (!widget.embedded) ...[
          Text(
            l10n.editorWorkbenchTools,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
        Text(l10n.editorWorkbenchToolsIntro),
        if (_working || widget.session.isToolRunning) ...[
          const SizedBox(height: AppSpacing.md),
          LinearProgressIndicator(value: progress?.fraction),
          Text(progress?.stage ?? l10n.editorWorkbenchPreparingBook),
          if (widget.session.isToolRunning)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: widget.session.cancelTool,
                child: Text(l10n.editorWorkbenchCancelTask),
              ),
            ),
        ],
        if (_error != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        const SizedBox(height: AppSpacing.md),
        LayoutBuilder(
          builder: (context, constraints) {
            // Docked panes always wrap their tool chips: a horizontal scroller
            // inside a narrow column hides half the choices. The dialog keeps
            // its scroller only on genuinely compact windows.
            if (!widget.embedded &&
                constraints.maxWidth < AppLayout.editorCompactBreakpoint) {
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final choice in toolChoices) ...[
                      choice,
                      const SizedBox(width: AppSpacing.sm),
                    ],
                  ],
                ),
              );
            }
            return Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: toolChoices,
            );
          },
        ),
        const Divider(height: AppSpacing.xxl),
        if (_selectedTool == _ProofreadingTool.audit) ...[
          Text(l10n.editorWorkbenchAuditDesc),
          const SizedBox(height: AppSpacing.md),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.tonal(
              key: const ValueKey('proofreading-audit-run'),
              onPressed: _working ? null : _auditBook,
              child: Text(l10n.editorWorkbenchAuditRun),
            ),
          ),
          if (_audit case final report? when _auditCurrent) ...[
            ListTile(
              key: const ValueKey('proofreading-audit-total'),
              title: Text(l10n.editorWorkbenchAuditTotal(report.total)),
            ),
            for (final kind in AuditIssueKind.values)
              if ((report.counts[kind] ?? 0) > 0)
                ListTile(
                  dense: true,
                  title: Text(
                    l10n.editorWorkbenchIssueCount(
                      _kindLabel(l10n, kind),
                      report.counts[kind]!,
                    ),
                  ),
                ),
            for (final issue in report.issues)
              ListTile(
                dense: true,
                title: Text(issue.chapterTitle),
                subtitle: Text(issue.message),
                trailing:
                    issue.kind == AuditIssueKind.missingNumber &&
                        issue.numberGap != null
                    ? TextButton.icon(
                        key: ValueKey('audit-ai-gap-${issue.chapterId}'),
                        onPressed: () => _analyzeGap(report, issue),
                        icon: const Icon(Icons.auto_awesome_outlined),
                        label: Text(l10n.editorWorkbenchAnalyzeGapWithAi),
                      )
                    : const Icon(Icons.chevron_right),
                onTap: () {
                  if (_auditCurrent &&
                      identical(_audit, report) &&
                      report.issues.contains(issue)) {
                    _locate(issue.chapterId, issue.blockId);
                  }
                },
              ),
            if (report.total > report.issues.length)
              ListTile(title: Text(l10n.editorWorkbenchAuditLimit)),
          ],
        ],
        if (_selectedTool == _ProofreadingTool.missed) ...[
          Text(l10n.editorWorkbenchMissedDesc),
          const SizedBox(height: AppSpacing.md),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.tonal(
              onPressed: _working
                  ? null
                  : () => _run(() async {
                      final found = await widget.session
                          .findMissedChapterCandidates();
                      if (mounted) setState(() => _missed = found);
                    }),
              child: Text(l10n.editorWorkbenchMissedRun),
            ),
          ),
          if (_missed case final items?) ...[
            ListTile(
              title: Text(l10n.editorWorkbenchMissedCount(items.length)),
            ),
            for (final item in items.take(100))
              ListTile(
                dense: true,
                title: Text(item.text, maxLines: 2),
                subtitle: Text(
                  l10n.editorWorkbenchMissedLocation(
                    item.chapterIndex + 1,
                    item.blockIndex + 1,
                  ),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _locate(item.chapterId, item.blockId),
              ),
            if (items.length > 100)
              ListTile(title: Text(l10n.editorWorkbenchMissedLimit)),
          ],
        ],
        if (_selectedTool == _ProofreadingTool.replace) ...[
          TextField(
            controller: _find,
            readOnly: _working,
            maxLength: replaceFindLimit,
            decoration: InputDecoration(
              labelText: l10n.editorWorkbenchFindText,
            ),
            onChanged: (_) => _dropPreview(),
          ),
          TextField(
            controller: _replacement,
            readOnly: _working,
            maxLength: replaceTextLimit,
            decoration: InputDecoration(
              labelText: l10n.editorWorkbenchReplaceWith,
            ),
            onChanged: (_) => _dropPreview(),
          ),
          DropdownButtonFormField<ReplaceScope>(
            initialValue: _scope,
            isExpanded: true,
            decoration: InputDecoration(labelText: l10n.editorWorkbenchScope),
            items: [
              DropdownMenuItem(
                value: ReplaceScope.all,
                child: Text(l10n.editorWorkbenchScopeAll),
              ),
              DropdownMenuItem(
                value: ReplaceScope.title,
                child: Text(l10n.editorWorkbenchScopeTitle),
              ),
              DropdownMenuItem(
                value: ReplaceScope.body,
                child: Text(l10n.editorWorkbenchScopeBody),
              ),
            ],
            onChanged: _working
                ? null
                : (value) => setState(() {
                    _scope = value ?? ReplaceScope.all;
                    _preview = null;
                  }),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.editorWorkbenchRegex),
            value: _regex,
            onChanged: _working
                ? null
                : (value) => setState(() {
                    _regex = value;
                    _preview = null;
                  }),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.editorWorkbenchCaseSensitive),
            value: _caseSensitive,
            onChanged: _working
                ? null
                : (value) => setState(() {
                    _caseSensitive = value;
                    _preview = null;
                  }),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.tonal(
              onPressed: _working
                  ? null
                  : () => _run(() async {
                      final result = await widget.session.previewReplace(
                        ReplaceOptions(
                          find: _find.text,
                          replace: _replacement.text,
                          scope: _scope,
                          regex: _regex,
                          caseSensitive: _caseSensitive,
                        ),
                      );
                      if (mounted) {
                        setState(() {
                          _preview = result;
                          _previewLabel = l10n.editorWorkbenchReplaceLabel;
                        });
                      }
                    }),
              child: Text(l10n.editorWorkbenchPreviewReplace),
            ),
          ),
        ],
        if (_selectedTool == _ProofreadingTool.renumber) ...[
          Text(l10n.editorWorkbenchRenumberDesc),
          const SizedBox(height: AppSpacing.md),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.tonal(
              onPressed: _working
                  ? null
                  : () => _run(() async {
                      final result = await widget.session.previewRenumber();
                      if (mounted) {
                        setState(() {
                          _preview = result;
                          _previewLabel = l10n.editorWorkbenchRenumberLabel;
                        });
                      }
                    }),
              child: Text(l10n.editorWorkbenchPreviewRenumber),
            ),
          ),
        ],
        if (_selectedTool == _ProofreadingTool.convert) ...[
          Text(l10n.editorWorkbenchConvertDesc),
          const SizedBox(height: AppSpacing.md),
          DropdownButtonFormField<ConvertMode>(
            initialValue: _convertMode,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: l10n.editorWorkbenchConvertDirection,
            ),
            items: [
              DropdownMenuItem(
                value: ConvertMode.simplified,
                child: Text(l10n.editorWorkbenchConvertSimplified),
              ),
              DropdownMenuItem(
                value: ConvertMode.taiwan,
                child: Text(l10n.editorWorkbenchConvertTraditional),
              ),
            ],
            onChanged: _working
                ? null
                : (value) => setState(() {
                    _convertMode = value ?? ConvertMode.simplified;
                    _preview = null;
                  }),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.tonal(
              onPressed: _working
                  ? null
                  : () => _run(() async {
                      final dictionaries = await loadOfflineDictionaries();
                      final result = await widget.session.previewConvert(
                        _convertMode,
                        dictionaries,
                      );
                      if (mounted) {
                        setState(() {
                          _preview = result;
                          _previewLabel = l10n.editorWorkbenchConvertLabel;
                        });
                      }
                    }),
              child: Text(l10n.editorWorkbenchPreviewConvert),
            ),
          ),
        ],
        if (_preview case final preview?) ...[
          const Divider(height: AppSpacing.xxl),
          Text(
            l10n.editorWorkbenchPreviewTitle(
              _previewLabel ?? l10n.editorWorkbenchBatchEdit,
            ),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          Text(
            l10n.editorWorkbenchPreviewStats(
              preview.hits,
              preview.patches.length,
            ),
          ),
          for (final sample in preview.samples)
            ListTile(
              dense: true,
              title: Text(sample.chapterTitle),
              subtitle: Text(
                '${sample.before}【${sample.match}】${sample.after}',
                maxLines: 3,
              ),
              onTap: () => _locate(sample.chapterId, sample.blockId),
            ),
          if (preview.samples.isEmpty)
            for (final patch in preview.patches.take(20))
              ListTile(
                dense: true,
                title: Text(
                  patch.blockId == null
                      ? l10n.editorChapterTitle
                      : l10n.editorWorkbenchBodyParagraph,
                ),
                subtitle: Text('${patch.before} → ${patch.after}', maxLines: 3),
                onTap: () => _locate(patch.chapterId, patch.blockId),
              ),
          const SizedBox(height: AppSpacing.sm),
          FilledButton(
            onPressed: _working || preview.patches.isEmpty
                ? null
                : _applyPreview,
            child: Text(l10n.editorWorkbenchApplyOneUndo),
          ),
        ],
      ],
    );
  }
}

String _toolLabel(AppLocalizations l10n, _ProofreadingTool tool) =>
    switch (tool) {
      _ProofreadingTool.audit => l10n.editorWorkbenchAuditTitle,
      _ProofreadingTool.missed => l10n.editorWorkbenchMissedTitle,
      _ProofreadingTool.replace => l10n.editorWorkbenchFindReplace,
      _ProofreadingTool.renumber => l10n.editorWorkbenchRenumberTitle,
      _ProofreadingTool.convert => l10n.editorWorkbenchConvertTitle,
      _ProofreadingTool.rules => l10n.ruleWorkbenchTitle,
      _ProofreadingTool.ai => l10n.aiProofreadingTitle,
    };

String _kindLabel(AppLocalizations l10n, AuditIssueKind kind) => switch (kind) {
  AuditIssueKind.missingNumber => l10n.editorWorkbenchIssueMissingNumber,
  AuditIssueKind.duplicateNumber => l10n.editorWorkbenchIssueDuplicateNumber,
  AuditIssueKind.emptyChapter => l10n.editorWorkbenchIssueEmptyChapter,
  AuditIssueKind.duplicateTitle => l10n.editorWorkbenchIssueDuplicateTitle,
  AuditIssueKind.tooLong => l10n.editorWorkbenchIssueTooLong,
  AuditIssueKind.tooShort => l10n.editorWorkbenchIssueTooShort,
  AuditIssueKind.emptyVolume => l10n.editorWorkbenchIssueEmptyVolume,
  AuditIssueKind.adLeftover => l10n.editorWorkbenchIssueAdLeftover,
  AuditIssueKind.titleFormat => l10n.editorWorkbenchIssueTitleFormat,
  AuditIssueKind.duplicateContent => l10n.editorWorkbenchIssueDuplicateContent,
};

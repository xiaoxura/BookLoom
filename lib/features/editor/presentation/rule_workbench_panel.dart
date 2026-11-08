import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bookloom/app/rule_providers.dart';
import 'package:bookloom/app/workbench_providers.dart';
import 'package:bookloom/core/editing/proofreading_rule.dart';
import 'package:bookloom/core/editing/proofreading_rule_scan.dart';
import 'package:bookloom/core/editing/safe_regex.dart';
import 'package:bookloom/core/errors/app_failure.dart';
import 'package:bookloom/core/model/block.dart';
import 'package:bookloom/core/parsing/import_rule_summary.dart';
import 'package:bookloom/core/platform/files.dart';
import 'package:bookloom/design/tokens/app_metrics.dart';
import 'package:bookloom/features/editor/application/ai_advertisement_request.dart';
import 'package:bookloom/features/editor/application/editor_session.dart';
import 'package:bookloom/features/editor/application/rule_workbench_task.dart';
import 'package:bookloom/features/editor/data/proofreading_rule_store.dart';
import 'package:bookloom/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

class RuleWorkbenchPanel extends ConsumerStatefulWidget {
  const RuleWorkbenchPanel({
    super.key,
    required this.session,
    required this.onLocate,
    this.onAnalyzeAdvertisement,
    this.initialRule,
    this.initialSessionId,
    this.initialSaveSeq,
  });

  final EditorSession session;
  final Future<void> Function(String chapterId, String? blockId) onLocate;
  final Future<void> Function(AiAdvertisementRequest)? onAnalyzeAdvertisement;
  final ProofreadingRule? initialRule;
  final String? initialSessionId;
  final int? initialSaveSeq;

  @override
  ConsumerState<RuleWorkbenchPanel> createState() => _RuleWorkbenchPanelState();
}

class _RuleWorkbenchPanelState extends ConsumerState<RuleWorkbenchPanel> {
  final _name = TextEditingController();
  final _pattern = TextEditingController();
  final _exclude = TextEditingController();
  final _search = TextEditingController();
  final _positive = TextEditingController();
  final _negative = TextEditingController();
  final _priority = TextEditingController(text: '0');
  final _titleCapture = TextEditingController();
  final _numberCapture = TextEditingController();
  final _selectedMatches = <String>{};
  final _followingShown = <String, int>{};
  RuleWorkbenchTask? _task;
  String? _loadRequestedSessionId;
  String? _panelSessionId;
  ProofreadingRule? _editingRule;
  String? _currentRuleId;
  String? _error;
  String? _notice;
  bool _fileBusy = false;
  bool _initialHandled = false;
  bool _initialRejected = false;
  bool _editing = false;
  bool _enabled = true;
  bool _caseSensitive = false;
  bool _wholeLine = false;
  int _headingLevel = 2;
  ProofreadingRuleKind _kind = ProofreadingRuleKind.advertisement;
  ProofreadingRuleTarget _target = ProofreadingRuleTarget.bodyLine;
  ProofreadingMatchMode _mode = ProofreadingMatchMode.literal;
  ProofreadingRuleAction _action =
      ProofreadingRuleAction.advertisementCandidate;
  ProofreadingRuleScope _scope = ProofreadingRuleScope.book;
  int _shown = 100;

  @override
  void didUpdateWidget(covariant RuleWorkbenchPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialRule != widget.initialRule ||
        oldWidget.initialSessionId != widget.initialSessionId ||
        oldWidget.initialSaveSeq != widget.initialSaveSeq) {
      _initialHandled = false;
      _initialRejected = false;
    }
    if (oldWidget.session != widget.session) {
      _task = null;
      _loadRequestedSessionId = null;
      _panelSessionId = null;
      _editing = false;
      _editingRule = null;
      _currentRuleId = null;
      _selectedMatches.clear();
      _followingShown.clear();
      _shown = 100;
      _initialHandled = false;
      _initialRejected = false;
    }
  }

  @override
  void dispose() {
    final task = _task;
    if (task != null && task.isBusy) scheduleMicrotask(task.cancel);
    _name.dispose();
    _pattern.dispose();
    _exclude.dispose();
    _search.dispose();
    _positive.dispose();
    _negative.dispose();
    _priority.dispose();
    _titleCapture.dispose();
    _numberCapture.dispose();
    super.dispose();
  }

  bool _matchesSearch(ProofreadingRule rule) {
    final query = _search.text.trim().toLowerCase();
    if (query.isEmpty) return true;
    return rule.name.toLowerCase().contains(query) ||
        rule.pattern.toLowerCase().contains(query);
  }

  void _beginEdit(RuleWorkbenchTask task, [ProofreadingRule? rule]) {
    if (task.isBusy) return;
    task.cancel();
    _name.text = rule?.name ?? '';
    _pattern.text = rule?.pattern ?? '';
    _exclude.text = rule?.excludePattern ?? '';
    _positive.text = rule?.positiveExamples.join('\n') ?? '';
    _negative.text = rule?.negativeExamples.join('\n') ?? '';
    _priority.text = (rule?.priority ?? 0).toString();
    _titleCapture.text = rule?.titleCaptureGroup?.toString() ?? '';
    _numberCapture.text = rule?.numberCaptureGroup?.toString() ?? '';
    setState(() {
      _editing = true;
      _editingRule = rule;
      _currentRuleId = rule?.id;
      _kind = rule?.kind ?? ProofreadingRuleKind.advertisement;
      _headingLevel = rule?.headingLevel ?? 2;
      _target = rule?.target ?? ProofreadingRuleTarget.bodyLine;
      _mode = rule?.mode ?? ProofreadingMatchMode.literal;
      _action = rule?.action ?? ProofreadingRuleAction.advertisementCandidate;
      _scope = rule?.scope ?? ProofreadingRuleScope.book;
      _enabled = rule?.enabled ?? true;
      _caseSensitive = rule?.caseSensitive ?? false;
      _wholeLine = rule?.wholeLineOnly ?? false;
      _selectedMatches.clear();
      _followingShown.clear();
      _shown = 100;
      _error = null;
    });
  }

  void _acceptInitial(RuleWorkbenchTask task, ProofreadingRule rule) {
    if (!mounted ||
        !identical(_task, task) ||
        _initialHandled ||
        !identical(widget.initialRule, rule)) {
      return;
    }
    final session = widget.session;
    if (widget.initialSessionId == null ||
        widget.initialSaveSeq == null ||
        session.sessionId != widget.initialSessionId ||
        session.saveSeq != widget.initialSaveSeq ||
        rule.source != ProofreadingRuleSource.ai ||
        rule.scope != ProofreadingRuleScope.book ||
        rule.bookId != session.book?.id) {
      setState(() {
        _initialHandled = true;
        _initialRejected = true;
      });
      return;
    }
    if (!task.isLoaded || task.isBusy) return;
    if (task.rules.any((existing) => existing.id == rule.id)) {
      setState(() {
        _initialHandled = true;
        _initialRejected = true;
      });
      return;
    }
    _initialHandled = true;
    task.putRule(rule);
    setState(() {
      _currentRuleId = rule.id;
      _selectedMatches.clear();
      _followingShown.clear();
      _shown = 100;
    });
  }

  void _formChanged(RuleWorkbenchTask task) {
    if (task.hasCurrentTrial) task.cancel();
    setState(() => _error = null);
  }

  List<String> _examples(String text) => text
      .split(RegExp(r'\r?\n'))
      .where((sample) => sample.trim().isNotEmpty)
      .toList();

  int? _captureCount() {
    if (_kind != ProofreadingRuleKind.chapter ||
        _mode != ProofreadingMatchMode.safeRegex) {
      return null;
    }
    try {
      return SafeRegex.compile(
        _pattern.text,
        caseSensitive: _caseSensitive,
      ).captureCount;
    } on AppFailure {
      return null;
    }
  }

  bool _invalidTitleCapture(int? captureCount) {
    return _invalidCapture(_titleCapture.text, captureCount);
  }

  bool _invalidCapture(String text, int? captureCount) {
    final value = text.trim();
    if (value.isEmpty) return false;
    final parsed = int.tryParse(value);
    return !RegExp(r'^(0|[1-9][0-9]*)$').hasMatch(value) ||
        parsed == null ||
        (captureCount != null && parsed > captureCount);
  }

  bool _invalidNumberCapture(int? captureCount) =>
      _numberCapture.text.trim().isNotEmpty &&
      (_titleCapture.text.trim().isEmpty ||
          _invalidCapture(_numberCapture.text, captureCount));

  ProofreadingRule _makeRule({required bool globalConfirmed}) {
    final bookId = widget.session.book?.id;
    if (bookId == null) {
      throw ValidationFailure(
        AppLocalizations.of(context).ruleWorkbenchOpenBook,
      );
    }
    final priority = int.tryParse(_priority.text.trim());
    if (priority == null) {
      throw ValidationFailure(
        AppLocalizations.of(context).ruleWorkbenchPriorityInvalid,
      );
    }
    final captureCount = _captureCount();
    if (_invalidTitleCapture(captureCount)) {
      throw ValidationFailure(
        AppLocalizations.of(context).ruleWorkbenchTitleCaptureInvalid,
      );
    }
    if (_invalidNumberCapture(captureCount)) {
      throw ValidationFailure(
        AppLocalizations.of(context).ruleWorkbenchNumberCaptureInvalid,
      );
    }
    final exclude = _exclude.text.trim();
    if (exclude.isNotEmpty &&
        (exclude.length > ProofreadingRule.maxExcludeUtf16 ||
            exclude.contains(RegExp(r'[\r\n]')))) {
      throw ValidationFailure(
        AppLocalizations.of(context).ruleWorkbenchExcludePatternInvalid,
      );
    }
    return ProofreadingRule.create(
      id: _editingRule?.id ?? const Uuid().v4(),
      name: _name.text.trim(),
      kind: _kind,
      headingLevel: _headingLevel,
      source: _editingRule?.source ?? ProofreadingRuleSource.user,
      bookId: bookId,
      target: _target,
      mode: _mode,
      pattern: _pattern.text,
      excludePattern: exclude.isEmpty ? null : exclude,
      wholeLineOnly: _target != ProofreadingRuleTarget.paragraph && _wholeLine,
      titleCaptureGroup:
          _kind == ProofreadingRuleKind.chapter &&
              _mode == ProofreadingMatchMode.safeRegex &&
              _titleCapture.text.trim().isNotEmpty
          ? int.parse(_titleCapture.text.trim())
          : null,
      numberCaptureGroup: _numberCapture.text.trim().isEmpty
          ? null
          : int.parse(_numberCapture.text.trim()),
      caseSensitive: _caseSensitive,
      action: _action,
      positiveExamples: _examples(_positive.text),
      negativeExamples: _examples(_negative.text),
      scope: _scope,
      globalScopeConfirmed: globalConfirmed,
      enabled: _enabled,
      priority: priority,
    );
  }

  Future<void> _commit(RuleWorkbenchTask task) async {
    try {
      final changedToGlobal =
          _scope == ProofreadingRuleScope.global &&
          _editingRule?.scope != ProofreadingRuleScope.global;
      if (changedToGlobal) {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(
              AppLocalizations.of(context).ruleWorkbenchGlobalConfirmTitle,
            ),
            content: Text(
              AppLocalizations.of(context).ruleWorkbenchGlobalConfirmBody,
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(
                  MaterialLocalizations.of(context).cancelButtonLabel,
                ),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(AppLocalizations.of(context).ruleWorkbenchConfirm),
              ),
            ],
          ),
        );
        if (confirmed != true || !mounted) return;
      }
      final checked = _makeRule(globalConfirmed: true);
      task.putRule(checked);
      if (mounted) {
        setState(() {
          _editing = false;
          _editingRule = null;
          _currentRuleId = checked.id;
          _selectedMatches.clear();
          _followingShown.clear();
          _shown = 100;
          _error = null;
        });
      }
    } on AppFailure catch (error) {
      if (mounted) setState(() => _error = error.message);
    }
  }

  Future<void> _toggleEnabled(
    RuleWorkbenchTask task,
    ProofreadingRule rule,
  ) async {
    try {
      task.putRule(
        ProofreadingRule.create(
          id: rule.id,
          name: rule.name,
          kind: rule.kind,
          headingLevel: rule.headingLevel,
          source: rule.source,
          bookId: rule.bookId,
          target: rule.target,
          mode: rule.mode,
          pattern: rule.pattern,
          excludePattern: rule.excludePattern,
          titleCaptureGroup: rule.titleCaptureGroup,
          numberCaptureGroup: rule.numberCaptureGroup,
          caseSensitive: rule.caseSensitive,
          action: rule.action,
          positiveExamples: rule.positiveExamples,
          negativeExamples: rule.negativeExamples,
          scope: rule.scope,
          globalScopeConfirmed: rule.scope == ProofreadingRuleScope.global,
          enabled: !rule.enabled,
          priority: rule.priority,
        ),
      );
      setState(() {
        _currentRuleId = rule.id;
        _selectedMatches.clear();
        _followingShown.clear();
        _shown = 100;
        _error = null;
      });
      await task.scan();
      if (task.phase == RuleWorkbenchPhase.ready && task.hasCurrentTrial) {
        await task.saveRule(rule.id);
      }
    } on AppFailure catch (error) {
      if (mounted) setState(() => _error = error.message);
    }
  }

  Future<void> _duplicateRule(
    RuleWorkbenchTask task,
    ProofreadingRule rule,
  ) async {
    final l10n = AppLocalizations.of(context);
    final suffix = l10n.ruleWorkbenchCopySuffix;
    final base = rule.name.length + suffix.length <= 128
        ? rule.name
        : rule.name.substring(0, 128 - suffix.length);
    final name = '$base$suffix';
    try {
      final copy = rule.duplicate(id: const Uuid().v4(), name: name);
      await ref.read(proofreadingRuleStoreProvider).save(copy);
      await task.load();
      if (mounted) {
        setState(() {
          _error = null;
          _notice = l10n.ruleWorkbenchDuplicated(name);
        });
      }
    } on AppFailure catch (error) {
      if (mounted) setState(() => _error = error.message);
    } on Object {
      if (mounted) setState(() => _error = l10n.editorWorkbenchToolFailed);
    }
  }

  Future<void> _delete(RuleWorkbenchTask task, ProofreadingRule rule) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppLocalizations.of(context).ruleWorkbenchDeleteTitle),
        content: Text(rule.name),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(AppLocalizations.of(context).ruleWorkbenchDelete),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await task.deleteRule(rule.id);
    if (mounted && task.phase != RuleWorkbenchPhase.failed) {
      setState(() {
        if (_currentRuleId == rule.id) _currentRuleId = null;
        _selectedMatches.clear();
        _followingShown.clear();
      });
    }
  }

  Future<void> _reload(RuleWorkbenchTask task) async {
    final discardDraft =
        _editing || task.rules.any((rule) => !task.isSaved(rule.id));
    if (discardDraft) {
      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(AppLocalizations.of(context).ruleWorkbenchReloadTitle),
          content: Text(
            AppLocalizations.of(context).ruleWorkbenchReloadWarning,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(AppLocalizations.of(context).ruleWorkbenchReload),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    setState(() {
      _editing = false;
      _editingRule = null;
      _currentRuleId = null;
      _selectedMatches.clear();
      _followingShown.clear();
      _shown = 100;
      _error = null;
    });
    _loadRequestedSessionId = widget.session.sessionId;
    await task.load();
  }

  bool _knownConflict(RuleWorkbenchTask task, Set<String> ids) {
    final trial = task.trial;
    if (trial == null || ids.length < 2) return false;
    final selected = task.matches.where((item) => ids.contains(item.id));
    final keys = selected.map((item) => _matchKey(item.match)).toSet();
    return trial.conflictSamples.any(
      (conflict) =>
          keys.contains(_matchKey(conflict.first)) &&
          keys.contains(_matchKey(conflict.second)),
    );
  }

  String _matchKey(RuleScanMatch match) =>
      '${match.chapterId}\u0000${match.blockId}\u0000${match.action.name}\u0000${match.startUtf16}\u0000${match.endUtf16}\u0000${match.headingLevel}\u0000${match.mappedTitle}\u0000${match.mappedNumber}\u0000${match.numberText}';

  Future<void> _saveAndApply(RuleWorkbenchTask task, String ruleId) async {
    final matchesById = {for (final item in task.matches) item.id: item};
    final ids = _selectedMatches
        .where((id) => matchesById[id]?.match.ruleIds.contains(ruleId) ?? false)
        .toSet();
    if (ids.isEmpty || ids.length > 100 || _knownConflict(task, ids)) return;
    await task.saveRule(ruleId);
    if (!mounted ||
        task.phase != RuleWorkbenchPhase.ready ||
        !task.hasCurrentTrial ||
        !task.isSaved(ruleId)) {
      return;
    }
    await task.applySelected(ids);
    if (mounted && task.phase == RuleWorkbenchPhase.applied) {
      setState(_selectedMatches.clear);
    }
  }

  Future<void> _locate(RuleWorkbenchMatch item) async {
    try {
      await widget.onLocate(item.match.chapterId, item.match.blockId);
    } on Object {
      if (mounted) {
        setState(
          () => _error = AppLocalizations.of(context).editorWorkbenchToolFailed,
        );
      }
    }
  }

  Future<void> _analyzeAdvertisement(
    RuleWorkbenchTask task,
    RuleWorkbenchMatch item,
  ) async {
    final sessionId = widget.session.sessionId;
    final saveSeq = widget.session.saveSeq;
    final match = item.match;
    if (sessionId == null ||
        !task.hasCurrentTrial ||
        task.isBusy ||
        match.action != ProofreadingRuleAction.advertisementCandidate ||
        item.selectedText.length > 8192) {
      return;
    }
    if (item.sourceBlockIndex < 0 ||
        item.sourceBlockIndex >= item.chapterBlocks.length ||
        item.chapterBlocks[item.sourceBlockIndex] is! TextBlock ||
        item.chapterBlocks[item.sourceBlockIndex].id != match.blockId ||
        (item.chapterBlocks[item.sourceBlockIndex] as TextBlock).text !=
            item.sourceText) {
      return;
    }
    var ruleName = match.ruleIds
        .map(
          (id) => task.rules.where((rule) => rule.id == id).firstOrNull?.name,
        )
        .whereType<String>()
        .join(', ');
    if (ruleName.length > 256) {
      final unit = ruleName.codeUnitAt(254);
      final end = unit >= 0xd800 && unit <= 0xdbff ? 254 : 255;
      ruleName = '${ruleName.substring(0, end)}…';
    }
    try {
      final chapter = await widget.session.readAiSelectionChapter(
        match.chapterId,
        isCancelled: () =>
            !mounted ||
            !task.hasCurrentTrial ||
            widget.session.sessionId != sessionId ||
            widget.session.saveSeq != saveSeq,
      );
      if (!mounted ||
          !task.hasCurrentTrial ||
          widget.session.sessionId != sessionId ||
          widget.session.saveSeq != saveSeq ||
          !chapter.blocks.any(
            (block) =>
                block is TextBlock &&
                block.id == match.blockId &&
                block.text == item.sourceText,
          )) {
        return;
      }
      final book = widget.session.book;
      if (book == null) return;
      final request = AiAdvertisementRequest.fromSelection(
        book: book,
        sessionId: sessionId,
        sessionRevision: saveSeq,
        chapterId: match.chapterId,
        blockId: match.blockId,
        startUtf16: match.startUtf16,
        endUtf16: match.endUtf16,
        original: item.selectedText,
        ruleName: ruleName.isEmpty ? null : ruleName,
      );
      if (!mounted ||
          !task.hasCurrentTrial ||
          widget.session.sessionId != sessionId ||
          widget.session.saveSeq != saveSeq) {
        return;
      }
      await widget.onAnalyzeAdvertisement?.call(request);
    } on Object {
      if (mounted) {
        setState(
          () =>
              _error = AppLocalizations.of(context)
                  .aiAdvertisementSelectionExpired,
        );
      }
    }
  }

  Future<void> _exportSharedRules(RuleWorkbenchTask task) async {
    final l10n = AppLocalizations.of(context);
    final seen = <String>{};
    final rules = task.rules.where((rule) => seen.add(rule.id)).toList();
    if (rules.isEmpty) {
      setState(() => _notice = l10n.ruleWorkbenchNoGlobalRules);
      return;
    }
    final selectedIds = await _chooseExportRules(rules);
    if (!mounted || selectedIds == null) return;
    final selected = rules
        .where((rule) => selectedIds.contains(rule.id))
        .toList();
    if (selected.isEmpty) return;
    setState(() {
      _fileBusy = true;
      _notice = null;
      _error = null;
    });
    File? prepared;
    try {
      prepared = File(
        p.join(
          Directory.systemTemp.path,
          'bookloom-rules-${const Uuid().v4()}.json',
        ),
      );
      await prepared.writeAsString(
        encodeProofreadingRules(selected),
        flush: true,
      );
      final outcome = await ref
          .read(fileServiceProvider)
          .savePreparedFile(
            prepared,
            suggestedName:
                'bookloom-rules-${DateTime.now().toIso8601String().substring(0, 10)}.json',
            mimeType: 'application/json',
          );
      if (mounted && outcome is SaveSaved) {
        setState(
          () => _notice = l10n.ruleWorkbenchRulesExported(selected.length),
        );
      }
    } on Object catch (error) {
      if (mounted) {
        setState(
          () => _error = error is AppFailure
              ? error.message
              : l10n.editorWorkbenchToolFailed,
        );
      }
    } finally {
      await prepared?.delete();
      if (mounted) setState(() => _fileBusy = false);
    }
  }

  Future<Set<String>?> _chooseExportRules(List<ProofreadingRule> rules) async {
    final l10n = AppLocalizations.of(context);
    final selected = <String>{for (final rule in rules) rule.id};
    return showDialog<Set<String>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final allSelected = selected.length == rules.length;
          return AlertDialog(
            key: const ValueKey('rule-export-dialog'),
            title: Text(l10n.ruleWorkbenchExportSelectTitle),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CheckboxListTile(
                    key: const ValueKey('rule-export-all'),
                    contentPadding: EdgeInsets.zero,
                    value: allSelected,
                    title: Text(l10n.ruleWorkbenchSelectAll),
                    onChanged: (value) => setDialogState(() {
                      selected.clear();
                      if (value == true) {
                        selected.addAll(rules.map((rule) => rule.id));
                      }
                    }),
                  ),
                  const Divider(height: 1),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 320),
                    child: SingleChildScrollView(
                      child: Column(
                        children: [
                          for (final rule in rules)
                            CheckboxListTile(
                              key: ValueKey('rule-export-${rule.id}'),
                              contentPadding: EdgeInsets.zero,
                              value: selected.contains(rule.id),
                              title: Text(rule.name),
                              subtitle: Text(
                                rule.scope == ProofreadingRuleScope.book
                                    ? l10n.ruleWorkbenchBookScope
                                    : l10n.ruleWorkbenchGlobalScope,
                              ),
                              onChanged: (value) => setDialogState(() {
                                if (value == true) {
                                  selected.add(rule.id);
                                } else {
                                  selected.remove(rule.id);
                                }
                              }),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: Text(l10n.commonCancel),
              ),
              FilledButton(
                key: const ValueKey('rule-export-confirm'),
                onPressed: selected.isEmpty
                    ? null
                    : () => Navigator.pop(
                        dialogContext,
                        Set<String>.of(selected),
                      ),
                child: Text(l10n.ruleWorkbenchExportSelected(selected.length)),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _importSharedRules(RuleWorkbenchTask task) async {
    final l10n = AppLocalizations.of(context);
    final files = ref.read(fileServiceProvider);
    final inputs = await files.pickImports(
      multiple: false,
      extensions: const <String>['json'],
    );
    if (inputs.isEmpty) return;
    final input = inputs.single;
    setState(() {
      _fileBusy = true;
      _notice = null;
      _error = null;
    });
    try {
      final bytes = <int>[];
      await for (final chunk in input.openRead()) {
        bytes.addAll(chunk);
        if (bytes.length > 2 * 1024 * 1024) {
          throw const ValidationFailure('规则文件超过 2 MiB。');
        }
      }
      final decoded = decodeProofreadingRules(utf8.decode(bytes));
      final shared = decoded
          .where((rule) => rule.scope == ProofreadingRuleScope.global)
          .toList();
      final bookRules = decoded
          .where((rule) => rule.scope == ProofreadingRuleScope.book)
          .toList();
      final currentBookId = widget.session.book?.id;
      if (bookRules.isNotEmpty && currentBookId == null) {
        throw const ValidationFailure('当前没有打开的书稿，无法复制本书规则。');
      }
      final remapped = <ProofreadingRule>[
        for (final rule in bookRules) rule.withBookId(currentBookId!),
      ];
      final usable = <ProofreadingRule>[...shared, ...remapped];
      if (usable.isEmpty) {
        if (mounted) {
          setState(() => _notice = l10n.ruleWorkbenchRulesNoSharedInFile);
        }
        return;
      }
      final existing = task.rules
          .where((rule) => usable.any((incoming) => incoming.id == rule.id))
          .length;
      if (!mounted) return;
      var copyConflicts = false;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            key: const ValueKey('rule-import-dialog'),
            title: Text(l10n.ruleWorkbenchRulesImportTitle),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.ruleWorkbenchRulesImportBody(
                    shared.length,
                    bookRules.length,
                    existing,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  l10n.ruleWorkbenchImportPreview,
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 180),
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final rule in usable)
                          Text(
                            '${rule.name} · '
                            '${rule.scope == ProofreadingRuleScope.global ? l10n.ruleWorkbenchGlobalScope : l10n.ruleWorkbenchBookScope}'
                            '${task.rules.any((existingRule) => existingRule.id == rule.id) ? ' · ${l10n.ruleWorkbenchImportWillSkip}' : ''}',
                            key: ValueKey('rule-import-preview-${rule.id}'),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                ),
                if (existing > 0)
                  CheckboxListTile(
                    key: const ValueKey('rule-import-copy-conflicts'),
                    contentPadding: EdgeInsets.zero,
                    title: Text(l10n.ruleWorkbenchRulesCopyConflicts),
                    value: copyConflicts,
                    onChanged: (value) {
                      setDialogState(() => copyConflicts = value ?? false);
                    },
                  ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(l10n.commonCancel),
              ),
              FilledButton(
                key: const ValueKey('rule-import-confirm'),
                onPressed: () => Navigator.pop(context, true),
                child: Text(l10n.ruleWorkbenchImportSharedRules),
              ),
            ],
          ),
        ),
      );
      if (confirmed != true || !mounted) return;
      final taken = {for (final rule in task.rules) rule.id};
      final imported = <ProofreadingRule>[];
      for (final rule in usable) {
        if (!taken.contains(rule.id) || !copyConflicts) {
          imported.add(rule);
          taken.add(rule.id);
          continue;
        }
        final base = rule.id.length > 100 ? rule.id.substring(0, 100) : rule.id;
        var suffix = const Uuid().v4().replaceAll('-', '').substring(0, 12);
        var candidate = '$base-$suffix';
        while (taken.contains(candidate)) {
          suffix = const Uuid().v4().replaceAll('-', '').substring(0, 12);
          candidate = '$base-$suffix';
        }
        imported.add(rule.withId(candidate));
        taken.add(candidate);
      }
      final merged = await ref
          .read(proofreadingRuleStoreProvider)
          .mergeMissing(imported);
      await task.load();
      if (mounted) {
        setState(
          () => _notice = l10n.ruleWorkbenchRulesImported(
            merged.addedIds.length,
            merged.skippedIds.length,
          ),
        );
      }
    } on AppFailure catch (error) {
      if (mounted) setState(() => _error = error.message);
    } on Object {
      if (mounted) {
        setState(() => _error = l10n.ruleWorkbenchRulesImportInvalid);
      }
    } finally {
      await input.release();
      if (mounted) setState(() => _fileBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final task = ref.watch(ruleWorkbenchTaskProvider(widget.session));
    final taskChanged = !identical(_task, task);
    if (taskChanged) {
      _task = task;
      _loadRequestedSessionId = null;
    }
    final sessionId = widget.session.sessionId;
    if (_panelSessionId != sessionId) {
      if (_panelSessionId != null && widget.initialRule != null) {
        _initialHandled = true;
        _initialRejected = true;
      }
      _panelSessionId = sessionId;
      _loadRequestedSessionId = null;
      _editing = false;
      _editingRule = null;
      _currentRuleId = null;
      _selectedMatches.clear();
      _followingShown.clear();
      _shown = 100;
      _error = null;
    }
    if (widget.initialRule case final initialRule? when !_initialHandled) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _acceptInitial(task, initialRule);
      });
    }
    if (taskChanged &&
        _currentRuleId == null &&
        task.selectedRuleIds.length == 1) {
      _currentRuleId = task.selectedRuleIds.single;
    }
    if (sessionId != null &&
        !task.isLoaded &&
        !task.isBusy &&
        _loadRequestedSessionId != sessionId) {
      _loadRequestedSessionId = sessionId;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted &&
            identical(_task, task) &&
            widget.session.sessionId == sessionId &&
            !task.isLoaded &&
            !task.isBusy) {
          unawaited(task.load());
        }
      });
    }
    final trial = task.hasCurrentTrial ? task.trial : null;
    final matches = trial == null ? <RuleWorkbenchMatch>[] : task.matches;
    final count = matches.length < _shown ? matches.length : _shown;
    return ListView.builder(
      padding: const EdgeInsets.all(AppSpacing.xl),
      itemCount: 1 + count + (matches.length > count ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == 0) return _controls(context, task, trial, count);
        if (index <= count) {
          return _matchTile(context, task, matches[index - 1]);
        }
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
          child: Center(
            child: TextButton.icon(
              key: const ValueKey('rule-more'),
              onPressed: () => setState(() => _shown += 100),
              icon: const Icon(Icons.expand_more),
              label: Text(AppLocalizations.of(context).ruleWorkbenchMore),
            ),
          ),
        );
      },
    );
  }

  Widget _importRulesSection(BuildContext context, ImportRuleSummary import) {
    final l10n = AppLocalizations.of(context);
    final subtitle = import.invalid
        ? l10n.ruleWorkbenchImportInvalid
        : [
            l10n.ruleWorkbenchImportPreset(import.presetName),
            if (import.isCustom) l10n.ruleWorkbenchImportCustom,
            l10n.ruleWorkbenchEnabled,
          ].join(' · ');
    return ExpansionTile(
      key: const ValueKey('rule-import-rules'),
      tilePadding: EdgeInsets.zero,
      title: Text(l10n.ruleWorkbenchImportRules),
      subtitle: Text(subtitle),
      childrenPadding: const EdgeInsets.only(left: AppSpacing.md),
      expandedCrossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (import.invalid)
          Text(
            l10n.ruleWorkbenchImportInvalid,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          )
        else ...[
          for (final (index, entry) in import.entries.indexed)
            ListTile(
              key: ValueKey('rule-import-entry-$index'),
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(_importRoleLabel(l10n, entry.role)),
              subtitle: SelectableText(entry.pattern),
            ),
          if (!import.hasEntries)
            Text(
              import.isAuto
                  ? l10n.ruleWorkbenchImportAutoNote
                  : l10n.ruleWorkbenchImportEmpty,
            ),
          if (import.hasEntries && import.isAuto)
            Text(l10n.ruleWorkbenchImportAutoNote),
          if (import.hasCustomSpec) Text(l10n.ruleWorkbenchImportCustomNote),
          const SizedBox(height: AppSpacing.sm),
          Text(l10n.ruleWorkbenchImportReadOnly),
        ],
      ],
    );
  }

  Widget _controls(
    BuildContext context,
    RuleWorkbenchTask task,
    RuleScanResult? trial,
    int shown,
  ) {
    final l10n = AppLocalizations.of(context);
    final canUseTrial = trial != null && !_editing && !task.isBusy;
    final selectedRule = task.rules
        .where((rule) => rule.id == _currentRuleId)
        .firstOrNull;
    final matchesById = {for (final item in task.matches) item.id: item};
    final selectedForApply = _selectedMatches
        .where((id) => matchesById[id]?.canApply ?? false)
        .toSet();
    final selectedCurrentRule = selectedRule == null
        ? <String>{}
        : selectedForApply
              .where(
                (id) =>
                    matchesById[id]!.match.ruleIds.contains(selectedRule.id),
              )
              .toSet();
    final hasConflict = _knownConflict(task, selectedForApply);
    final hasCurrentRuleConflict = _knownConflict(task, selectedCurrentRule);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.ruleWorkbenchOffline),
        if (_initialRejected)
          Text(
            l10n.ruleWorkbenchInitialRejected,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        if (task.importRules case final import?) ...[
          const SizedBox(height: AppSpacing.sm),
          _importRulesSection(context, import),
        ],
        const SizedBox(height: AppSpacing.md),
        Text(
          l10n.ruleWorkbenchRules,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        if (task.rules.isNotEmpty)
          TextField(
            key: const ValueKey('rule-search'),
            controller: _search,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: l10n.ruleWorkbenchSearch,
              suffixIcon: _search.text.isEmpty
                  ? null
                  : IconButton(
                      key: const ValueKey('rule-search-clear'),
                      tooltip: l10n.ruleWorkbenchClearSearch,
                      onPressed: () {
                        _search.clear();
                        setState(() {});
                      },
                      icon: const Icon(Icons.clear),
                    ),
            ),
            onChanged: (_) => setState(() {}),
          ),
        if (task.rules.isEmpty && !task.isBusy) Text(l10n.ruleWorkbenchEmpty),
        if (task.rules.isNotEmpty &&
            _search.text.trim().isNotEmpty &&
            task.rules.where(_matchesSearch).isEmpty)
          Text(l10n.ruleWorkbenchNoMatches),
        for (final rule in task.rules.where(_matchesSearch))
          ListTile(
            key: ValueKey('rule-row-${rule.id}'),
            contentPadding: EdgeInsets.zero,
            onTap: task.isBusy || _editing
                ? null
                : () => setState(() => _currentRuleId = rule.id),
            leading: Checkbox(
              key: ValueKey('rule-select-${rule.id}'),
              value: task.selectedRuleIds.contains(rule.id),
              onChanged: task.isBusy || _editing
                  ? null
                  : (value) {
                      task.setRuleSelected(rule.id, value == true);
                      setState(() {
                        _currentRuleId = rule.id;
                        _selectedMatches.clear();
                        _followingShown.clear();
                        _shown = 100;
                      });
                    },
            ),
            title: Text(rule.name),
            subtitle: Text(
              [
                _sourceLabel(l10n, rule.source),
                if (rule.kind == ProofreadingRuleKind.chapter)
                  rule.headingLevel == 1
                      ? l10n.ruleWorkbenchVolumeLevel
                      : l10n.ruleWorkbenchChapterLevel,
                rule.scope == ProofreadingRuleScope.book
                    ? l10n.ruleWorkbenchBookScope
                    : l10n.ruleWorkbenchGlobalScope,
                rule.enabled
                    ? l10n.ruleWorkbenchEnabled
                    : l10n.ruleWorkbenchDisabled,
                if (_currentRuleId == rule.id) l10n.ruleWorkbenchCurrent,
                if (!task.isSaved(rule.id)) l10n.ruleWorkbenchUnsaved,
              ].join(' · '),
            ),
            trailing: PopupMenuButton<String>(
              tooltip: l10n.ruleWorkbenchActions,
              enabled: !task.isBusy && !_editing,
              onSelected: (choice) {
                if (choice == 'edit') _beginEdit(task, rule);
                if (choice == 'toggle') unawaited(_toggleEnabled(task, rule));
                if (choice == 'delete') unawaited(_delete(task, rule));
                if (choice == 'duplicate') {
                  unawaited(_duplicateRule(task, rule));
                }
              },
              itemBuilder: (context) => [
                if (rule.source != ProofreadingRuleSource.builtIn) ...[
                  PopupMenuItem(
                    value: 'edit',
                    child: Text(l10n.ruleWorkbenchEdit),
                  ),
                  PopupMenuItem(
                    value: 'toggle',
                    child: Text(
                      rule.enabled
                          ? l10n.ruleWorkbenchDisable
                          : l10n.ruleWorkbenchEnable,
                    ),
                  ),
                  PopupMenuItem(
                    value: 'delete',
                    child: Text(l10n.ruleWorkbenchDelete),
                  ),
                ],
                PopupMenuItem(
                  value: 'duplicate',
                  child: Text(l10n.ruleWorkbenchDuplicate),
                ),
              ],
            ),
          ),
        const SizedBox(height: AppSpacing.sm),
        if (selectedRule != null)
          ExpansionTile(
            key: const ValueKey('rule-definition'),
            title: Text(l10n.ruleWorkbenchDefinition),
            children: [
              ListTile(
                title: Text('${l10n.ruleWorkbenchId}: ${selectedRule.id}'),
              ),
              ListTile(
                title: Text('${l10n.ruleWorkbenchName}: ${selectedRule.name}'),
              ),
              ListTile(
                title: Text(
                  '${l10n.ruleWorkbenchBookId}: ${selectedRule.bookId}',
                ),
              ),
              ListTile(
                title: Text(
                  '${l10n.ruleWorkbenchSource}: ${_sourceLabel(l10n, selectedRule.source)}',
                ),
              ),
              ListTile(
                title: Text(
                  '${l10n.ruleWorkbenchKind}: ${selectedRule.kind == ProofreadingRuleKind.chapter ? l10n.ruleWorkbenchChapter : l10n.ruleWorkbenchAdvertisement}',
                ),
              ),
              ListTile(
                title: Text(
                  '${l10n.ruleWorkbenchTarget}: ${_targetLabel(l10n, selectedRule.target)}',
                ),
              ),
              if (selectedRule.kind == ProofreadingRuleKind.chapter)
                ListTile(
                  title: Text(
                    '${l10n.ruleWorkbenchHeadingLevel}: ${selectedRule.headingLevel == 1 ? l10n.ruleWorkbenchVolumeLevel : l10n.ruleWorkbenchChapterLevel}',
                  ),
                ),
              ListTile(
                title: Text(
                  '${l10n.ruleWorkbenchMode}: ${selectedRule.mode == ProofreadingMatchMode.literal ? l10n.ruleWorkbenchLiteral : l10n.ruleWorkbenchSafeRegex}',
                ),
              ),
              ListTile(
                title: Text(
                  '${l10n.ruleWorkbenchPattern}: ${selectedRule.pattern}',
                ),
              ),
              if (selectedRule.excludePattern != null)
                ListTile(
                  key: const ValueKey('rule-definition-exclude'),
                  title: Text(
                    '${l10n.ruleWorkbenchExcludePattern}: ${selectedRule.excludePattern}',
                  ),
                ),
              if (selectedRule.wholeLineOnly)
                ListTile(
                  key: const ValueKey('rule-definition-whole-line'),
                  title: Text(
                    '${l10n.ruleWorkbenchWholeLine}: ${l10n.ruleWorkbenchEnabled}',
                  ),
                ),
              if (selectedRule.kind == ProofreadingRuleKind.chapter &&
                  selectedRule.mode == ProofreadingMatchMode.safeRegex)
                ListTile(
                  title: Text(
                    '${l10n.ruleWorkbenchTitleCaptureGroup}: ${selectedRule.titleCaptureGroup?.toString() ?? l10n.ruleWorkbenchFullHeadingLine}',
                  ),
                ),
              if (selectedRule.numberCaptureGroup != null)
                ListTile(
                  title: Text(
                    '${l10n.ruleWorkbenchNumberCaptureGroup}: ${selectedRule.numberCaptureGroup}',
                  ),
                ),
              ListTile(
                title: Text(
                  '${l10n.ruleWorkbenchAction}: ${_actionLabel(l10n, selectedRule.action, headingLevel: selectedRule.headingLevel)}',
                ),
              ),
              ListTile(
                title: Text(
                  '${l10n.ruleWorkbenchScope}: ${selectedRule.scope == ProofreadingRuleScope.book ? l10n.ruleWorkbenchBookScope : l10n.ruleWorkbenchGlobalScope}',
                ),
              ),
              ListTile(
                title: Text(
                  '${l10n.ruleWorkbenchPriority}: ${selectedRule.priority}',
                ),
              ),
              ListTile(
                title: Text(
                  '${l10n.ruleWorkbenchEnabled}: ${selectedRule.enabled ? l10n.ruleWorkbenchEnabled : l10n.ruleWorkbenchDisabled}',
                ),
              ),
              ListTile(
                title: Text(
                  '${l10n.ruleWorkbenchCaseSensitive}: ${selectedRule.caseSensitive ? l10n.ruleWorkbenchEnabled : l10n.ruleWorkbenchDisabled}',
                ),
              ),
              ListTile(
                key: const ValueKey('rule-definition-positive'),
                contentPadding: EdgeInsets.zero,
                title: Text(l10n.ruleWorkbenchPositive),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final example in selectedRule.positiveExamples)
                      SelectableText(example),
                  ],
                ),
              ),
              ListTile(
                key: const ValueKey('rule-definition-negative'),
                contentPadding: EdgeInsets.zero,
                title: Text(l10n.ruleWorkbenchNegative),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final example in selectedRule.negativeExamples)
                      SelectableText(example),
                  ],
                ),
              ),
            ],
          ),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            OutlinedButton.icon(
              key: const ValueKey('rule-new'),
              onPressed: task.isBusy || _editing
                  ? null
                  : () => _beginEdit(task),
              icon: const Icon(Icons.add),
              label: Text(l10n.ruleWorkbenchNew),
            ),
            FilledButton.tonalIcon(
              key: const ValueKey('rule-scan'),
              onPressed: task.isBusy || _editing || task.selectedRuleIds.isEmpty
                  ? null
                  : () {
                      setState(() {
                        _selectedMatches.clear();
                        _followingShown.clear();
                        _shown = 100;
                      });
                      unawaited(task.scan());
                    },
              icon: const Icon(Icons.search),
              label: Text(l10n.ruleWorkbenchScan),
            ),
            OutlinedButton.icon(
              key: const ValueKey('rule-export'),
              onPressed: _fileBusy || task.isBusy || _editing || !task.isLoaded
                  ? null
                  : () => unawaited(_exportSharedRules(task)),
              icon: const Icon(Icons.upload_file),
              label: Text(l10n.ruleWorkbenchExportSharedRules),
            ),
            OutlinedButton.icon(
              key: const ValueKey('rule-import'),
              onPressed: _fileBusy || task.isBusy || _editing || !task.isLoaded
                  ? null
                  : () => unawaited(_importSharedRules(task)),
              icon: const Icon(Icons.download),
              label: Text(l10n.ruleWorkbenchImportSharedRules),
            ),
          ],
        ),
        if (_notice != null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: Text(_notice!, key: const ValueKey('rule-notice')),
          ),
        if (_editing) ...[
          const Divider(height: AppSpacing.xxl),
          _form(context, task),
        ],
        if (task.isBusy) ...[
          const SizedBox(height: AppSpacing.md),
          const LinearProgressIndicator(),
          Text(_phaseLabel(l10n, task.phase)),
          TextButton.icon(
            key: const ValueKey('rule-cancel-task'),
            onPressed: task.cancel,
            icon: const Icon(Icons.close),
            label: Text(l10n.editorWorkbenchCancelTask),
          ),
        ] else if (task.phase != RuleWorkbenchPhase.idle) ...[
          const SizedBox(height: AppSpacing.md),
          Text(_phaseLabel(l10n, task.phase)),
        ],
        if (_error != null || task.failure != null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: Text(
              _error ?? task.failure!.message,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        if (task.phase == RuleWorkbenchPhase.failed && !task.isBusy)
          TextButton.icon(
            key: const ValueKey('rule-reload'),
            onPressed: () => unawaited(_reload(task)),
            icon: const Icon(Icons.refresh),
            label: Text(l10n.ruleWorkbenchReload),
          ),
        if (trial != null) ...[
          const Divider(height: AppSpacing.xxl),
          Text(
            l10n.ruleWorkbenchResults,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          Text(
            '${l10n.ruleWorkbenchCoverage}: ${trial.coverage.chapters} ${l10n.ruleWorkbenchChapters}, '
            '${trial.coverage.textBlocks} ${l10n.ruleWorkbenchBlocks}, '
            '${trial.coverage.bodyLines} ${l10n.ruleWorkbenchLines}, '
            '${trial.coverage.inputUtf16} UTF-16',
          ),
          Text(
            '${l10n.ruleWorkbenchTotalMatches}: ${trial.totalMatches} · '
            '${l10n.ruleWorkbenchDistinctMatches}: ${trial.distinctMatches}',
          ),
          Text(
            '${l10n.ruleWorkbenchConflicts}: ${trial.totalConflicts} · '
            '${l10n.ruleWorkbenchConflictSamples}: ${trial.conflictSamples.length < 100 ? trial.conflictSamples.length : 100} · '
            '${l10n.ruleWorkbenchTruncated}: ${trial.totalConflicts - (trial.conflictSamples.length < 100 ? trial.conflictSamples.length : 100)}',
          ),
          Text('${l10n.ruleWorkbenchShown}: $shown / ${trial.distinctMatches}'),
          for (final rule in task.rules.where(
            (rule) => task.selectedRuleIds.contains(rule.id),
          ))
            Text(
              '${rule.name}: ${trial.executedRuleIds.contains(rule.id) ? '${l10n.ruleWorkbenchExecuted} ${trial.matchesByRuleId[rule.id] ?? 0}' : l10n.ruleWorkbenchNotExecuted}',
            ),
          if (trial.totalConflicts > 0)
            ExpansionTile(
              title: Text(l10n.ruleWorkbenchConflictDetails),
              children: [
                for (final conflict in trial.conflictSamples.take(100))
                  ListTile(
                    dense: true,
                    title: Text(_conflictLabel(l10n, conflict.kind)),
                    subtitle: Text(
                      '${conflict.first.chapterTitle} · '
                      '${conflict.first.lineNumber} / ${conflict.second.lineNumber}',
                    ),
                  ),
                if (trial.conflictSamples.length > 100)
                  Text(
                    '${l10n.ruleWorkbenchConflictSamples}: 100 / ${trial.conflictSamples.length}',
                  ),
              ],
            ),
          if (hasConflict)
            Text(
              l10n.aiProofreadingConflict,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          if (selectedForApply.length > 100) Text(l10n.ruleWorkbenchMaxApply),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              FilledButton.tonal(
                key: const ValueKey('rule-save'),
                onPressed:
                    canUseTrial &&
                        selectedRule != null &&
                        selectedRule.source != ProofreadingRuleSource.builtIn &&
                        task.selectedRuleIds.contains(selectedRule.id) &&
                        !task.isSaved(selectedRule.id)
                    ? () => unawaited(task.saveRule(selectedRule.id))
                    : null,
                child: Text(l10n.ruleWorkbenchSaveOnly),
              ),
              FilledButton(
                key: const ValueKey('rule-apply-selected'),
                onPressed:
                    canUseTrial &&
                        selectedForApply.isNotEmpty &&
                        selectedForApply.length <= 100 &&
                        !hasConflict
                    ? () => unawaited(task.applySelected(selectedForApply))
                    : null,
                child: Text(l10n.ruleWorkbenchApplySelected),
              ),
              FilledButton.tonal(
                key: const ValueKey('rule-save-apply'),
                onPressed:
                    canUseTrial &&
                        selectedRule != null &&
                        selectedRule.source != ProofreadingRuleSource.builtIn &&
                        task.selectedRuleIds.contains(selectedRule.id) &&
                        selectedCurrentRule.isNotEmpty &&
                        selectedCurrentRule.length <= 100 &&
                        !hasCurrentRuleConflict
                    ? () => unawaited(_saveAndApply(task, selectedRule.id))
                    : null,
                child: Text(l10n.ruleWorkbenchSaveApply),
              ),
            ],
          ),
          if (_hasCandidate(trial)) Text(l10n.ruleWorkbenchCandidateNotice),
        ],
        if (task.phase == RuleWorkbenchPhase.applied)
          Text('${l10n.aiProofreadingAppliedCount}: ${task.lastAppliedCount}'),
        const SizedBox(height: AppSpacing.md),
      ],
    );
  }

  bool _hasCandidate(RuleScanResult trial) => trial.samples.any(
    (match) => match.action == ProofreadingRuleAction.advertisementCandidate,
  );

  Widget _form(BuildContext context, RuleWorkbenchTask task) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.ruleWorkbenchIdentify,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        TextField(
          key: const ValueKey('rule-name'),
          controller: _name,
          maxLength: 128,
          decoration: InputDecoration(labelText: l10n.ruleWorkbenchName),
          onChanged: (_) => _formChanged(task),
        ),
        DropdownButtonFormField<ProofreadingRuleKind>(
          key: const ValueKey('rule-kind'),
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
          onChanged: (value) {
            if (value == null) return;
            setState(() {
              _kind = value;
              if (value != ProofreadingRuleKind.chapter) {
                _titleCapture.clear();
                _numberCapture.clear();
                _headingLevel = 2;
              }
              _target = value == ProofreadingRuleKind.chapter
                  ? ProofreadingRuleTarget.headingLine
                  : ProofreadingRuleTarget.bodyLine;
              _action = value == ProofreadingRuleKind.chapter
                  ? ProofreadingRuleAction.chapterCandidate
                  : ProofreadingRuleAction.advertisementCandidate;
            });
            _formChanged(task);
          },
        ),
        if (_kind == ProofreadingRuleKind.advertisement)
          DropdownButtonFormField<ProofreadingRuleTarget>(
            key: const ValueKey('rule-target'),
            initialValue: _target,
            isExpanded: true,
            decoration: InputDecoration(labelText: l10n.ruleWorkbenchTarget),
            items: [
              DropdownMenuItem(
                value: ProofreadingRuleTarget.bodyLine,
                child: Text(l10n.ruleWorkbenchBodyLine),
              ),
              DropdownMenuItem(
                value: ProofreadingRuleTarget.paragraph,
                child: Text(l10n.ruleWorkbenchParagraph),
              ),
            ],
            onChanged: (value) {
              if (value != null) {
                setState(() {
                  _target = value;
                  if (value == ProofreadingRuleTarget.paragraph) {
                    _wholeLine = false;
                  }
                });
              }
              _formChanged(task);
            },
          )
        else
          Text(l10n.ruleWorkbenchHeadingLine),
        if (_target != ProofreadingRuleTarget.paragraph)
          SwitchListTile(
            key: const ValueKey('rule-whole-line'),
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.ruleWorkbenchWholeLine),
            subtitle: Text(l10n.ruleWorkbenchWholeLineHelper),
            value: _wholeLine,
            onChanged: (value) {
              setState(() => _wholeLine = value);
              _formChanged(task);
            },
          ),
        if (_kind == ProofreadingRuleKind.chapter)
          DropdownButtonFormField<int>(
            key: const ValueKey('rule-heading-level'),
            initialValue: _headingLevel,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: l10n.ruleWorkbenchHeadingLevel,
            ),
            items: [
              DropdownMenuItem(
                value: 1,
                child: Text(l10n.ruleWorkbenchVolumeLevel),
              ),
              DropdownMenuItem(
                value: 2,
                child: Text(l10n.ruleWorkbenchChapterLevel),
              ),
            ],
            onChanged: (value) {
              if (value == null) return;
              setState(() => _headingLevel = value);
              _formChanged(task);
            },
          ),
        DropdownButtonFormField<ProofreadingMatchMode>(
          key: const ValueKey('rule-mode'),
          initialValue: _mode,
          isExpanded: true,
          decoration: InputDecoration(labelText: l10n.ruleWorkbenchMode),
          items: [
            DropdownMenuItem(
              value: ProofreadingMatchMode.literal,
              child: Text(l10n.ruleWorkbenchLiteral),
            ),
            DropdownMenuItem(
              value: ProofreadingMatchMode.safeRegex,
              child: Text(l10n.ruleWorkbenchSafeRegex),
            ),
          ],
          onChanged: (value) {
            if (value != null) {
              setState(() {
                _mode = value;
                if (value != ProofreadingMatchMode.safeRegex) {
                  _titleCapture.clear();
                  _numberCapture.clear();
                }
              });
            }
            _formChanged(task);
          },
        ),
        TextField(
          key: const ValueKey('rule-pattern'),
          controller: _pattern,
          maxLength: ProofreadingRule.maxPatternUtf16,
          decoration: InputDecoration(labelText: l10n.ruleWorkbenchPattern),
          onChanged: (_) => _formChanged(task),
        ),
        if (_kind == ProofreadingRuleKind.chapter &&
            _mode == ProofreadingMatchMode.safeRegex)
          ExpansionTile(
            key: const ValueKey('rule-advanced'),
            tilePadding: EdgeInsets.zero,
            initiallyExpanded: _titleCapture.text.isNotEmpty,
            title: Text(l10n.ruleWorkbenchAdvanced),
            children: [
              TextField(
                key: const ValueKey('rule-title-capture'),
                controller: _titleCapture,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: l10n.ruleWorkbenchTitleCaptureGroup,
                  helperText: [
                    l10n.ruleWorkbenchTitleCaptureHelper,
                    if (_captureCount() case final count?)
                      '${l10n.ruleWorkbenchAvailableGroups}: 0–$count',
                  ].join(' '),
                  errorText: _invalidTitleCapture(_captureCount())
                      ? l10n.ruleWorkbenchTitleCaptureInvalid
                      : null,
                ),
                onChanged: (_) {
                  if (_titleCapture.text.trim().isEmpty) _numberCapture.clear();
                  _formChanged(task);
                },
              ),
              TextField(
                key: const ValueKey('rule-number-capture'),
                controller: _numberCapture,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: l10n.ruleWorkbenchNumberCaptureGroup,
                  helperText: l10n.ruleWorkbenchNumberCaptureHelper,
                  errorText: _invalidNumberCapture(_captureCount())
                      ? l10n.ruleWorkbenchNumberCaptureInvalid
                      : null,
                ),
                onChanged: (_) => _formChanged(task),
              ),
            ],
          ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(l10n.ruleWorkbenchCaseSensitive),
          value: _caseSensitive,
          onChanged: (value) {
            setState(() => _caseSensitive = value);
            _formChanged(task);
          },
        ),
        TextField(
          key: const ValueKey('rule-positive'),
          controller: _positive,
          maxLines: 4,
          decoration: InputDecoration(
            labelText: l10n.ruleWorkbenchPositive,
            helperText: l10n.ruleWorkbenchOnePerLine,
          ),
          onChanged: (_) => _formChanged(task),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          l10n.ruleWorkbenchExclude,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        TextField(
          key: const ValueKey('rule-exclude'),
          controller: _exclude,
          maxLines: 1,
          decoration: InputDecoration(
            labelText: l10n.ruleWorkbenchExcludePattern,
            helperText: l10n.ruleWorkbenchExcludePatternHelper,
          ),
          onChanged: (_) => _formChanged(task),
        ),
        const SizedBox(height: AppSpacing.sm),
        TextField(
          key: const ValueKey('rule-negative'),
          controller: _negative,
          maxLines: 4,
          decoration: InputDecoration(
            labelText: l10n.ruleWorkbenchNegative,
            helperText: l10n.ruleWorkbenchOnePerLine,
          ),
          onChanged: (_) => _formChanged(task),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          l10n.ruleWorkbenchEffect,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        if (_kind == ProofreadingRuleKind.advertisement)
          DropdownButtonFormField<ProofreadingRuleAction>(
            key: const ValueKey('rule-action'),
            initialValue: _action,
            isExpanded: true,
            decoration: InputDecoration(labelText: l10n.ruleWorkbenchAction),
            items: [
              DropdownMenuItem(
                value: ProofreadingRuleAction.advertisementCandidate,
                child: Text(l10n.ruleWorkbenchCandidate),
              ),
              DropdownMenuItem(
                value: ProofreadingRuleAction.exactDeletion,
                child: Text(l10n.ruleWorkbenchExactDeletion),
              ),
            ],
            onChanged: (value) {
              if (value != null) setState(() => _action = value);
              _formChanged(task);
            },
          )
        else
          Text(
            _headingLevel == 1
                ? l10n.ruleWorkbenchVolumeEffect
                : l10n.ruleWorkbenchChapterEffect,
          ),
        DropdownButtonFormField<ProofreadingRuleScope>(
          key: const ValueKey('rule-scope'),
          initialValue: _scope,
          isExpanded: true,
          decoration: InputDecoration(labelText: l10n.ruleWorkbenchScope),
          items: [
            DropdownMenuItem(
              value: ProofreadingRuleScope.book,
              child: Text(l10n.ruleWorkbenchBookScope),
            ),
            DropdownMenuItem(
              value: ProofreadingRuleScope.global,
              child: Text(l10n.ruleWorkbenchGlobalScope),
            ),
          ],
          onChanged: (value) {
            if (value != null) setState(() => _scope = value);
            _formChanged(task);
          },
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(l10n.ruleWorkbenchEnabled),
          value: _enabled,
          onChanged: (value) {
            setState(() => _enabled = value);
            _formChanged(task);
          },
        ),
        TextField(
          key: const ValueKey('rule-priority'),
          controller: _priority,
          keyboardType: const TextInputType.numberWithOptions(signed: true),
          decoration: InputDecoration(labelText: l10n.ruleWorkbenchPriority),
          onChanged: (_) => _formChanged(task),
        ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            FilledButton(
              key: const ValueKey('rule-commit'),
              onPressed: () => unawaited(_commit(task)),
              child: Text(l10n.ruleWorkbenchUseDefinition),
            ),
            TextButton(
              onPressed: () => setState(() {
                _editing = false;
                _editingRule = null;
                _error = null;
              }),
              child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
            ),
          ],
        ),
      ],
    );
  }

  Widget _matchTile(
    BuildContext context,
    RuleWorkbenchTask task,
    RuleWorkbenchMatch item,
  ) {
    final l10n = AppLocalizations.of(context);
    final match = item.match;
    final isVolume = match.headingLevel == 1;
    final followingChaptersKey = '${item.id}-chapters';
    final canApply = task.hasCurrentTrial && !task.isBusy && item.canApply;
    final selected = _selectedMatches.contains(item.id);
    final after = item.sourceText.replaceRange(
      match.startUtf16,
      match.endUtf16,
      '',
    );
    return ExpansionTile(
      key: ValueKey('rule-hit-${item.id}'),
      title: Row(
        children: [
          if (item.canApply)
            Checkbox(
              key: ValueKey('rule-check-${item.id}'),
              value: selected,
              onChanged: canApply
                  ? (value) => setState(() {
                      if (value == true) {
                        _selectedMatches.add(item.id);
                      } else {
                        _selectedMatches.remove(item.id);
                      }
                    })
                  : null,
            ),
          Expanded(
            child: Text(
              '${match.chapterTitle} · ${l10n.ruleWorkbenchLine} ${match.lineNumber} · '
              '${_actionLabel(l10n, match.action, headingLevel: match.headingLevel)}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      subtitle: Text(
        item.selectedText,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      children: [
        Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${l10n.ruleWorkbenchRule}: ${match.ruleIds.map((id) => task.rules.where((rule) => rule.id == id).firstOrNull?.name ?? id).join(', ')}',
              ),
              Text(
                '${l10n.ruleWorkbenchOffset}: ${match.startUtf16}-${match.endUtf16} UTF-16',
              ),
              Text(l10n.aiProofreadingOriginal),
              SelectableText(item.sourceText),
              const SizedBox(height: AppSpacing.sm),
              if (match.action == ProofreadingRuleAction.chapterCandidate) ...[
                Text(l10n.ruleWorkbenchSplitPrefix),
                SelectableText(item.splitPrefix),
                Text(l10n.ruleWorkbenchRemoveHeadingLine),
                SelectableText(item.splitSourceLine),
                if (match.numberText != null)
                  Text('${l10n.ruleWorkbenchNumberToken}: ${match.numberText}'),
                if (match.mappedNumber != null)
                  Text(
                    '${l10n.ruleWorkbenchParsedNumber}: ${match.mappedNumber}',
                  ),
                Text(
                  '${isVolume ? l10n.ruleWorkbenchNewVolumeTitle : l10n.ruleWorkbenchSplitTitle}: ${item.splitTitle}',
                ),
                if (item.hasUnsupportedHeadingLineEnding)
                  Text(
                    l10n.ruleWorkbenchUnsupportedCrLine,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                Text(
                  isVolume
                      ? l10n.ruleWorkbenchVolumeFrontMatter
                      : l10n.ruleWorkbenchSplitSuffix,
                ),
                SelectableText(item.splitSuffix),
                Text(
                  isVolume
                      ? l10n.ruleWorkbenchVolumePreview
                      : l10n.aiProofreadingSplitResources,
                ),
                Text(
                  '${isVolume ? l10n.ruleWorkbenchVolumeFollowingBlockCount : l10n.ruleWorkbenchFollowingCount}: ${item.followingBlockCount}',
                ),
                if (item.followingBlockCount > 0)
                  ExpansionTile(
                    key: ValueKey('rule-following-blocks-${item.id}'),
                    title: Text(
                      isVolume
                          ? l10n.ruleWorkbenchVolumeFollowingBlocks
                          : l10n.ruleWorkbenchFollowingBlocks,
                    ),
                    children: [
                      for (final block in item.followingBlocks.take(
                        _followingShown[item.id] ?? 100,
                      ))
                        _followingBlock(context, block),
                      if (item.followingBlockCount >
                          (_followingShown[item.id] ?? 100))
                        TextButton.icon(
                          onPressed: () => setState(
                            () => _followingShown[item.id] =
                                (_followingShown[item.id] ?? 100) + 100,
                          ),
                          icon: const Icon(Icons.expand_more),
                          label: Text(l10n.ruleWorkbenchMore),
                        ),
                    ],
                  ),
                if (isVolume) ...[
                  Text(
                    '${l10n.ruleWorkbenchVolumeFollowingChapterCount}: ${item.followingChapters.length}',
                  ),
                  if (item.followingChapters.isNotEmpty)
                    ExpansionTile(
                      key: ValueKey('rule-following-chapters-${item.id}'),
                      title: Text(l10n.ruleWorkbenchVolumeFollowingChapters),
                      children: [
                        for (final chapter in item.followingChapters.take(
                          _followingShown[followingChaptersKey] ?? 100,
                        ))
                          ListTile(
                            key: ValueKey(
                              'rule-following-chapter-${item.id}-${chapter.id}',
                            ),
                            title: Text(
                              chapter.frontMatter && chapter.title.isEmpty
                                  ? l10n.ruleWorkbenchVolumeFrontMatter
                                  : chapter.title,
                            ),
                          ),
                        if (item.followingChapters.length >
                            (_followingShown[followingChaptersKey] ?? 100))
                          TextButton.icon(
                            key: ValueKey('rule-more-chapters-${item.id}'),
                            onPressed: () => setState(
                              () => _followingShown[followingChaptersKey] =
                                  (_followingShown[followingChaptersKey] ??
                                      100) +
                                  100,
                            ),
                            icon: const Icon(Icons.expand_more),
                            label: Text(l10n.ruleWorkbenchMoreChapters),
                          ),
                      ],
                    ),
                ],
              ] else if (match.action ==
                  ProofreadingRuleAction.exactDeletion) ...[
                Text('${l10n.ruleWorkbenchDeleteExact}: ${item.selectedText}'),
                Text(l10n.ruleWorkbenchAfter),
                SelectableText(after),
              ] else
                Text(l10n.ruleWorkbenchCandidateNotice),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  TextButton.icon(
                    key: ValueKey('rule-locate-${item.id}'),
                    onPressed: () => unawaited(_locate(item)),
                    icon: const Icon(Icons.my_location),
                    label: Text(l10n.aiProofreadingLocate),
                  ),
                  if (item.canApply)
                    TextButton.icon(
                      key: ValueKey('rule-apply-${item.id}'),
                      onPressed: canApply
                          ? () => unawaited(task.applySelected({item.id}))
                          : null,
                      icon: const Icon(Icons.check),
                      label: Text(l10n.aiProofreadingApplyOne),
                    ),
                  if (widget.onAnalyzeAdvertisement != null &&
                      match.action ==
                          ProofreadingRuleAction.advertisementCandidate)
                    Tooltip(
                      message: item.selectedText.length > 8192
                          ? l10n.aiAdvertisementSelectionLimit
                          : l10n.aiAdvertisementAnalyze,
                      child: TextButton.icon(
                        key: ValueKey('rule-ai-analyze-${item.id}'),
                        onPressed:
                            canApply ||
                                !task.hasCurrentTrial ||
                                task.isBusy ||
                                item.selectedText.length > 8192
                            ? null
                            : () =>
                                  unawaited(_analyzeAdvertisement(task, item)),
                        icon: const Icon(Icons.auto_awesome_outlined),
                        label: Text(l10n.aiAdvertisementAnalyze),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _followingBlock(BuildContext context, Block block) {
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
              if (caption != null) SelectableText(caption),
              if (alt.isNotEmpty) SelectableText(alt),
            ],
            if (block case FootnoteBlock(:final text, :final marker)) ...[
              if (marker != null) SelectableText(marker),
              SelectableText(text),
            ],
          ],
        ),
      ),
    );
  }
}

String _sourceLabel(AppLocalizations l10n, ProofreadingRuleSource source) =>
    switch (source) {
      ProofreadingRuleSource.builtIn => l10n.ruleWorkbenchBuiltIn,
      ProofreadingRuleSource.user => l10n.ruleWorkbenchUser,
      ProofreadingRuleSource.ai => l10n.ruleWorkbenchAiSource,
    };

String _actionLabel(
  AppLocalizations l10n,
  ProofreadingRuleAction action, {
  int headingLevel = 2,
}) => switch (action) {
  ProofreadingRuleAction.chapterCandidate =>
    headingLevel == 1
        ? l10n.ruleWorkbenchVolumeCandidate
        : l10n.ruleWorkbenchChapter,
  ProofreadingRuleAction.advertisementCandidate => l10n.ruleWorkbenchCandidate,
  ProofreadingRuleAction.exactDeletion => l10n.ruleWorkbenchExactDeletion,
};

String _targetLabel(AppLocalizations l10n, ProofreadingRuleTarget target) =>
    switch (target) {
      ProofreadingRuleTarget.headingLine => l10n.ruleWorkbenchHeadingLine,
      ProofreadingRuleTarget.bodyLine => l10n.ruleWorkbenchBodyLine,
      ProofreadingRuleTarget.paragraph => l10n.ruleWorkbenchParagraph,
    };

String _importRoleLabel(AppLocalizations l10n, ImportRuleRole role) =>
    switch (role) {
      ImportRuleRole.chapter => l10n.ruleWorkbenchImportEntryChapter,
      ImportRuleRole.volume => l10n.ruleWorkbenchImportEntryVolume,
      ImportRuleRole.drop => l10n.ruleWorkbenchImportEntryDrop,
      ImportRuleRole.inlineJunk => l10n.ruleWorkbenchImportEntryInlineJunk,
    };

String _conflictLabel(AppLocalizations l10n, RuleScanConflictKind kind) =>
    switch (kind) {
      RuleScanConflictKind.chapterBoundary => l10n.ruleWorkbenchChapterConflict,
      RuleScanConflictKind.deletionAndChapter =>
        l10n.ruleWorkbenchDeleteChapterConflict,
      RuleScanConflictKind.overlappingDeletions =>
        l10n.ruleWorkbenchDeletionConflict,
    };

String _phaseLabel(AppLocalizations l10n, RuleWorkbenchPhase phase) =>
    switch (phase) {
      RuleWorkbenchPhase.idle => l10n.aiProofreadingIdle,
      RuleWorkbenchPhase.loading => l10n.ruleWorkbenchLoading,
      RuleWorkbenchPhase.scanning => l10n.ruleWorkbenchScanning,
      RuleWorkbenchPhase.ready => l10n.ruleWorkbenchReady,
      RuleWorkbenchPhase.saving => l10n.ruleWorkbenchSaving,
      RuleWorkbenchPhase.saved => l10n.ruleWorkbenchSaved,
      RuleWorkbenchPhase.deleted => l10n.ruleWorkbenchDeleted,
      RuleWorkbenchPhase.applying => l10n.aiProofreadingApplying,
      RuleWorkbenchPhase.applied => l10n.aiProofreadingApplied,
      RuleWorkbenchPhase.cancelled => l10n.aiProofreadingCancelled,
      RuleWorkbenchPhase.stale => l10n.aiProofreadingStale,
      RuleWorkbenchPhase.failed => l10n.aiProofreadingFailed,
    };

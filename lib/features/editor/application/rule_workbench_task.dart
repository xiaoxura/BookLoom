import 'dart:collection';
import 'dart:convert';

import 'package:bookloom/core/editing/proofreading_rule.dart';
import 'package:bookloom/core/editing/proofreading_rule_scan.dart';
import 'package:bookloom/core/editing/proofreading_rule_store.dart';
import 'package:bookloom/core/editing/rule_heading_mapping.dart';
import 'package:bookloom/core/editing/rule_scan_changes.dart';
import 'package:bookloom/core/errors/app_failure.dart';
import 'package:bookloom/core/model/block.dart';
import 'package:bookloom/core/model/book.dart';
import 'package:bookloom/core/model/chapter.dart';
import 'package:bookloom/core/parsing/import_rule_summary.dart';
import 'package:bookloom/core/platform/background_jobs.dart';
import 'package:bookloom/features/editor/application/editor_session.dart';
import 'package:flutter/foundation.dart';

enum RuleWorkbenchPhase {
  idle,
  loading,
  scanning,
  ready,
  saving,
  saved,
  applying,
  applied,
  deleted,
  cancelled,
  stale,
  failed,
}

final class RuleWorkbenchMatch {
  RuleWorkbenchMatch({
    required this.id,
    required this.match,
    required this.sourceText,
    this.chapterBlocks = const [],
    this.sourceBlockIndex = -1,
    List<Chapter> followingChapters = const [],
  }) : followingChapters = UnmodifiableListView(followingChapters);

  final String id;
  final RuleScanMatch match;
  final String sourceText;
  final List<Block> chapterBlocks;
  final int sourceBlockIndex;
  final List<Chapter> followingChapters;

  Iterable<Block> get followingBlocks =>
      chapterBlocks.skip(sourceBlockIndex + 1);
  int get followingBlockCount => chapterBlocks.length - sourceBlockIndex - 1;

  String get selectedText =>
      sourceText.substring(match.startUtf16, match.endUtf16);
  int get _lineStart => match.startUtf16 == 0
      ? 0
      : 1 +
            [
              sourceText.lastIndexOf('\n', match.startUtf16 - 1),
              sourceText.lastIndexOf('\r', match.startUtf16 - 1),
            ].reduce((left, right) => left > right ? left : right);
  int get _lineEnd {
    final ends = [
      sourceText.indexOf('\n', match.startUtf16),
      sourceText.indexOf('\r', match.startUtf16),
    ].where((offset) => offset >= 0);
    return ends.isEmpty
        ? sourceText.length
        : ends.reduce((left, right) => left < right ? left : right);
  }

  String get splitSourceLine => sourceText.substring(_lineStart, _lineEnd);
  String get splitTitle {
    final title = match.mappedTitle ?? splitSourceLine.trim();
    final number = match.mappedNumber;
    return number == null
        ? title
        : RuleHeadingMapping.composeTitle(
            title: title,
            number: number,
            headingLevel: match.headingLevel,
          );
  }

  bool get hasUnsupportedHeadingLineEnding =>
      match.action == ProofreadingRuleAction.chapterCandidate &&
      !RuleScanChanges.supportsHeadingLineEnding(sourceText, _lineEnd);
  String get splitPrefix => sourceText.substring(0, _lineStart);
  String get splitSuffix {
    var end = _lineEnd;
    if (end < sourceText.length && sourceText[end] == '\r') end++;
    if (end < sourceText.length && sourceText[end] == '\n') end++;
    return sourceText.substring(end);
  }

  bool get canApply => switch (match.action) {
    ProofreadingRuleAction.advertisementCandidate => false,
    ProofreadingRuleAction.exactDeletion => true,
    ProofreadingRuleAction.chapterCandidate =>
      match.endUtf16 <= _lineEnd &&
          !hasUnsupportedHeadingLineEnding &&
          splitTitle.isNotEmpty &&
          splitTitle.length <= 256,
  };
}

class RuleWorkbenchTask extends ChangeNotifier {
  factory RuleWorkbenchTask({
    required EditorSession session,
    required ProofreadingRuleStore store,
    BackgroundJobs? jobs,
  }) => RuleWorkbenchTask._(session, store, jobs);

  RuleWorkbenchTask._(this._session, this._store, BackgroundJobs? jobs)
    : _jobs = jobs ?? BackgroundJobs(),
      _ownsJobs = jobs == null {
    _session.addListener(_sessionChanged);
  }

  final EditorSession _session;
  final ProofreadingRuleStore _store;
  final BackgroundJobs _jobs;
  final bool _ownsJobs;
  RuleWorkbenchPhase _phase = RuleWorkbenchPhase.idle;
  List<ProofreadingRule> _rules = const [];
  final Set<String> _selectedRuleIds = {};
  final Map<String, ProofreadingRule> _persistedRules = {};
  ImportRuleSummary? _importRules;
  RuleScanResult? _trial;
  Book? _snapshot;
  List<RuleWorkbenchMatch> _matches = const [];
  String? _bookId;
  String? _sessionId;
  int? _revision;
  String? _trialFingerprint;
  String? _loadedSessionId;
  AppFailure? _failure;
  bool _working = false;
  bool _disposed = false;
  bool _workerActive = false;
  bool _applying = false;
  bool _commitFinished = false;
  int _generation = 0;
  int _lastAppliedCount = 0;

  RuleWorkbenchPhase get phase => _phase;
  List<ProofreadingRule> get rules => _rules;
  Set<String> get selectedRuleIds => Set<String>.unmodifiable(_selectedRuleIds);
  RuleScanResult? get trial => _trial;

  /// Read-only snapshot of the import rules currently applied to this book.
  ImportRuleSummary? get importRules => _importRules;
  List<RuleWorkbenchMatch> get matches => _matches;
  AppFailure? get failure => _failure;
  bool get isBusy => _working;
  bool get isLoaded =>
      _loadedSessionId != null && _loadedSessionId == _session.sessionId;
  int get lastAppliedCount => _lastAppliedCount;
  bool get hasCurrentTrial =>
      _trial != null && _isCurrent && _trialFingerprint == _fingerprint;
  bool isSaved(String id) {
    final saved = _persistedRules[id];
    final current = _rules.where((rule) => rule.id == id).firstOrNull;
    return saved != null &&
        current != null &&
        proofreadingRuleFingerprint(saved) ==
            proofreadingRuleFingerprint(current);
  }

  String get _fingerprint => jsonEncode([
    for (final rule in _rules.where(
      (rule) => _selectedRuleIds.contains(rule.id),
    ))
      proofreadingRuleFingerprint(rule),
  ]);
  bool get _isCurrent =>
      !_disposed &&
      _session.sessionId != null &&
      _session.sessionId == _sessionId &&
      _session.book?.id == _bookId &&
      _session.saveSeq == _revision;

  void putRule(ProofreadingRule rule) {
    if (_disposed || _working) return;
    if (rule.source == ProofreadingRuleSource.builtIn ||
        !rule.appliesToBook(_session.book?.id ?? '')) {
      throw const ValidationFailure('规则来源或作用域无效。');
    }
    _rules = List<ProofreadingRule>.unmodifiable(
      <ProofreadingRule>[
        for (final current in _rules)
          if (current.id != rule.id) current,
        rule,
      ]..sort((left, right) => left.id.compareTo(right.id)),
    );
    _selectedRuleIds.add(rule.id);
    _invalidate(RuleWorkbenchPhase.idle);
  }

  void setRuleSelected(String id, bool selected) {
    if (_disposed || _working || !_rules.any((rule) => rule.id == id)) return;
    if (selected) {
      _selectedRuleIds.add(id);
    } else {
      _selectedRuleIds.remove(id);
    }
    _invalidate(RuleWorkbenchPhase.idle);
  }

  Future<void> load() => _run(RuleWorkbenchPhase.loading, () async {
    final source = _session.book;
    final identity = _session.sessionId;
    if (source == null || identity == null) {
      throw const ValidationFailure('请先打开书稿。');
    }
    final generation = _generation;
    _bookId = source.id;
    _sessionId = identity;
    _revision = _session.saveSeq;
    _clearTrial();
    _importRules = ImportRuleSummary.fromOptions(source.parseOptions);
    final loaded = await _store.loadForBook(source.id);
    if (_disposed ||
        generation != _generation ||
        _session.book?.id != source.id ||
        _session.sessionId != identity) {
      throw const TaskCancelled();
    }
    _rules = List<ProofreadingRule>.unmodifiable(loaded);
    _loadedSessionId = identity;
    _persistedRules
      ..clear()
      ..addEntries(loaded.map((rule) => MapEntry(rule.id, rule)));
    _selectedRuleIds.clear();
    _clearTrial();
    _phase = RuleWorkbenchPhase.idle;
  });

  Future<void> scan() => _run(RuleWorkbenchPhase.scanning, () async {
    if (_selectedRuleIds.isEmpty) {
      throw const ValidationFailure('请明确选择本次试跑的规则。');
    }
    _clearTrial();
    _bookId = _session.book?.id;
    _sessionId = _session.sessionId;
    _revision = _session.saveSeq;
    final generation = _generation;
    final fingerprint = _fingerprint;
    bool current() =>
        generation == _generation && _isCurrent && fingerprint == _fingerprint;
    if (!current()) throw const ValidationFailure('书稿尚未就绪。');
    const limits = RuleScanLimits(maxSamples: 20000);
    final snapshot = await _session.readRuleSnapshot(
      limits: limits,
      isCancelled: () => !current(),
    );
    if (!current()) throw const TaskCancelled();
    final work = ProofreadingRuleScan.scanInBackground(
      snapshot,
      selectedRules: _rules.where((rule) => _selectedRuleIds.contains(rule.id)),
      loadedChapterIds: snapshot.chapters.map((chapter) => chapter.id).toSet(),
      jobs: _jobs,
      revision: _revision!,
      limits: limits,
    );
    _workerActive = true;
    final result = await work;
    _workerActive = false;
    if (!current()) throw const TaskCancelled();
    if (result.hiddenMatches != 0) {
      throw const ValidationFailure('试跑未保留完整命中，不能用于应用。');
    }
    final sources = <String, (String, List<Block>, int)>{
      for (final chapter in snapshot.chapters)
        for (final (index, block) in chapter.blocks.indexed)
          if (block is TextBlock)
            '${chapter.id}\u0000${block.id}': (
              block.text,
              chapter.blocks,
              index,
            ),
    };
    final chapterIndices = {
      for (final (index, chapter) in snapshot.chapters.indexed)
        chapter.id: index,
    };
    final followingByChapter = <String, List<Chapter>>{};
    List<Chapter> followingChapters(String chapterId) =>
        followingByChapter.putIfAbsent(chapterId, () {
          final sourceIndex = chapterIndices[chapterId]!;
          final source = snapshot.chapters[sourceIndex];
          return snapshot.chapters
              .skip(sourceIndex + 1)
              .takeWhile(
                (chapter) =>
                    !chapter.isVolume && chapter.parentId == source.parentId,
              )
              .toList(growable: false);
        });
    _snapshot = snapshot;
    _trial = result;
    _trialFingerprint = fingerprint;
    _matches = List<RuleWorkbenchMatch>.unmodifiable([
      for (var index = 0; index < result.samples.length; index++)
        RuleWorkbenchMatch(
          id: 'rule-hit-$index',
          match: result.samples[index],
          sourceText:
              sources['${result.samples[index].chapterId}\u0000${result.samples[index].blockId}']!
                  .$1,
          chapterBlocks:
              sources['${result.samples[index].chapterId}\u0000${result.samples[index].blockId}']!
                  .$2,
          sourceBlockIndex:
              sources['${result.samples[index].chapterId}\u0000${result.samples[index].blockId}']!
                  .$3,
          followingChapters: result.samples[index].headingLevel == 1
              ? followingChapters(result.samples[index].chapterId)
              : const [],
        ),
    ]);
    _phase = RuleWorkbenchPhase.ready;
  });

  Future<void> saveRule(String id) => _run(RuleWorkbenchPhase.saving, () async {
    _requireTrial();
    final rule = _rules.where((rule) => rule.id == id).firstOrNull;
    if (rule == null || !_selectedRuleIds.contains(id)) {
      throw const ValidationFailure('请先试跑当前规则。');
    }
    final generation = _generation;
    final fingerprint = _trialFingerprint;
    bool current() =>
        generation == _generation &&
        hasCurrentTrial &&
        fingerprint == _trialFingerprint;
    await _verifyStoredRules([id]);
    if (!current()) throw const TaskCancelled();
    await _store.save(
      rule,
      isCurrent: current,
      expectedRules: {
        for (final selectedId in _selectedRuleIds)
          selectedId: _persistedRules[selectedId],
      },
    );
    if (_disposed) return;
    if (_session.book?.id != _bookId || _session.sessionId != _sessionId) {
      _phase = RuleWorkbenchPhase.stale;
      return;
    }
    _persistedRules[id] = rule;
    _phase = hasCurrentTrial
        ? RuleWorkbenchPhase.ready
        : RuleWorkbenchPhase.saved;
  });

  Future<void> applySelected(
    Set<String> ids,
  ) => _run(RuleWorkbenchPhase.applying, () async {
    _requireTrial();
    if (ids.isEmpty || ids.length > 100) {
      throw const ValidationFailure('请选择 1–100 项变更，超出时请分批处理。');
    }
    final chosen = _matches.where((item) => ids.contains(item.id)).toList();
    if (chosen.length != ids.length || chosen.any((item) => !item.canApply)) {
      throw const ValidationFailure('所选命中不能直接应用。');
    }
    final generation = _generation;
    final expectedRules = <String, ProofreadingRule?>{
      for (final id in _selectedRuleIds) id: _persistedRules[id],
    };
    await _verifyStoredRules(_selectedRuleIds);
    _requireTrial();
    if (generation != _generation) throw const TaskCancelled();
    final changes = RuleScanChanges.build(
      snapshot: _snapshot!,
      sessionId: _sessionId!,
      saveSeq: _revision!,
      selectedMatches: chosen.map((item) => item.match).toList(),
    );
    _applying = true;
    _commitFinished = false;
    try {
      await _session.applyAiChanges(
        textProposals: changes.textProposals,
        splitProposals: changes.splitProposals,
        selectedIds: changes.selectedIds,
        commitGuard: (commit) => _store.runIfCurrent(expectedRules, () {
          _commitFinished = true;
          try {
            commit();
          } catch (_) {
            _commitFinished = false;
            rethrow;
          }
        }, isCurrent: () => generation == _generation && hasCurrentTrial),
      );
    } finally {
      _applying = false;
      _commitFinished = false;
      if (!_disposed &&
          (_session.book?.id != _bookId || _session.sessionId != _sessionId)) {
        _sessionChanged();
      }
    }
    if (_disposed || generation != _generation) throw const TaskCancelled();
    _lastAppliedCount = chosen.length;
    _revision = _session.saveSeq;
    _clearTrial();
    _phase = RuleWorkbenchPhase.applied;
  });

  Future<void> deleteRule(String id) =>
      _run(RuleWorkbenchPhase.saving, () async {
        if (!_rules.any(
          (rule) =>
              rule.id == id && rule.source != ProofreadingRuleSource.builtIn,
        )) {
          throw const ValidationFailure('规则不存在或不可删除。');
        }
        final generation = _generation;
        final identity = _session.sessionId;
        final bookId = _session.book?.id;
        bool current() =>
            !_disposed &&
            generation == _generation &&
            identity != null &&
            _session.sessionId == identity &&
            _session.book?.id == bookId;
        await _store.delete(
          id,
          isCurrent: current,
          expectedRules: {id: _persistedRules[id]},
        );
        if (_disposed) return;
        if (_session.sessionId != identity || _session.book?.id != bookId) {
          _phase = RuleWorkbenchPhase.stale;
          return;
        }
        _rules = List<ProofreadingRule>.unmodifiable(
          _rules.where((rule) => rule.id != id),
        );
        _selectedRuleIds.remove(id);
        _persistedRules.remove(id);
        _revision = _session.saveSeq;
        _clearTrial();
        _phase = RuleWorkbenchPhase.deleted;
      });

  Future<void> _verifyStoredRules(Iterable<String> ids) async {
    final current = {
      for (final rule in await _store.loadForBook(_bookId!))
        rule.id: proofreadingRuleFingerprint(rule),
    };
    for (final id in ids) {
      final expected = _persistedRules[id];
      if (current[id] !=
          (expected == null ? null : proofreadingRuleFingerprint(expected))) {
        throw const ValidationFailure('已保存规则发生变化，请重新载入并试跑。');
      }
    }
  }

  void _requireTrial() {
    if (!hasCurrentTrial) throw const ValidationFailure('规则或书稿已变化，请重新完成全书试跑。');
  }

  Future<void> _run(
    RuleWorkbenchPhase phase,
    Future<void> Function() action,
  ) async {
    if (_disposed || _working) return;
    _working = true;
    _failure = null;
    _phase = phase;
    notifyListeners();
    try {
      await action();
    } on TaskCancelled {
      if (_phase != RuleWorkbenchPhase.stale) {
        _phase = RuleWorkbenchPhase.cancelled;
      }
    } on AppFailure catch (error) {
      if (_phase != RuleWorkbenchPhase.stale &&
          _phase != RuleWorkbenchPhase.cancelled) {
        _failure = error;
        _phase = RuleWorkbenchPhase.failed;
      }
    } on Object {
      if (_phase != RuleWorkbenchPhase.stale &&
          _phase != RuleWorkbenchPhase.cancelled) {
        _failure = const ValidationFailure('规则任务失败，请检查本地存储后重试。');
        _phase = RuleWorkbenchPhase.failed;
      }
    } finally {
      _workerActive = false;
      _working = false;
      if (!_disposed) notifyListeners();
    }
  }

  void cancel() {
    if (_disposed) return;
    if (_applying && _commitFinished) return;
    _generation++;
    if (_workerActive) _jobs.cancelActive();
    if (_applying) _session.cancelTool();
    _clearTrial();
    _failure = null;
    _phase = RuleWorkbenchPhase.cancelled;
    notifyListeners();
  }

  void _sessionChanged() {
    if (_disposed || _bookId == null || _isCurrent) return;
    if (_applying &&
        _commitFinished &&
        _session.book?.id == _bookId &&
        _session.sessionId == _sessionId &&
        _session.saveSeq == _revision! + 1) {
      return;
    }
    if (_session.book?.id != _bookId || _session.sessionId != _sessionId) {
      _rules = const [];
      _importRules = null;
      _loadedSessionId = null;
      _selectedRuleIds.clear();
      _persistedRules.clear();
    } else if (_session.book case final book?) {
      _importRules = ImportRuleSummary.fromOptions(book.parseOptions);
    }
    if (_phase == RuleWorkbenchPhase.stale) return;
    _generation++;
    if (_workerActive) _jobs.cancelActive();
    if (_applying) _session.cancelTool();
    _invalidate(RuleWorkbenchPhase.stale);
  }

  void _clearTrial() {
    _trial = null;
    _snapshot = null;
    _matches = const [];
    _trialFingerprint = null;
  }

  void _invalidate(RuleWorkbenchPhase phase) {
    _clearTrial();
    _failure = null;
    _phase = phase;
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _generation++;
    _disposed = true;
    _session.removeListener(_sessionChanged);
    if (_workerActive) _jobs.cancelActive();
    if (_applying) _session.cancelTool();
    if (_ownsJobs) _jobs.dispose();
    _clearTrial();
    super.dispose();
  }
}

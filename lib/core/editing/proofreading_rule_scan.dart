import 'dart:collection';

import 'package:bookloom/core/editing/proofreading_rule.dart';
import 'package:bookloom/core/errors/app_failure.dart';
import 'package:bookloom/core/model/block.dart';
import 'package:bookloom/core/model/book.dart';
import 'package:bookloom/core/platform/background_jobs.dart';

final class RuleScanLimits {
  const RuleScanLimits({
    this.maxRules = 32,
    this.maxChapters = 10000,
    this.maxBlocks = 100000,
    this.maxLines = 200000,
    this.maxInputUtf16 = 8000000,
    this.maxScanUtf16 = 32000000,
    this.maxMatches = 20000,
    this.maxConflicts = 20000,
    this.maxSamples = 100,
  });

  final int maxRules;
  final int maxChapters;
  final int maxBlocks;
  final int maxLines;
  final int maxInputUtf16;
  final int maxScanUtf16;
  final int maxMatches;
  final int maxConflicts;
  final int maxSamples;

  bool get isValid =>
      maxRules > 0 &&
      maxChapters > 0 &&
      maxBlocks > 0 &&
      maxLines > 0 &&
      maxInputUtf16 > 0 &&
      maxScanUtf16 > 0 &&
      maxMatches > 0 &&
      maxConflicts > 0 &&
      maxSamples >= 0;
}

final class RuleScanCoverage {
  const RuleScanCoverage({
    required this.chapters,
    required this.textBlocks,
    required this.otherBlocks,
    required this.bodyLines,
    required this.inputUtf16,
    required this.scanUnits,
    required this.scanUtf16,
  });

  final int chapters;
  final int textBlocks;
  final int otherBlocks;
  final int bodyLines;
  final int inputUtf16;
  final int scanUnits;
  final int scanUtf16;
}

final class RuleScanMatch {
  RuleScanMatch({
    required this.chapterId,
    required this.chapterTitle,
    required this.blockId,
    required this.lineNumber,
    required this.startUtf16,
    required this.endUtf16,
    this.mappedTitle,
    this.mappedNumber,
    this.numberText,
    this.headingLevel = 2,
    required this.action,
    required List<String> ruleIds,
    required this.excerpt,
    required this.before,
    required this.after,
  }) : ruleIds = List<String>.unmodifiable(ruleIds);

  final String chapterId;
  final String chapterTitle;
  final String blockId;
  final int lineNumber;
  final int startUtf16;
  final int endUtf16;
  final String? mappedTitle;
  final int? mappedNumber;
  final String? numberText;
  final int headingLevel;
  final ProofreadingRuleAction action;
  final List<String> ruleIds;
  final String excerpt;
  final String before;
  final String after;
}

enum RuleScanConflictKind {
  chapterBoundary,
  deletionAndChapter,
  overlappingDeletions,
}

final class RuleScanConflict {
  const RuleScanConflict(this.kind, this.first, this.second);

  final RuleScanConflictKind kind;
  final RuleScanMatch first;
  final RuleScanMatch second;
}

/// A read-only trial. Counts describe the entire supplied snapshot; samples do
/// not carry enough information to apply changes or save a rule.
final class RuleScanResult {
  RuleScanResult({
    required this.bookId,
    required this.bookRevision,
    required List<String> executedRuleIds,
    required Map<String, int> matchesByRuleId,
    required this.totalMatches,
    required this.distinctMatches,
    required List<RuleScanMatch> samples,
    required this.totalConflicts,
    required List<RuleScanConflict> conflictSamples,
    required this.coverage,
  }) : executedRuleIds = List<String>.unmodifiable(executedRuleIds),
       matchesByRuleId = Map<String, int>.unmodifiable(matchesByRuleId),
       samples = List<RuleScanMatch>.unmodifiable(samples),
       conflictSamples = List<RuleScanConflict>.unmodifiable(conflictSamples);

  final String bookId;
  final int bookRevision;
  final List<String> executedRuleIds;
  final Map<String, int> matchesByRuleId;
  final int totalMatches;
  final int distinctMatches;
  final List<RuleScanMatch> samples;
  final int totalConflicts;
  final List<RuleScanConflict> conflictSamples;
  final RuleScanCoverage coverage;

  int get hiddenMatches => distinctMatches - samples.length;
  int get hiddenConflicts => totalConflicts - conflictSamples.length;
}

abstract final class ProofreadingRuleScan {
  /// [loadedChapterIds] must identify every chapter and volume whose blocks
  /// have been loaded. Book.chapters alone may contain lazy, empty bodies.
  static RuleScanResult scan(
    Book book, {
    required Iterable<ProofreadingRule> selectedRules,
    required Set<String> loadedChapterIds,
    RuleScanLimits limits = const RuleScanLimits(),
    bool Function()? isCancelled,
  }) => _scan(
    _snapshot(book, selectedRules, loadedChapterIds, limits, isCancelled),
    isCancelled,
  );

  /// Runs matching in a killable isolate for regex timeout and cancellation.
  /// The caller owns [jobs] and may call cancelActive on it.
  static Future<RuleScanResult> scanInBackground(
    Book book, {
    required Iterable<ProofreadingRule> selectedRules,
    required Set<String> loadedChapterIds,
    required BackgroundJobs jobs,
    required int revision,
    RuleScanLimits limits = const RuleScanLimits(),
    Duration timeout = const Duration(minutes: 2),
  }) {
    return jobs.run<_ScanRequest, RuleScanResult>(
      _ScanRequest(
        book,
        List<ProofreadingRule>.unmodifiable(selectedRules),
        Set<String>.unmodifiable(loadedChapterIds),
        limits,
      ),
      _scanRequestJob,
      revision: revision,
      timeout: timeout,
    );
  }
}

RuleScanResult _scanRequestJob(
  _ScanRequest request,
  void Function(double, String) progress,
) => _scan(
  _snapshot(
    request.book,
    request.rules,
    request.loadedIds,
    request.limits,
    null,
  ),
  null,
);

final class _ScanRequest {
  const _ScanRequest(this.book, this.rules, this.loadedIds, this.limits);

  final Book book;
  final List<ProofreadingRule> rules;
  final Set<String> loadedIds;
  final RuleScanLimits limits;
}

_ScanInput _snapshot(
  Book book,
  Iterable<ProofreadingRule> selectedRules,
  Set<String> loadedChapterIds,
  RuleScanLimits limits,
  bool Function()? isCancelled,
) {
  if (!limits.isValid || book.id.isEmpty || book.revision < 0) {
    throw const ValidationFailure('规则试跑输入或预算无效。');
  }
  final ruleList = <ProofreadingRule>[];
  for (final rule in selectedRules) {
    if (ruleList.length >= limits.maxRules) {
      throw const ValidationFailure('选定规则超过试跑预算。');
    }
    ruleList.add(rule);
  }
  if (book.chapters.length > limits.maxChapters) {
    throw const ValidationFailure('章节数超过规则试跑预算。');
  }
  final chapterList = List.of(book.chapters);
  final blockLists = <List<Block>>[];
  var snapshottedBlocks = 0;
  for (final chapter in chapterList) {
    snapshottedBlocks += chapter.blocks.length;
    if (snapshottedBlocks > limits.maxBlocks) {
      throw const ValidationFailure('正文块超过规则试跑预算。');
    }
    blockLists.add(List<Block>.of(chapter.blocks));
  }
  if (loadedChapterIds.length > limits.maxChapters) {
    throw const ValidationFailure('已加载章节标识超过规则试跑预算。');
  }
  final loadedIds = Set<String>.of(loadedChapterIds);
  _checkCancelled(isCancelled);
  final selected = <ProofreadingRule>[];
  final ruleIds = <String>{};
  for (final rule in ruleList) {
    _checkCancelled(isCancelled);
    if (!ruleIds.add(rule.id)) {
      throw const ValidationFailure('选定规则过多或规则 ID 重复。');
    }
    if (rule.enabled && rule.appliesToBook(book.id)) selected.add(rule);
  }
  selected.sort((left, right) {
    final byPriority = right.priority.compareTo(left.priority);
    return byPriority != 0 ? byPriority : left.id.compareTo(right.id);
  });

  final chapterIds = <String>{};
  final blockIds = <String>{};
  final chapters = <_ChapterSnapshot>[];
  var inputUtf16 = 0;
  var blockCount = 0;
  var textBlocks = 0;
  var otherBlocks = 0;
  var bodyLines = 0;
  for (final (chapterIndex, chapter) in chapterList.indexed) {
    _checkCancelled(isCancelled);
    if (chapter.id.isEmpty ||
        chapter.bookId != book.id ||
        !chapterIds.add(chapter.id)) {
      throw const ValidationFailure('书稿章节标识不一致，无法完整试跑。');
    }
    inputUtf16 += chapter.title.length;
    if (inputUtf16 > limits.maxInputUtf16) _inputBudgetFailure();
    final blocks = <_BlockSnapshot>[];
    for (final block in blockLists[chapterIndex]) {
      _checkCancelled(isCancelled);
      if (++blockCount > limits.maxBlocks ||
          block.id.isEmpty ||
          !blockIds.add(block.id)) {
        throw const ValidationFailure('正文块过多或块 ID 重复，无法完整试跑。');
      }
      if (block is! TextBlock) {
        otherBlocks++;
        continue;
      }
      final body = block.text;
      inputUtf16 += body.length;
      if (body.length > 32768 || inputUtf16 > limits.maxInputUtf16) {
        _inputBudgetFailure();
      }
      final lines = _lines(body);
      bodyLines += lines.length;
      if (bodyLines > limits.maxLines) _inputBudgetFailure();
      blocks.add(
        _BlockSnapshot(chapter.id, chapter.title, block.id, body, lines),
      );
      textBlocks++;
    }
    chapters.add(_ChapterSnapshot(blocks));
  }
  if (loadedIds.length != chapterIds.length ||
      !loadedIds.containsAll(chapterIds)) {
    throw const ValidationFailure('部分章节正文尚未加载，无法声称完成全书试跑。');
  }
  _checkCancelled(isCancelled);
  return _ScanInput(
    book.id,
    book.revision,
    chapters,
    selected,
    limits,
    textBlocks,
    otherBlocks,
    bodyLines,
    inputUtf16,
  );
}

RuleScanResult _scan(_ScanInput input, bool Function()? isCancelled) {
  final hits = <_Hit>[];
  final seen =
      <(String, String, int, int, int, String?, int, int?, String?), _Hit>{};
  final counts = <String, int>{};
  var total = 0;
  var scanUnits = 0;
  var scanUtf16 = 0;

  void scanText(
    _BlockSnapshot block,
    String text,
    int base,
    ProofreadingRule rule,
    int? lineNumber,
  ) {
    scanUnits++;
    scanUtf16 += text.length;
    if (scanUtf16 > input.limits.maxScanUtf16) {
      throw const ValidationFailure('规则扫描预算耗尽，未完成全书试跑。');
    }
    for (final match in rule.matchScanText(text)) {
      _checkCancelled(isCancelled);
      if (++total > input.limits.maxMatches) {
        throw const ValidationFailure('规则命中超过预算，未完成全书试跑。');
      }
      counts[rule.id] = counts[rule.id]! + 1;
      final start = base + match.startUtf16;
      final end = base + match.endUtf16;
      final actualLine = lineNumber ?? _lineNumber(block.lines, start);
      final key = (
        block.chapterId,
        block.id,
        rule.action.index,
        start,
        end,
        match.mappedTitle,
        rule.headingLevel,
        match.mappedNumber,
        match.numberText,
      );
      final previous = seen[key];
      if (previous != null) {
        previous.ruleIds.add(rule.id);
      } else {
        final hit = _Hit(
          hits.length,
          block,
          actualLine,
          start,
          end,
          match.mappedTitle,
          rule.headingLevel,
          match.mappedNumber,
          match.numberText,
          rule.action,
          [rule.id],
        );
        seen[key] = hit;
        hits.add(hit);
      }
    }
  }

  for (final rule in input.rules) {
    _checkCancelled(isCancelled);
    counts[rule.id] = 0;
    for (final chapter in input.chapters) {
      _checkCancelled(isCancelled);
      for (final block in chapter.blocks) {
        _checkCancelled(isCancelled);
        if (rule.target == ProofreadingRuleTarget.paragraph) {
          scanText(block, block.text, 0, rule, null);
        } else {
          for (final line in block.lines) {
            _checkCancelled(isCancelled);
            scanText(
              block,
              block.text.substring(line.start, line.end),
              line.start,
              rule,
              line.number,
            );
          }
        }
      }
    }
  }

  final samples = hits.take(input.limits.maxSamples).map(_sample).toList();
  final conflicts = <RuleScanConflict>[];
  var totalConflicts = 0;

  void addConflict(RuleScanConflictKind kind, _Hit first, _Hit second) {
    _checkCancelled(isCancelled);
    if (++totalConflicts > input.limits.maxConflicts) {
      throw const ValidationFailure('规则冲突超过预算，无法完整试跑。');
    }
    if (conflicts.length < input.limits.maxSamples) {
      conflicts.add(RuleScanConflict(kind, _sample(first), _sample(second)));
    }
  }

  void expire(SplayTreeSet<_Hit> active, int start) {
    while (active.isNotEmpty && active.first.end <= start) {
      _checkCancelled(isCancelled);
      active.remove(active.first);
    }
  }

  final byBlock = <String, List<_Hit>>{};
  for (final hit in hits) {
    if (hit.action == ProofreadingRuleAction.chapterCandidate ||
        hit.action == ProofreadingRuleAction.exactDeletion) {
      byBlock.putIfAbsent(hit.block.id, () => []).add(hit);
    }
  }
  for (final blockHits in byBlock.values) {
    _checkCancelled(isCancelled);
    blockHits.sort((left, right) {
      final start = left.start.compareTo(right.start);
      if (start != 0) return start;
      final end = left.end.compareTo(right.end);
      return end != 0 ? end : left.index.compareTo(right.index);
    });

    final candidatesByLine = <int, List<_Hit>>{};
    final deletionsByLine = <int, List<_Hit>>{};
    for (final hit in blockHits) {
      _checkCancelled(isCancelled);
      final lines = hit.action == ProofreadingRuleAction.chapterCandidate
          ? candidatesByLine
          : deletionsByLine;
      lines.putIfAbsent(hit.lineNumber, () => []).add(hit);
    }
    for (final entry in candidatesByLine.entries) {
      _checkCancelled(isCancelled);
      final candidates = entry.value;
      for (var index = 0; index < candidates.length; index++) {
        _checkCancelled(isCancelled);
        for (var next = index + 1; next < candidates.length; next++) {
          _checkCancelled(isCancelled);
          addConflict(
            RuleScanConflictKind.chapterBoundary,
            candidates[index],
            candidates[next],
          );
        }
        for (final deletion in deletionsByLine[entry.key] ?? const <_Hit>[]) {
          _checkCancelled(isCancelled);
          addConflict(
            RuleScanConflictKind.deletionAndChapter,
            candidates[index],
            deletion,
          );
        }
      }
    }

    int byEnd(_Hit left, _Hit right) {
      final end = left.end.compareTo(right.end);
      return end != 0 ? end : left.index.compareTo(right.index);
    }

    final activeDeletions = SplayTreeSet<_Hit>(byEnd);
    final activeCandidates = SplayTreeSet<_Hit>(byEnd);
    for (final hit in blockHits) {
      _checkCancelled(isCancelled);
      expire(activeDeletions, hit.start);
      expire(activeCandidates, hit.start);
      if (hit.action == ProofreadingRuleAction.exactDeletion) {
        for (final deletion in activeDeletions) {
          _checkCancelled(isCancelled);
          addConflict(RuleScanConflictKind.overlappingDeletions, deletion, hit);
        }
        for (final candidate in activeCandidates) {
          _checkCancelled(isCancelled);
          if (candidate.lineNumber != hit.lineNumber) {
            addConflict(
              RuleScanConflictKind.deletionAndChapter,
              candidate,
              hit,
            );
          }
        }
        activeDeletions.add(hit);
      } else {
        for (final deletion in activeDeletions) {
          _checkCancelled(isCancelled);
          if (deletion.lineNumber != hit.lineNumber) {
            addConflict(RuleScanConflictKind.deletionAndChapter, hit, deletion);
          }
        }
        activeCandidates.add(hit);
      }
    }
  }
  _checkCancelled(isCancelled);
  return RuleScanResult(
    bookId: input.bookId,
    bookRevision: input.revision,
    executedRuleIds: input.rules.map((rule) => rule.id).toList(),
    matchesByRuleId: counts,
    totalMatches: total,
    distinctMatches: hits.length,
    samples: samples,
    totalConflicts: totalConflicts,
    conflictSamples: conflicts,
    coverage: RuleScanCoverage(
      chapters: input.chapters.length,
      textBlocks: input.textBlocks,
      otherBlocks: input.otherBlocks,
      bodyLines: input.bodyLines,
      inputUtf16: input.inputUtf16,
      scanUnits: scanUnits,
      scanUtf16: scanUtf16,
    ),
  );
}

RuleScanMatch _sample(_Hit hit) => RuleScanMatch(
  chapterId: hit.block.chapterId,
  chapterTitle: hit.block.chapterTitle,
  blockId: hit.block.id,
  lineNumber: hit.lineNumber,
  startUtf16: hit.start,
  endUtf16: hit.end,
  mappedTitle: hit.mappedTitle,
  headingLevel: hit.headingLevel,
  mappedNumber: hit.mappedNumber,
  numberText: hit.numberText,
  action: hit.action,
  ruleIds: hit.ruleIds,
  excerpt: _excerpt(hit.block.text, hit.start, hit.end),
  before: _contextBefore(hit.block.text, hit.start),
  after: _contextAfter(hit.block.text, hit.end),
);

String _contextBefore(String text, int start) {
  var contextStart = start > 80 ? start - 80 : 0;
  if (contextStart > 0 &&
      text.codeUnitAt(contextStart) >= 0xdc00 &&
      text.codeUnitAt(contextStart) <= 0xdfff) {
    contextStart++;
  }
  return text.substring(contextStart, start);
}

String _contextAfter(String text, int end) {
  var contextEnd = end + 80 < text.length ? end + 80 : text.length;
  if (contextEnd < text.length &&
      contextEnd > end &&
      text.codeUnitAt(contextEnd - 1) >= 0xd800 &&
      text.codeUnitAt(contextEnd - 1) <= 0xdbff) {
    contextEnd--;
  }
  return text.substring(end, contextEnd);
}

String _excerpt(String text, int start, int end) {
  var excerptEnd = end < start + 160 ? end : start + 160;
  if (excerptEnd < end &&
      excerptEnd > start &&
      text.codeUnitAt(excerptEnd - 1) >= 0xd800 &&
      text.codeUnitAt(excerptEnd - 1) <= 0xdbff) {
    excerptEnd--;
  }
  return text.substring(start, excerptEnd);
}

List<_Line> _lines(String text) {
  final lines = <_Line>[];
  var start = 0;
  for (var index = 0; index < text.length; index++) {
    final unit = text.codeUnitAt(index);
    if (unit != 10 && unit != 13) continue;
    lines.add(_Line(lines.length + 1, start, index));
    if (unit == 13 &&
        index + 1 < text.length &&
        text.codeUnitAt(index + 1) == 10) {
      index++;
    }
    start = index + 1;
  }
  lines.add(_Line(lines.length + 1, start, text.length));
  return lines;
}

int _lineNumber(List<_Line> lines, int offset) {
  var low = 0;
  var high = lines.length - 1;
  while (low < high) {
    final middle = (low + high + 1) ~/ 2;
    if (lines[middle].start <= offset) {
      low = middle;
    } else {
      high = middle - 1;
    }
  }
  return lines[low].number;
}

void _checkCancelled(bool Function()? isCancelled) {
  if (isCancelled?.call() ?? false) throw const TaskCancelled();
}

Never _inputBudgetFailure() =>
    throw const ValidationFailure('书稿超出规则试跑输入预算，未完成全书试跑。');

final class _ScanInput {
  const _ScanInput(
    this.bookId,
    this.revision,
    this.chapters,
    this.rules,
    this.limits,
    this.textBlocks,
    this.otherBlocks,
    this.bodyLines,
    this.inputUtf16,
  );

  final String bookId;
  final int revision;
  final List<_ChapterSnapshot> chapters;
  final List<ProofreadingRule> rules;
  final RuleScanLimits limits;
  final int textBlocks;
  final int otherBlocks;
  final int bodyLines;
  final int inputUtf16;
}

final class _ChapterSnapshot {
  const _ChapterSnapshot(this.blocks);
  final List<_BlockSnapshot> blocks;
}

final class _BlockSnapshot {
  const _BlockSnapshot(
    this.chapterId,
    this.chapterTitle,
    this.id,
    this.text,
    this.lines,
  );
  final String chapterId;
  final String chapterTitle;
  final String id;
  final String text;
  final List<_Line> lines;
}

final class _Line {
  const _Line(this.number, this.start, this.end);
  final int number;
  final int start;
  final int end;
}

final class _Hit {
  _Hit(
    this.index,
    this.block,
    this.lineNumber,
    this.start,
    this.end,
    this.mappedTitle,
    this.headingLevel,
    this.mappedNumber,
    this.numberText,
    this.action,
    this.ruleIds,
  );
  final int index;
  final _BlockSnapshot block;
  final int lineNumber;
  final int start;
  final int end;
  final String? mappedTitle;
  final int headingLevel;
  final int? mappedNumber;
  final String? numberText;
  final ProofreadingRuleAction action;
  final List<String> ruleIds;
}

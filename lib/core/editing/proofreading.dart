import 'package:bookloom/core/editing/rule_heading_mapping.dart';
import 'package:bookloom/core/editing/safe_regex.dart';
import 'package:bookloom/core/errors/app_failure.dart';
import 'package:bookloom/core/model/block.dart';
import 'package:bookloom/core/model/book.dart';
import 'package:bookloom/core/model/chapter.dart';
import 'package:bookloom/core/text/word_count.dart';

const int replaceFindLimit = 200;
const int replaceTextLimit = 500;
const int replaceHitLimit = 200000;
const int previewSampleLimit = 20;
const int previewContextLength = 16;
const int duplicateContentMinLength = 100;

enum AuditIssueKind {
  missingNumber,
  duplicateNumber,
  emptyChapter,
  duplicateTitle,
  tooLong,
  tooShort,
  emptyVolume,
  adLeftover,
  titleFormat,
  duplicateContent,
}

class AuditIssue {
  const AuditIssue({
    required this.kind,
    required this.chapterId,
    required this.chapterIndex,
    required this.chapterTitle,
    required this.message,
    this.blockId,
    this.numberGap,
  });

  final AuditIssueKind kind;
  final String chapterId;
  final int chapterIndex;
  final String chapterTitle;
  final String? blockId;
  final String message;
  final AuditNumberGap? numberGap;
}

class AuditNumberGap {
  const AuditNumberGap({
    required this.afterChapterId,
    required this.firstMissing,
    required this.lastMissing,
    this.beforeChapterId,
  });

  final String? beforeChapterId;
  final String afterChapterId;
  final int firstMissing;
  final int lastMissing;
}

class AuditReport {
  AuditReport(Map<AuditIssueKind, int> counts, List<AuditIssue> issues)
    : counts = Map<AuditIssueKind, int>.unmodifiable(counts),
      issues = List<AuditIssue>.unmodifiable(issues);

  final Map<AuditIssueKind, int> counts;
  final List<AuditIssue> issues;
  int get total => counts.values.fold(0, (total, value) => total + value);
}

class MissedChapterCandidate {
  const MissedChapterCandidate({
    required this.chapterId,
    required this.chapterIndex,
    required this.blockId,
    required this.blockIndex,
    required this.text,
  });

  final String chapterId;
  final int chapterIndex;
  final String blockId;
  final int blockIndex;
  final String text;
}

enum ReplaceScope { title, body, all }

enum ReplaceField { title, body }

class ReplaceOptions {
  const ReplaceOptions({
    required this.find,
    required this.replace,
    this.scope = ReplaceScope.all,
    this.regex = false,
    this.caseSensitive = false,
  });

  final String find;
  final String replace;
  final ReplaceScope scope;
  final bool regex;
  final bool caseSensitive;
}

/// A sparse, immutable edit to one field. A null [blockId] means the title.
class TextPatch {
  const TextPatch({
    required this.chapterId,
    required this.blockId,
    required this.before,
    required this.after,
  });

  final String chapterId;
  final String? blockId;
  final String before;
  final String after;
}

class ReplaceSample {
  const ReplaceSample({
    required this.chapterId,
    required this.blockId,
    required this.chapterTitle,
    required this.field,
    required this.before,
    required this.match,
    required this.after,
  });

  final String chapterId;
  final String? blockId;
  final String chapterTitle;
  final ReplaceField field;
  final String before;
  final String match;
  final String after;
}

/// The caller supplies its in-memory save sequence, not [Book.revision].
/// Applying [patches] requires comparing that same sequence again and doing
/// one atomic, undoable batch in the editor session.
class ToolPreview {
  ToolPreview({
    required this.baseRevision,
    required this.hits,
    required List<TextPatch> patches,
    required List<ReplaceSample> samples,
  }) : patches = List<TextPatch>.unmodifiable(patches),
       samples = List<ReplaceSample>.unmodifiable(samples);

  final int baseRevision;
  final int hits;
  final List<TextPatch> patches;
  final List<ReplaceSample> samples;
}

abstract final class Proofreading {
  static const _numerals = '０１２３４５６７８９零〇一二三四五六七八九十百千万萬亿億两兩壹贰貳叁參肆伍陆陸柒捌玖拾佰仟';
  static final RegExp _numbered = RegExp(
    '^(\\s*(?:正文[\\s·:：\\-—]*)?第\\s*)([$_numerals\\d]{1,32})(?:(\\s*[~～\\-—]\\s*)([$_numerals\\d]{1,32}))?(\\s*[章节節回话話集部])',
  );
  static final RegExp _candidate = RegExp(
    '^(?:正文[\\s·:：\\-—]*)?第\\s*[$_numerals\\d]{1,32}(?:\\s*[~～\\-—]\\s*[$_numerals\\d]{1,32})?\\s*[章节節回话話卷部篇集]|^(?:序章|序言|楔子|引子|前言|引言|番外|后记|尾声|终章|大结局|完本感言|附录)',
  );
  static final RegExp _headingSeparator = RegExp(r'[章节回卷部篇集][\s、.．:：·\-—]');
  static final RegExp _whitespaceRun = RegExp(r'\s+');
  static final RegExp _blankLine = RegExp(r'\n\s*\n');
  static final RegExp _terminalQuestion = RegExp(r'[！？!?]$');
  static final RegExp _inlineJunk = RegExp(
    r'内容还在处理中|正在手打中|本章未完|手机阅读|记住本站|求月票|更新最快|无弹窗|笔趣阁|最新章节|电子书|txt',
    caseSensitive: false,
  );
  static final RegExp _inlineHeading = RegExp(
    '第\\s*[$_numerals\\d]{1,8}(?:\\s*[~～\\-—]\\s*[$_numerals\\d]{1,8})?\\s*[章节]',
  );
  static final RegExp _adStrong = RegExp(
    r'爱下电子书|ixdzs|苦读书|书友群|txt下载|https?://\S+|www\.[a-z0-9-]+\.(?:com|net|org|cc|info|cn)',
    caseSensitive: false,
  );
  static final RegExp _adShort = RegExp(
    r'本章未完.{0,20}(?:下一页|继续)|请记住(?:本书|本站|域名|地址)|更新最快|无弹窗.{0,10}(?:阅读|小说)|笔趣阁|顶点小说|八一中文网|(?:求|跪求|感谢)?\s*(?:月票|推荐票|订阅|收藏|打赏)|^(?:上一章|下一章|返回目录|加入书签|章节目录)$|内容还在处理中|正在手打中|请稍后重试',
  );

  /// Input must have all chapter bodies loaded. Only text paragraphs are
  /// considered; image captions and footnotes are intentionally excluded.
  static List<MissedChapterCandidate> findMissedChapters(Book book) {
    final found = <MissedChapterCandidate>[];
    for (final (chapterIndex, chapter) in book.chapters.indexed) {
      if (chapter.isVolume) continue;
      for (final (blockIndex, block) in chapter.blocks.indexed) {
        if (block is! TextBlock) continue;
        final text = block.text.trim();
        if (text.isEmpty || text.length > 50 || text == chapter.title.trim()) {
          continue;
        }
        if (text.length > 24 && RegExp(r'[。！？!?…]$').hasMatch(text)) {
          continue;
        }
        if (RegExp(r'[。！？!?]$').hasMatch(text) &&
            !_headingSeparator.hasMatch(text) &&
            !(_terminalQuestion.hasMatch(text) &&
                _adjacentQuestionHeading(book.chapters, chapterIndex, text))) {
          continue;
        }
        if (!_candidate.hasMatch(text) &&
            !(_inlineJunk.hasMatch(text) && _inlineHeading.hasMatch(text))) {
          continue;
        }
        final numbered = _numbered.firstMatch(text);
        if (numbered != null &&
            (!_validNumberedRange(numbered) ||
                numbered[4] != null && _narrativeAfterNumber(numbered, text))) {
          continue;
        }
        found.add(
          MissedChapterCandidate(
            chapterId: chapter.id,
            chapterIndex: chapterIndex,
            blockId: block.id,
            blockIndex: blockIndex,
            text: text,
          ),
        );
      }
    }
    return List<MissedChapterCandidate>.unmodifiable(found);
  }

  static AuditReport audit(Book book) {
    final counts = {for (final kind in AuditIssueKind.values) kind: 0};
    final issues = <AuditIssue>[];

    void add(
      AuditIssueKind kind,
      Chapter chapter,
      int index,
      String message, {
      String? blockId,
      AuditNumberGap? numberGap,
    }) {
      final count = counts[kind]! + 1;
      counts[kind] = count;
      if (count <= previewSampleLimit) {
        issues.add(
          AuditIssue(
            kind: kind,
            chapterId: chapter.id,
            chapterIndex: index,
            chapterTitle: chapter.title,
            blockId: blockId,
            message: message,
            numberGap: numberGap,
          ),
        );
      }
    }

    for (final issue in _numberIssues(book.chapters)) {
      add(
        issue.kind,
        book.chapters[issue.chapterIndex],
        issue.chapterIndex,
        issue.message,
        numberGap: issue.numberGap,
      );
    }

    final childCounts = <String, int>{};
    for (final chapter in book.chapters) {
      if (!chapter.isVolume && chapter.parentId != null) {
        childCounts.update(
          chapter.parentId!,
          (value) => value + 1,
          ifAbsent: () => 1,
        );
      }
    }
    final firstBlock =
        <String, ({int index, String chapterId, String title})>{};
    for (final (index, chapter) in book.chapters.indexed) {
      if (chapter.isVolume) continue;
      for (final block in chapter.blocks) {
        if (block is! TextBlock) continue;
        for (final paragraph in block.text.split(_blankLine)) {
          final normalized = paragraph.replaceAll(_whitespaceRun, ' ').trim();
          if (normalized.length < duplicateContentMinLength) continue;
          final previous = firstBlock[normalized];
          if (previous == null) {
            firstBlock[normalized] = (
              index: index,
              chapterId: chapter.id,
              title: chapter.title,
            );
            continue;
          }
          add(
            AuditIssueKind.duplicateContent,
            chapter,
            index,
            '本段与第 ${previous.index + 1} 项《${previous.title}》的正文段落完全重复，'
            '建议核对是否重复粘贴。',
            blockId: block.id,
          );
        }
      }
    }
    final titleStyles = <int, ({bool arabic, String marker})>{};
    for (final (index, chapter) in book.chapters.indexed) {
      if (chapter.isVolume || chapter.frontMatter) continue;
      final match = _numbered.firstMatch(chapter.title);
      if (match == null) continue;
      titleStyles[index] = (
        arabic: RegExp(r'[0-9０-９]').hasMatch(match.group(2) ?? ''),
        marker: match.group(5) ?? '',
      );
    }
    if (titleStyles.length >= 3) {
      final styleCounts = <({bool arabic, String marker}), int>{};
      for (final style in titleStyles.values) {
        styleCounts.update(style, (value) => value + 1, ifAbsent: () => 1);
      }
      final ranked = styleCounts.entries.toList()
        ..sort((left, right) => right.value.compareTo(left.value));
      final top = ranked.first;
      final tied = ranked.length > 1 && ranked[1].value == top.value;
      if (!tied && top.value * 2 > titleStyles.length) {
        String styleLabel(({bool arabic, String marker}) style) =>
            '${style.arabic ? '阿拉伯数字' : '中文数字'}·${style.marker}';
        for (final entry in titleStyles.entries) {
          if (entry.value == top.key) continue;
          add(
            AuditIssueKind.titleFormat,
            book.chapters[entry.key],
            entry.key,
            '本章标题为「${styleLabel(entry.value)}」，'
            '与本书多数「${styleLabel(top.key)}」不一致，建议统一标题格式。',
          );
        }
      }
    }
    final firstTitle = <String, int>{};
    for (final (index, chapter) in book.chapters.indexed) {
      final titleKey = chapter.title.trim().replaceAll(RegExp(r'\s+'), ' ');
      if (titleKey.isNotEmpty) {
        final previous = firstTitle.putIfAbsent(titleKey, () => index);
        if (previous != index) {
          add(
            AuditIssueKind.duplicateTitle,
            chapter,
            index,
            '标题重复，首次出现在第 ${previous + 1} 项，建议核对标题。',
          );
        }
      }
      for (final block in chapter.blocks) {
        if (block is! TextBlock) continue;
        for (final line in block.text.split('\n')) {
          final text = line.trim();
          if (_isAdLine(text)) {
            var excerptEnd = text.length > 32 ? 32 : text.length;
            if (excerptEnd > 0 &&
                excerptEnd < text.length &&
                _isHighSurrogate(text.codeUnitAt(excerptEnd - 1))) {
              excerptEnd--;
            }
            final excerpt = text.length > 32
                ? '${text.substring(0, excerptEnd)}…'
                : text;
            add(
              AuditIssueKind.adLeftover,
              chapter,
              index,
              '疑似广告残留：$excerpt；建议人工确认后删除。',
              blockId: block.id,
            );
          }
        }
      }
      if (chapter.isVolume) {
        if ((childCounts[chapter.id] ?? 0) == 0) {
          add(AuditIssueKind.emptyVolume, chapter, index, '卷内没有章节，建议补章或删除空卷。');
        }
        continue;
      }
      final length = WordCount.ofBlocks(chapter.blocks);
      if (length == 0) {
        add(AuditIssueKind.emptyChapter, chapter, index, '章节没有正文，建议检查分章位置。');
      } else if (!chapter.frontMatter && _numbered.hasMatch(chapter.title)) {
        if (length > 30000) {
          add(
            AuditIssueKind.tooLong,
            chapter,
            index,
            '本章 $length 字，超过 30000 字，建议检查是否漏分章。',
          );
        } else if (length < 120) {
          add(
            AuditIssueKind.tooShort,
            chapter,
            index,
            '本章 $length 字，少于 120 字，建议检查正文是否缺失。',
          );
        }
      }
    }
    return AuditReport(counts, issues);
  }

  static ToolPreview previewRenumber(Book book, {required int baseRevision}) {
    final patches = <TextPatch>[];
    final samples = <ReplaceSample>[];
    for (final entries in _numberedGroups(
      book.chapters,
      rejectInvalidRanges: true,
    ).values) {
      var next = 0;
      for (final entry in entries) {
        next++;
        final end = next + entry.end - entry.value;
        if (end > 99999999) {
          throw const ValidationFailure('重编号结果超过八位章号上限，请先调整章节范围。');
        }
        final endRaw = entry.match[4];
        final range = endRaw == null
            ? ''
            : '${entry.match[3]}${_renumberedNumeral(endRaw, end)}';
        final replacement =
            '${entry.match[1]}'
            '${_renumberedNumeral(entry.raw, next)}$range${entry.match[5]}';
        final title =
            replacement + entry.chapter.title.substring(entry.match.end);
        next = end;
        if (title == entry.chapter.title) continue;
        patches.add(
          TextPatch(
            chapterId: entry.chapter.id,
            blockId: null,
            before: entry.chapter.title,
            after: title,
          ),
        );
        if (samples.length < previewSampleLimit) {
          samples.add(
            ReplaceSample(
              chapterId: entry.chapter.id,
              blockId: null,
              chapterTitle: entry.chapter.title,
              field: ReplaceField.title,
              before: entry.match[1]!,
              match: entry.match[0]!.substring(
                entry.match[1]!.length,
                entry.match[0]!.length - entry.match[5]!.length,
              ),
              after: entry.chapter.title.substring(entry.match.end),
            ),
          );
        }
      }
    }
    return ToolPreview(
      baseRevision: baseRevision,
      hits: patches.length,
      patches: patches,
      samples: samples,
    );
  }

  /// One scan produces the count, samples, and sparse patches. Run this pure
  /// function through BackgroundJobs for isolation, timeout and cancellation.
  static ToolPreview previewReplace(
    Book book, {
    required int baseRevision,
    required ReplaceOptions options,
  }) {
    if (options.find.isEmpty) {
      throw const ValidationFailure('查找内容不能为空。');
    }
    if (options.find.length > replaceFindLimit ||
        options.replace.length > replaceTextLimit) {
      throw const ValidationFailure('查找最多 200 字，替换最多 500 字。');
    }
    final safe = options.regex
        ? SafeRegex.compile(options.find, caseSensitive: options.caseSensitive)
        : SafePattern(
            RegExp(
              RegExp.escape(options.find),
              caseSensitive: options.caseSensitive,
              unicode: true,
            ),
            0,
          );
    if (options.regex) _validateReplacement(options.replace);
    final patches = <TextPatch>[];
    final samples = <ReplaceSample>[];
    var hits = 0;

    void scan(Chapter chapter, String? blockId, String original) {
      StringBuffer? output;
      var copiedThrough = 0;
      for (final match in safe.regex.allMatches(original)) {
        if (++hits > replaceHitLimit) {
          throw const ValidationFailure('命中超过 200000 处，请缩小查找范围。');
        }
        if (samples.length < previewSampleLimit) {
          samples.add(
            ReplaceSample(
              chapterId: chapter.id,
              blockId: blockId,
              chapterTitle: chapter.title,
              field: blockId == null ? ReplaceField.title : ReplaceField.body,
              before: original.substring(
                _contextStart(original, match.start),
                match.start,
              ),
              match: match.group(0)!,
              after: original.substring(
                match.end,
                _contextEnd(original, match.end),
              ),
            ),
          );
        }
        output ??= StringBuffer();
        output.write(original.substring(copiedThrough, match.start));
        output.write(
          options.regex
              ? _expandReplacement(options.replace, match, safe.captureCount)
              : options.replace,
        );
        copiedThrough = match.end;
      }
      if (output == null) return;
      output.write(original.substring(copiedThrough));
      final replaced = output.toString();
      if (replaced != original) {
        patches.add(
          TextPatch(
            chapterId: chapter.id,
            blockId: blockId,
            before: original,
            after: replaced,
          ),
        );
      }
    }

    for (final chapter in book.chapters) {
      if (options.scope != ReplaceScope.body) {
        scan(chapter, null, chapter.title);
      }
      if (options.scope != ReplaceScope.title) {
        for (final block in chapter.blocks) {
          if (block is TextBlock) scan(chapter, block.id, block.text);
        }
      }
    }
    return ToolPreview(
      baseRevision: baseRevision,
      hits: hits,
      patches: patches,
      samples: samples,
    );
  }

  static List<AuditNumberGap> numberGaps(List<Chapter> chapters) =>
      List<AuditNumberGap>.unmodifiable(
        _numberIssues(chapters)
            .map((issue) => issue.numberGap)
            .whereType<AuditNumberGap>(),
      );

  static Iterable<AuditIssue> _numberIssues(List<Chapter> chapters) sync* {
    for (final entries in _numberedGroups(chapters).values) {
      final ordered = entries.toList()
        ..sort((left, right) {
          final byNumber = left.value.compareTo(right.value);
          return byNumber != 0 ? byNumber : left.index.compareTo(right.index);
        });
      var coveredThrough = 0;
      _NumberedEntry? covering;
      for (final entry in ordered) {
        if (entry.value <= coveredThrough) {
          yield AuditIssue(
            kind: AuditIssueKind.duplicateNumber,
            chapterId: entry.chapter.id,
            chapterIndex: entry.index,
            chapterTitle: entry.chapter.title,
            message: entry.value == entry.end
                ? '同卷章号重复：第 ${entry.value} 章，建议核对或重编号。'
                : '同卷章号范围重叠：第 ${entry.value} 至 ${entry.end} 章，建议核对或重编号。',
          );
        }
        if (entry.value > coveredThrough + 1) {
          yield AuditIssue(
            kind: AuditIssueKind.missingNumber,
            chapterId: entry.chapter.id,
            chapterIndex: entry.index,
            chapterTitle: entry.chapter.title,
            message:
                '同卷章号缺少 ${coveredThrough + 1} 至 ${entry.value - 1}，建议检查漏章候选。',
            numberGap: AuditNumberGap(
              beforeChapterId: covering?.chapter.id,
              afterChapterId: entry.chapter.id,
              firstMissing: coveredThrough + 1,
              lastMissing: entry.value - 1,
            ),
          );
        }
        if (entry.end > coveredThrough) {
          coveredThrough = entry.end;
          covering = entry;
        }
      }
    }
  }

  static Map<String?, List<_NumberedEntry>> _numberedGroups(
    List<Chapter> chapters, {
    bool rejectInvalidRanges = false,
  }) {
    final groups = <String?, List<_NumberedEntry>>{};
    for (final (index, chapter) in chapters.indexed) {
      if (chapter.isVolume || chapter.frontMatter) continue;
      final match = _numbered.firstMatch(chapter.title);
      if (match == null) continue;
      final raw = match[2]!;
      final value = _parseNumber(raw);
      if (value == null || value < 1) {
        if (rejectInvalidRanges && match[4] != null) {
          throw ValidationFailure('章节「${chapter.title}」的章号范围无效，请先修改标题。');
        }
        continue;
      }
      final end = match[4] == null ? value : _parseNumber(match[4]!);
      if (end == null || end < value) {
        if (rejectInvalidRanges) {
          throw ValidationFailure('章节「${chapter.title}」的章号范围无效，请先修改标题。');
        }
        continue;
      }
      groups
          .putIfAbsent(chapter.parentId, () => <_NumberedEntry>[])
          .add(_NumberedEntry(chapter, index, match, raw, value, end));
    }
    return groups;
  }

  static int? _parseNumber(String raw) =>
      RuleHeadingMapping.parseNumber(raw) ??
      int.tryParse(raw) ??
      _parseChinese(raw);

  static bool _validNumberedRange(RegExpMatch match) {
    final start = _parseNumber(match[2]!);
    final end = match[4] == null ? start : _parseNumber(match[4]!);
    return start != null && start > 0 && end != null && end >= start;
  }

  static bool _narrativeAfterNumber(RegExpMatch match, String title) =>
      RegExp(r'^[的里中内]').hasMatch(title.substring(match.end).trimLeft());

  static bool _adjacentQuestionHeading(
    List<Chapter> chapters,
    int chapterIndex,
    String title,
  ) {
    final match = _numbered.firstMatch(title);
    if (match == null || !_validNumberedRange(match)) return false;
    if (_narrativeAfterNumber(match, title)) return false;
    final start = _parseNumber(match[2]!)!;
    final end = _parseNumber(match[4] ?? match[2]!)!;
    final current = chapters[chapterIndex];
    final currentMatch = _numbered.firstMatch(current.title);
    final currentEnd = currentMatch != null && _validNumberedRange(currentMatch)
        ? _parseNumber(currentMatch[4] ?? currentMatch[2]!)
        : null;
    int? nextStart;
    for (var index = chapterIndex + 1; index < chapters.length; index++) {
      final next = chapters[index];
      if (next.isVolume) break;
      if (next.parentId != current.parentId) continue;
      final nextMatch = _numbered.firstMatch(next.title);
      if (nextMatch != null && _validNumberedRange(nextMatch)) {
        nextStart = _parseNumber(nextMatch[2]!);
        break;
      }
    }
    final followsCurrent = currentEnd != null && currentEnd + 1 == start;
    final precedesNext = nextStart != null && end + 1 == nextStart;
    return currentEnd != null && nextStart != null
        ? followsCurrent && precedesNext
        : followsCurrent || precedesNext;
  }

  static String _renumberedNumeral(String raw, int value) =>
      RegExp(r'^\d+$').hasMatch(raw)
      ? value.toString().padLeft(raw.startsWith('0') ? raw.length : 0, '0')
      : _numberToChinese(value);

  static int? _parseChinese(String raw) {
    const digits = '零一二三四五六七八九';
    const formal = '零壹贰叁肆伍陆柒捌玖';
    const units = <String, int>{
      '十': 10,
      '拾': 10,
      '百': 100,
      '佰': 100,
      '千': 1000,
      '仟': 1000,
      '万': 10000,
    };
    var total = 0;
    var section = 0;
    var digit = 0;
    for (final rune in raw.runes) {
      final character = String.fromCharCode(rune);
      final char = character == '〇' ? '零' : character;
      final number = digits.indexOf(char);
      final formalNumber = formal.indexOf(char);
      if (number >= 0 || formalNumber >= 0 || char == '两') {
        digit = char == '两' ? 2 : (number >= 0 ? number : formalNumber);
        continue;
      }
      final unit = units[char];
      if (unit == null) return null;
      if (unit < 10000) {
        section += (digit == 0 ? 1 : digit) * unit;
      } else {
        total += (section + digit) * unit;
        section = 0;
      }
      digit = 0;
    }
    return total + section + digit;
  }

  static String _numberToChinese(int value) {
    if (value > 9999) return '$value';
    const digits = '零一二三四五六七八九';
    const units = <String>['', '十', '百', '千'];
    final out = StringBuffer();
    var pendingZero = false;
    for (var place = 3; place >= 0; place--) {
      final digit = value ~/ _pow10(place) % 10;
      if (digit == 0) {
        if (out.isNotEmpty) pendingZero = true;
        continue;
      }
      if (pendingZero) out.write('零');
      pendingZero = false;
      if (!(place == 1 && digit == 1 && out.isEmpty)) out.write(digits[digit]);
      out.write(units[place]);
    }
    return out.toString();
  }

  static int _pow10(int exponent) {
    var value = 1;
    for (var i = 0; i < exponent; i++) {
      value *= 10;
    }
    return value;
  }

  static bool _isAdLine(String text) =>
      text.isNotEmpty &&
      (_adStrong.hasMatch(text) ||
          (text.length <= 80 && _adShort.hasMatch(text)));

  static int _contextStart(String text, int start) {
    var result = (start - previewContextLength).clamp(0, text.length);
    if (result < text.length && _isLowSurrogate(text.codeUnitAt(result))) {
      result++;
    }
    return result;
  }

  static int _contextEnd(String text, int end) {
    var result = (end + previewContextLength).clamp(0, text.length);
    if (result > 0 &&
        result < text.length &&
        _isHighSurrogate(text.codeUnitAt(result - 1))) {
      result--;
    }
    return result;
  }

  static bool _isLowSurrogate(int unit) => unit >= 0xdc00 && unit <= 0xdfff;
  static bool _isHighSurrogate(int unit) => unit >= 0xd800 && unit <= 0xdbff;

  static void _validateReplacement(String replacement) {
    for (var i = 0; i < replacement.length - 1; i++) {
      if (replacement[i] != r'$') continue;
      if (replacement[i + 1] == r'$') {
        i++;
        continue;
      }
      if (replacement[i + 1] == "'" ||
          replacement[i + 1] == '`' ||
          replacement[i + 1] == '<') {
        throw const ValidationFailure(r"不支持 $`、$' 或 $<...> 替换语法。");
      }
    }
  }

  static String _expandReplacement(String source, Match match, int captures) {
    final out = StringBuffer();
    for (var i = 0; i < source.length; i++) {
      final char = source[i];
      if (char != r'$' || i + 1 >= source.length) {
        out.write(char);
        continue;
      }
      final next = source[i + 1];
      if (next == r'$') {
        out.write(r'$');
        i++;
      } else if (next == '&') {
        out.write(match.group(0));
        i++;
      } else if (_isDigit(next) && next != '0') {
        var group = int.parse(next);
        var consumed = 1;
        if (i + 2 < source.length && _isDigit(source[i + 2])) {
          final doubleDigit = group * 10 + int.parse(source[i + 2]);
          if (doubleDigit <= captures) {
            group = doubleDigit;
            consumed = 2;
          }
        }
        if (group <= captures) {
          out.write(match.group(group) ?? '');
          i += consumed;
        } else {
          out.write(char);
        }
      } else {
        out.write(char);
      }
    }
    return out.toString();
  }

  static bool _isDigit(String value) =>
      value.codeUnitAt(0) >= 48 && value.codeUnitAt(0) <= 57;
}

class _NumberedEntry {
  const _NumberedEntry(
    this.chapter,
    this.index,
    this.match,
    this.raw,
    this.value,
    this.end,
  );
  final Chapter chapter;
  final int index;
  final RegExpMatch match;
  final String raw;
  final int value;
  final int end;
}

import 'package:bookloom/core/model/block.dart';
import 'package:bookloom/core/model/chapter.dart';
import 'package:bookloom/core/model/metadata.dart';
import 'package:bookloom/core/model/parse_options.dart';
import 'package:bookloom/core/model/parse_result.dart';
import 'package:bookloom/core/parsing/rules.dart';
import 'package:uuid/uuid.dart';

const _uuid = Uuid();
const _maxParagraphLength = 20000;
const _maxDescriptionLength = 2000;
const _maxDescriptionLines = 30;
const _chineseNumerals = '零〇一二三四五六七八九十百千万两壹贰叁肆伍陆柒捌玖拾佰仟';

final _descriptionHeader = RegExp(
  r'^([内內]容[简簡]介|作品[简簡]介|[图圖][书書][简簡]介|[简簡]介|文案)(?:[ \t\u3000]*[:：][ \t\u3000]*(.*)|[ \t\u3000]+(.*))?$',
);
final _descriptionBoundary = RegExp(
  r'^(?:(?:[书書]名|[书書]籍名[称稱]|作品名[称稱]|作者|著者|分[类類]|[类類][别別]|[类類]型|[标標][签籤]|[状狀][态態]|字[数數]|出版社|出版[时時][间間]|[内內]容[标標][签籤]|主角|配角)\s*[:：]|目[录錄]$|正文$|作品信息$|[图圖][书書]信息$|[书書]籍信息$)',
);

final _volume = RegExp(
  '^(?:正文[\\s·:：\\-—]*)?第\\s*[$_chineseNumerals\\d]{1,8}\\s*[卷部篇集](?:\\s*[、.．:：·\\-—]\\s*)?[^。]{0,30}\$',
);
final _volumeAlternate = RegExp(
  '^[卷部篇集]\\s*[$_chineseNumerals\\d]{1,6}(?:\\s*[、.．:：·\\-—]\\s*)?[^。]{0,24}\$',
);
final _chapter = RegExp(
  '^(?:正文[\\s·:：\\-—]*)?第\\s*[$_chineseNumerals\\d]{1,8}(?:\\s*[~～\\-—]\\s*[$_chineseNumerals\\d]{1,8})?\\s*[章节回话](?:\\s*[、.．:：·\\-—]\\s*)?[^。]{0,30}\$',
);
final _chapterRange = RegExp(
  '^(?:正文[\\s·:：\\-—]*)?第\\s*[$_chineseNumerals\\d]{1,8}\\s*[~～\\-—]\\s*[$_chineseNumerals\\d]{1,8}\\s*[章节回话]',
);
final _chapterNumber = RegExp(
  '^(?:正文[\\s·:：\\-—]*)?第\\s*([$_chineseNumerals\\d]{1,8})(?:\\s*[~～\\-—]\\s*([$_chineseNumerals\\d]{1,8}))?\\s*[章节回话]',
);
final _chapterReference = RegExp(
  r'^的(?:故事|草稿|内容|情节|标题|正文)(?:仍|还|已经|整理|讲述|提到|写|是|在)',
);
final _excludedPart = RegExp(
  '^第\\s*[$_chineseNumerals\\d]{1,8}\\s*部(?:门|队|属|分|件|落)',
);
final _special = RegExp(
  r'^(?:序章|序言|序|楔子|引子|前言|引言|后记|尾声|终章|最终章|完本感言|大结局|番外(?:篇)?(?:[\s:：·、.．\-—]?\s*[0-9一二三四五六七八九十百千]{0,6})?|附录|作者的话|[内內]容[简簡]介|作品[简簡]介)(?:[\s:：·、.．\-—].{0,30})?$',
);
final _english = RegExp(
  r'^(?:chapter|part|volume|section|page|prologue|epilogue)\b[\s.:：\-—]*.{0,40}$',
  caseSensitive: false,
);
final _headingCore = RegExp(
  '第\\s*[$_chineseNumerals\\d]{1,8}(?:\\s*[~～\\-—]\\s*[$_chineseNumerals\\d]{1,8})?\\s*[章节回卷部篇集]',
);
final _terminalQuestion = RegExp(r'[！？!?]$');
final _inlineJunk = RegExp(
  r'内容还在处理中|正在手打中|正在更新中|本章未完|请稍后|请稍候|加载中|手机用户|手机阅读|记住本站|求月票|求推荐票|更新最快|无弹窗|笔趣阁|最新章节|电子书|txt',
  caseSensitive: false,
);
final _titleMarker = RegExp(
  '^(第\\s*[$_chineseNumerals\\d]{1,8}\\s*[章节回话卷部篇集])([^\\s、.．:：·\\-—（(【\\[《「『〈])',
);
final _terminal = RegExp(r'''[。！？!?…；;」』"'）)】》”’]$''');
final _asciiEnd = RegExp(r'[A-Za-z0-9]$');
final _asciiStart = RegExp(r'^[A-Za-z0-9]');

final _strongAds = <RegExp>[
  RegExp(r'爱下电子书|ixdzs|苦读书|书友群|下载和分享更多电子书|txt下载', caseSensitive: false),
  RegExp(r'https?://\S+', caseSensitive: false),
  RegExp(r'^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$'),
  RegExp(r'^[-—=~*_·]{3,}$'),
  RegExp(r'^[-—=~*_·]{2,}[^。！？]{0,18}[-—=~*_·]{2,}$'),
  RegExp(r'^[-—=~*_·]*章节内容开始[-—=~*_·]*$'),
];
final _shortAds = <RegExp>[
  RegExp(r'本章未完[，,]?\s*(请)?(点击|翻)[^。！？]{0,12}(下一页|继续)'),
  RegExp(r'请记住(本书|本站|域名|地址)'),
  RegExp(r'(手机|移动)(端|用户)?(请)?(浏览|阅读|访问)'),
  RegExp(r'更新最快|无弹窗[^。！？]{0,10}(阅读|小说)'),
  RegExp(r'笔趣阁|顶点小说|八一中文网|新笔趣|书趣阁|全文免费阅读|免费阅读全文'),
  RegExp(r'www\.[a-z0-9-]+\.(?:com|net|org|cc|info|cn)', caseSensitive: false),
  RegExp(r'^[（(【\[]?\s*(?:求|跪求|感谢)?\s*(?:月票|推荐票|订阅|收藏|打赏)'),
  RegExp(r'^(?:上一章|下一章|返回目录|加入书签|章节目录)$'),
  RegExp(r'内容还在处理中|正在手打中|正在更新中|请稍后重试|请稍候'),
];

/// Pure text stage of TXT import. Byte decoding belongs to [parseTxtBytes].
/// [bookId] is the future owning book; this function does not persist anything.
ParseResult parseTxtText(
  String text, {
  required String bookId,
  required String filename,
  ParseOptions options = const ParseOptions(),
  String? actualEncoding,
  double? encodingConfidence,
}) {
  if (options.convertMode != ConvertMode.none) {
    throw UnsupportedError('TXT character conversion is not implemented yet.');
  }
  final rules = resolveTxtRules(options);

  final normalized = normalizeTxtText(text);
  if (normalized.trim().isEmpty) {
    final info = _inferMetadata(filename, normalized);
    return ParseResult(
      format: ImportFormat.txt,
      actualEncoding: actualEncoding,
      encodingConfidence: encodingConfidence,
      suggestedMeta: BookMeta(title: info.title, author: info.author),
      chapters: const <Chapter>[],
      warnings: const <ParseWarning>[
        ParseWarning(code: 'empty_source', message: '原文没有可导入的正文。'),
      ],
    );
  }
  final originalLines = <_Line>[
    for (final (index, value) in normalized.split('\n').indexed)
      _Line(value, index + 1),
  ];
  final warnings = <ParseWarning>[];
  final lines = _applyRuleDrops(originalLines, rules, warnings);
  if (lines.every((line) => line.text.trim().isEmpty)) {
    final info = _inferMetadata(filename, normalized);
    return ParseResult(
      format: ImportFormat.txt,
      actualEncoding: actualEncoding,
      encodingConfidence: encodingConfidence,
      suggestedMeta: BookMeta(title: info.title, author: info.author),
      chapters: const <Chapter>[],
      warnings: const <ParseWarning>[
        ParseWarning(code: 'empty_source', message: '规则清洗后没有可导入的正文。'),
      ],
    );
  }
  final detected = _detectHeadings(lines, rules);
  final tocEnd = _leadingTocEnd(lines, detected);
  var headings = detected
      .where((heading) => heading.lineIndex > tocEnd)
      .toList();
  headings = _pruneHeadingOnlyDocument(headings, lines);
  if (headings.isEmpty) headings = _fallbackHeadings(lines);

  final chapters = <Chapter>[];
  final locations = <String, ParseSourceLocation>{};
  var currentVolumeId = null as String?;

  void appendChapter({
    required String title,
    required int level,
    required bool frontMatter,
    required List<_Line> bodyLines,
    required int headingLine,
  }) {
    final id = _uuid.v4();
    final paragraphs = _buildParagraphs(
      bodyLines,
      filterAds: options.filterAds,
    );
    final blocks = <Block>[];
    for (final paragraph in paragraphs) {
      final blockId = _uuid.v4();
      blocks.add(TextBlock(id: blockId, text: paragraph.text));
      locations[blockId] = ParseSourceLocation(line: paragraph.line);
    }
    final parentId = level == 2 && !frontMatter ? currentVolumeId : null;
    chapters.add(
      Chapter(
        id: id,
        bookId: bookId,
        title: title,
        parentId: parentId,
        level: level,
        order: chapters.length,
        blocks: blocks,
        frontMatter: frontMatter,
      ),
    );
    locations[id] = ParseSourceLocation(line: headingLine);
    if (level == 1) currentVolumeId = id;
  }

  if (headings.isEmpty) {
    appendChapter(
      title: '正文',
      level: 2,
      frontMatter: false,
      bodyLines: lines,
      headingLine: 1,
    );
    warnings.add(
      const ParseWarning(code: 'no_headings', message: '没有识别到章节标题，已按单章导入。'),
    );
  } else {
    final first = headings.first;
    final frontStart = tocEnd + 1;
    final frontLines = lines.sublist(
      frontStart.clamp(0, lines.length),
      first.lineIndex,
    );
    if (_buildParagraphs(frontLines, filterAds: options.filterAds).isNotEmpty) {
      final hasDescription = frontLines
          .take(8)
          .any((line) => _descriptionHeader.hasMatch(line.text.trim()));
      appendChapter(
        title: hasDescription ? '内容简介' : '前言',
        level: 2,
        frontMatter: true,
        bodyLines: frontLines,
        headingLine: frontLines.first.line,
      );
    }
    for (var i = 0; i < headings.length; i++) {
      final heading = headings[i];
      final bodyEnd = i + 1 < headings.length
          ? headings[i + 1].lineIndex
          : lines.length;
      final intro = _descriptionHeader.firstMatch(
        lines[heading.lineIndex].text.trim(),
      );
      final inlineBody = (intro?[2] ?? intro?[3])?.trim();
      appendChapter(
        title: inlineBody != null && inlineBody.isNotEmpty
            ? intro![1]!
            : heading.title,
        level: heading.level,
        frontMatter: _isFrontMatterHeading(heading.title),
        bodyLines: <_Line>[
          if (inlineBody != null && inlineBody.isNotEmpty)
            _Line(inlineBody, lines[heading.lineIndex].line),
          ...lines.sublist(heading.lineIndex + 1, bodyEnd),
        ],
        headingLine: lines[heading.lineIndex].line,
      );
    }
  }

  final info = _inferMetadata(filename, normalized);
  if (chapters.length > 2000) {
    warnings.add(
      const ParseWarning(
        code: 'many_chapters',
        message: '章节数量超过 2000，校对列表可能较长。',
      ),
    );
  }
  return ParseResult(
    format: ImportFormat.txt,
    actualEncoding: actualEncoding,
    encodingConfidence: encodingConfidence,
    suggestedMeta: BookMeta(
      title: info.title,
      author: info.author,
      description: _inferDescription(
        lines,
        headings,
        tocEnd,
        options.filterAds,
      ),
    ),
    chapters: chapters,
    warnings: warnings,
    sourceLocations: locations,
  );
}

/// Normalizes line boundaries and removes control characters that cannot be
/// rendered as book text. Tabs and line feeds remain meaningful to paragraphing.
String normalizeTxtText(String text) => text
    .replaceAll('\r\n', '\n')
    .replaceAll('\r', '\n')
    .replaceAll('\u2028', '\n')
    .replaceAll('\u2029', '\n\n')
    .replaceAll(
      RegExp(
        r'[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F\u200B-\u200F\uFEFF]',
      ),
      '',
    );

bool _isAd(String text) {
  final value = text.trim();
  if (value.isEmpty) return false;
  if (_strongAds.any((pattern) => pattern.hasMatch(value))) return true;
  if (value.length > 80) return false;
  return _shortAds.any((pattern) => pattern.hasMatch(value));
}

List<_Paragraph> _buildParagraphs(List<_Line> raw, {required bool filterAds}) {
  final lines = <_Line>[
    for (final line in raw)
      filterAds && _isAd(line.text) ? _Line('', line.line) : line,
  ];
  final content = lines.where((line) => line.text.trim().isNotEmpty).toList();
  if (content.isEmpty) return [];
  final indented = content
      .where((line) => RegExp(r'^(?:\u3000{1,2}|\t| {2,})').hasMatch(line.text))
      .length;
  final useIndent = indented * 2 >= content.length;
  final result = <_Paragraph>[];

  void addBounded(String text, int line) {
    var remaining = text;
    while (remaining.length > _maxParagraphLength) {
      final split = _safeSplitIndex(remaining);
      result.add(_Paragraph(remaining.substring(0, split), line));
      remaining = remaining.substring(split);
    }
    if (remaining.isNotEmpty) result.add(_Paragraph(remaining, line));
  }

  if (useIndent) {
    for (final line in lines) {
      final trimmed = line.text.trim();
      if (trimmed.isNotEmpty) addBounded(trimmed, line.line);
    }
    return result;
  }

  var buffer = '';
  var startLine = 1;
  void flush() {
    if (buffer.isNotEmpty) addBounded(buffer, startLine);
    buffer = '';
  }

  for (final line in lines) {
    final trimmed = line.text.trim();
    if (trimmed.isEmpty) {
      flush();
      continue;
    }
    if (buffer.isEmpty) {
      buffer = trimmed;
      startLine = line.line;
    } else {
      final separator =
          _asciiEnd.hasMatch(buffer) && _asciiStart.hasMatch(trimmed)
          ? ' '
          : '';
      buffer += '$separator$trimmed';
    }
    while (buffer.length > _maxParagraphLength) {
      final split = _safeSplitIndex(buffer);
      result.add(_Paragraph(buffer.substring(0, split), startLine));
      buffer = buffer.substring(split);
      startLine = line.line;
    }
    if (_terminal.hasMatch(trimmed)) flush();
  }
  flush();
  return result;
}

int _safeSplitIndex(String text) {
  final last = text.codeUnitAt(_maxParagraphLength - 1);
  final next = text.codeUnitAt(_maxParagraphLength);
  return last >= 0xd800 && last <= 0xdbff && next >= 0xdc00 && next <= 0xdfff
      ? _maxParagraphLength - 1
      : _maxParagraphLength;
}

List<_Line> _applyRuleDrops(
  List<_Line> lines,
  CompiledTxtRules rules,
  List<ParseWarning> warnings,
) {
  if (rules.isEmpty) return lines;
  var warnedLongLine = false;
  final cleaned = <_Line>[];
  for (final line in lines) {
    if (line.text.length > maxRuleLineLength) {
      // Long text must not enter a user regular expression. Keep it intact.
      if (!warnedLongLine) {
        warnings.add(
          ParseWarning(
            code: 'rule_line_too_long',
            message: '部分长行超过规则匹配上限，已保留原文。',
            line: line.line,
          ),
        );
        warnedLongLine = true;
      }
      cleaned.add(line);
    } else if (_shouldDropRuleLine(line.text, rules)) {
      cleaned.add(_Line('', line.line));
    } else {
      cleaned.add(line);
    }
  }
  return cleaned;
}

bool _shouldDropRuleLine(String text, CompiledTxtRules rules) {
  if (!rules.matchesDrop(text.trim())) return false;
  final recovered = rules.stripInlineJunk(text.trim());
  return recovered == null || _classify(recovered, rules) == null;
}

List<_Heading> _detectHeadings(List<_Line> lines, CompiledTxtRules rules) {
  final headings = <_Heading>[];
  for (var i = 0; i < lines.length; i++) {
    final raw = lines[i].text.trim();
    if (raw.isEmpty) continue;
    if (raw.length > maxRuleLineLength) continue;
    var classified = _classify(raw, rules);
    if (classified == null) {
      final customSuffix = rules.stripInlineJunk(raw);
      if (customSuffix != null) classified = _classify(customSuffix, rules);
    }
    if (classified == null) {
      final match = _headingCore.firstMatch(raw);
      if (match != null && match.start > 0) {
        final prefix = raw.substring(0, match.start).trim();
        if (prefix.length <= 24 && _inlineJunk.hasMatch(prefix)) {
          classified = _classify(raw.substring(match.start).trim(), rules);
        }
      }
    }
    if (classified != null) {
      headings.add(_Heading(i, classified.$1, classified.$2, classified.$3));
    }
  }
  final kept = <_Heading>[];
  for (var index = 0; index < headings.length; index++) {
    if (_keepHeading(headings, kept, index)) kept.add(headings[index]);
  }
  return kept;
}

int? _parseChapterNumber(String text) {
  final arabic = int.tryParse(text);
  if (arabic != null) return arabic;
  const digits = '零一二三四五六七八九';
  const variants = <String, String>{
    '〇': '零',
    '两': '二',
    '壹': '一',
    '贰': '二',
    '叁': '三',
    '肆': '四',
    '伍': '五',
    '陆': '六',
    '柒': '七',
    '捌': '八',
    '玖': '九',
    '拾': '十',
    '佰': '百',
    '仟': '千',
  };
  const units = <String, int>{'十': 10, '百': 100, '千': 1000, '万': 10000};
  var total = 0;
  var section = 0;
  var number = 0;
  for (final character in text.split('')) {
    final normalized = variants[character] ?? character;
    final digit = digits.indexOf(normalized);
    if (digit >= 0) {
      number = number * 10 + digit;
      continue;
    }
    final unit = units[normalized];
    if (unit == null) return null;
    if (unit == 10000) {
      total += (section + number) * unit;
      section = 0;
    } else {
      section += (number == 0 ? 1 : number) * unit;
    }
    number = 0;
  }
  return total + section + number;
}

({int start, int end})? _headingNumbers(_Heading heading) {
  if (heading.level != 2) return null;
  final match = _chapterNumber.firstMatch(heading.title);
  if (match == null) return null;
  final start = _parseChapterNumber(match[1]!);
  final end = _parseChapterNumber(match[2] ?? match[1]!);
  if (start == null || end == null || start < 1 || end < start) return null;
  return (start: start, end: end);
}

bool _keepHeading(List<_Heading> headings, List<_Heading> kept, int index) {
  final heading = headings[index];
  if (heading.score != 95 || !_terminalQuestion.hasMatch(heading.title)) {
    return true;
  }
  final number = _headingNumbers(heading);
  if (number == null) return heading.lineIndex == 0;
  final start = number.start;
  final end = number.end;
  if (heading.lineIndex == 0 ||
      start == 1 &&
          headings
              .take(index)
              .every(
                (other) =>
                    other.level == 1 || _isFrontMatterHeading(other.title),
              )) {
    return true;
  }
  for (final other in kept.reversed) {
    final otherNumber = _headingNumbers(other);
    if (otherNumber == null) continue;
    if (otherNumber.end + 1 == start) {
      return true;
    }
    break;
  }
  for (var next = index + 1; next < headings.length; next++) {
    final other = headings[next];
    if (_terminalQuestion.hasMatch(other.title)) continue;
    final otherNumber = _headingNumbers(other);
    if (otherNumber == null) continue;
    if (end + 1 == otherNumber.start) {
      return true;
    }
    break;
  }
  return false;
}

(String, int, int)? _classify(String text, CompiledTxtRules rules) {
  if (text.length > maxRuleLineLength) return null;
  final customTitle = _cleanTitle(text);
  if (rules.volume?.hasMatch(text) ?? false) return (customTitle, 1, 110);
  if (rules.chapter?.hasMatch(text) ?? false) return (customTitle, 2, 105);
  final number = _chapterNumber.firstMatch(text);
  if (number != null &&
      _chapterReference.hasMatch(text.substring(number.end))) {
    return null;
  }
  if (text.length > 42 ||
      _excludedPart.hasMatch(text) ||
      RegExp(r'。$').hasMatch(text)) {
    return null;
  }
  if (_terminalQuestion.hasMatch(text) &&
      (text.length > 26 || !_chapter.hasMatch(text))) {
    return null;
  }
  if (text.length > 26 && RegExp(r'[，,；;]').hasMatch(text)) return null;
  final title = _cleanTitle(text);
  if (_volume.hasMatch(text) || _volumeAlternate.hasMatch(text)) {
    return (title, 1, 100);
  }
  if (_chapter.hasMatch(text)) return (title, 2, 95);
  if (_special.hasMatch(text)) return (title, 2, 90);
  if (_english.hasMatch(text)) return (title, 2, 85);
  return null;
}

String _cleanTitle(String text) {
  final compact = text
      .replaceAll('\u3000', ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  final stripped = compact
      .replaceFirst(
        RegExp(
          r'[（(【\[]\s*(?:求|感谢|首发|更新|本章|第[一二三四五六七八九十\d]+更)[^）)】\]]{0,20}[）)】\]]\s*$',
        ),
        '',
      )
      .trim();
  if (_chapterRange.hasMatch(stripped)) return stripped;
  return (stripped.isEmpty ? compact : stripped).replaceFirstMapped(
    _titleMarker,
    (match) => '${match[1]} ${match[2]}',
  );
}

bool _isFrontMatterHeading(String title) =>
    _descriptionHeader.hasMatch(title) ||
    RegExp(r'^(?:序章|序言|序|楔子|引子|前言|引言)').hasMatch(title);

List<_Heading> _pruneHeadingOnlyDocument(
  List<_Heading> headings,
  List<_Line> lines,
) {
  if (headings.length < 5) return headings;
  // A short volume/chapter can have only one line of body, so the average
  // distance between headings says little. Suppress only a document that is
  // almost entirely headings, such as a copied table of contents with no body.
  final contentLineCount = lines
      .where((line) => line.text.trim().isNotEmpty)
      .length;
  final nonHeadingCount = contentLineCount - headings.length;
  return nonHeadingCount <= headings.length ~/ 10 ? [] : headings;
}

int _leadingTocEnd(List<_Line> lines, List<_Heading> headings) {
  if (headings.length < 6 || headings.first.lineIndex > 30) return -1;
  var end = 0;
  while (end + 1 < headings.length &&
      headings[end + 1].lineIndex - headings[end].lineIndex <= 1) {
    end++;
  }
  if (end < 3 || end + 1 >= headings.length) return -1;
  final gap = headings[end + 1].lineIndex - headings[end].lineIndex;
  final laterTitles = headings
      .skip(end + 1)
      .map((heading) => heading.title)
      .toSet();
  final repeated = headings
      .take(end + 1)
      .where((heading) => laterTitles.contains(heading.title))
      .length;
  final hasTocLabel = lines
      .take(headings.first.lineIndex)
      .any((line) => line.text.trim() == '目录');
  if (gap < 2 || (!hasTocLabel && repeated * 2 < end + 1)) return -1;
  return headings[end].lineIndex;
}

List<_Heading> _fallbackHeadings(List<_Line> lines) {
  final spans = <(int, int)>[];
  var start = -1;
  for (var i = 0; i < lines.length; i++) {
    if (lines[i].text.trim().isNotEmpty) {
      if (start < 0) start = i;
    } else if (start >= 0) {
      spans.add((start, i));
      start = -1;
    }
  }
  if (start >= 0) spans.add((start, lines.length));
  if (spans.length < 5) return [];
  final candidates = spans.where((span) {
    final first = lines[span.$1].text.trim();
    return first.length <= 24 &&
        span.$2 - span.$1 - 1 >= 2 &&
        !RegExp(r'[。！？，、；;]$').hasMatch(first);
  }).toList();
  if (candidates.length < 4 || candidates.length * 2 < spans.length) return [];
  return [
    for (final span in candidates)
      _Heading(span.$1, _cleanTitle(lines[span.$1].text), 2, 40),
  ];
}

String _inferDescription(
  List<_Line> lines,
  List<_Heading> headings,
  int tocEnd,
  bool filterAds,
) {
  final headingAt = <int, _Heading>{
    for (final heading in headings) heading.lineIndex: heading,
  };
  for (var index = tocEnd + 1; index < lines.length; index++) {
    final heading = headingAt[index];
    if (heading != null && !_isFrontMatterHeading(heading.title)) break;
    final intro = _descriptionHeader.firstMatch(lines[index].text.trim());
    if (intro == null) continue;

    final body = <_Line>[];
    final inlineBody = (intro[2] ?? intro[3])?.trim();
    if (inlineBody != null && inlineBody.isNotEmpty) {
      body.add(_Line(inlineBody, lines[index].line));
    }
    var length = inlineBody?.length ?? 0;
    if (length > _maxDescriptionLength) return '';
    var contentLines = inlineBody == null || inlineBody.isEmpty ? 0 : 1;
    for (var next = index + 1; next < lines.length; next++) {
      final value = lines[next].text.trim();
      if (headingAt.containsKey(next) ||
          _descriptionHeader.hasMatch(value) ||
          _descriptionBoundary.hasMatch(value)) {
        break;
      }
      if (value.isNotEmpty) {
        length += value.length;
        contentLines++;
        if (length > _maxDescriptionLength ||
            contentLines > _maxDescriptionLines) {
          return '';
        }
      }
      body.add(lines[next]);
    }
    return _buildParagraphs(
      body,
      filterAds: filterAds,
    ).map((paragraph) => paragraph.text).join('\n\n');
  }
  return '';
}

({String title, String author}) _inferMetadata(String filename, String text) {
  final base = filename.replaceFirst(RegExp(r'\.[^.]+$'), '').trim();
  final filenameMatch = RegExp(
    r'《([^》]{1,60})》[^《》]{0,40}?作\s*者\s*[:：]\s*([^\s/|,，、;；]{1,20})',
  ).firstMatch(base);
  var title = filenameMatch?[1]?.trim() ?? base;
  var author = filenameMatch?[2]?.trim() ?? '';
  if (filenameMatch == null) {
    title = RegExp(r'^《([^》]+)》').firstMatch(title)?[1] ?? title;
    title = title
        .replaceAll(
          RegExp(
            r'[（(【\[]\s*(?:精校|全本|完结|校对|下载|txt|TXT|无删减|整理)[^）)】\]]*\s*[）)】\]]',
          ),
          '',
        )
        .replaceFirst(RegExp(r'\s*作\s*者\s*[:：].*$'), '')
        .trim();
  }
  final sample = text.length > 2000 ? text.substring(0, 2000) : text;
  final textTitle = RegExp(r'《([^》\n]{1,40})》').firstMatch(sample)?[1]?.trim();
  final textAuthor = RegExp(r'(?:作\s*者|著\s*者)\s*[:：]\s*([^\s/|,，、』」》<>]{1,20})')
      .firstMatch(sample)?[1]
      ?.trim();
  if (textTitle != null && textTitle.isNotEmpty) title = textTitle;
  if (textAuthor != null && textAuthor.isNotEmpty) author = textAuthor;
  return (title: title.isEmpty ? '未命名' : title, author: author);
}

class _Line {
  const _Line(this.text, this.line);
  final String text;
  final int line;
}

class _Paragraph {
  const _Paragraph(this.text, this.line);
  final String text;
  final int line;
}

class _Heading {
  const _Heading(this.lineIndex, this.title, this.level, this.score);
  final int lineIndex;
  final String title;
  final int level;
  final int score;
}

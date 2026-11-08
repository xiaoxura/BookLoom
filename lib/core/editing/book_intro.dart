import 'package:bookloom/core/model/block.dart';
import 'package:bookloom/core/model/chapter.dart';

/// A recognized book intro: the front-matter style chapter that carries the
/// book description between explicit markers, such as:
///
/// ```text
/// 『萌师在上：逆徒别乱来/作者:风与天幕』
/// 『状态:已完结』
/// 『内容简介:穿进修仙小说……』
/// 正文
/// ```
class BookIntro {
  const BookIntro({required this.chapterId, required this.description});

  /// The chapter that carries the description. Recognition success also hides
  /// this chapter from the chapter directory.
  final String chapterId;

  /// The extracted description text, joined by paragraph.
  final String description;
}

/// Only chapters near the start of the book can be the intro carrier.
const int maxIntroScanChapters = 4;

/// Descriptions beyond these limits are not trusted as an intro; the chapter
/// stays visible instead of silently truncating content.
const int _maxDescriptionCharacters = 2000;
const int _maxDescriptionBlocks = 30;

const List<String> _openers = <String>[
  '『',
  '「',
  '《',
  '〈',
  '【',
  '〔',
  '（',
  '(',
  '“',
  '"',
];
const List<String> _closers = <String>[
  '』',
  '」',
  '》',
  '】',
  '〕',
  '）',
  ')',
  '”',
  '"',
];

/// Preface-shaped titles that may carry the description once an explicit
/// marker is found inside.
final RegExp _introChapterTitle = RegExp(
  r'^(?:序章|序言|序|楔子|引子|引言|前言|作品信息|[图圖][书書]信息|[书書]籍信息|'
  r'[内內]容[简簡]介|作品[简簡]介|[图圖][书書][简簡]介|[简簡]介|文案)',
);

/// Titles that alone declare the chapter to be the description itself; the
/// whole body becomes the description even without an explicit marker.
final RegExp _exactDescriptionTitle = RegExp(
  r'^(?:[内內]容[简簡]介|[内內]容介[绍紹]|作品[简簡]介|[图圖][书書][简簡]介|[简簡]介|文案)$',
);

/// An explicit intro line, optionally wrapped in decorative brackets:
/// 『内容简介:…』、内容简介：…、 lone 内容简介. Mirrors the txt import rule:
/// a bare label line or a label with a colon/whitespace-separated body.
final RegExp _descriptionMarker = RegExp(
  r'^[『「《〈【〔（(“"]?\s*'
  r'(?:[内內]容[简簡]介|[内內]容介[绍紹]|作品[简簡]介|[图圖][书書][简簡]介|[简簡]介|文案)'
  r'(?:[ \t\u3000]*[:：][ \t\u3000]*(.*)|[ \t\u3000]+(.*))?$',
);

/// Companion meta items that end the description, e.g. 『状态:已完结』.
final RegExp _metaBoundary = RegExp(
  r'^[『「《〈【〔（(“"]?\s*'
  r'(?:[书書]名|[书書]籍名[称稱]|作品名|作者|著者|笔名|别名|[分類类][别類别]|类型|'
  r'[标標][签籤籤]?|[状狀][态態]|字[数數]|出版社|出版[时時][间間]|[内內]容[标標][签籤]|'
  r'主角|配角|上传|更新|首发|完结|状态|[简簡]介)[ \t\u3000]*[:：]',
);

/// Body starts and chapter headings always end the description.
final RegExp _contentBoundary = RegExp(
  r'^(?:正文$|目[录錄]$|第[0-9零〇一二三四五六七八九十百千万两壹贰貳叁肆伍陆陸柒捌玖拾佰仟]{1,8}[章节回卷部篇集])',
);

/// Scans the first few chapters of a book and returns the first detected
/// intro. [chapters] is mixed structural content; its blocks are enough.
BookIntro? detectBookIntro(List<Chapter> chapters) {
  var position = 0;
  for (final chapter in chapters) {
    if (chapter.isVolume) continue;
    if (position >= maxIntroScanChapters) break;
    position++;
    final intro = detectChapterIntro(chapter);
    if (intro != null) return intro;
  }
  return null;
}

/// Detects an intro inside one candidate chapter, e.g. an already-loaded body.
BookIntro? detectChapterIntro(Chapter chapter) {
  final title = chapter.title.trim();
  if (title.isEmpty) return null;
  if (!_introChapterTitle.hasMatch(title)) return null;
  final blocks = chapter.blocks.whereType<TextBlock>().toList(growable: false);
  if (blocks.isEmpty) return null;
  final description =
      _markerDescription(blocks) ??
      (_exactDescriptionTitle.hasMatch(title)
          ? _assembled(inline: '', wrapped: false, remaining: blocks)
          : null);
  if (description == null) return null;
  return BookIntro(chapterId: chapter.id, description: description);
}

/// True when the chapter title alone makes the chapter a plausible intro
/// carrier and its body should be inspected.
bool isIntroChapterCandidate(Chapter chapter) {
  if (chapter.isVolume) return false;
  final title = chapter.title.trim();
  return title.isNotEmpty && _introChapterTitle.hasMatch(title);
}

String? _markerDescription(List<TextBlock> blocks) {
  for (var index = 0; index < blocks.length; index++) {
    final first = _firstLine(blocks[index].text);
    final match = _descriptionMarker.firstMatch(first);
    if (match == null) continue;
    final inline = (match[1] ?? match[2] ?? '').trim();
    final wrapped = first.isNotEmpty && _openers.contains(first[0]);
    // A marker line that opens and closes on itself carries the whole
    // description; continuation paragraphs only follow an unfinished item.
    final selfContained =
        wrapped &&
        inline.isNotEmpty &&
        _closers.contains(inline.substring(inline.length - 1));
    return _assembled(
      inline: inline,
      wrapped: wrapped,
      remaining: selfContained
          ? const <TextBlock>[]
          : blocks.sublist(index + 1),
    );
  }
  return null;
}

/// Collects the description paragraphs after the marker until a boundary or
/// the trusted limits; an oversized body means the chapter is not a clean
/// intro and is reported as unrecognized (null).
String? _assembled({
  required String inline,
  required bool wrapped,
  required List<TextBlock> remaining,
}) {
  final parts = <String>[];
  var characters = 0;
  bool overLimit = false;

  void add(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return;
    characters += trimmed.length;
    if (characters > _maxDescriptionCharacters) {
      overLimit = true;
      return;
    }
    parts.add(trimmed);
  }

  bool endsClosed(String value) =>
      wrapped &&
      value.isNotEmpty &&
      _closers.contains(value.substring(value.length - 1));

  var closed = endsClosed(inline);
  if (inline.isNotEmpty) add(inline);
  for (final block in remaining) {
    if (closed || overLimit) break;
    final lines = block.text
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    if (lines.isEmpty) continue;
    if (_isBoundary(lines.first)) break;
    if (parts.length >= _maxDescriptionBlocks) {
      overLimit = true;
      break;
    }
    add(lines.join('\n'));
    if (endsClosed(lines.last) || endsClosed(block.text.trim())) {
      closed = true;
    }
  }
  if (overLimit || parts.isEmpty) return null;
  var description = parts.join('\n');
  if (endsClosed(description)) {
    description = description.substring(0, description.length - 1);
  }
  final trimmed = description.trim();
  return trimmed.isEmpty ? null : trimmed;
}

bool _isBoundary(String line) =>
    _metaBoundary.hasMatch(line) || _contentBoundary.hasMatch(line);

String _firstLine(String text) {
  final index = text.indexOf('\n');
  return (index < 0 ? text : text.substring(0, index)).trim();
}

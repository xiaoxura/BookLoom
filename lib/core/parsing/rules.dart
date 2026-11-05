import 'dart:convert';

import 'package:bookloom/core/model/parse_options.dart';

const int maxRuleJsonBytes = 16 * 1024;
const int maxRulePatternLength = 256;
const int maxRuleLineLength = 512;
const int _maxRuleListLength = 16;
const Set<String> _fields = <String>{
  'id',
  'name',
  'chapter',
  'volume',
  'drop',
  'inlineJunk',
};

/// Validation fails before a rule can be compiled or applied.
class RuleValidationException implements Exception {
  const RuleValidationException(this.field, this.message);

  final String field;
  final String message;

  @override
  String toString() => '$field: $message';
}

/// The portable, bounded subset of Web RuleSpec used by TXT parsing.
class RuleSpec {
  factory RuleSpec({
    String? id,
    required String name,
    String? chapter,
    String? volume,
    List<String>? drop,
    List<String>? inlineJunk,
  }) {
    final fields = <String, Object?>{'name': name};
    if (id != null) fields['id'] = id;
    if (chapter != null) fields['chapter'] = chapter;
    if (volume != null) fields['volume'] = volume;
    if (drop != null) fields['drop'] = drop;
    if (inlineJunk != null) fields['inlineJunk'] = inlineJunk;
    return RuleSpec.fromMap(fields);
  }

  RuleSpec._({
    required this.id,
    required this.name,
    required this.chapter,
    required this.volume,
    required this.drop,
    required this.inlineJunk,
  });

  final String? id;
  final String name;
  final String? chapter;
  final String? volume;
  final List<String> drop;
  final List<String> inlineJunk;

  static RuleSpec fromMap(Object? value) {
    if (value is! Map) {
      throw const RuleValidationException(r'$', '规则必须是 JSON 对象');
    }
    for (final key in value.keys) {
      if (key is! String) {
        throw const RuleValidationException(r'$', '字段名必须是字符串');
      }
      if (!_fields.contains(key)) {
        throw RuleValidationException(key, '未知字段');
      }
    }
    final id = _optionalText(value, 'id', 64);
    final name = _requiredText(value, 'name', 80);
    final chapter = _optionalPattern(value, 'chapter');
    final volume = _optionalPattern(value, 'volume');
    final drop = _patternList(value, 'drop');
    final inlineJunk = _patternList(value, 'inlineJunk');
    return RuleSpec._(
      id: id,
      name: name,
      chapter: chapter,
      volume: volume,
      drop: List<String>.unmodifiable(drop),
      inlineJunk: List<String>.unmodifiable(inlineJunk),
    );
  }

  static RuleSpec fromJsonString(String source) {
    if (source.length > maxRuleJsonBytes ||
        utf8.encode(source).length > maxRuleJsonBytes) {
      throw const RuleValidationException(r'$', '规则 JSON 超过 16 KiB');
    }
    Object? decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException {
      throw const RuleValidationException(r'$', 'JSON 语法无效');
    }
    return RuleSpec.fromMap(decoded);
  }

  Map<String, Object?> toMap() {
    final map = <String, Object?>{'name': name};
    if (id != null) map['id'] = id;
    if (chapter != null) map['chapter'] = chapter;
    if (volume != null) map['volume'] = volume;
    if (drop.isNotEmpty) map['drop'] = List<String>.of(drop);
    if (inlineJunk.isNotEmpty) map['inlineJunk'] = List<String>.of(inlineJunk);
    return map;
  }

  String toJsonString() {
    final encoded = jsonEncode(toMap());
    if (utf8.encode(encoded).length > maxRuleJsonBytes) {
      throw const RuleValidationException(r'$', '规则 JSON 超过 16 KiB');
    }
    return encoded;
  }
}

String? validateRuleSpec(Object? value) {
  try {
    RuleSpec.fromMap(value);
    return null;
  } on RuleValidationException catch (error) {
    return error.toString();
  }
}

String _requiredText(Map<dynamic, dynamic> value, String field, int maxLength) {
  final raw = value[field];
  if (raw is! String || raw.trim().isEmpty) {
    throw RuleValidationException(field, '必须是非空字符串');
  }
  final text = raw.trim();
  if (text.length > maxLength) {
    throw RuleValidationException(field, '长度不能超过 $maxLength');
  }
  return text;
}

String? _optionalText(
  Map<dynamic, dynamic> value,
  String field,
  int maxLength,
) {
  if (!value.containsKey(field) || value[field] == null) return null;
  return _requiredText(value, field, maxLength);
}

String? _optionalPattern(Map<dynamic, dynamic> value, String field) {
  if (!value.containsKey(field) || value[field] == null) return null;
  final raw = value[field];
  if (raw is! String) {
    throw RuleValidationException(field, '必须是正则字符串');
  }
  _validatePattern(raw, field);
  return raw;
}

List<String> _patternList(Map<dynamic, dynamic> value, String field) {
  if (!value.containsKey(field) || value[field] == null) {
    return const <String>[];
  }
  final raw = value[field];
  if (raw is! List) {
    throw RuleValidationException(field, '必须是字符串数组');
  }
  if (raw.length > _maxRuleListLength) {
    throw RuleValidationException(field, '最多 $_maxRuleListLength 条');
  }
  final values = <String>[];
  for (var i = 0; i < raw.length; i++) {
    final item = raw[i];
    if (item is! String) {
      throw RuleValidationException('$field[$i]', '必须是正则字符串');
    }
    _validatePattern(item, '$field[$i]');
    values.add(item);
  }
  return values;
}

/// Deliberately conservative: only literal text, character classes, simple
/// groups, bounded repetition and one unbounded atom repeat are accepted.
/// Incompatible JS/Dart features fail at import rather than changing meaning.
void _validatePattern(String source, String field) {
  if (source.isEmpty || source.length > maxRulePatternLength) {
    throw RuleValidationException(field, '正则长度必须在 1–$maxRulePatternLength 之间');
  }
  var inClass = false;
  var unboundedRepeats = 0;
  var quantifiers = 0;
  var lastRepeatEnd = -1;
  String? lastRepeatAtom;
  for (var i = 0; i < source.length; i++) {
    final char = source[i];
    if (char == r'\') {
      if (i + 1 >= source.length) {
        throw RuleValidationException(field, '正则末尾不能只有反斜杠');
      }
      final escaped = source[++i];
      const portableEscapes = r'dDsSwWbBnrtfv\.^$|?*+()[]{}-/';
      if (!portableEscapes.contains(escaped)) {
        throw RuleValidationException(field, '包含未支持的反向引用或跨语言转义');
      }
      continue;
    }
    if (char == '[' && !inClass) {
      inClass = true;
      continue;
    }
    if (char == ']' && inClass) {
      inClass = false;
      continue;
    }
    if (inClass) continue;
    if (char == '(' && i + 1 < source.length && source[i + 1] == '?') {
      if (i + 2 >= source.length || source[i + 2] != ':') {
        throw RuleValidationException(field, '只支持普通分组和 (?:...) 分组');
      }
      i += 2;
      continue;
    }
    if (char == ')' &&
        i + 1 < source.length &&
        (source[i + 1] == '*' ||
            source[i + 1] == '+' ||
            source[i + 1] == '?' ||
            source[i + 1] == '{')) {
      throw RuleValidationException(field, '不支持对分组重复匹配');
    }
    if (char == '*' || char == '+' || char == '?') {
      quantifiers++;
      if (char == '*' || char == '+') unboundedRepeats++;
      if (i == 0 ||
          source[i - 1] == '.' && char != '?' ||
          source[i - 1] == '*' ||
          source[i - 1] == '+' ||
          source[i - 1] == '?') {
        throw RuleValidationException(field, '包含危险或无效量词');
      }
      final atom = _atomBefore(source, i);
      if (lastRepeatAtom == atom && i - atom.length == lastRepeatEnd + 1) {
        throw RuleValidationException(field, '相邻重复匹配可能导致过量回溯');
      }
      lastRepeatAtom = atom;
      lastRepeatEnd = i;
    } else if (char == '{') {
      final match = RegExp(r'^\{([0-9]{1,3})(?:,([0-9]{1,3}))?\}')
          .firstMatch(source.substring(i));
      if (match == null) {
        throw RuleValidationException(field, '只支持有限上界的重复次数');
      }
      final lower = int.parse(match[1]!);
      final upper = int.parse(match[2] ?? match[1]!);
      if (upper > 128 || lower > upper) {
        throw RuleValidationException(field, '重复次数上界不能超过 128');
      }
      quantifiers++;
      final atom = _atomBefore(source, i);
      if (lastRepeatAtom == atom && i - atom.length == lastRepeatEnd + 1) {
        throw RuleValidationException(field, '相邻重复匹配可能导致过量回溯');
      }
      lastRepeatAtom = atom;
      lastRepeatEnd = i + match[0]!.length - 1;
      i += match[0]!.length - 1;
    }
    if (unboundedRepeats > 1 || quantifiers > 12) {
      throw RuleValidationException(field, '重复匹配过多');
    }
  }
  RegExp regex;
  try {
    regex = RegExp(source, caseSensitive: false);
  } on FormatException {
    throw RuleValidationException(field, '正则语法无效');
  }
  for (final probe in <String>['', 'abc', 'a b', '第1章']) {
    final match = regex.firstMatch(probe);
    if (match != null && match.start == match.end) {
      throw RuleValidationException(field, '正则不能产生零宽匹配');
    }
  }
}

String _atomBefore(String source, int quantifierStart) {
  if (quantifierStart == 0) return '';
  final end = quantifierStart - 1;
  if (source[end] == ']') {
    final start = source.lastIndexOf('[', end);
    if (start >= 0) return source.substring(start, quantifierStart);
  }
  if (end > 0 && source[end - 1] == r'\') {
    return source.substring(end - 1, quantifierStart);
  }
  return source[end];
}

const List<String> rulePresetIds = <String>[
  'auto',
  'ixdzs',
  'biquge',
  'numbered',
  'bare-number',
  'english',
];

final Map<String, RuleSpec> _presets = <String, RuleSpec>{
  'auto': RuleSpec(id: 'auto', name: '自动识别'),
  'ixdzs': RuleSpec(
    id: 'ixdzs',
    name: '爱下电子书',
    drop: <String>['爱下电子书', 'ixdzs', '章节内容开始', '内容还在处理中', '请稍后重试'],
    inlineJunk: <String>['内容还在处理中', '请稍后重试', '正在手打中'],
  ),
  'biquge': RuleSpec(
    id: 'biquge',
    name: '笔趣阁系',
    drop: <String>['笔趣阁', '最新章节', '无弹窗', '请记住本站', '手机阅读', '顶点小说', '八一中文'],
    inlineJunk: <String>['请记住本站', '最新章节', '无弹窗'],
  ),
  'numbered': RuleSpec(
    id: 'numbered',
    name: '数字标题',
    chapter: r'\s{0,8}\d{1,4}\s{0,8}[、.．:：]\s{0,8}.{0,40}',
  ),
  'bare-number': RuleSpec(
    id: 'bare-number',
    name: '裸数字标题',
    chapter: r'\s{0,8}\d{1,4}\s{0,8}',
  ),
  'english': RuleSpec(
    id: 'english',
    name: '英文 Chapter / Section',
    chapter: r'(?:chapter|part|volume|section|page)\s{1,8}[0-9ivxlcdm]{1,12}\b.{0,60}',
    volume: r'(?:part|volume)\s{1,8}[0-9ivxlcdm]{1,12}\b.{0,40}',
  ),
};

RuleSpec? getRulePreset(String id) => _presets[id];

/// A compiled rule set for bounded, single-line TXT matching.
class CompiledTxtRules {
  const CompiledTxtRules({
    this.chapter,
    this.volume,
    this.drop = const <RegExp>[],
    this.inlineJunk = const <RegExp>[],
  });

  final RegExp? chapter;
  final RegExp? volume;
  final List<RegExp> drop;
  final List<RegExp> inlineJunk;

  bool get isEmpty =>
      chapter == null && volume == null && drop.isEmpty && inlineJunk.isEmpty;

  bool matchesDrop(String line) =>
      drop.any((pattern) => pattern.hasMatch(line));

  String? stripInlineJunk(String line) {
    for (final pattern in inlineJunk) {
      final match = pattern.firstMatch(line);
      if (match != null &&
          match.start == 0 &&
          match.end > 0 &&
          match.end <= 24) {
        final suffix = line.substring(match.end).trim();
        if (suffix.isNotEmpty) return suffix;
      }
    }
    return null;
  }
}

CompiledTxtRules resolveTxtRules(ParseOptions options) {
  final presetId = options.rulePreset;
  final base = presetId == 'custom' ? null : getRulePreset(presetId);
  if (base == null && presetId != 'custom') {
    throw RuleValidationException('rulePreset', '未知预设：$presetId');
  }
  final custom = options.ruleSpec == null
      ? null
      : RuleSpec.fromMap(options.ruleSpec);
  if (presetId == 'custom' && custom == null) {
    throw const RuleValidationException('ruleSpec', '自定义预设需要规则配置');
  }
  RegExp? anchored(String? source) =>
      source == null ? null : RegExp('^(?:$source)\$', caseSensitive: false);
  final RegExp? chapter = anchored(custom?.chapter ?? base?.chapter);
  final RegExp? volume = anchored(custom?.volume ?? base?.volume);
  final drop = <RegExp>[
    for (final source in <String>[...?base?.drop, ...?custom?.drop])
      RegExp(source, caseSensitive: false),
  ];
  final inlineJunk = <RegExp>[
    for (final source in <String>[...?base?.inlineJunk, ...?custom?.inlineJunk])
      RegExp(source, caseSensitive: false),
  ];
  return CompiledTxtRules(
    chapter: chapter,
    volume: volume,
    drop: List<RegExp>.unmodifiable(drop),
    inlineJunk: List<RegExp>.unmodifiable(inlineJunk),
  );
}

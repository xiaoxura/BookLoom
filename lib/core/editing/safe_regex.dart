import 'package:bookloom/core/errors/app_failure.dart';

/// A deliberately small regular-expression subset for scanning untrusted books.
///
/// Dart's regexp engine can backtrack without yielding to a timer. Callers must
/// still run the scan in a cancellable [BackgroundJobs] isolate; this validator
/// rejects common ambiguous repetitions before that isolate is started.
abstract final class SafeRegex {
  static SafePattern compile(String source, {required bool caseSensitive}) {
    final captureCount = _validate(source);
    try {
      return SafePattern(
        RegExp(source, caseSensitive: caseSensitive, unicode: true),
        captureCount,
      );
    } on FormatException {
      throw const ValidationFailure('正则表达式格式无效，请检查查找内容。');
    }
  }

  static int _validate(String source) {
    final frames = <_Frame>[_Frame()];
    var captures = 0;
    for (var i = 0; i < source.length; i++) {
      final char = source[i];
      final frame = frames.last;
      if (char == '\\') {
        if (++i >= source.length) _invalid('正则表达式不能以反斜杠结尾。');
        final escaped = source[i];
        if (RegExp(r'[1-9kKpPcCxXuU0]').hasMatch(escaped)) {
          _invalid('不支持反向引用、Unicode 属性或扩展转义，请使用普通字符类。');
        }
        if (!r'dDsSwWbBfnrtv\.^$|?*+(){}[]/-'.contains(escaped)) {
          _invalid('不支持的正则转义：\\$escaped。');
        }
        frame.atom = _Atom.character;
        frame.hasContent = true;
        continue;
      }
      if (char == '[') {
        i = _classEnd(source, i);
        frame.atom = _Atom.character;
        frame.hasContent = true;
        continue;
      }
      if (char == '(') {
        var capturing = true;
        if (i + 1 < source.length && source[i + 1] == '?') {
          if (i + 2 < source.length && source[i + 2] == ':') {
            capturing = false;
            i += 2;
          } else {
            _invalid('仅支持普通捕获组和 (?:...)；不支持环视或命名组。');
          }
        }
        if (capturing) captures++;
        frames.add(_Frame());
        continue;
      }
      if (char == ')') {
        if (frames.length == 1) _invalid('正则表达式的括号不匹配。');
        final closed = frames.removeLast();
        if (!closed.hasContent) {
          _invalid('不支持空分组。');
        }
        final parent = frames.last;
        if (closed.hasVariable && parent.variableInBranch) {
          _invalid('同一正则分支不能包含多个可变量词。');
        }
        if (closed.hasVariable) {
          parent.variableInBranch = true;
          parent.hasVariable = true;
        }
        parent.atom = _Atom.group;
        parent.hasContent = true;
        parent.groupHasVariable = closed.hasVariable;
        parent.groupHasAlternation = closed.hasAlternation;
        continue;
      }
      if (char == '|') {
        if (!frame.hasContent) _invalid('不支持空的正则分支。');
        frame.hasAlternation = true;
        frame.atom = _Atom.none;
        frame.hasContent = false;
        frame.variableInBranch = false;
        continue;
      }
      if (char == '*' || char == '+' || char == '?' || char == '{') {
        if (char == '{' && !_looksLikeQuantifier(source, i)) {
          _invalid('花括号仅支持 {n}、{n,} 或 {n,m} 量词。');
        }
        if (frame.atom == _Atom.none) _invalid('量词前缺少可重复字符。');
        final variable = char != '{' || _isVariableRange(source, i);
        if (frame.atom == _Atom.group &&
            (frame.groupHasVariable || frame.groupHasAlternation)) {
          _invalid('不支持含量词或分支的分组再次重复。');
        }
        if (variable && frame.variableInBranch) {
          _invalid('同一正则分支不能包含多个可变量词。');
        }
        if (variable && frame.atom == _Atom.wildcard) {
          _invalid('不支持重复通配符，请缩小匹配范围。');
        }
        if (variable) {
          frame.variableInBranch = true;
          frame.hasVariable = true;
        }
        if (char == '{') i = _quantifierEnd(source, i);
        frame.atom = _Atom.none;
        continue;
      }
      if (char == '}') _invalid('正则表达式有多余的右花括号。');
      frame.atom = char == '.' ? _Atom.wildcard : _Atom.character;
      frame.hasContent = true;
    }
    if (frames.length != 1) _invalid('正则表达式的括号不匹配。');
    if (!frames.single.hasContent && source.isNotEmpty) {
      _invalid('正则表达式不能以量词或空分支结尾。');
    }
    return captures;
  }

  static int _classEnd(String source, int start) {
    var i = start + 1;
    if (i < source.length && source[i] == '^') i++;
    if (i < source.length && source[i] == ']') i++;
    for (; i < source.length; i++) {
      if (source[i] == '\\') {
        if (++i >= source.length) break;
        if (RegExp(r'[1-9kKpPcCxXuU0]').hasMatch(source[i])) {
          _invalid('字符类中有不支持的转义。');
        }
      } else if (source[i] == ']') {
        return i;
      }
    }
    _invalid('正则表达式的字符类没有结束。');
  }

  static bool _looksLikeQuantifier(String source, int start) =>
      RegExp(r'^\{\d{1,4}(?:,\d{0,4})?\}').hasMatch(source.substring(start));

  static bool _isVariableRange(String source, int start) {
    final match = RegExp(r'^\{(\d{1,4})(?:,(\d{0,4}))?\}')
        .firstMatch(source.substring(start))!;
    final lower = int.parse(match[1]!);
    final upperRaw = match[2];
    if (lower > 1000) _invalid('正则量词上限不能超过 1000。');
    if (upperRaw == null) return false;
    if (upperRaw.isEmpty) return true;
    final upper = int.parse(upperRaw);
    if (upper < lower || upper > 1000 || upper - lower > 100) {
      _invalid('正则量词范围过大或顺序无效。');
    }
    return upper != lower;
  }

  static int _quantifierEnd(String source, int start) =>
      source.indexOf('}', start);

  static Never _invalid(String message) => throw ValidationFailure(message);
}

class SafePattern {
  const SafePattern(this.regex, this.captureCount);
  final RegExp regex;
  final int captureCount;
}

enum _Atom { none, character, wildcard, group }

class _Frame {
  _Atom atom = _Atom.none;
  bool hasContent = false;
  bool variableInBranch = false;
  bool hasVariable = false;
  bool hasAlternation = false;
  bool groupHasVariable = false;
  bool groupHasAlternation = false;
}

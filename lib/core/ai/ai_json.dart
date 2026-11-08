import 'dart:convert';

Object? decodeStrictAiJson(String source) {
  if (source.length > 524288) _invalid();
  try {
    final stack = <_JsonFrame>[];
    var cursor = 0;
    while (cursor < source.length) {
      final code = source.codeUnitAt(cursor);
      if (code == 0x22) {
        final start = cursor++;
        var closed = false;
        while (cursor < source.length) {
          final current = source.codeUnitAt(cursor++);
          if (current == 0x5c) {
            cursor++;
          } else if (current == 0x22) {
            closed = true;
            break;
          }
        }
        if (!closed) _invalid();
        if (stack.isNotEmpty && stack.last.expectsKey) {
          final frame = stack.last;
          final key = jsonDecode(source.substring(start, cursor)) as String;
          if (!frame.keys.add(key)) _invalid();
          frame.expectsKey = false;
        }
        continue;
      }
      if (code == 0x7b || code == 0x5b) {
        if (stack.length >= 32) _invalid();
        stack.add(_JsonFrame(code == 0x7b));
      } else if (code == 0x7d || code == 0x5d) {
        if (stack.isEmpty || stack.last.isObject != (code == 0x7d)) {
          _invalid();
        }
        stack.removeLast();
      } else if (code == 0x2c && stack.isNotEmpty && stack.last.isObject) {
        stack.last.expectsKey = true;
      }
      cursor++;
    }
    if (stack.isNotEmpty) _invalid();
    return jsonDecode(source);
  } on FormatException {
    _invalid();
  }
}

class _JsonFrame {
  _JsonFrame(this.isObject) : expectsKey = isObject;

  final bool isObject;
  bool expectsKey;
  final Set<String> keys = <String>{};
}

Never _invalid() => throw const FormatException('AI JSON 格式无效或存在歧义。');

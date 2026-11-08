import 'package:bookloom/core/errors/app_failure.dart';

abstract final class RuleHeadingMapping {
  static const maxNumber = 999999999;
  static const _digits = '零一二三四五六七八九';
  static const _aliases = <String, String>{
    '〇': '零',
    '两': '二',
    '兩': '二',
    '壹': '一',
    '贰': '二',
    '貳': '二',
    '叁': '三',
    '參': '三',
    '肆': '四',
    '伍': '五',
    '陆': '六',
    '陸': '六',
    '柒': '七',
    '捌': '八',
    '玖': '九',
    '拾': '十',
    '佰': '百',
    '仟': '千',
    '萬': '万',
    '億': '亿',
  };
  static final _arabic = RegExp(r'^[0-9]{1,9}$');
  static final _chinese = RegExp(r'^[零一二三四五六七八九十百千万亿]+$');
  static final _digitSequence = RegExp(r'^[零一二三四五六七八九]+$');
  static final _prefix = RegExp(
    r'^(?:正文[\s·:：\-—]*)?第\s*([0-9０-９零〇一二三四五六七八九十百千万萬亿億两兩壹贰貳叁參肆伍陆陸柒捌玖拾佰仟]+)\s*([章回节節话話集部卷])',
  );
  static final _rangePrefix = RegExp(
    r'^(?:正文[\s·:：\-—]*)?第\s*[0-9０-９零〇一二三四五六七八九十百千万萬亿億两兩壹贰貳叁參肆伍陆陸柒捌玖拾佰仟]+\s*[~～\-—]\s*[0-9０-９零〇一二三四五六七八九十百千万萬亿億两兩壹贰貳叁參肆伍陆陸柒捌玖拾佰仟]+\s*[章回节節话話集部卷]',
  );

  static int? parseNumber(String raw) {
    final source = raw.trim();
    if (source.isEmpty || source.length > 32) return null;
    final normalized = StringBuffer();
    for (final code in source.runes) {
      if (code >= 0xff10 && code <= 0xff19) {
        normalized.writeCharCode(code - 0xff10 + 0x30);
      } else {
        final character = String.fromCharCode(code);
        normalized.write(_aliases[character] ?? character);
      }
    }
    final text = normalized.toString();
    if (_arabic.hasMatch(text)) {
      final value = int.parse(text);
      return value > 0 ? value : null;
    }
    if (!_chinese.hasMatch(text)) return null;
    if (_digitSequence.hasMatch(text)) {
      if (text.length > 9) return null;
      final value = int.parse(
        text.split('').map((character) => _digits.indexOf(character)).join(),
      );
      return value > 0 ? value : null;
    }
    var total = 0;
    var section = 0;
    var number = 0;
    for (final character in text.split('')) {
      final digit = _digits.indexOf(character);
      if (digit >= 0) {
        number = number * 10 + digit;
      } else if (character == '亿') {
        total = (total + section + number) * 100000000;
        section = 0;
        number = 0;
      } else if (character == '万') {
        total += (section + number) * 10000;
        section = 0;
        number = 0;
      } else {
        final unit = switch (character) {
          '十' => 10,
          '百' => 100,
          '千' => 1000,
          _ => 0,
        };
        section += (number == 0 ? 1 : number) * unit;
        number = 0;
      }
      if (total + section + number > maxNumber) return null;
    }
    final value = total + section + number;
    if (value <= 0 || value > maxNumber) return null;
    final canonicalSource = text.replaceFirst(RegExp(r'^一十'), '十');
    return canonicalSource == _canonical(value) ? value : null;
  }

  static String composeTitle({
    required String title,
    required int number,
    required int headingLevel,
  }) {
    if (title.isEmpty ||
        title != title.trim() ||
        title.contains('\n') ||
        title.contains('\r') ||
        _rangePrefix.hasMatch(title) ||
        number <= 0 ||
        number > maxNumber ||
        (headingLevel != 1 && headingLevel != 2)) {
      _invalid();
    }
    final prefix = _prefix.firstMatch(title);
    final String result;
    if (prefix != null) {
      if (parseNumber(prefix[1]!) != number ||
          (prefix[2] == '卷' ? 1 : 2) != headingLevel) {
        _invalid();
      }
      result = title;
    } else {
      result = '第$number${headingLevel == 1 ? '卷' : '章'} $title';
    }
    if (result.length > 256) _invalid();
    return result;
  }

  static String _canonical(int value) {
    final groups = <int>[];
    for (var remaining = value; remaining > 0; remaining ~/= 10000) {
      groups.add(remaining % 10000);
    }
    final output = StringBuffer();
    var skipped = false;
    for (var index = groups.length - 1; index >= 0; index--) {
      final group = groups[index];
      if (group == 0) {
        skipped = output.isNotEmpty;
        continue;
      }
      if (output.isNotEmpty && (skipped || group < 1000)) output.write('零');
      output.write(_smallChinese(group));
      output.write(const ['', '万', '亿'][index]);
      skipped = false;
    }
    return output.toString().replaceFirst(RegExp(r'^一十'), '十');
  }

  static String _smallChinese(int value) {
    final output = StringBuffer();
    var remaining = value;
    var skipped = false;
    for (final (unit, suffix) in const [
      (1000, '千'),
      (100, '百'),
      (10, '十'),
      (1, ''),
    ]) {
      final digit = remaining ~/ unit;
      remaining %= unit;
      if (digit == 0) {
        if (output.isNotEmpty && remaining > 0) skipped = true;
      } else {
        if (skipped) output.write('零');
        output.write('${_digits[digit]}$suffix');
        skipped = false;
      }
    }
    return output.toString();
  }

  static Never _invalid() =>
      throw const ValidationFailure('章号映射与标题或卷章层级不一致，请调整捕获组后重新试跑。');
}

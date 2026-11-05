import 'dart:convert';
import 'dart:typed_data';

import 'package:bookloom/core/model/parse_options.dart';
import 'package:bookloom/core/model/parse_result.dart';
import 'package:bookloom/core/parsing/encoding_tables.g.dart';
import 'package:bookloom/core/parsing/txt_parser.dart';

/// The selected decoder's output and the confidence of automatic detection.
class TxtDecodeResult {
  const TxtDecodeResult({
    required this.text,
    required this.encoding,
    required this.confidence,
  });

  final String text;
  final String encoding;
  final double confidence;
}

/// Decode bytes from the immutable source, then run the pure text chapterizer.
/// A manual encoding change must call this entry again with the original bytes.
ParseResult parseTxtBytes(
  Uint8List bytes, {
  required String bookId,
  required String filename,
  ParseOptions options = const ParseOptions(),
}) {
  final decoded = decodeTxtBytes(bytes, preferredEncoding: options.encoding);
  final parsed = parseTxtText(
    decoded.text,
    bookId: bookId,
    filename: filename,
    options: options,
    actualEncoding: decoded.encoding,
    encodingConfidence: decoded.confidence,
  );
  if (decoded.confidence >= 0.6) return parsed;
  return ParseResult(
    format: parsed.format,
    actualEncoding: parsed.actualEncoding,
    encodingConfidence: parsed.encodingConfidence,
    suggestedMeta: parsed.suggestedMeta,
    chapters: parsed.chapters,
    coverAssetId: parsed.coverAssetId,
    warnings: <ParseWarning>[
      ...parsed.warnings,
      const ParseWarning(
        code: 'low_encoding_confidence',
        message: '编码识别置信度较低，请预览原文并手动选择编码。',
      ),
    ],
    sourceLocations: parsed.sourceLocations,
  );
}

/// Strict decoder. BOM takes precedence; without BOM, UTF-8 is checked before
/// comparing GB18030 and Big5 candidates. Invalid manual input throws.
TxtDecodeResult decodeTxtBytes(
  Uint8List bytes, {
  String preferredEncoding = 'auto',
}) {
  final preferred = _canonicalEncoding(preferredEncoding);
  if (bytes.isEmpty) {
    return const TxtDecodeResult(text: '', encoding: 'utf-8', confidence: 1);
  }
  if (_startsWith(bytes, const <int>[0xef, 0xbb, 0xbf])) {
    return TxtDecodeResult(
      text: utf8.decode(bytes.sublist(3)),
      encoding: 'utf-8',
      confidence: 1,
    );
  }
  if (_startsWith(bytes, const <int>[0xff, 0xfe])) {
    return TxtDecodeResult(
      text: _decodeUtf16(bytes, littleEndian: true, offset: 2),
      encoding: 'utf-16le',
      confidence: 1,
    );
  }
  if (_startsWith(bytes, const <int>[0xfe, 0xff])) {
    return TxtDecodeResult(
      text: _decodeUtf16(bytes, littleEndian: false, offset: 2),
      encoding: 'utf-16be',
      confidence: 1,
    );
  }

  if (preferred != 'auto') {
    return TxtDecodeResult(
      text: _decodeWith(bytes, preferred),
      encoding: preferred,
      confidence: 1,
    );
  }

  final utf16Guess = _sniffUtf16(bytes);
  if (utf16Guess != null) {
    try {
      final text = _decodeWith(bytes, utf16Guess);
      if (text.isNotEmpty) {
        return TxtDecodeResult(
          text: text,
          encoding: utf16Guess,
          confidence: 0.9,
        );
      }
    } on FormatException {
      // Continue to strict UTF-8 and legacy candidates.
    }
  }
  try {
    return TxtDecodeResult(
      text: utf8.decode(bytes),
      encoding: 'utf-8',
      confidence: 1,
    );
  } on FormatException {
    // An invalid UTF-8 sequence must never be silently replaced.
  }

  final candidates = <({String name, String text, int score})>[];
  for (final name in const <String>['gb18030', 'big5']) {
    try {
      final text = _decodeWith(bytes, name);
      candidates.add((name: name, text: text, score: _quality(text)));
    } on FormatException {
      // The candidate is invalid; a valid alternative may still exist.
    }
  }
  if (candidates.isEmpty) {
    throw const FormatException('Input is invalid in UTF-8, GB18030 and Big5.');
  }
  candidates.sort((a, b) => b.score.compareTo(a.score));
  final best = candidates.first;
  final second = candidates.length > 1 ? candidates[1].score : 0;
  final delta = (best.score - second).clamp(0, 1000000);
  final denominator = best.score.abs() + second.abs() + 1;
  final confidence = candidates.length == 1
      ? 0.9
      : (0.5 + 0.45 * delta / denominator).clamp(0.5, 0.95);
  return TxtDecodeResult(
    text: best.text,
    encoding: best.name,
    confidence: confidence,
  );
}

String _canonicalEncoding(String value) => switch (value.trim().toLowerCase()) {
  'auto' => 'auto',
  'utf-8' || 'utf8' => 'utf-8',
  'gb18030' || 'gbk' || 'gb2312' => 'gb18030',
  'big5' || 'big-5' => 'big5',
  'utf-16le' || 'utf16le' => 'utf-16le',
  'utf-16be' || 'utf16be' => 'utf-16be',
  _ => throw ArgumentError.value(
    value,
    'preferredEncoding',
    'Unsupported TXT encoding',
  ),
};

bool _startsWith(Uint8List bytes, List<int> prefix) {
  if (bytes.length < prefix.length) return false;
  for (var i = 0; i < prefix.length; i++) {
    if (bytes[i] != prefix[i]) return false;
  }
  return true;
}

String _decodeWith(Uint8List bytes, String encoding) => switch (encoding) {
  'utf-8' => utf8.decode(bytes),
  'utf-16le' => _decodeUtf16(bytes, littleEndian: true),
  'utf-16be' => _decodeUtf16(bytes, littleEndian: false),
  'gb18030' => _decodeGb18030(bytes),
  'big5' => _decodeBig5(bytes),
  _ => throw ArgumentError.value(encoding, 'encoding'),
};

String? _sniffUtf16(Uint8List bytes) {
  if (bytes.length < 16 || bytes.length.isOdd) return null;
  final length = bytes.length < 8192 ? bytes.length : 8192;
  var evenZero = 0;
  var oddZero = 0;
  for (var i = 0; i < length; i++) {
    if (bytes[i] == 0) {
      if (i.isEven) {
        evenZero++;
      } else {
        oddZero++;
      }
    }
  }
  final pairs = length ~/ 2;
  if (oddZero > pairs * 0.35 && evenZero < pairs * 0.05) return 'utf-16le';
  if (evenZero > pairs * 0.35 && oddZero < pairs * 0.05) return 'utf-16be';
  return null;
}

String _decodeUtf16(
  Uint8List bytes, {
  required bool littleEndian,
  int offset = 0,
}) {
  if ((bytes.length - offset).isOdd) {
    throw FormatException(
      'Incomplete UTF-16 code unit at byte ${bytes.length - 1}.',
    );
  }
  final result = StringBuffer();
  int unitAt(int i) => littleEndian
      ? bytes[i] | (bytes[i + 1] << 8)
      : (bytes[i] << 8) | bytes[i + 1];
  for (var i = offset; i < bytes.length; i += 2) {
    final unit = unitAt(i);
    if (unit >= 0xd800 && unit <= 0xdbff) {
      if (i + 3 >= bytes.length) {
        throw FormatException('Incomplete UTF-16 surrogate at byte $i.');
      }
      final low = unitAt(i + 2);
      if (low < 0xdc00 || low > 0xdfff) {
        throw FormatException('Invalid UTF-16 surrogate at byte $i.');
      }
      result.writeCharCode(0x10000 + ((unit - 0xd800) << 10) + low - 0xdc00);
      i += 2;
    } else if (unit >= 0xdc00 && unit <= 0xdfff) {
      throw FormatException('Unexpected UTF-16 low surrogate at byte $i.');
    } else {
      result.writeCharCode(unit);
    }
  }
  return result.toString();
}

String _decodeGb18030(Uint8List bytes) {
  final result = StringBuffer();
  for (var i = 0; i < bytes.length;) {
    final first = bytes[i];
    if (first < 0x80) {
      result.writeCharCode(first);
      i++;
      continue;
    }
    if (first == 0x80) {
      result.writeCharCode(0x20ac);
      i++;
      continue;
    }
    if (first < 0x81 || first > 0xfe || i + 1 >= bytes.length) {
      throw FormatException('Invalid GB18030 sequence at byte $i.');
    }
    final second = bytes[i + 1];
    if (second >= 0x30 && second <= 0x39) {
      if (i + 3 >= bytes.length) {
        throw FormatException(
          'Incomplete GB18030 four-byte sequence at byte $i.',
        );
      }
      final third = bytes[i + 2];
      final fourth = bytes[i + 3];
      if (third < 0x81 || third > 0xfe || fourth < 0x30 || fourth > 0x39) {
        throw FormatException('Invalid GB18030 four-byte sequence at byte $i.');
      }
      final pointer =
          ((first - 0x81) * 10 + second - 0x30) * 1260 +
          (third - 0x81) * 10 +
          fourth -
          0x30;
      final codePoint = _gb18030RangeCodePoint(pointer);
      if (codePoint == null) {
        throw FormatException('Unassigned GB18030 pointer at byte $i.');
      }
      result.writeCharCode(codePoint);
      i += 4;
      continue;
    }
    if (!((second >= 0x40 && second <= 0x7e) ||
        (second >= 0x80 && second <= 0xfe))) {
      throw FormatException('Invalid GB18030 trailing byte at byte ${i + 1}.');
    }
    final pointer =
        (first - 0x81) * 190 + second - (second < 0x7f ? 0x40 : 0x41);
    final codePoint = gb18030TwoByteIndex[pointer];
    if (codePoint < 0) {
      throw FormatException('Unassigned GB18030 pointer at byte $i.');
    }
    result.writeCharCode(codePoint);
    i += 2;
  }
  return result.toString();
}

int? _gb18030RangeCodePoint(int pointer) {
  if ((pointer > 39419 && pointer < 189000) || pointer > 1237575) return null;
  if (pointer == 7457) return 0xe7c7;
  var low = 0;
  var high = gb18030RangePointers.length - 1;
  while (low < high) {
    final mid = (low + high + 1) ~/ 2;
    if (gb18030RangePointers[mid] <= pointer) {
      low = mid;
    } else {
      high = mid - 1;
    }
  }
  final point =
      gb18030RangeCodePoints[low] + pointer - gb18030RangePointers[low];
  return point <= 0x10ffff ? point : null;
}

String _decodeBig5(Uint8List bytes) {
  final result = StringBuffer();
  for (var i = 0; i < bytes.length;) {
    final first = bytes[i];
    if (first < 0x80) {
      result.writeCharCode(first);
      i++;
      continue;
    }
    if (first < 0x81 || first > 0xfe || i + 1 >= bytes.length) {
      throw FormatException('Invalid Big5 sequence at byte $i.');
    }
    final second = bytes[i + 1];
    if (!((second >= 0x40 && second <= 0x7e) ||
        (second >= 0xa1 && second <= 0xfe))) {
      throw FormatException('Invalid Big5 trailing byte at byte ${i + 1}.');
    }
    final pointer =
        (first - 0x81) * 157 + second - (second < 0x7f ? 0x40 : 0x62);
    switch (pointer) {
      case 1133:
        result.write('\u00ca\u0304');
      case 1135:
        result.write('\u00ca\u030c');
      case 1164:
        result.write('\u00ea\u0304');
      case 1166:
        result.write('\u00ea\u030c');
      default:
        final codePoint = big5Index[pointer];
        if (codePoint < 0) {
          throw FormatException('Unassigned Big5 pointer at byte $i.');
        }
        result.writeCharCode(codePoint);
    }
    i += 2;
  }
  return result.toString();
}

final Set<int> _commonChinese = '的一是了在人有我他这這们們中来來上大为為和国國地到以说說时時要就出会會可也对對生能而子那得于着著下自之年过過发發后後作里裡用道行所然家种種事成方多经經去法学學如都同现現当當没沒动動面起看定天分还還进進好小部其些主样樣理心她本前开開但因只从從想实實日军者意无無力它与與长長把机機十民第公此已工使情明性知全三又关關点點正业業外将將两兩高间間由问問很最重并物手应應战戰向头頭文体體政美相见見被利二等产產或新己制身果加西月话話合回特代内內信表化老给給世位次度门門任常先海通教儿兒原东東声聲提立及比员員解水名真论論处處走义義各入几口认認条條平系气氣题題活更别別打女变變四神总總何电電数安少报報才结結反受目太量再感建务務做接必场場件计計管期市直德资資命山金指克许許统統区區保至队隊形社便空决決治展马馬科司五基眼书書非则則听聽白却界达達光放强強即像难難且权權思王象完设設式色路記南品住告类類求据據程北边邊死张張该該交规規万萬取拉格望觉覺术術领領共确確传傳师師观觀清今切院让讓识識候带帶导導争运運笑飞飛风風步改收根干造言联聯持组組每济濟车車亲親极極林服快办辦议議往元英士证證近失转轉夫令准布始怎呢存未远遠叫台单單影具'
    .runes
    .toSet();
final Set<int> _distinctiveChinese =
    '风灯風燈这這们們说說学學书書车車爱愛国國观觀东東开開关關对對头頭还還间間后後长長发發见見听聽读讀写寫门門鱼魚岛島'.runes.toSet();

int _quality(String text) {
  final sample = text.length > 30000 ? text.substring(0, 30000) : text;
  var score = 0;
  for (final rune in sample.runes) {
    if (rune == 0xfffd) {
      score -= 12;
    } else if (rune >= 0xe000 && rune <= 0xf8ff) {
      score -= 8;
    } else if (rune < 0x20 && rune != 0x09 && rune != 0x0a && rune != 0x0d) {
      score -= 10;
    } else if ((rune >= 0x3400 && rune <= 0x9fff) ||
        (rune >= 0x20000 && rune <= 0x2fa1f)) {
      score += 1;
      if (_commonChinese.contains(rune)) score += 2;
      if (_distinctiveChinese.contains(rune)) score += 3;
    }
  }
  if (RegExp(r'第\s*[一二三四五六七八九十百千万\d]+\s*[章节回卷部]').hasMatch(sample)) {
    score += 12;
  }
  return score;
}

import 'dart:convert';
import 'dart:typed_data';

import 'package:bookloom/core/model/parse_options.dart';
import 'package:bookloom/core/parsing/txt_encoding.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List withBom(List<int> bom, List<int> bytes) =>
    Uint8List.fromList(<int>[...bom, ...bytes]);

Uint8List utf16Bytes(String text, {required bool littleEndian}) {
  final output = <int>[];
  for (final unit in text.codeUnits) {
    if (littleEndian) {
      output.addAll(<int>[unit & 0xff, unit >> 8]);
    } else {
      output.addAll(<int>[unit >> 8, unit & 0xff]);
    }
  }
  return Uint8List.fromList(output);
}

void main() {
  test('UTF-8 BOM wins over a manual encoding choice', () {
    final result = decodeTxtBytes(
      withBom(<int>[0xef, 0xbb, 0xbf], utf8.encode('第一章 灯火')),
      preferredEncoding: 'big5',
    );
    expect(result.text, '第一章 灯火');
    expect(result.encoding, 'utf-8');
    expect(result.confidence, 1);
  });

  test('strict UTF-8 accepts ASCII and rejects malformed sequences', () {
    final valid = decodeTxtBytes(Uint8List.fromList(utf8.encode('hello')));
    expect(valid.encoding, 'utf-8');
    expect(valid.text, 'hello');
    expect(
      () => decodeTxtBytes(Uint8List.fromList(<int>[0xff])),
      throwsFormatException,
    );
    expect(
      () => decodeTxtBytes(
        Uint8List.fromList(<int>[0xc0, 0xaf]),
        preferredEncoding: 'utf-8',
      ),
      throwsFormatException,
    );
  });

  test('GB18030 decodes two and four byte characters, including non-BMP', () {
    final bytes = Uint8List.fromList(<int>[
      ...ascii.encode('A'),
      0xb7, 0xe7, // 风
      0x95, 0x32, 0x82, 0x36, // U+20000
    ]);
    final result = decodeTxtBytes(bytes, preferredEncoding: 'gb18030');
    expect(result.text, 'A风𠀀');
    expect(result.encoding, 'gb18030');
    expect(result.confidence, 1);
  });

  test('GB18030 rejects the reserved four-byte pointer hole', () {
    expect(
      () => decodeTxtBytes(
        Uint8List.fromList(<int>[0x84, 0x31, 0xa5, 0x30]),
        preferredEncoding: 'gb18030',
      ),
      throwsFormatException,
    );
  });

  test('Big5 decodes traditional text and special two-code-point mappings', () {
    final traditional = decodeTxtBytes(
      Uint8List.fromList(<int>[0xad, 0xb7, 0xbf, 0x4f]),
      preferredEncoding: 'big5',
    );
    expect(traditional.text, '風燈');
    final special = decodeTxtBytes(
      Uint8List.fromList(<int>[0x88, 0x62]),
      preferredEncoding: 'big5',
    );
    expect(special.text, '\u00ca\u0304');
  });

  test(
    'UTF-16 BOMs and manual little/big endian choices preserve surrogate pairs',
    () {
      for (final little in <bool>[true, false]) {
        final bytes = utf16Bytes('海𠀀', littleEndian: little);
        final encoding = little ? 'utf-16le' : 'utf-16be';
        expect(
          decodeTxtBytes(
            withBom(little ? <int>[0xff, 0xfe] : <int>[0xfe, 0xff], bytes),
          ).text,
          '海𠀀',
        );
        expect(decodeTxtBytes(bytes, preferredEncoding: encoding).text, '海𠀀');
      }
      expect(
        () => decodeTxtBytes(
          Uint8List.fromList(<int>[0x00, 0xd8]),
          preferredEncoding: 'utf-16le',
        ),
        throwsFormatException,
      );
    },
  );

  test('auto detects ASCII-heavy UTF-16 without a BOM', () {
    final little = decodeTxtBytes(
      utf16Bytes('Chapter 1\nA quiet harbor.', littleEndian: true),
    );
    final big = decodeTxtBytes(
      utf16Bytes('Chapter 1\nA quiet harbor.', littleEndian: false),
    );
    expect(little.encoding, 'utf-16le');
    expect(big.encoding, 'utf-16be');
    expect(little.text, 'Chapter 1\nA quiet harbor.');
    expect(big.text, little.text);
  });

  test(
    'auto detection reports actual legacy encoding and non-perfect confidence',
    () {
      final gb = decodeTxtBytes(
        Uint8List.fromList(<int>[0xb7, 0xe7, 0x20, 0xb5, 0xc6]),
      );
      expect(gb.text, '风 灯');
      expect(gb.encoding, 'gb18030');
      expect(gb.confidence, inInclusiveRange(0.0, 1.0));
      expect(gb.confidence, lessThan(1));

      final big5 = decodeTxtBytes(
        Uint8List.fromList(<int>[0xad, 0xb7, 0x20, 0xbf, 0x4f]),
      );
      expect(big5.text, '風 燈');
      expect(big5.encoding, 'big5');
    },
  );

  test('manual re-selection re-decodes original bytes', () {
    final bytes = Uint8List.fromList(<int>[0xad, 0xb7, 0xbf, 0x4f]);
    final selected = decodeTxtBytes(bytes, preferredEncoding: 'big5');
    expect(selected.text, '風燈');
    expect(
      decodeTxtBytes(bytes, preferredEncoding: 'gb18030').text,
      isNot(selected.text),
    );
  });

  test('parse bytes carries encoding and confidence into ParseResult', () {
    final result = parseTxtBytes(
      Uint8List.fromList(utf8.encode('第一章 早晨\n窗外有光。')),
      bookId: 'test-book',
      filename: '早晨.txt',
      options: const ParseOptions(),
    );
    expect(result.actualEncoding, 'utf-8');
    expect(result.encodingConfidence, 1);
    expect(result.chapters.single.title, '第一章 早晨');
  });
}

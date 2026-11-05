import 'dart:io';

import 'package:bookloom/core/conversion/opencc_converter.dart';
import 'package:bookloom/core/model/parse_options.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, String> _bundledDictionaries() => <String, String>{
  for (final String file in OpenCcConverter.requiredDictionaryFiles)
    file: File('${OpenCcConverter.assetPrefix}$file').readAsStringSync(),
};

void main() {
  late OpenCcConverter converter;

  setUpAll(() {
    converter = OpenCcConverter.loadData(_bundledDictionaries());
  });

  test('Taiwan standard uses segmentation and regional phrase chain', () {
    expect(
      converter.convertText('鼠标里面的硅二极管坏了，导致光标分辨率降低。', ConvertMode.taiwan),
      '滑鼠裡面的矽二極體壞了，導致游標解析度降低。',
    );
  });

  test('traditional to simplified honors phrase before character mapping', () {
    expect(converter.convertText('江流宛轉遶芳甸', ConvertMode.simplified), '江流宛转绕芳甸');
    expect(converter.convertText('一目瞭然', ConvertMode.simplified), '一目了然');
  });

  test('no conversion preserves every rune and punctuation', () {
    const String input = '😀 𠮷、ABC\n繁简';
    expect(converter.convertText(input, ConvertMode.none), input);
  });

  test(
    'complete ideographic descriptions protect their component characters',
    () {
      expect(converter.convertText('⿰钅里钅', ConvertMode.taiwan), '⿰钅里釒');
    },
  );

  test('all required dictionaries are bundled and malformed input fails', () {
    expect(OpenCcConverter.requiredDictionaryFiles.length, 10);
    for (final String file in OpenCcConverter.requiredDictionaryFiles) {
      expect(File('${OpenCcConverter.assetPrefix}$file').existsSync(), isTrue);
    }
    final Map<String, String> incomplete = _bundledDictionaries()
      ..remove('TWPhrases.txt');
    expect(() => OpenCcConverter.loadData(incomplete), throwsFormatException);
  });
}

import 'dart:convert';

import 'package:bookloom/core/ai/ai_json.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'rejects duplicate keys including escaped aliases and nested objects',
    () {
      for (final text in <String>[
        '{"schema_version":2,"schema_version":1,"proposals":[]}',
        r'{"id":"first","\u0069d":"second"}',
        '{"items":[{"action":"delete_text","action":"run_script"}]}',
      ]) {
        expect(() => decodeStrictAiJson(text), throwsFormatException);
      }
    },
  );

  test(
    'keeps JSON-looking text, escaping and keys in separate objects valid',
    () {
      final object = <String, Object>{
        'items': [
          {'id': 'one'},
          {'id': 'two'},
        ],
        'text': '{"schema_version":2,"schema_version":1}\\"😀',
        'nested': <String, Object>{'items': <Object>[]},
      };
      expect(decodeStrictAiJson(jsonEncode(object)), object);
      expect(decodeStrictAiJson(r'{"\u0069d":"valid"}'), {'id': 'valid'});
    },
  );

  test('rejects deep or oversized input before creating an unbounded tree', () {
    expect(
      () => decodeStrictAiJson('${'[' * 33}0${']' * 33}'),
      throwsFormatException,
    );
    expect(() => decodeStrictAiJson(' ' * 524289), throwsFormatException);
  });

  test(
    'rejects malformed syntax without leaking source through exceptions',
    () {
      for (final text in <String>[
        '{"private":"secret',
        r'{"private":"secret\',
        '{"private":secret}',
        '{"private":"secret"]',
        '}{',
      ]) {
        expect(
          () => decodeStrictAiJson(text),
          throwsA(
            isA<FormatException>().having(
              (error) => error.toString(),
              'diagnostic',
              isNot(contains('secret')),
            ),
          ),
        );
      }
    },
  );
}

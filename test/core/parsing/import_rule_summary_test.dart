import 'package:bookloom/core/model/parse_options.dart';
import 'package:bookloom/core/parsing/import_rule_summary.dart';
import 'package:bookloom/core/parsing/rules.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('default options show automatic import detection read-only', () {
    final summary = ImportRuleSummary.fromOptions(const ParseOptions());

    expect(summary.presetId, 'auto');
    expect(summary.presetName, '自动识别');
    expect(summary.isAuto, isTrue);
    expect(summary.isCustom, isFalse);
    expect(summary.hasCustomSpec, isFalse);
    expect(summary.invalid, isFalse);
    expect(summary.entries, isEmpty);
  });

  test('numbered preset exposes only its chapter pattern', () {
    final summary = ImportRuleSummary.fromOptions(
      const ParseOptions(rulePreset: 'numbered'),
    );

    expect(summary.presetName, '数字标题');
    expect(summary.invalid, isFalse);
    expect(summary.entries, hasLength(1));
    expect(summary.entries.single.role, ImportRuleRole.chapter);
    expect(
      summary.entries.single.pattern,
      r'\s{0,8}\d{1,4}\s{0,8}[、.．:：]\s{0,8}.{0,40}',
    );
  });

  test('english preset lists chapter before volume definitions', () {
    final summary = ImportRuleSummary.fromOptions(
      const ParseOptions(rulePreset: 'english'),
    );

    expect(summary.entries.map((entry) => entry.role), [
      ImportRuleRole.chapter,
      ImportRuleRole.volume,
    ]);
    expect(summary.entries.first.pattern, getRulePreset('english')!.chapter);
    expect(summary.entries.last.pattern, getRulePreset('english')!.volume);
  });

  test('advertisement preset keeps drop and inline patterns in order', () {
    final summary = ImportRuleSummary.fromOptions(
      const ParseOptions(rulePreset: 'biquge'),
    );
    final preset = getRulePreset('biquge')!;

    expect(
      summary.entries
          .where((entry) => entry.role == ImportRuleRole.drop)
          .map((entry) => entry.pattern),
      preset.drop,
    );
    expect(
      summary.entries
          .where((entry) => entry.role == ImportRuleRole.inlineJunk)
          .map((entry) => entry.pattern),
      preset.inlineJunk,
    );
    expect(
      summary.entries.any((entry) => entry.role == ImportRuleRole.chapter),
      isFalse,
    );
  });

  test('custom preset reports its own name and definitions', () {
    final summary = ImportRuleSummary.fromOptions(
      const ParseOptions(
        rulePreset: 'custom',
        ruleSpec: <String, Object?>{
          'name': '我的章节规则',
          'chapter': r'^第\d+章',
          'drop': <String>['推广'],
        },
      ),
    );

    expect(summary.isCustom, isTrue);
    expect(summary.presetName, '我的章节规则');
    expect(summary.invalid, isFalse);
    expect(summary.hasCustomSpec, isTrue);
    expect(summary.entries.map((entry) => (entry.role, entry.pattern)), [
      (ImportRuleRole.chapter, r'^第\d+章'),
      (ImportRuleRole.drop, '推广'),
    ]);
  });

  test('custom definitions merge onto a named preset exactly once', () {
    final summary = ImportRuleSummary.fromOptions(
      const ParseOptions(
        rulePreset: 'english',
        ruleSpec: <String, Object?>{
          'name': '英文增强',
          'chapter': r'^Chapter \d+$',
          'drop': <String>['synthetic-drop'],
        },
      ),
    );
    final base = getRulePreset('english')!;

    expect(summary.presetName, '英文增强');
    expect(summary.hasCustomSpec, isTrue);
    expect(summary.isCustom, isFalse);
    expect(
      summary.entries
          .firstWhere((entry) => entry.role == ImportRuleRole.chapter)
          .pattern,
      r'^Chapter \d+$',
    );
    expect(
      summary.entries
          .firstWhere((entry) => entry.role == ImportRuleRole.volume)
          .pattern,
      base.volume,
    );
    expect(
      summary.entries
          .where((entry) => entry.role == ImportRuleRole.drop)
          .map((entry) => entry.pattern),
      [...base.drop, 'synthetic-drop'],
    );
  });

  test('unknown preset is reported invalid instead of throwing', () {
    final summary = ImportRuleSummary.fromOptions(
      const ParseOptions(rulePreset: 'unknown-site'),
    );

    expect(summary.invalid, isTrue);
    expect(summary.presetName, 'unknown-site');
    expect(summary.entries, isEmpty);
  });

  test('malformed custom definitions never break the host panel', () {
    for (final spec in <Map<String, Object?>>[
      <String, Object?>{'chapter': 1},
      <String, Object?>{'name': '零宽', 'chapter': 'a*'},
      <String, Object?>{'name': '未知字段', 'unknown': 'x'},
    ]) {
      final summary = ImportRuleSummary.fromOptions(
        ParseOptions(rulePreset: 'custom', ruleSpec: spec),
      );
      expect(summary.invalid, isTrue, reason: '$spec');
      expect(summary.entries, isEmpty, reason: '$spec');
    }
  });

  test('summary applies the same merge as the importer compiler', () {
    const options = ParseOptions(
      rulePreset: 'numbered',
      ruleSpec: <String, Object?>{'name': '数字加强', 'chapter': r'^\d{1,4}、'},
    );
    final summary = ImportRuleSummary.fromOptions(options);
    final compiled = resolveTxtRules(options);

    expect(summary.entries.single.pattern, options.ruleSpec!['chapter']);
    expect(compiled.chapter!.pattern, '^(?:${options.ruleSpec!['chapter']})\$');
  });
}

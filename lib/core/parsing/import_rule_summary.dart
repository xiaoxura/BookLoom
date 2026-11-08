import 'package:bookloom/core/model/parse_options.dart';
import 'package:bookloom/core/parsing/rules.dart';

/// Where an import rule applies while the TXT importer runs.
enum ImportRuleRole { chapter, volume, drop, inlineJunk }

final class ImportRuleEntry {
  const ImportRuleEntry(this.role, this.pattern);

  final ImportRuleRole role;
  final String pattern;
}

/// Read-only view of the rules a book's last TXT import used.
///
/// It intentionally exposes no matching or persistence API: the importer keeps
/// owning execution semantics, and the workbench only renders this snapshot.
final class ImportRuleSummary {
  ImportRuleSummary._({
    required this.presetId,
    required this.presetName,
    required this.isAuto,
    required this.isCustom,
    required this.hasCustomSpec,
    required this.invalid,
    required List<ImportRuleEntry> entries,
  }) : entries = List<ImportRuleEntry>.unmodifiable(entries);

  final String presetId;
  final String presetName;

  /// `auto` keeps the importer's unnamed built-in heuristics only.
  final bool isAuto;

  /// `custom` replaces the named preset with the stored custom definition.
  final bool isCustom;

  /// A custom definition was stored on top of the selected preset.
  final bool hasCustomSpec;

  /// The stored options could not be resolved; no entry is shown as active.
  final bool invalid;

  final List<ImportRuleEntry> entries;

  bool get hasEntries => entries.isNotEmpty;

  static ImportRuleSummary empty() => ImportRuleSummary._(
    presetId: 'auto',
    presetName: '自动识别',
    isAuto: true,
    isCustom: false,
    hasCustomSpec: false,
    invalid: false,
    entries: const [],
  );

  /// Never throws: corrupted stored options render as [invalid] instead of
  /// breaking the editor panel that hosts the read-only view.
  factory ImportRuleSummary.fromOptions(ParseOptions options) {
    final presetId = options.rulePreset;
    final base = presetId == 'custom' ? null : getRulePreset(presetId);
    final isKnownPreset = presetId == 'custom' || base != null;
    if (!isKnownPreset) {
      return ImportRuleSummary._(
        presetId: presetId,
        presetName: presetId,
        isAuto: false,
        isCustom: false,
        hasCustomSpec: options.ruleSpec != null,
        invalid: true,
        entries: const [],
      );
    }
    final RuleSpec resolved;
    try {
      resolved = resolveRuleSpec(options);
    } on RuleValidationException {
      return ImportRuleSummary._(
        presetId: presetId,
        presetName: base?.name ?? presetId,
        isAuto: presetId == 'auto',
        isCustom: presetId == 'custom',
        hasCustomSpec: options.ruleSpec != null,
        invalid: true,
        entries: const [],
      );
    }
    return ImportRuleSummary._(
      presetId: presetId,
      presetName: resolved.name,
      isAuto: presetId == 'auto',
      isCustom: presetId == 'custom',
      hasCustomSpec: options.ruleSpec != null,
      invalid: false,
      entries: <ImportRuleEntry>[
        if (resolved.chapter case final pattern?)
          ImportRuleEntry(ImportRuleRole.chapter, pattern),
        if (resolved.volume case final pattern?)
          ImportRuleEntry(ImportRuleRole.volume, pattern),
        for (final pattern in resolved.drop)
          ImportRuleEntry(ImportRuleRole.drop, pattern),
        for (final pattern in resolved.inlineJunk)
          ImportRuleEntry(ImportRuleRole.inlineJunk, pattern),
      ],
    );
  }
}

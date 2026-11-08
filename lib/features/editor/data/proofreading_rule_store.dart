import 'dart:async';
import 'dart:convert';

import 'package:bookloom/core/editing/proofreading_rule.dart';
import 'package:bookloom/core/editing/proofreading_rule_store.dart';
import 'package:bookloom/core/errors/app_failure.dart';
import 'package:bookloom/core/storage/app_database.dart';
import 'package:bookloom/core/storage/settings_store.dart';

class SettingsProofreadingRuleStore implements ProofreadingRuleStore {
  SettingsProofreadingRuleStore(AppDatabase db)
    : _db = db,
      _settings = SettingsStore(db);

  static const String settingsKey = 'proofreading.rules.v1';
  static const int maxRules = 256;
  static const int maxJsonBytes = 2 * 1024 * 1024;

  final AppDatabase _db;
  final SettingsStore _settings;

  @override
  Future<RuleMergeResult> mergeMissing(
    List<ProofreadingRule> rules, {
    bool Function()? isCurrent,
  }) async {
    if (rules.length > maxRules) {
      throw const ValidationFailure('规则数量超出上限。');
    }
    final ids = <String>{};
    for (final rule in rules) {
      if (rule.source == ProofreadingRuleSource.builtIn) {
        throw const ValidationFailure('内置规则不能恢复为本地规则。');
      }
      if (!ids.add(rule.id)) {
        throw const ValidationFailure('规则文件包含重复标识。');
      }
    }
    final addedIds = <String>[];
    final skippedIds = <String>[];
    await _db.transaction(() async {
      final existing = _decode(await _settings.read(settingsKey));
      final existingIds = {for (final rule in existing) rule.id};
      final added = <ProofreadingRule>[];
      for (final rule in rules) {
        if (existingIds.contains(rule.id)) {
          skippedIds.add(rule.id);
        } else {
          added.add(rule);
          addedIds.add(rule.id);
        }
      }
      if (existing.length + added.length > maxRules) {
        throw const ValidationFailure('规则数量超出上限。');
      }
      if (added.isEmpty) return;
      _requireCurrent(isCurrent);
      final encoded = _encode([...existing, ...added]);
      _requireCurrent(isCurrent);
      await _settings.write(settingsKey, encoded);
      _requireCurrent(isCurrent);
    });
    return RuleMergeResult(
      addedIds: List<String>.unmodifiable(addedIds),
      skippedIds: List<String>.unmodifiable(skippedIds),
    );
  }

  @override
  Future<List<ProofreadingRule>> loadForBook(String bookId) async {
    _validateIdentifier(bookId);
    return _db.transaction(() async {
      final rules = _decode(await _settings.read(settingsKey));
      return List<ProofreadingRule>.unmodifiable(
        rules.where((rule) => rule.appliesToBook(bookId)),
      );
    });
  }

  @override
  Future<void> save(
    ProofreadingRule rule, {
    bool Function()? isCurrent,
    Map<String, ProofreadingRule?>? expectedRules,
  }) async {
    if (rule.source == ProofreadingRuleSource.builtIn) {
      throw const ValidationFailure('内置规则不能保存或覆盖。');
    }
    final expected = _snapshotExpectedRules(expectedRules);
    await _db.transaction(() async {
      final rules = _decode(await _settings.read(settingsKey));
      _requireExpectedRules(rules, expected);
      _requireCurrent(isCurrent);
      final index = rules.indexWhere((current) => current.id == rule.id);
      if (index < 0) {
        rules.add(rule);
      } else {
        rules[index] = rule;
      }
      final encoded = _encode(rules);
      _requireCurrent(isCurrent);
      await _settings.write(settingsKey, encoded);
      _requireCurrent(isCurrent);
    });
  }

  @override
  Future<void> delete(
    String ruleId, {
    bool Function()? isCurrent,
    Map<String, ProofreadingRule?>? expectedRules,
  }) async {
    _validateIdentifier(ruleId);
    final expected = _snapshotExpectedRules(expectedRules);
    await _db.transaction(() async {
      final rules = _decode(await _settings.read(settingsKey));
      _requireExpectedRules(rules, expected);
      _requireCurrent(isCurrent);
      final before = rules.length;
      rules.removeWhere((rule) => rule.id == ruleId);
      if (rules.length != before) {
        final encoded = _encode(rules);
        _requireCurrent(isCurrent);
        await _settings.write(settingsKey, encoded);
      }
      _requireCurrent(isCurrent);
    });
  }

  @override
  Future<void> runIfCurrent(
    Map<String, ProofreadingRule?> expectedRules,
    void Function() action, {
    bool Function()? isCurrent,
  }) async {
    final callerZone = Zone.current;
    final expected = _snapshotExpectedRules(
      expectedRules,
      requireNonEmpty: true,
    );
    await _db.transaction(() async {
      final rules = _decode(await _settings.read(settingsKey));
      _requireExpectedRules(rules, expected);
      _requireCurrent(isCurrent);
      callerZone.run(action);
    });
  }
}

Map<String, String?>? _snapshotExpectedRules(
  Map<String, ProofreadingRule?>? expectedRules, {
  bool requireNonEmpty = false,
}) {
  if (expectedRules == null) {
    if (requireNonEmpty) {
      throw const ValidationFailure('必须指定需要核对的规则。');
    }
    return null;
  }
  if (expectedRules.length > 32 || requireNonEmpty && expectedRules.isEmpty) {
    throw const ValidationFailure('规则核对数量无效。');
  }
  final snapshot = <String, String?>{};
  for (final entry in expectedRules.entries) {
    _validateIdentifier(entry.key);
    if (entry.value != null && entry.value!.id != entry.key) {
      throw const ValidationFailure('规则标识与预期值不一致。');
    }
    snapshot[entry.key] = entry.value == null
        ? null
        : proofreadingRuleFingerprint(entry.value!);
  }
  return snapshot;
}

void _requireExpectedRules(
  List<ProofreadingRule> rules,
  Map<String, String?>? expected,
) {
  if (expected == null) return;
  final current = {for (final rule in rules) rule.id: rule};
  for (final entry in expected.entries) {
    final rule = current[entry.key];
    if ((rule == null ? null : proofreadingRuleFingerprint(rule)) !=
        entry.value) {
      throw const ValidationFailure('规则已变更，请重新试跑后操作。');
    }
  }
}

void _requireCurrent(bool Function()? isCurrent) {
  if (isCurrent != null && !isCurrent()) {
    throw const ValidationFailure('规则已过期，请重新试跑后保存。');
  }
}

List<ProofreadingRule> _decode(String? source) {
  if (source == null) return <ProofreadingRule>[];
  try {
    if (utf8.encode(source).length >
        SettingsProofreadingRuleStore.maxJsonBytes) {
      _corrupt();
    }
    _checkUtf16(source);
    _rejectDuplicateJsonKeys(source);
    final root = _object(jsonDecode(source));
    _keys(root, const {'schema_version', 'rules'});
    if (root['schema_version'] != 1 || root['schema_version'] is! int) {
      _corrupt();
    }
    final entries = root['rules'];
    if (entries is! List ||
        entries.length > SettingsProofreadingRuleStore.maxRules) {
      _corrupt();
    }
    final ids = <String>{};
    final rules = <ProofreadingRule>[];
    for (final entry in entries) {
      final rule = _decodeRule(_object(entry));
      if (!ids.add(rule.id)) _corrupt();
      rules.add(rule);
    }
    return rules;
  } on FormatException {
    _corrupt();
  } on ValidationFailure {
    _corrupt();
  }
}

ProofreadingRule _decodeRule(Map<String, dynamic> entry) {
  _keys(
    entry,
    const {
      'id',
      'name',
      'kind',
      'enabled',
      'source',
      'scope',
      'book_id',
      'target',
      'mode',
      'pattern',
      'case_sensitive',
      'action',
      'priority',
      'positive_examples',
      'negative_examples',
    },
    optional: const {
      'exclude',
      'whole_line',
      'title_capture_group',
      'heading_level',
      'number_capture_group',
    },
  );
  final source = switch (entry['source']) {
    'user' => ProofreadingRuleSource.user,
    'ai' => ProofreadingRuleSource.ai,
    _ => _corrupt(),
  };
  final scope = switch (entry['scope']) {
    'book' => ProofreadingRuleScope.book,
    'global' => ProofreadingRuleScope.global,
    _ => _corrupt(),
  };
  return ProofreadingRule.create(
    id: _string(entry['id']),
    name: _string(entry['name']),
    kind: switch (entry['kind']) {
      'chapter' => ProofreadingRuleKind.chapter,
      'advertisement' => ProofreadingRuleKind.advertisement,
      _ => _corrupt(),
    },
    enabled: _bool(entry['enabled']),
    source: source,
    scope: scope,
    globalScopeConfirmed: scope == ProofreadingRuleScope.global,
    bookId: _string(entry['book_id']),
    target: switch (entry['target']) {
      'heading_line' => ProofreadingRuleTarget.headingLine,
      'body_line' => ProofreadingRuleTarget.bodyLine,
      'paragraph' => ProofreadingRuleTarget.paragraph,
      _ => _corrupt(),
    },
    mode: switch (entry['mode']) {
      'literal' => ProofreadingMatchMode.literal,
      'safe_regex' => ProofreadingMatchMode.safeRegex,
      _ => _corrupt(),
    },
    pattern: _string(entry['pattern']),
    excludePattern: entry.containsKey('exclude')
        ? _string(entry['exclude'])
        : null,
    wholeLineOnly: entry.containsKey('whole_line')
        ? _bool(entry['whole_line'])
        : false,
    titleCaptureGroup: entry.containsKey('title_capture_group')
        ? _int(entry['title_capture_group'])
        : null,
    numberCaptureGroup: entry.containsKey('number_capture_group')
        ? _int(entry['number_capture_group'])
        : null,
    headingLevel: entry.containsKey('heading_level')
        ? _int(entry['heading_level'])
        : 2,
    caseSensitive: _bool(entry['case_sensitive']),
    action: switch (entry['action']) {
      'chapter_candidate' => ProofreadingRuleAction.chapterCandidate,
      'advertisement_candidate' =>
        ProofreadingRuleAction.advertisementCandidate,
      'exact_deletion' => ProofreadingRuleAction.exactDeletion,
      _ => _corrupt(),
    },
    priority: _int(entry['priority']),
    positiveExamples: _strings(entry['positive_examples']),
    negativeExamples: _strings(entry['negative_examples']),
  );
}

String _encode(List<ProofreadingRule> rules) {
  if (rules.length > SettingsProofreadingRuleStore.maxRules ||
      rules.any((rule) => rule.source == ProofreadingRuleSource.builtIn)) {
    throw const ValidationFailure('规则数量超出上限或包含内置规则。');
  }
  final source = jsonEncode({
    'schema_version': 1,
    'rules': [
      for (final rule in rules)
        {
          'id': rule.id,
          'name': rule.name,
          'kind': rule.kind.name,
          'enabled': rule.enabled,
          'source': rule.source.name,
          'scope': rule.scope.name,
          'book_id': rule.bookId,
          'target': switch (rule.target) {
            ProofreadingRuleTarget.headingLine => 'heading_line',
            ProofreadingRuleTarget.bodyLine => 'body_line',
            ProofreadingRuleTarget.paragraph => 'paragraph',
          },
          'mode': switch (rule.mode) {
            ProofreadingMatchMode.literal => 'literal',
            ProofreadingMatchMode.safeRegex => 'safe_regex',
          },
          'pattern': rule.pattern,
          if (rule.excludePattern != null) 'exclude': rule.excludePattern,
          if (rule.wholeLineOnly) 'whole_line': true,
          if (rule.titleCaptureGroup != null)
            'title_capture_group': rule.titleCaptureGroup,
          if (rule.headingLevel != 2) 'heading_level': rule.headingLevel,
          if (rule.numberCaptureGroup != null)
            'number_capture_group': rule.numberCaptureGroup,
          'case_sensitive': rule.caseSensitive,
          'action': switch (rule.action) {
            ProofreadingRuleAction.chapterCandidate => 'chapter_candidate',
            ProofreadingRuleAction.advertisementCandidate =>
              'advertisement_candidate',
            ProofreadingRuleAction.exactDeletion => 'exact_deletion',
          },
          'priority': rule.priority,
          'positive_examples': rule.positiveExamples,
          'negative_examples': rule.negativeExamples,
        },
    ],
  });
  if (utf8.encode(source).length > SettingsProofreadingRuleStore.maxJsonBytes) {
    throw const ValidationFailure('规则数据超出存储上限。');
  }
  return source;
}

/// Strict transfer encoding for rule files and backups.
String encodeProofreadingRules(List<ProofreadingRule> rules) => _encode(rules);

/// Decodes a rule transfer file with the same schema as stored rules.
List<ProofreadingRule> decodeProofreadingRules(String raw) {
  try {
    return _decode(raw);
  } on AppFailure {
    throw const ValidationFailure('规则文件格式无效或版本不兼容。');
  }
}

Map<String, dynamic> _object(Object? value) {
  if (value is Map<String, dynamic>) return value;
  _corrupt();
}

void _keys(
  Map<String, dynamic> value,
  Set<String> expected, {
  Set<String> optional = const {},
}) {
  if (!expected.every(value.containsKey) ||
      value.keys.any(
        (key) => !expected.contains(key) && !optional.contains(key),
      )) {
    _corrupt();
  }
}

String _string(Object? value) {
  if (value is String) return value;
  _corrupt();
}

bool _bool(Object? value) {
  if (value is bool) return value;
  _corrupt();
}

int _int(Object? value) {
  if (value is int) return value;
  _corrupt();
}

List<String> _strings(Object? value) {
  if (value is! List) _corrupt();
  return [for (final item in value) _string(item)];
}

void _validateIdentifier(String value) {
  if (value.trim().isEmpty || value.length > 128) {
    throw const ValidationFailure('规则或书籍标识无效。');
  }
  try {
    _checkUtf16(value);
  } on FormatException {
    throw const ValidationFailure('规则或书籍标识无效。');
  }
}

void _checkUtf16(String value) {
  for (var index = 0; index < value.length; index++) {
    final code = value.codeUnitAt(index);
    if (code >= 0xd800 && code <= 0xdbff) {
      if (++index >= value.length) throw const FormatException();
      final next = value.codeUnitAt(index);
      if (next < 0xdc00 || next > 0xdfff) throw const FormatException();
    } else if (code >= 0xdc00 && code <= 0xdfff) {
      throw const FormatException();
    }
  }
}

void _rejectDuplicateJsonKeys(String source) {
  final stack = <_JsonObjectFrame?>[];
  for (var index = 0; index < source.length; index++) {
    final code = source.codeUnitAt(index);
    if (code == 0x22) {
      final start = index++;
      var closed = false;
      while (index < source.length) {
        final current = source.codeUnitAt(index++);
        if (current == 0x5c) {
          index++;
        } else if (current == 0x22) {
          closed = true;
          break;
        }
      }
      if (!closed) throw const FormatException();
      if (stack.isNotEmpty && stack.last?.expectsKey == true) {
        final frame = stack.last!;
        final key = jsonDecode(source.substring(start, index)) as String;
        if (!frame.keys.add(key)) throw const FormatException();
        frame.expectsKey = false;
      }
      index--;
    } else if (code == 0x7b || code == 0x5b) {
      if (stack.length >= 32) throw const FormatException();
      stack.add(code == 0x7b ? _JsonObjectFrame() : null);
    } else if (code == 0x7d || code == 0x5d) {
      if (stack.isEmpty || (stack.last != null) != (code == 0x7d)) {
        throw const FormatException();
      }
      stack.removeLast();
    } else if (code == 0x2c && stack.isNotEmpty && stack.last != null) {
      stack.last!.expectsKey = true;
    }
  }
  if (stack.isNotEmpty) throw const FormatException();
}

class _JsonObjectFrame {
  bool expectsKey = true;
  final Set<String> keys = <String>{};
}

Never _corrupt() => throw const StorageFailure('规则数据已损坏或版本不兼容，无法读取或修改。');

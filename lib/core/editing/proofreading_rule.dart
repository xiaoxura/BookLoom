import 'package:bookloom/core/ai/ai_json.dart';
import 'package:bookloom/core/editing/rule_heading_mapping.dart';
import 'package:bookloom/core/editing/safe_regex.dart';
import 'package:bookloom/core/errors/app_failure.dart';

enum ProofreadingRuleKind { chapter, advertisement }

enum ProofreadingRuleTarget { headingLine, bodyLine, paragraph }

enum ProofreadingMatchMode { literal, safeRegex }

enum ProofreadingRuleAction {
  chapterCandidate,
  advertisementCandidate,
  exactDeletion,
}

enum ProofreadingRuleScope { book, global }

enum ProofreadingRuleSource { builtIn, user, ai }

class ProofreadingRuleMatch {
  const ProofreadingRuleMatch(
    this.startUtf16,
    this.endUtf16, {
    this.mappedTitle,
    this.mappedNumber,
    this.numberText,
  });

  final int startUtf16;
  final int endUtf16;
  final String? mappedTitle;
  final int? mappedNumber;
  final String? numberText;
}

/// A definition only. Matching a sample does not scan a book or apply an edit.
class ProofreadingRule {
  ProofreadingRule._({
    required this.id,
    required this.name,
    required this.kind,
    required this.enabled,
    required this.source,
    required this.scope,
    required this.bookId,
    required this.target,
    required this.mode,
    required this.pattern,
    required this.excludePattern,
    required this._compiledExclude,
    required this.wholeLineOnly,
    required this.titleCaptureGroup,
    required this.numberCaptureGroup,
    required this.headingLevel,
    required this.caseSensitive,
    required this.action,
    required this.priority,
    required this.positiveExamples,
    required this.negativeExamples,
    required this._compiledPattern,
  });

  static const int maxPatternUtf16 = 256;
  static const int maxExcludeUtf16 = 256;
  static const int maxExampleUtf16 = 2048;
  static const int maxExamplesPerPolarity = 12;
  static const int maxPatternAndExamplesUtf16 = 8192;

  final String id;
  final String name;
  final ProofreadingRuleKind kind;
  final bool enabled;
  final ProofreadingRuleSource source;
  final ProofreadingRuleScope scope;
  final String bookId;
  final ProofreadingRuleTarget target;
  final ProofreadingMatchMode mode;
  final String pattern;

  /// Optional literal text: a match is skipped when the line containing its
  /// start also contains this text. Null keeps the previous behavior.
  final String? excludePattern;
  final RegExp? _compiledExclude;

  /// When true, the match must cover the entire line after trimming its
  /// leading and trailing whitespace. Paragraph targets are not supported.
  final bool wholeLineOnly;
  final int? titleCaptureGroup;
  final int? numberCaptureGroup;
  final int headingLevel;
  final bool caseSensitive;
  final ProofreadingRuleAction action;
  final int priority;
  final List<String> positiveExamples;
  final List<String> negativeExamples;
  final RegExp _compiledPattern;

  static ProofreadingRule create({
    required String id,
    required String name,
    required ProofreadingRuleKind kind,
    required ProofreadingRuleSource source,
    required String bookId,
    required ProofreadingRuleTarget target,
    required ProofreadingMatchMode mode,
    required String pattern,
    String? excludePattern,
    bool wholeLineOnly = false,
    int? titleCaptureGroup,
    int? numberCaptureGroup,
    int headingLevel = 2,
    required bool caseSensitive,
    required ProofreadingRuleAction action,
    required List<String> positiveExamples,
    required List<String> negativeExamples,
    ProofreadingRuleScope scope = ProofreadingRuleScope.book,
    bool globalScopeConfirmed = false,
    bool enabled = true,
    int priority = 0,
  }) {
    _boundedString(id, 128);
    _boundedString(name, 128);
    _boundedString(bookId, 128);
    _boundedString(pattern, maxPatternUtf16);
    if (excludePattern != null) {
      _boundedString(excludePattern, maxExcludeUtf16);
      if (excludePattern.contains('\n') || excludePattern.contains('\r')) {
        _invalid();
      }
    }
    if (pattern.contains('\n') ||
        pattern.contains('\r') ||
        scope == ProofreadingRuleScope.global && !globalScopeConfirmed ||
        priority < -1000 ||
        priority > 1000 ||
        (headingLevel != 1 && headingLevel != 2) ||
        kind == ProofreadingRuleKind.advertisement && headingLevel != 2 ||
        numberCaptureGroup != null &&
            (kind != ProofreadingRuleKind.chapter ||
                mode != ProofreadingMatchMode.safeRegex ||
                titleCaptureGroup == null ||
                numberCaptureGroup < 0) ||
        kind == ProofreadingRuleKind.chapter &&
            (target != ProofreadingRuleTarget.headingLine ||
                action != ProofreadingRuleAction.chapterCandidate) ||
        kind == ProofreadingRuleKind.advertisement &&
            (target == ProofreadingRuleTarget.headingLine ||
                action == ProofreadingRuleAction.chapterCandidate) ||
        wholeLineOnly && target == ProofreadingRuleTarget.paragraph ||
        titleCaptureGroup != null &&
            (kind != ProofreadingRuleKind.chapter ||
                mode != ProofreadingMatchMode.safeRegex ||
                titleCaptureGroup < 0)) {
      _invalid();
    }
    if (positiveExamples.isEmpty ||
        positiveExamples.length > maxExamplesPerPolarity ||
        negativeExamples.length > maxExamplesPerPolarity) {
      _invalid();
    }
    var totalUtf16 = pattern.length + (excludePattern?.length ?? 0);
    for (final sample in [...positiveExamples, ...negativeExamples]) {
      _boundedString(sample, maxExampleUtf16);
      if (sample.contains('\n') || sample.contains('\r')) _invalid();
      totalUtf16 += sample.length;
      if (totalUtf16 > maxPatternAndExamplesUtf16) _invalid();
    }

    final RegExp compiledPattern;
    final int captureCount;
    try {
      if (mode == ProofreadingMatchMode.safeRegex) {
        final safePattern = SafeRegex.compile(
          pattern,
          caseSensitive: caseSensitive,
        );
        compiledPattern = safePattern.regex;
        captureCount = safePattern.captureCount;
      } else {
        compiledPattern = RegExp(
          RegExp.escape(pattern),
          caseSensitive: caseSensitive,
          unicode: true,
        );
        captureCount = 0;
      }
    } on FormatException {
      _invalid();
    } on ValidationFailure {
      _invalid();
    }
    final RegExp? compiledExclude = excludePattern == null
        ? null
        : RegExp(
            RegExp.escape(excludePattern),
            caseSensitive: caseSensitive,
            unicode: true,
          );
    if (titleCaptureGroup != null && titleCaptureGroup > captureCount) {
      _invalid();
    }
    if (numberCaptureGroup != null && numberCaptureGroup > captureCount) {
      _invalid();
    }
    final rule = ProofreadingRule._(
      id: id,
      name: name,
      kind: kind,
      enabled: enabled,
      source: source,
      scope: scope,
      bookId: bookId,
      target: target,
      mode: mode,
      pattern: pattern,
      excludePattern: excludePattern,
      compiledExclude: compiledExclude,
      wholeLineOnly: wholeLineOnly,
      titleCaptureGroup: titleCaptureGroup,
      numberCaptureGroup: numberCaptureGroup,
      headingLevel: headingLevel,
      caseSensitive: caseSensitive,
      action: action,
      priority: priority,
      positiveExamples: List<String>.unmodifiable(positiveExamples),
      negativeExamples: List<String>.unmodifiable(negativeExamples),
      compiledPattern: compiledPattern,
    );
    if (mode == ProofreadingMatchMode.safeRegex) {
      for (final probe in <String>['', 'x', 'a b', '第1章', '😀']) {
        rule._rejectZeroLengthMatches(probe);
      }
    }
    for (final sample in rule.positiveExamples) {
      if (rule.matchSample(sample).isEmpty) _invalid();
    }
    for (final sample in rule.negativeExamples) {
      if (rule.matchSample(sample).isNotEmpty) _invalid();
    }
    return rule;
  }

  /// Copies this rule for editing. Built-in rules become editable user rules.
  ProofreadingRule duplicate({required String id, required String name}) =>
      create(
        id: id,
        name: name,
        kind: kind,
        source: source == ProofreadingRuleSource.builtIn
            ? ProofreadingRuleSource.user
            : source,
        bookId: bookId,
        target: target,
        mode: mode,
        pattern: pattern,
        excludePattern: excludePattern,
        wholeLineOnly: wholeLineOnly,
        titleCaptureGroup: titleCaptureGroup,
        numberCaptureGroup: numberCaptureGroup,
        headingLevel: headingLevel,
        caseSensitive: caseSensitive,
        action: action,
        priority: priority,
        positiveExamples: positiveExamples,
        negativeExamples: negativeExamples,
        scope: scope,
        globalScopeConfirmed: true,
        enabled: enabled,
      );

  /// Copies this definition under another ID, keeping every other field.
  ProofreadingRule withId(String newId) => create(
    id: newId,
    name: name,
    kind: kind,
    source: source,
    bookId: bookId,
    target: target,
    mode: mode,
    pattern: pattern,
    excludePattern: excludePattern,
    wholeLineOnly: wholeLineOnly,
    titleCaptureGroup: titleCaptureGroup,
    numberCaptureGroup: numberCaptureGroup,
    headingLevel: headingLevel,
    caseSensitive: caseSensitive,
    action: action,
    priority: priority,
    positiveExamples: positiveExamples,
    negativeExamples: negativeExamples,
    scope: scope,
    globalScopeConfirmed: true,
    enabled: enabled,
  );

  /// Copies this definition onto another book, keeping its identity and
  /// behavior. Used when importing a rule preset into the open book.
  ProofreadingRule withBookId(String bookId) => create(
    id: id,
    name: name,
    kind: kind,
    source: source,
    bookId: bookId,
    target: target,
    mode: mode,
    pattern: pattern,
    excludePattern: excludePattern,
    wholeLineOnly: wholeLineOnly,
    titleCaptureGroup: titleCaptureGroup,
    numberCaptureGroup: numberCaptureGroup,
    headingLevel: headingLevel,
    caseSensitive: caseSensitive,
    action: action,
    priority: priority,
    positiveExamples: positiveExamples,
    negativeExamples: negativeExamples,
    scope: scope,
    globalScopeConfirmed: true,
    enabled: enabled,
  );

  bool appliesToBook(String candidateBookId) =>
      scope == ProofreadingRuleScope.global || bookId == candidateBookId;

  /// Bounded, single-line sample matching; offsets are UTF-16 code units.
  List<ProofreadingRuleMatch> matchSample(String sample) {
    _boundedString(sample, maxExampleUtf16);
    if (sample.contains('\n') || sample.contains('\r')) _invalid();
    return List<ProofreadingRuleMatch>.unmodifiable(matchScanText(sample));
  }

  /// Scan one bounded body line or paragraph with the validated pattern.
  /// Offsets are UTF-16 code units; callers must enforce their total scan budget.
  Iterable<ProofreadingRuleMatch> matchScanText(String text) sync* {
    if (text.length > 32768) {
      throw const ValidationFailure('正文块过长，无法安全试跑规则。');
    }
    final captureGroup = titleCaptureGroup;
    final numberGroup = numberCaptureGroup;
    final excludedRanges = _excludedLineRanges(text);
    var excludedIndex = 0;
    final wholeLineBounds = wholeLineOnly ? _trimmedBounds(text) : null;
    if (wholeLineOnly && wholeLineBounds == null) return;
    for (final match in _compiledPattern.allMatches(text)) {
      if (match.start == match.end) _invalid();
      if (wholeLineBounds != null &&
          (match.start != wholeLineBounds.$1 ||
              match.end != wholeLineBounds.$2)) {
        continue;
      }
      while (excludedIndex < excludedRanges.length &&
          excludedRanges[excludedIndex].$2 <= match.start) {
        excludedIndex++;
      }
      if (excludedIndex < excludedRanges.length &&
          excludedRanges[excludedIndex].$1 <= match.start) {
        continue;
      }
      if (!_utf16Boundary(text, match.start) ||
          !_utf16Boundary(text, match.end)) {
        continue;
      }
      String? mappedTitle;
      if (captureGroup != null) {
        final captured = match.group(captureGroup);
        if (captured == null) {
          throw const ValidationFailure('章节标题捕获组未参与匹配，无法完成全书试跑。');
        }
        mappedTitle = captured.trim();
        if (mappedTitle.isEmpty ||
            mappedTitle.length > maxPatternUtf16 ||
            mappedTitle.contains('\n') ||
            mappedTitle.contains('\r')) {
          throw const ValidationFailure('章节标题映射为空、跨行或过长，无法完成全书试跑。');
        }
        try {
          _boundedString(mappedTitle, maxPatternUtf16);
        } on ValidationFailure {
          throw const ValidationFailure('章节标题映射包含无效字符，无法完成全书试跑。');
        }
      }
      int? mappedNumber;
      String? numberText;
      if (numberGroup != null) {
        final captured = match.group(numberGroup);
        if (captured == null) {
          throw const ValidationFailure('章号捕获组未参与匹配，无法完成全书试跑。');
        }
        numberText = captured.trim();
        mappedNumber = RuleHeadingMapping.parseNumber(numberText);
        if (mappedNumber == null) {
          throw const ValidationFailure('章号映射为空或不是合法正整数，无法完成全书试跑。');
        }
        RuleHeadingMapping.composeTitle(
          title: mappedTitle!,
          number: mappedNumber,
          headingLevel: headingLevel,
        );
      }
      yield ProofreadingRuleMatch(
        match.start,
        match.end,
        mappedTitle: mappedTitle,
        mappedNumber: mappedNumber,
        numberText: numberText,
      );
    }
  }

  /// The exact span of [text] without leading or trailing whitespace.
  ///
  /// Uses Dart's own `trim()` semantics so the whole-line condition cannot
  /// drift from the whitespace definition used elsewhere.
  static (int, int)? _trimmedBounds(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return null;
    final start = text.indexOf(trimmed);
    return (start, start + trimmed.length);
  }

  /// Line ranges whose text contains [excludePattern]. Matches that begin in
  /// one of these lines are suppressed without changing any other match.
  List<(int, int)> _excludedLineRanges(String text) {
    final exclude = _compiledExclude;
    if (exclude == null) return const [];
    final ranges = <(int, int)>[];
    var start = 0;
    for (var index = 0; index <= text.length; index++) {
      final atEnd = index == text.length;
      final code = atEnd ? 0 : text.codeUnitAt(index);
      if (code != 0x0a && code != 0x0d && !atEnd) continue;
      if (start <= index && exclude.hasMatch(text.substring(start, index))) {
        ranges.add((start, index));
      }
      if (!atEnd &&
          code == 0x0d &&
          index + 1 < text.length &&
          text.codeUnitAt(index + 1) == 0x0a) {
        index++;
      }
      start = index + 1;
    }
    return ranges;
  }

  void _rejectZeroLengthMatches(String probe) {
    for (final match in _compiledPattern.allMatches(probe)) {
      if (match.start == match.end) _invalid();
    }
  }
}

bool _utf16Boundary(String text, int offset) {
  if (offset == 0 || offset == text.length) return true;
  final before = text.codeUnitAt(offset - 1);
  final after = text.codeUnitAt(offset);
  return !(before >= 0xd800 &&
      before <= 0xdbff &&
      after >= 0xdc00 &&
      after <= 0xdfff);
}

class RuleProposal {
  RuleProposal({
    required this.proposalId,
    required this.rule,
    required this.reason,
    required List<String> requiredPositiveExamples,
    required List<String> requiredNegativeExamples,
  }) : requiredPositiveExamples = List<String>.unmodifiable(
         requiredPositiveExamples,
       ),
       requiredNegativeExamples = List<String>.unmodifiable(
         requiredNegativeExamples,
       );

  final String proposalId;
  final ProofreadingRule rule;
  final String reason;
  final List<String> requiredPositiveExamples;
  final List<String> requiredNegativeExamples;
}

/// The model supplies content only; identity, origin and scope come from the caller.
abstract final class RuleProposalDecoder {
  static RuleProposal decode(
    String response, {
    required String proposalId,
    required String ruleId,
    required String bookId,
    required ProofreadingRuleSource source,
    required List<String> requiredPositiveExamples,
    required List<String> requiredNegativeExamples,
    ProofreadingRuleScope scope = ProofreadingRuleScope.book,
    bool globalScopeConfirmed = false,
    bool enabled = true,
    int priority = 0,
  }) {
    _boundedString(proposalId, 128);
    if (response.length > 16384 || source == ProofreadingRuleSource.builtIn) {
      _invalid();
    }
    final Object? decoded;
    try {
      decoded = decodeStrictAiJson(response);
    } on FormatException {
      _invalid();
    }
    final root = _object(decoded);
    _keys(
      root,
      const {
        'schema_version',
        'name',
        'kind',
        'target',
        'match',
        'action',
        'positive_examples',
        'negative_examples',
        'reason',
      },
      optional: const {'heading_level'},
    );
    if (root['schema_version'] is! int || root['schema_version'] != 1) {
      _invalid();
    }
    final match = _object(root['match']);
    _keys(
      match,
      const {'mode', 'pattern', 'case_sensitive'},
      optional: const {'title_capture_group', 'number_capture_group'},
    );
    final caseSensitive = match['case_sensitive'];
    if (caseSensitive is! bool) _invalid();
    final Object? titleCaptureGroup = match['title_capture_group'];
    if (match.containsKey('title_capture_group') && titleCaptureGroup is! int) {
      _invalid();
    }
    final Object? numberCaptureGroup = match['number_capture_group'];
    if (match.containsKey('number_capture_group') &&
        numberCaptureGroup is! int) {
      _invalid();
    }
    final headingLevel = root.containsKey('heading_level')
        ? root['heading_level']
        : 2;
    if (headingLevel is! int) _invalid();
    final rule = ProofreadingRule.create(
      id: ruleId,
      name: _string(root, 'name', 128),
      kind: switch (root['kind']) {
        'chapter' => ProofreadingRuleKind.chapter,
        'advertisement' => ProofreadingRuleKind.advertisement,
        _ => _invalid(),
      },
      source: source,
      bookId: bookId,
      target: switch (root['target']) {
        'heading_line' => ProofreadingRuleTarget.headingLine,
        'body_line' => ProofreadingRuleTarget.bodyLine,
        'paragraph' => ProofreadingRuleTarget.paragraph,
        _ => _invalid(),
      },
      mode: switch (match['mode']) {
        'literal' => ProofreadingMatchMode.literal,
        'safe_regex' => ProofreadingMatchMode.safeRegex,
        _ => _invalid(),
      },
      pattern: _string(match, 'pattern', ProofreadingRule.maxPatternUtf16),
      titleCaptureGroup: titleCaptureGroup as int?,
      numberCaptureGroup: numberCaptureGroup as int?,
      headingLevel: headingLevel,
      caseSensitive: caseSensitive,
      action: switch (root['action']) {
        'chapter_candidate' => ProofreadingRuleAction.chapterCandidate,
        'advertisement_candidate' =>
          ProofreadingRuleAction.advertisementCandidate,
        'exact_deletion' => ProofreadingRuleAction.exactDeletion,
        _ => _invalid(),
      },
      positiveExamples: _examples(root['positive_examples']),
      negativeExamples: _examples(root['negative_examples']),
      scope: scope,
      globalScopeConfirmed: globalScopeConfirmed,
      enabled: enabled,
      priority: priority,
    );
    _validateRequiredExamples(
      rule,
      requiredPositiveExamples,
      requiredNegativeExamples,
    );
    return RuleProposal(
      proposalId: proposalId,
      rule: rule,
      reason: _string(root, 'reason', 1024),
      requiredPositiveExamples: requiredPositiveExamples,
      requiredNegativeExamples: requiredNegativeExamples,
    );
  }

  static void _validateRequiredExamples(
    ProofreadingRule rule,
    List<String> positiveExamples,
    List<String> negativeExamples,
  ) {
    if (positiveExamples.isEmpty ||
        positiveExamples.length > ProofreadingRule.maxExamplesPerPolarity ||
        negativeExamples.length > ProofreadingRule.maxExamplesPerPolarity) {
      _invalid();
    }
    var totalUtf16 = rule.pattern.length;
    for (final sample in [...positiveExamples, ...negativeExamples]) {
      totalUtf16 += sample.length;
      if (totalUtf16 > ProofreadingRule.maxPatternAndExamplesUtf16) {
        _invalid();
      }
    }
    for (final sample in positiveExamples) {
      if (rule.matchSample(sample).isEmpty) _invalid();
    }
    for (final sample in negativeExamples) {
      if (rule.matchSample(sample).isNotEmpty) _invalid();
    }
  }

  static Map<String, dynamic> _object(Object? value) {
    if (value is Map<String, dynamic>) return value;
    _invalid();
  }

  static void _keys(
    Map<String, dynamic> value,
    Set<String> expected, {
    Set<String> optional = const {},
  }) {
    if (!expected.every(value.containsKey) ||
        value.keys.any(
          (key) => !expected.contains(key) && !optional.contains(key),
        )) {
      _invalid();
    }
  }

  static String _string(Map<String, dynamic> item, String key, int limit) {
    final value = item[key];
    if (value is! String) _invalid();
    _boundedString(value, limit);
    return value;
  }

  static List<String> _examples(Object? value) {
    if (value is! List ||
        value.length > ProofreadingRule.maxExamplesPerPolarity) {
      _invalid();
    }
    final examples = <String>[];
    for (final sample in value) {
      if (sample is! String) _invalid();
      examples.add(sample);
    }
    return examples;
  }
}

void _boundedString(String value, int limit) {
  if (value.trim().isEmpty || value.length > limit) _invalid();
  for (var index = 0; index < value.length; index++) {
    final code = value.codeUnitAt(index);
    if (code >= 0xd800 && code <= 0xdbff) {
      if (++index >= value.length) _invalid();
      final next = value.codeUnitAt(index);
      if (next < 0xdc00 || next > 0xdfff) _invalid();
    } else if (code >= 0xdc00 && code <= 0xdfff) {
      _invalid();
    }
  }
}

Never _invalid() => throw const ValidationFailure('规则提案验证失败，请调整规则或样例。');

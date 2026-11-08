import 'dart:async';

import 'package:bookloom/core/editing/proofreading_rule.dart';
import 'package:bookloom/core/editing/proofreading_rule_scan.dart';
import 'package:bookloom/core/editing/proofreading_rule_store.dart';
import 'package:bookloom/core/errors/app_failure.dart';
import 'package:bookloom/core/model/block.dart';
import 'package:bookloom/core/model/book.dart';
import 'package:bookloom/core/model/chapter.dart';
import 'package:bookloom/core/model/metadata.dart';
import 'package:bookloom/core/model/parse_options.dart';
import 'package:bookloom/core/platform/background_jobs.dart';
import 'package:bookloom/features/editor/application/editor_session.dart';
import 'package:bookloom/features/editor/application/rule_workbench_task.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late _Fixture fixture;

  setUp(() async {
    fixture = await _Fixture.open();
  });

  tearDown(() async {
    await fixture.dispose();
  });

  test('lone CR heading preview cannot be applied', () {
    const source = '前文\r【第二章 风雨】\r尾声';
    final start = source.indexOf('【');
    final match = RuleScanMatch(
      chapterId: 'a',
      chapterTitle: '第一章',
      blockId: 'p1',
      lineNumber: 2,
      startUtf16: start,
      endUtf16: start + '【第二章 风雨】'.length,
      action: ProofreadingRuleAction.chapterCandidate,
      ruleIds: const ['chapter'],
      excerpt: '【第二章 风雨】',
      before: '前文\r',
      after: '\r尾声',
    );
    final preview = RuleWorkbenchMatch(
      id: 'cr-heading',
      match: match,
      sourceText: source,
    );

    expect(preview.splitSourceLine, '【第二章 风雨】');
    expect(preview.hasUnsupportedHeadingLineEnding, isTrue);
    expect(preview.canApply, isFalse);
  });

  test('load exposes read-only import rules without selecting them', () async {
    await fixture.dispose();
    fixture = await _Fixture.open(
      parseOptions: const ParseOptions(rulePreset: 'numbered'),
    );
    final rule = _advertisementRule(id: 'book-rule', pattern: '广告');
    fixture.ruleStore.definitions[rule.id] = rule;

    await fixture.task.load();

    final import = fixture.task.importRules!;
    expect(import.presetId, 'numbered');
    expect(import.presetName, '数字标题');
    expect(import.entries, hasLength(1));
    expect(import.entries.single.pattern, contains(r'\d{1,4}'));
    expect(fixture.task.rules.map((current) => current.id), [rule.id]);
    expect(fixture.task.selectedRuleIds, isEmpty);
    await fixture.task.scan();
    expect(fixture.task.failure, isA<ValidationFailure>());
    expect(fixture.task.trial, isNull);
    expect(fixture.store.loadedChapterIds, isNotEmpty);
  });

  test('import rules refresh after reparse and clear on book switch', () async {
    await fixture.dispose();
    fixture = await _Fixture.open(
      parseOptions: const ParseOptions(rulePreset: 'biquge'),
    );
    await fixture.task.load();
    expect(fixture.task.importRules!.presetId, 'biquge');
    expect(fixture.task.importRules!.entries, isNotEmpty);
    final store = fixture.store;

    store.books['book'] = store.books['book']!.copyWith(
      parseOptions: const ParseOptions(rulePreset: 'english'),
    );
    await fixture.session.open('book');
    expect(fixture.task.importRules, isNull);
    await fixture.task.load();
    expect(fixture.task.importRules!.presetId, 'english');

    await fixture.session.open('other');
    expect(fixture.task.importRules, isNull);
    expect(fixture.task.rules, isEmpty);
    await fixture.task.load();
    expect(fixture.task.importRules!.presetId, 'auto');
    expect(fixture.task.importRules!.entries, isEmpty);
  });

  test('loaded book and global rules require explicit selection and a trial to save', () async {
    final bookRule = _advertisementRule(id: 'book-rule', pattern: '广告');
    final globalRule = _advertisementRule(
      id: 'global-rule',
      pattern: '宣传',
      scope: ProofreadingRuleScope.global,
      positiveExamples: const ['宣传文案'],
    );
    fixture.ruleStore.definitions.addAll({
      bookRule.id: bookRule,
      globalRule.id: globalRule,
    });

    await fixture.task.load();

    expect(fixture.task.rules.map((rule) => rule.id).toSet(), {
      bookRule.id,
      globalRule.id,
    });
    expect(fixture.task.selectedRuleIds, isEmpty);
    await fixture.task.scan();
    expect(fixture.task.failure, isA<ValidationFailure>());
    await fixture.task.saveRule(bookRule.id);
    expect(fixture.ruleStore.saved, isEmpty);

    fixture.task.setRuleSelected(bookRule.id, true);
    await fixture.task.saveRule(bookRule.id);
    expect(fixture.task.failure, isA<ValidationFailure>());
    expect(fixture.ruleStore.saved, isEmpty);

    await fixture.task.scan();
    expect(fixture.task.hasCurrentTrial, isTrue);
    expect(fixture.task.trial!.coverage.chapters, 2);
    await fixture.task.saveRule(bookRule.id);
    expect(fixture.task.phase, RuleWorkbenchPhase.ready);
    expect(fixture.task.isSaved(bookRule.id), isTrue);
    expect(fixture.ruleStore.saved.map((rule) => rule.id), [bookRule.id]);
  });

  test(
    'trial reads all lazy chapters and the unsaved CRLF and emoji draft',
    () async {
      final rule = _advertisementRule(id: 'ad', pattern: '广告');
      fixture.store.setBody('book', 'a', '😀开头\r\n广告草稿\r\n尾声');
      fixture.store.setBody('book', 'b', '另一章广告');
      await _loadSelected(fixture, [rule]);
      fixture.session.editBlockText('p1', '😀开头\r\n广告草稿\r\n尾声');
      final revision = fixture.session.saveSeq;

      await fixture.task.scan();

      expect(fixture.task.phase, RuleWorkbenchPhase.ready);
      expect(fixture.task.trial!.coverage.chapters, 2);
      expect(fixture.task.trial!.matchesByRuleId['ad'], 2);
      expect(fixture.store.loadedChapterIds, ['book/a', 'book/b']);
      expect(fixture.session.dirty, isTrue);
      expect(fixture.session.saveSeq, revision);
      expect(fixture.store.savedDirtyIds, isEmpty);
      final draftMatch = fixture.task.matches.firstWhere(
        (match) => match.match.chapterId == 'a',
      );
      expect(draftMatch.match.startUtf16, 6);
      expect(draftMatch.match.lineNumber, 2);
      expect(draftMatch.selectedText, '广告');
      expect(draftMatch.splitTitle, '广告草稿');
      expect(draftMatch.splitPrefix, '😀开头\r\n');
      expect(draftMatch.splitSuffix, '尾声');
    },
  );

  test(
    'saving a rule does not change book text, save sequence, or undo history',
    () async {
      final rule = _advertisementRule(id: 'ad', pattern: '广告');
      await _loadSelected(fixture, [rule]);
      final originalText = _text(fixture.session.activeChapter!, 'p1');
      final revision = fixture.session.saveSeq;

      await fixture.task.scan();
      await fixture.task.saveRule(rule.id);

      expect(fixture.ruleStore.saved, [rule]);
      expect(_text(fixture.session.activeChapter!, 'p1'), originalText);
      expect(fixture.session.saveSeq, revision);
      expect(fixture.session.dirty, isFalse);
      expect(fixture.session.canUndo, isFalse);
      expect(fixture.store.savedDirtyIds, isEmpty);
    },
  );

  test('a body edit preserves the saved rule but expires its trial', () async {
    final rule = _advertisementRule(id: 'ad', pattern: '广告');
    await _loadSelected(fixture, [rule]);
    await fixture.task.scan();
    await fixture.task.saveRule(rule.id);
    expect(fixture.task.hasCurrentTrial, isTrue);

    fixture.session.editBlockText('p1', '人工修改后的正文');

    expect(fixture.task.phase, RuleWorkbenchPhase.stale);
    expect(fixture.task.hasCurrentTrial, isFalse);
    expect(fixture.task.isSaved(rule.id), isTrue);
    expect(fixture.task.rules.single.id, rule.id);
  });

  test(
    'changing a definition, examples, scope, or selection expires the trial',
    () async {
      final original = _advertisementRule(id: 'ad', pattern: '广告');
      final cases =
          <({String name, void Function(_Fixture, ProofreadingRule) change})>[
            (
              name: 'definition',
              change: (current, rule) =>
                  current.task.putRule(_copyRule(rule, name: '改名规则')),
            ),
            (
              name: 'examples',
              change: (current, rule) => current.task.putRule(
                _copyRule(rule, positiveExamples: const ['广告横幅']),
              ),
            ),
            (
              name: 'scope',
              change: (current, rule) => current.task.putRule(
                _copyRule(rule, scope: ProofreadingRuleScope.global),
              ),
            ),
            (
              name: 'selection',
              change: (current, rule) =>
                  current.task.setRuleSelected(rule.id, false),
            ),
          ];

      for (final testCase in cases) {
        await fixture.dispose();
        fixture = await _Fixture.open();
        await _loadSelected(fixture, [original]);
        await fixture.task.scan();
        final oldMatchId = fixture.task.matches.first.id;
        final revision = fixture.session.saveSeq;

        testCase.change(fixture, original);

        expect(fixture.task.hasCurrentTrial, isFalse, reason: testCase.name);
        expect(fixture.task.matches, isEmpty, reason: testCase.name);
        await fixture.task.saveRule(original.id);
        expect(
          fixture.task.failure,
          isA<ValidationFailure>(),
          reason: testCase.name,
        );
        await fixture.task.applySelected({oldMatchId});
        expect(
          fixture.task.failure,
          isA<ValidationFailure>(),
          reason: testCase.name,
        );
        expect(fixture.session.saveSeq, revision, reason: testCase.name);
        expect(fixture.ruleStore.saved, isEmpty, reason: testCase.name);
      }
    },
  );

  test(
    'selected mixed split and deletion apply as one undoable command',
    () async {
      final splitRule = _chapterRule(id: 'chapter', pattern: '第三章');
      final removeRule = _advertisementRule(id: 'remove', pattern: '待删广告');
      final keepRule = _advertisementRule(id: 'keep', pattern: '保留广告');
      const source = '😀前文\r\n第三章 风雨\r\n待删广告\r\n保留广告\r\n尾声';
      await fixture.dispose();
      fixture = await _Fixture.open(firstText: source);
      await _loadSelected(fixture, [splitRule, removeRule, keepRule]);
      await fixture.task.scan();
      final splitId = _matchFor(fixture.task, '第三章').id;
      final removeId = _matchFor(fixture.task, '待删广告').id;
      final originalRevision = fixture.session.saveSeq;

      await fixture.task.applySelected({splitId, removeId});

      expect(fixture.task.lastAppliedCount, 2);
      expect(fixture.session.saveSeq, originalRevision + 1);
      expect(fixture.session.book!.chapters, hasLength(3));
      final appliedText = _bookText(fixture.session.book!);
      expect(appliedText, isNot(contains('待删广告')));
      expect(appliedText, contains('保留广告'));
      expect(fixture.session.canUndo, isTrue);
      await fixture.session.flush();
      expect(fixture.task.phase, RuleWorkbenchPhase.applied);

      await fixture.session.undo();
      expect(fixture.session.saveSeq, originalRevision + 2);
      expect(fixture.session.book!.chapters.map((chapter) => chapter.id), [
        'a',
        'b',
      ]);
      expect(_text(fixture.session.activeChapter!, 'p1'), source);
      expect(fixture.session.canUndo, isFalse);
      expect(fixture.session.canRedo, isTrue);

      await fixture.session.redo();
      expect(fixture.session.saveSeq, originalRevision + 3);
      expect(fixture.session.book!.chapters, hasLength(3));
      final redoneText = _bookText(fixture.session.book!);
      expect(redoneText, isNot(contains('待删广告')));
      expect(redoneText, contains('保留广告'));
    },
  );

  test(
    'mapped chapter title previews separately from the removed line',
    () async {
      const source = '😀前文\r\n【第二章 风雨】\r\n后文';
      await fixture.dispose();
      fixture = await _Fixture.open(firstText: source);
      final rule = ProofreadingRule.create(
        id: 'mapped',
        name: '映射标题',
        kind: ProofreadingRuleKind.chapter,
        source: ProofreadingRuleSource.user,
        bookId: 'book',
        target: ProofreadingRuleTarget.headingLine,
        mode: ProofreadingMatchMode.safeRegex,
        pattern: r'【第二章 ([^】]+)】',
        titleCaptureGroup: 1,
        caseSensitive: true,
        action: ProofreadingRuleAction.chapterCandidate,
        positiveExamples: const ['【第二章 风雨】'],
        negativeExamples: const ['普通正文'],
      );
      await _loadSelected(fixture, [rule]);
      final revision = fixture.session.saveSeq;

      await fixture.task.scan();

      expect(fixture.task.hasCurrentTrial, isTrue);
      final match = fixture.task.matches.single;
      expect(match.match.mappedTitle, '风雨');
      expect(match.splitTitle, '风雨');
      expect(match.splitSourceLine, '【第二章 风雨】');
      expect(match.splitPrefix, '😀前文\r\n');
      expect(match.splitSuffix, '后文');
      expect(fixture.session.saveSeq, revision);
      expect(_text(fixture.session.activeChapter!, 'p1'), source);

      await fixture.task.saveRule(rule.id);
      expect(fixture.task.isSaved(rule.id), isTrue);
      expect(_text(fixture.session.activeChapter!, 'p1'), source);
      expect(fixture.session.saveSeq, revision);

      await fixture.task.applySelected({match.id});
      expect(fixture.task.phase, RuleWorkbenchPhase.applied);
      expect(fixture.session.book!.chapters[1].title, '风雨');
      expect(_bookText(fixture.session.book!), isNot(contains('【第二章 风雨】')));
      await fixture.session.undo();
      expect(_text(fixture.session.activeChapter!, 'p1'), source);
    },
  );

  test('changing the title mapping expires a completed trial', () async {
    const source = '前文\n【第二章 风雨】\n后文';
    await fixture.dispose();
    fixture = await _Fixture.open(firstText: source);
    final original = ProofreadingRule.create(
      id: 'mapped',
      name: '映射标题',
      kind: ProofreadingRuleKind.chapter,
      source: ProofreadingRuleSource.user,
      bookId: 'book',
      target: ProofreadingRuleTarget.headingLine,
      mode: ProofreadingMatchMode.safeRegex,
      pattern: r'【第二章 ([^】]+)】',
      titleCaptureGroup: 1,
      caseSensitive: true,
      action: ProofreadingRuleAction.chapterCandidate,
      positiveExamples: const ['【第二章 风雨】'],
      negativeExamples: const ['普通正文'],
    );
    await _loadSelected(fixture, [original]);
    await fixture.task.scan();
    final oldMatchId = fixture.task.matches.single.id;
    fixture.task.putRule(_copyRule(original, titleCaptureGroup: 0));

    expect(fixture.task.hasCurrentTrial, isFalse);
    await fixture.task.saveRule(original.id);
    expect(fixture.task.failure, isA<ValidationFailure>());
    await fixture.task.applySelected({oldMatchId});
    expect(fixture.task.failure, isA<ValidationFailure>());
    expect(_text(fixture.session.activeChapter!, 'p1'), source);
    expect(fixture.ruleStore.saved, isEmpty);
  });

  test('number mapping preserves existing prefixes and applies composed chapter and volume titles', () async {
    for (final entry in [
      (2, '风雨', '第2章 风雨'),
      (2, '第二回 风雨', '第二回 风雨'),
      (1, '风雨', '第2卷 风雨'),
    ]) {
      const token = '二';
      final source = '前文\n【$token ${entry.$2}】\n后文';
      await fixture.dispose();
      fixture = await _Fixture.open(firstText: source);
      final rule = ProofreadingRule.create(
        id: 'numbered',
        name: '章号映射',
        kind: ProofreadingRuleKind.chapter,
        headingLevel: entry.$1,
        source: ProofreadingRuleSource.user,
        bookId: 'book',
        target: ProofreadingRuleTarget.headingLine,
        mode: ProofreadingMatchMode.safeRegex,
        pattern: r'【(二) ([^】]+)】',
        titleCaptureGroup: 2,
        numberCaptureGroup: 1,
        caseSensitive: true,
        action: ProofreadingRuleAction.chapterCandidate,
        positiveExamples: ['【$token ${entry.$2}】'],
        negativeExamples: const [],
      );
      await _loadSelected(fixture, [rule]);
      await fixture.task.scan();
      final preview = fixture.task.matches.single;
      expect(preview.match.numberText, token);
      expect(preview.match.mappedNumber, 2);
      expect(preview.match.mappedTitle, entry.$2);
      expect(preview.splitTitle, entry.$3);
      expect(preview.splitSourceLine, '【$token ${entry.$2}】');
      final revision = fixture.session.saveSeq;
      await fixture.task.saveRule(rule.id);
      expect(fixture.session.saveSeq, revision);
      await fixture.task.applySelected({preview.id});
      expect(fixture.task.phase, RuleWorkbenchPhase.applied);
      expect(
        fixture.session.book!.chapters.any(
          (chapter) => chapter.title == entry.$3 && chapter.level == entry.$1,
        ),
        isTrue,
      );
      expect(
        _bookText(fixture.session.book!),
        isNot(contains('【$token ${entry.$2}】')),
      );
      await fixture.session.undo();
      expect(_text(fixture.session.activeChapter!, 'p1'), source);
    }
  });

  for (final nested in [false, true]) {
    test(
      'volume preview collects only continuous siblings (nested=$nested)',
      () async {
        const sourceText = '前文\n第二卷 风雨\n卷前正文';
        final parent = nested ? 'old-volume' : null;
        await fixture.dispose();
        fixture = await _Fixture.open(
          chapters: [
            if (nested)
              const Chapter(
                id: 'old-volume',
                bookId: 'book',
                title: '第一卷',
                level: 1,
              ),
            Chapter(
              id: 'a',
              bookId: 'book',
              title: '原章',
              parentId: parent,
              blocks: const [
                TextBlock(id: 'p1', text: sourceText),
                ImageBlock(id: 'image', assetId: 'asset'),
                FootnoteBlock(id: 'note', text: '卷前脚注'),
              ],
            ),
            Chapter(id: 'b', bookId: 'book', title: '后续第一章', parentId: parent),
            Chapter(id: 'c', bookId: 'book', title: '后续第二章', parentId: parent),
            if (nested)
              const Chapter(id: 'stop', bookId: 'book', title: '不同归属')
            else
              const Chapter(id: 'stop', bookId: 'book', title: '下一卷', level: 1),
            const Chapter(id: 'after-stop', bookId: 'book', title: '边界之后'),
          ],
        );
        final rule = _volumeRule();
        await _loadSelected(fixture, [rule]);
        final revision = fixture.session.saveSeq;
        await fixture.task.scan();

        expect(fixture.task.phase, RuleWorkbenchPhase.ready);
        final preview = fixture.task.matches.single;
        expect(preview.match.headingLevel, 1);
        expect(preview.splitTitle, '第二卷 风雨');
        expect(preview.splitSourceLine, '第二卷 风雨');
        expect(preview.splitPrefix, '前文\n');
        expect(preview.splitSuffix, '卷前正文');
        expect(preview.followingBlocks.map((block) => block.id), [
          'image',
          'note',
        ]);
        expect(preview.followingChapters.map((chapter) => chapter.id), [
          'b',
          'c',
        ]);
        expect(
          () => preview.followingChapters.add(
            fixture.session.book!.chapters.first,
          ),
          throwsUnsupportedError,
        );
        expect(fixture.session.saveSeq, revision);
        expect(fixture.session.dirty, isFalse);
        expect(fixture.ruleStore.saved, isEmpty);
      },
    );
  }

  test(
    'changing heading level expires the trial and rescan uses the new level',
    () async {
      await fixture.dispose();
      fixture = await _Fixture.open(firstText: '前文\n第二卷 风雨\n后文');
      final rule = _volumeRule();
      await _loadSelected(fixture, [rule]);
      await fixture.task.scan();
      final oldId = fixture.task.matches.single.id;
      fixture.task.putRule(_copyRule(rule, headingLevel: 2));

      expect(fixture.task.hasCurrentTrial, isFalse);
      await fixture.task.applySelected({oldId});
      expect(fixture.task.failure, isA<ValidationFailure>());
      expect(fixture.session.dirty, isFalse);
      await fixture.task.scan();
      expect(fixture.task.matches.single.match.headingLevel, 2);
      expect(fixture.task.matches.single.followingChapters, isEmpty);
    },
  );

  test('advertisement candidates remain review-only', () async {
    final candidate = _advertisementRule(
      id: 'candidate',
      pattern: '广告',
      action: ProofreadingRuleAction.advertisementCandidate,
    );
    await _loadSelected(fixture, [candidate]);
    await fixture.task.scan();
    final match = fixture.task.matches.first;
    final source = _text(fixture.session.activeChapter!, 'p1');
    final revision = fixture.session.saveSeq;

    expect(match.canApply, isFalse);
    await fixture.task.applySelected({match.id});

    expect(fixture.task.failure, isA<ValidationFailure>());
    expect(_text(fixture.session.activeChapter!, 'p1'), source);
    expect(fixture.session.saveSeq, revision);
    expect(fixture.session.canUndo, isFalse);
  });

  test(
    'same-line chapter and deletion conflict rejects the whole selection',
    () async {
      const source = '前文\r\n第三章广告 风雨\r\n尾声';
      await fixture.dispose();
      fixture = await _Fixture.open(firstText: source);
      await _loadSelected(fixture, [
        _chapterRule(id: 'chapter', pattern: '第三章'),
        _advertisementRule(id: 'remove', pattern: '广告'),
      ]);
      await fixture.task.scan();
      expect(fixture.task.trial!.conflictSamples, isNotEmpty);
      final ids = fixture.task.matches.map((match) => match.id).toSet();
      final revision = fixture.session.saveSeq;

      await fixture.task.applySelected(ids);

      expect(fixture.task.failure, isA<ValidationFailure>());
      expect(_text(fixture.session.activeChapter!, 'p1'), source);
      expect(fixture.session.book!.chapters, hasLength(2));
      expect(fixture.session.saveSeq, revision);
      expect(fixture.session.dirty, isFalse);
      expect(fixture.session.canUndo, isFalse);
      expect(fixture.store.savedDirtyIds, isEmpty);
    },
  );

  test(
    'cancelling a delayed rule read does not publish loaded rules',
    () async {
      final rule = _advertisementRule(id: 'ad', pattern: '广告');
      fixture.ruleStore.definitions[rule.id] = rule;
      fixture.ruleStore
        ..loadStarted = Completer<void>()
        ..loadGate = Completer<void>();
      final loading = fixture.task.load();
      await fixture.ruleStore.loadStarted!.future;

      fixture.task.cancel();
      fixture.ruleStore.loadGate!.complete();
      await loading;

      expect(fixture.task.phase, RuleWorkbenchPhase.cancelled);
      expect(fixture.task.rules, isEmpty);
      expect(fixture.task.selectedRuleIds, isEmpty);
    },
  );

  test('cancelling while lazily reading a chapter leaves no trial', () async {
    await _loadSelected(fixture, [_advertisementRule(id: 'ad', pattern: '广告')]);
    fixture.store
      ..gatedChapterId = 'b'
      ..chapterReadStarted = Completer<void>()
      ..chapterReadGate = Completer<void>();
    final scanning = fixture.task.scan();
    await fixture.store.chapterReadStarted!.future;

    fixture.task.cancel();
    fixture.store.chapterReadGate!.complete();
    await scanning;

    expect(fixture.task.phase, RuleWorkbenchPhase.cancelled);
    expect(fixture.task.trial, isNull);
    expect(fixture.task.matches, isEmpty);
    expect(fixture.task.hasCurrentTrial, isFalse);
    expect(fixture.store.savedDirtyIds, isEmpty);
  });

  test('a late worker result after cancellation is never published', () async {
    await _loadSelected(fixture, [_advertisementRule(id: 'ad', pattern: '广告')]);
    fixture.jobs
      ..runStarted = Completer<void>()
      ..runGate = Completer<void>();
    final scanning = fixture.task.scan();
    await fixture.jobs.runStarted!.future;

    fixture.task.cancel();
    fixture.jobs.runGate!.complete();
    await scanning;

    expect(fixture.jobs.cancelCount, 1);
    expect(fixture.task.phase, RuleWorkbenchPhase.cancelled);
    expect(fixture.task.trial, isNull);
    expect(fixture.task.matches, isEmpty);
    expect(fixture.task.hasCurrentTrial, isFalse);
    expect(fixture.session.canUndo, isFalse);
  });

  test(
    'switching books during lazy read cannot publish or touch the new book',
    () async {
      await _loadSelected(fixture, [
        _advertisementRule(id: 'ad', pattern: '广告'),
      ]);
      fixture.store
        ..gatedChapterId = 'b'
        ..chapterReadStarted = Completer<void>()
        ..chapterReadGate = Completer<void>();
      final scanning = fixture.task.scan();
      await fixture.store.chapterReadStarted!.future;

      await fixture.session.open('other');
      fixture.store.chapterReadGate!.complete();
      await scanning;

      expect(fixture.session.book!.id, 'other');
      expect(_text(fixture.session.activeChapter!, 'other-p1'), '另一本书的正文');
      expect(fixture.task.phase, RuleWorkbenchPhase.stale);
      expect(fixture.task.trial, isNull);
      expect(fixture.task.matches, isEmpty);
      expect(fixture.store.savedDirtyIds, isEmpty);
    },
  );

  test(
    'closing during lazy read prevents a late trial from publishing',
    () async {
      await _loadSelected(fixture, [
        _advertisementRule(id: 'ad', pattern: '广告'),
      ]);
      fixture.store
        ..gatedChapterId = 'b'
        ..chapterReadStarted = Completer<void>()
        ..chapterReadGate = Completer<void>();
      final scanning = fixture.task.scan();
      await fixture.store.chapterReadStarted!.future;

      await fixture.session.close();
      fixture.sessionClosed = true;
      fixture.store.chapterReadGate!.complete();
      await scanning;

      expect(fixture.task.phase, RuleWorkbenchPhase.cancelled);
      expect(fixture.task.trial, isNull);
      expect(fixture.task.matches, isEmpty);
      expect(fixture.store.savedDirtyIds, isEmpty);
    },
  );

  test(
    'read failure and scan budget exhaustion publish no partial matches',
    () async {
      await _loadSelected(fixture, [
        _advertisementRule(id: 'ad', pattern: '广告'),
      ]);
      fixture.store.missingChapterIds.add('b');

      await fixture.task.scan();

      expect(fixture.task.phase, RuleWorkbenchPhase.failed);
      expect(fixture.task.failure, isA<ValidationFailure>());
      expect(fixture.task.trial, isNull);
      expect(fixture.task.matches, isEmpty);

      await fixture.dispose();
      fixture = await _Fixture.open(firstText: List.filled(32769, 'x').join());
      await _loadSelected(fixture, [_advertisementRule(id: 'x', pattern: 'x')]);

      await fixture.task.scan();

      expect(fixture.task.phase, RuleWorkbenchPhase.failed);
      expect(fixture.task.failure, isA<ValidationFailure>());
      expect(fixture.task.trial, isNull);
      expect(fixture.task.matches, isEmpty);
      expect(fixture.session.canUndo, isFalse);
    },
  );

  test(
    'delayed rule save rechecks currency and does not persist a stale draft',
    () async {
      await fixture.task.load();
      final draft = _advertisementRule(id: 'new-ad', pattern: '广告');
      fixture.task.putRule(draft);
      await fixture.task.scan();
      fixture.ruleStore
        ..saveStarted = Completer<void>()
        ..saveGate = Completer<void>();
      final saving = fixture.task.saveRule(draft.id);
      await fixture.ruleStore.saveStarted!.future;

      fixture.session.editBlockText('p1', '保存期间发生正文编辑');
      fixture.ruleStore.saveGate!.complete();
      await saving;

      expect(fixture.task.phase, RuleWorkbenchPhase.stale);
      expect(fixture.ruleStore.definitions.containsKey(draft.id), isFalse);
      expect(fixture.ruleStore.saved, isEmpty);
    },
  );

  test(
    'delayed rule save guard also prevents persistence after cancellation',
    () async {
      await fixture.task.load();
      final draft = _advertisementRule(id: 'new-ad', pattern: '广告');
      fixture.task.putRule(draft);
      await fixture.task.scan();
      fixture.ruleStore
        ..saveStarted = Completer<void>()
        ..saveGate = Completer<void>();
      final saving = fixture.task.saveRule(draft.id);
      await fixture.ruleStore.saveStarted!.future;

      fixture.task.cancel();
      fixture.ruleStore.saveGate!.complete();
      await saving;

      expect(fixture.ruleStore.definitions.containsKey(draft.id), isFalse);
      expect(fixture.ruleStore.saved, isEmpty);
      expect(fixture.task.phase, RuleWorkbenchPhase.cancelled);
      expect(fixture.task.failure, isNull);
    },
  );

  test(
    'cancelling after save commit preserves the saved rule and phase',
    () async {
      await fixture.task.load();
      final draft = _advertisementRule(id: 'new-ad', pattern: '广告');
      fixture.task.putRule(draft);
      await fixture.task.scan();
      fixture.ruleStore
        ..saveCommitted = Completer<void>()
        ..saveCommittedGate = Completer<void>();
      final saving = fixture.task.saveRule(draft.id);
      await fixture.ruleStore.saveCommitted!.future;

      expect(fixture.ruleStore.definitions[draft.id], same(draft));
      fixture.task.cancel();
      fixture.ruleStore.saveCommittedGate!.complete();
      await saving;

      expect(fixture.ruleStore.definitions[draft.id], same(draft));
      expect(fixture.ruleStore.saved, [draft]);
      expect(fixture.task.phase, RuleWorkbenchPhase.saved);
      expect(fixture.task.failure, isNull);
    },
  );

  test(
    'external definition changes prevent applying or overwriting stored rules',
    () async {
      final stored = _advertisementRule(id: 'ad', pattern: '广告');
      await _loadSelected(fixture, [stored]);
      await fixture.task.scan();
      final matchId = fixture.task.matches.first.id;
      final revision = fixture.session.saveSeq;
      final external = _copyRule(
        stored,
        pattern: '推广',
        positiveExamples: const ['推广内容'],
      );
      fixture.ruleStore.definitions[stored.id] = external;

      await fixture.task.applySelected({matchId});

      expect(fixture.task.failure, isA<ValidationFailure>());
      expect(_text(fixture.session.activeChapter!, 'p1'), '😀广告和广告。尾文');
      expect(fixture.session.saveSeq, revision);
      expect(fixture.session.canUndo, isFalse);

      await fixture.dispose();
      fixture = await _Fixture.open();
      await _loadSelected(fixture, [stored]);
      fixture.task.putRule(_copyRule(stored, name: '本地编辑'));
      await fixture.task.scan();
      fixture.ruleStore.definitions[stored.id] = external;

      await fixture.task.saveRule(stored.id);

      expect(fixture.task.failure, isA<ValidationFailure>());
      expect(fixture.ruleStore.saved, isEmpty);
      expect(fixture.ruleStore.definitions[stored.id], same(external));
    },
  );

  test(
    'apply rechecks stored definitions after the session worker finishes',
    () async {
      final stored = _advertisementRule(id: 'ad', pattern: '广告');
      await _loadSelected(fixture, [stored]);
      await fixture.task.scan();
      final matchId = fixture.task.matches.first.id;
      final originalText = _text(fixture.session.activeChapter!, 'p1');
      final originalRevision = fixture.session.saveSeq;
      fixture.jobs
        ..runStarted = Completer<void>()
        ..runGate = Completer<void>();

      final applying = fixture.task.applySelected({matchId});
      await fixture.jobs.runStarted!.future;
      final external = _copyRule(
        stored,
        pattern: '推广',
        positiveExamples: const ['推广内容'],
      );
      fixture.ruleStore.definitions[stored.id] = external;
      fixture.jobs.runGate!.complete();
      await applying;

      expect(fixture.ruleStore.runIfCurrentCalls, 1);
      expect(
        fixture.ruleStore.lastRunIfCurrentExpectedRules?.keys,
        contains(stored.id),
      );
      expect(fixture.task.failure, isA<ValidationFailure>());
      expect(_text(fixture.session.activeChapter!, 'p1'), originalText);
      expect(fixture.session.book!.chapters, hasLength(2));
      expect(fixture.session.saveSeq, originalRevision);
      expect(fixture.session.dirty, isFalse);
      expect(fixture.session.canUndo, isFalse);
      expect(fixture.store.savedDirtyIds, isEmpty);
    },
  );

  test(
    'save CAS rejects an external same-id edit during storage delay',
    () async {
      final stored = _advertisementRule(id: 'ad', pattern: '广告');
      await _loadSelected(fixture, [stored]);
      fixture.task.putRule(_copyRule(stored, name: '本地编辑'));
      await fixture.task.scan();
      fixture.ruleStore
        ..saveStarted = Completer<void>()
        ..saveGate = Completer<void>();
      final saving = fixture.task.saveRule(stored.id);
      await fixture.ruleStore.saveStarted!.future;
      final external = _copyRule(
        stored,
        pattern: '推广',
        positiveExamples: const ['推广内容'],
      );
      fixture.ruleStore.definitions[stored.id] = external;
      fixture.ruleStore.saveGate!.complete();
      await saving;

      expect(
        fixture.ruleStore.lastSaveExpectedRules?[stored.id]?.pattern,
        '广告',
      );
      expect(fixture.ruleStore.saved, isEmpty);
      expect(fixture.ruleStore.definitions[stored.id], same(external));
      expect(fixture.task.failure, isA<ValidationFailure>());
      expect(fixture.task.phase, isNot(RuleWorkbenchPhase.idle));
    },
  );

  test(
    'cancelled delayed delete cannot remove the rule or settle to idle',
    () async {
      final stored = _advertisementRule(id: 'ad', pattern: '广告');
      await _loadSelected(fixture, [stored]);
      fixture.ruleStore
        ..deleteStarted = Completer<void>()
        ..deleteGate = Completer<void>();
      final deleting = fixture.task.deleteRule(stored.id);
      await fixture.ruleStore.deleteStarted!.future;

      fixture.task.cancel();
      fixture.ruleStore.deleteGate!.complete();
      await deleting;

      expect(
        fixture.ruleStore.lastDeleteExpectedRules?[stored.id]?.id,
        stored.id,
      );
      expect(fixture.ruleStore.definitions[stored.id], same(stored));
      expect(fixture.ruleStore.deleted, isEmpty);
      expect(fixture.task.rules.single.id, stored.id);
      expect(fixture.task.phase, RuleWorkbenchPhase.cancelled);
      expect(fixture.task.failure, isNull);
    },
  );

  test('cancelling after delete commit preserves deleted phase', () async {
    final stored = _advertisementRule(id: 'ad', pattern: '广告');
    await _loadSelected(fixture, [stored]);
    fixture.ruleStore
      ..deleteCommitted = Completer<void>()
      ..deleteCommittedGate = Completer<void>();
    final deleting = fixture.task.deleteRule(stored.id);
    await fixture.ruleStore.deleteCommitted!.future;

    expect(fixture.ruleStore.definitions.containsKey(stored.id), isFalse);
    fixture.task.cancel();
    fixture.ruleStore.deleteCommittedGate!.complete();
    await deleting;

    expect(fixture.ruleStore.definitions.containsKey(stored.id), isFalse);
    expect(fixture.ruleStore.deleted, [stored.id]);
    expect(fixture.task.rules, isEmpty);
    expect(fixture.task.phase, RuleWorkbenchPhase.deleted);
    expect(fixture.task.failure, isNull);
  });

  test('external same-id edit during delete delay is retained', () async {
    final stored = _advertisementRule(id: 'ad', pattern: '广告');
    await _loadSelected(fixture, [stored]);
    fixture.ruleStore
      ..deleteStarted = Completer<void>()
      ..deleteGate = Completer<void>();
    final deleting = fixture.task.deleteRule(stored.id);
    await fixture.ruleStore.deleteStarted!.future;
    final external = _copyRule(
      stored,
      pattern: '推广',
      positiveExamples: const ['推广内容'],
    );
    fixture.ruleStore.definitions[stored.id] = external;
    fixture.ruleStore.deleteGate!.complete();
    await deleting;

    expect(
      fixture.ruleStore.lastDeleteExpectedRules?[stored.id]?.pattern,
      '广告',
    );
    expect(fixture.ruleStore.definitions[stored.id], same(external));
    expect(fixture.ruleStore.deleted, isEmpty);
    expect(fixture.task.rules.single.id, stored.id);
    expect(fixture.task.phase, isNot(RuleWorkbenchPhase.idle));
  });

  test(
    'book switch during delete clears old rules and protects new-book rules',
    () async {
      final oldRule = _advertisementRule(id: 'old-ad', pattern: '广告');
      final otherRule = _advertisementRule(
        id: 'other-rule',
        pattern: '正文',
        bookId: 'other',
      );
      fixture.ruleStore.definitions.addAll({
        oldRule.id: oldRule,
        otherRule.id: otherRule,
      });
      await _loadSelected(fixture, [oldRule]);
      fixture.ruleStore
        ..deleteStarted = Completer<void>()
        ..deleteGate = Completer<void>();
      final deleting = fixture.task.deleteRule(oldRule.id);
      await fixture.ruleStore.deleteStarted!.future;

      await fixture.session.open('other');
      expect(fixture.task.rules, isEmpty);
      expect(fixture.task.selectedRuleIds, isEmpty);
      expect(fixture.task.isLoaded, isFalse);
      fixture.ruleStore.deleteGate!.complete();
      await deleting;

      expect(fixture.ruleStore.definitions[oldRule.id], same(oldRule));
      expect(fixture.ruleStore.definitions[otherRule.id], same(otherRule));
      expect(fixture.ruleStore.deleted, isEmpty);
      expect(fixture.task.phase, isNot(RuleWorkbenchPhase.idle));
      await fixture.task.load();
      expect(fixture.task.isLoaded, isTrue);
      expect(fixture.task.rules.map((rule) => rule.id), [otherRule.id]);
      expect(fixture.task.selectedRuleIds, isEmpty);

      await fixture.task.scan();
      expect(fixture.task.failure, isA<ValidationFailure>());
      expect(fixture.task.trial, isNull);
      expect(fixture.task.matches, isEmpty);
      fixture.task.setRuleSelected(otherRule.id, true);
      await fixture.task.scan();
      expect(fixture.task.trial!.executedRuleIds, [otherRule.id]);
    },
  );

  test(
    'book switch during apply clears old rules before a new trial can start',
    () async {
      final oldRule = _advertisementRule(id: 'old-ad', pattern: '广告');
      final otherRule = _advertisementRule(
        id: 'other-rule',
        pattern: '正文',
        bookId: 'other',
      );
      fixture.ruleStore.definitions.addAll({
        oldRule.id: oldRule,
        otherRule.id: otherRule,
      });
      await _loadSelected(fixture, [oldRule]);
      await fixture.task.scan();
      final matchId = fixture.task.matches.first.id;
      fixture.jobs
        ..runStarted = Completer<void>()
        ..runGate = Completer<void>();
      final applying = fixture.task.applySelected({matchId});
      await fixture.jobs.runStarted!.future;

      await fixture.session.open('other');
      expect(fixture.task.rules, isEmpty);
      expect(fixture.task.selectedRuleIds, isEmpty);
      expect(fixture.task.isLoaded, isFalse);
      fixture.jobs.runGate!.complete();
      await applying;

      expect(fixture.session.book!.id, 'other');
      expect(_text(fixture.session.activeChapter!, 'other-p1'), '另一本书的正文');
      expect(fixture.task.phase, RuleWorkbenchPhase.stale);
      expect(fixture.task.trial, isNull);
      expect(fixture.task.matches, isEmpty);
      expect(fixture.store.savedDirtyIds, isEmpty);
      expect(fixture.session.canUndo, isFalse);
      await fixture.task.load();
      expect(fixture.task.isLoaded, isTrue);
      expect(fixture.task.rules.map((rule) => rule.id), [otherRule.id]);
      expect(fixture.task.selectedRuleIds, isEmpty);

      await fixture.task.scan();
      expect(fixture.task.failure, isA<ValidationFailure>());
      expect(fixture.task.trial, isNull);
      expect(fixture.task.matches, isEmpty);
      fixture.task.setRuleSelected(otherRule.id, true);
      await fixture.task.scan();
      expect(fixture.task.trial!.executedRuleIds, [otherRule.id]);
    },
  );
}

Future<void> _loadSelected(
  _Fixture fixture,
  List<ProofreadingRule> rules,
) async {
  fixture.ruleStore.definitions.addEntries(
    rules.map((rule) => MapEntry(rule.id, rule)),
  );
  await fixture.task.load();
  for (final rule in rules) {
    fixture.task.setRuleSelected(rule.id, true);
  }
}

ProofreadingRule _advertisementRule({
  required String id,
  required String pattern,
  ProofreadingRuleAction action = ProofreadingRuleAction.exactDeletion,
  ProofreadingRuleScope scope = ProofreadingRuleScope.book,
  String bookId = 'book',
  String name = '广告规则',
  List<String>? positiveExamples,
  List<String> negativeExamples = const ['普通文本'],
}) => ProofreadingRule.create(
  id: id,
  name: name,
  kind: ProofreadingRuleKind.advertisement,
  source: ProofreadingRuleSource.user,
  scope: scope,
  globalScopeConfirmed: scope == ProofreadingRuleScope.global,
  bookId: bookId,
  target: ProofreadingRuleTarget.bodyLine,
  mode: ProofreadingMatchMode.literal,
  pattern: pattern,
  caseSensitive: true,
  action: action,
  positiveExamples: positiveExamples ?? [pattern],
  negativeExamples: negativeExamples,
);

ProofreadingRule _chapterRule({required String id, required String pattern}) =>
    ProofreadingRule.create(
      id: id,
      name: '章节标题规则',
      kind: ProofreadingRuleKind.chapter,
      source: ProofreadingRuleSource.user,
      bookId: 'book',
      target: ProofreadingRuleTarget.headingLine,
      mode: ProofreadingMatchMode.literal,
      pattern: pattern,
      caseSensitive: true,
      action: ProofreadingRuleAction.chapterCandidate,
      positiveExamples: const ['第三章 风雨'],
      negativeExamples: const ['普通正文'],
    );

ProofreadingRule _volumeRule() => ProofreadingRule.create(
  id: 'volume',
  name: '卷规则',
  kind: ProofreadingRuleKind.chapter,
  headingLevel: 1,
  source: ProofreadingRuleSource.user,
  bookId: 'book',
  target: ProofreadingRuleTarget.headingLine,
  mode: ProofreadingMatchMode.literal,
  pattern: '第二卷',
  caseSensitive: true,
  action: ProofreadingRuleAction.chapterCandidate,
  positiveExamples: const ['第二卷 风雨'],
  negativeExamples: const ['普通正文'],
);

ProofreadingRule _copyRule(
  ProofreadingRule source, {
  String? name,
  String? pattern,
  ProofreadingRuleScope? scope,
  List<String>? positiveExamples,
  List<String>? negativeExamples,
  int? titleCaptureGroup,
  int? headingLevel,
}) {
  final nextScope = scope ?? source.scope;
  return ProofreadingRule.create(
    id: source.id,
    name: name ?? source.name,
    kind: source.kind,
    headingLevel: headingLevel ?? source.headingLevel,
    enabled: source.enabled,
    source: source.source,
    scope: nextScope,
    globalScopeConfirmed: nextScope == ProofreadingRuleScope.global,
    bookId: source.bookId,
    target: source.target,
    mode: source.mode,
    pattern: pattern ?? source.pattern,
    titleCaptureGroup: titleCaptureGroup ?? source.titleCaptureGroup,
    numberCaptureGroup: source.numberCaptureGroup,
    caseSensitive: source.caseSensitive,
    action: source.action,
    priority: source.priority,
    positiveExamples: positiveExamples ?? source.positiveExamples,
    negativeExamples: negativeExamples ?? source.negativeExamples,
  );
}

RuleWorkbenchMatch _matchFor(RuleWorkbenchTask task, String text) =>
    task.matches.singleWhere((match) => match.selectedText == text);

String _text(Chapter chapter, String blockId) => (chapter.blocks.singleWhere(
  (block) => block.id == blockId,
) as TextBlock).text;

String _bookText(Book book) => book.chapters
    .expand((chapter) => chapter.blocks.whereType<TextBlock>())
    .map((block) => block.text)
    .join();

class _Fixture {
  _Fixture._({
    required this.store,
    required this.ruleStore,
    required this.jobs,
    required this.session,
    required this.task,
  });

  static Future<_Fixture> open({
    String firstText = '😀广告和广告。尾文',
    String secondText = '另一章正文',
    List<Chapter>? chapters,
    ParseOptions parseOptions = const ParseOptions(),
  }) async {
    final store = _FakeEditorBookStore(
      firstText: firstText,
      secondText: secondText,
      chapters: chapters,
      parseOptions: parseOptions,
    );
    final ruleStore = _FakeProofreadingRuleStore();
    final jobs = _FakeBackgroundJobs();
    final session = EditorSession.withStore(
      store: store,
      jobs: jobs,
      debounce: const Duration(milliseconds: 800),
    );
    await session.open('book');
    final task = RuleWorkbenchTask(
      session: session,
      store: ruleStore,
      jobs: jobs,
    );
    return _Fixture._(
      store: store,
      ruleStore: ruleStore,
      jobs: jobs,
      session: session,
      task: task,
    );
  }

  final _FakeEditorBookStore store;
  final _FakeProofreadingRuleStore ruleStore;
  final _FakeBackgroundJobs jobs;
  final EditorSession session;
  final RuleWorkbenchTask task;
  bool sessionClosed = false;
  bool _disposed = false;

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    task.dispose();
    if (!sessionClosed) session.dispose();
  }
}

class _FakeEditorBookStore implements EditorBookStore {
  _FakeEditorBookStore({
    required String firstText,
    required String secondText,
    List<Chapter>? chapters,
    ParseOptions parseOptions = const ParseOptions(),
  }) {
    final now = DateTime.utc(2026, 11, 6);
    books['book'] = Book(
      id: 'book',
      meta: BookMeta(title: '测试书'),
      chapters: const [
        Chapter(id: 'a', bookId: 'book', title: '第一章', order: 0),
        Chapter(id: 'b', bookId: 'book', title: '第二章', order: 1),
      ],
      createdAt: now,
      updatedAt: now,
      parseOptions: parseOptions,
    );
    bodies[('book', 'a')] = Chapter(
      id: 'a',
      bookId: 'book',
      title: '第一章',
      order: 0,
      blocks: [TextBlock(id: 'p1', text: firstText)],
    );
    bodies[('book', 'b')] = Chapter(
      id: 'b',
      bookId: 'book',
      title: '第二章',
      order: 1,
      blocks: [TextBlock(id: 'p2', text: secondText)],
    );
    if (chapters != null) {
      books['book'] = books['book']!.copyWith(
        chapters: [
          for (final chapter in chapters) chapter.copyWith(blocks: const []),
        ],
      );
      for (final chapter in chapters) {
        bodies[('book', chapter.id)] = chapter;
      }
    }
    books['other'] = Book(
      id: 'other',
      meta: BookMeta(title: '另一本书'),
      chapters: const [Chapter(id: 'other-a', bookId: 'other', title: '正文')],
      createdAt: now,
      updatedAt: now,
    );
    bodies[('other', 'other-a')] = const Chapter(
      id: 'other-a',
      bookId: 'other',
      title: '正文',
      blocks: [TextBlock(id: 'other-p1', text: '另一本书的正文')],
    );
  }

  final Map<String, Book> books = {};
  final Map<(String, String), Chapter> bodies = {};
  final List<String> loadedChapterIds = [];
  final List<Set<String>> savedDirtyIds = [];
  final Set<String> missingChapterIds = {};
  String? gatedChapterId;
  Completer<void>? chapterReadStarted;
  Completer<void>? chapterReadGate;

  void setBody(String bookId, String chapterId, String text) {
    final old = bodies[(bookId, chapterId)]!;
    bodies[(bookId, chapterId)] = old.copyWith(
      blocks: [TextBlock(id: chapterId == 'a' ? 'p1' : 'p2', text: text)],
    );
  }

  @override
  Future<Book?> loadBook(String bookId) async => books[bookId];

  @override
  Future<Chapter?> loadChapter(String bookId, String chapterId) async {
    loadedChapterIds.add('$bookId/$chapterId');
    if (chapterId == gatedChapterId && chapterReadGate != null) {
      final started = chapterReadStarted;
      if (started != null && !started.isCompleted) started.complete();
      await chapterReadGate!.future;
    }
    if (missingChapterIds.contains(chapterId)) return null;
    return bodies[(bookId, chapterId)];
  }

  @override
  Future<Book> saveBook(
    Book source, {
    required int expectedRevision,
    required Set<String> dirtyChapterIds,
    Set<String> deletedChapterIds = const <String>{},
  }) async {
    final current = books[source.id];
    if (current == null || current.revision != expectedRevision) {
      throw const StorageFailure('书稿修订发生变化。');
    }
    savedDirtyIds.add(Set<String>.of(dirtyChapterIds));
    for (final chapter in source.chapters) {
      if (dirtyChapterIds.contains(chapter.id)) {
        bodies[(source.id, chapter.id)] = chapter;
      }
    }
    final saved = source.copyWith(
      chapters: [
        for (final chapter in source.chapters)
          chapter.copyWith(blocks: const <Block>[]),
      ],
      revision: expectedRevision + 1,
    );
    books[source.id] = saved;
    return saved;
  }
}

class _FakeProofreadingRuleStore implements ProofreadingRuleStore {
  final Map<String, ProofreadingRule> definitions = {};
  final List<ProofreadingRule> saved = [];
  final List<String> deleted = [];
  int runIfCurrentCalls = 0;
  Map<String, ProofreadingRule?>? lastSaveExpectedRules;
  Map<String, ProofreadingRule?>? lastDeleteExpectedRules;
  Map<String, ProofreadingRule?>? lastRunIfCurrentExpectedRules;
  Completer<void>? loadStarted;
  Completer<void>? loadGate;
  Completer<void>? saveStarted;
  Completer<void>? saveGate;
  Completer<void>? saveCommitted;
  Completer<void>? saveCommittedGate;
  Completer<void>? deleteStarted;
  Completer<void>? deleteGate;
  Completer<void>? deleteCommitted;
  Completer<void>? deleteCommittedGate;

  @override
  Future<List<ProofreadingRule>> loadForBook(String bookId) async {
    final started = loadStarted;
    if (started != null && !started.isCompleted) started.complete();
    final gate = loadGate;
    if (gate != null) await gate.future;
    return [
      for (final rule in definitions.values)
        if (rule.appliesToBook(bookId)) rule,
    ];
  }

  @override
  Future<RuleMergeResult> mergeMissing(
    List<ProofreadingRule> rules, {
    bool Function()? isCurrent,
  }) async {
    final added = <String>[];
    final skipped = <String>[];
    for (final rule in rules) {
      if (definitions.containsKey(rule.id)) {
        skipped.add(rule.id);
      } else {
        definitions[rule.id] = rule;
        saved.add(rule);
        added.add(rule.id);
      }
    }
    return RuleMergeResult(addedIds: added, skippedIds: skipped);
  }

  @override
  Future<void> save(
    ProofreadingRule rule, {
    bool Function()? isCurrent,
    Map<String, ProofreadingRule?>? expectedRules,
  }) async {
    lastSaveExpectedRules = expectedRules == null
        ? null
        : Map<String, ProofreadingRule?>.of(expectedRules);
    final started = saveStarted;
    if (started != null && !started.isCompleted) started.complete();
    final gate = saveGate;
    if (gate != null) await gate.future;
    if (expectedRules != null && !_matchesExpectedRules(expectedRules)) {
      throw const ValidationFailure('规则定义已变化。');
    }
    if (isCurrent != null && !isCurrent()) {
      throw const ValidationFailure('当前规则试跑已失效。');
    }
    definitions[rule.id] = rule;
    saved.add(rule);
    final committed = saveCommitted;
    if (committed != null && !committed.isCompleted) committed.complete();
    final committedGate = saveCommittedGate;
    if (committedGate != null) await committedGate.future;
  }

  @override
  Future<void> delete(
    String ruleId, {
    bool Function()? isCurrent,
    Map<String, ProofreadingRule?>? expectedRules,
  }) async {
    lastDeleteExpectedRules = expectedRules == null
        ? null
        : Map<String, ProofreadingRule?>.of(expectedRules);
    final started = deleteStarted;
    if (started != null && !started.isCompleted) started.complete();
    final gate = deleteGate;
    if (gate != null) await gate.future;
    if (expectedRules != null && !_matchesExpectedRules(expectedRules)) {
      throw const ValidationFailure('规则定义已变化。');
    }
    if (isCurrent != null && !isCurrent()) {
      throw const ValidationFailure('删除操作已失效。');
    }
    deleted.add(ruleId);
    definitions.remove(ruleId);
    final committed = deleteCommitted;
    if (committed != null && !committed.isCompleted) committed.complete();
    final committedGate = deleteCommittedGate;
    if (committedGate != null) await committedGate.future;
  }

  @override
  Future<void> runIfCurrent(
    Map<String, ProofreadingRule?> expectedRules,
    void Function() action, {
    bool Function()? isCurrent,
  }) async {
    runIfCurrentCalls++;
    lastRunIfCurrentExpectedRules = Map<String, ProofreadingRule?>.of(
      expectedRules,
    );
    if (!_matchesExpectedRules(expectedRules)) {
      throw const ValidationFailure('规则定义已变化。');
    }
    if (isCurrent != null && !isCurrent()) {
      throw const ValidationFailure('当前规则试跑已失效。');
    }
    action();
  }

  bool _matchesExpectedRules(Map<String, ProofreadingRule?> expectedRules) =>
      expectedRules.entries.every(
        (entry) => _sameRuleDefinition(definitions[entry.key], entry.value),
      );
}

bool _sameRuleDefinition(ProofreadingRule? left, ProofreadingRule? right) {
  if (identical(left, right)) return true;
  if (left == null || right == null) return false;
  return left.id == right.id &&
      left.name == right.name &&
      left.kind == right.kind &&
      left.headingLevel == right.headingLevel &&
      left.enabled == right.enabled &&
      left.source == right.source &&
      left.scope == right.scope &&
      left.bookId == right.bookId &&
      left.target == right.target &&
      left.mode == right.mode &&
      left.pattern == right.pattern &&
      left.titleCaptureGroup == right.titleCaptureGroup &&
      left.numberCaptureGroup == right.numberCaptureGroup &&
      left.caseSensitive == right.caseSensitive &&
      left.action == right.action &&
      left.priority == right.priority &&
      _sameStrings(left.positiveExamples, right.positiveExamples) &&
      _sameStrings(left.negativeExamples, right.negativeExamples);
}

bool _sameStrings(List<String> left, List<String> right) =>
    left.length == right.length &&
    left.indexed.every((entry) => entry.$2 == right[entry.$1]);

class _FakeBackgroundJobs extends BackgroundJobs {
  bool _busy = false;
  int cancelCount = 0;
  Completer<void>? runStarted;
  Completer<void>? runGate;

  @override
  bool get isBusy => _busy;

  @override
  Future<R> run<T, R>(
    T input,
    FutureOr<R> Function(T, void Function(double, String)) compute, {
    required int revision,
    Duration timeout = const Duration(minutes: 2),
    void Function(JobProgress)? onProgress,
  }) async {
    _busy = true;
    try {
      final started = runStarted;
      if (started != null && !started.isCompleted) started.complete();
      final gate = runGate;
      if (gate != null) await gate.future;
      return await compute(input, (fraction, stage) {
        onProgress?.call(JobProgress(1, revision, fraction, stage));
      });
    } finally {
      _busy = false;
    }
  }

  @override
  void cancelActive() {
    cancelCount++;
  }
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bookloom/core/editing/proofreading_rule.dart';
import 'package:bookloom/core/editing/proofreading_rule_store.dart';
import 'package:bookloom/core/errors/app_failure.dart';
import 'package:bookloom/core/storage/app_database.dart';
import 'package:bookloom/core/storage/settings_store.dart';
import 'package:bookloom/features/editor/data/proofreading_rule_store.dart';
import 'package:flutter_test/flutter_test.dart';

ProofreadingRule _rule(
  String id, {
  String bookId = 'book-a',
  String name = '清理推广语',
  bool enabled = true,
  ProofreadingRuleSource source = ProofreadingRuleSource.user,
  ProofreadingRuleScope scope = ProofreadingRuleScope.book,
  ProofreadingRuleKind kind = ProofreadingRuleKind.advertisement,
  ProofreadingRuleTarget target = ProofreadingRuleTarget.bodyLine,
  ProofreadingMatchMode mode = ProofreadingMatchMode.literal,
  String pattern = '点击阅读',
  String? excludePattern,
  bool wholeLineOnly = false,
  bool caseSensitive = true,
  ProofreadingRuleAction action = ProofreadingRuleAction.exactDeletion,
  int priority = 7,
  List<String> positiveExamples = const ['点击阅读本书'],
  List<String> negativeExamples = const ['普通剧情'],
  int? titleCaptureGroup,
  int? numberCaptureGroup,
  int headingLevel = 2,
}) => ProofreadingRule.create(
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
  positiveExamples: positiveExamples,
  negativeExamples: negativeExamples,
  scope: scope,
  globalScopeConfirmed: scope == ProofreadingRuleScope.global,
  enabled: enabled,
  priority: priority,
);

void main() {
  late AppDatabase db;
  late SettingsStore settings;
  late ProofreadingRuleStore store;

  setUp(() {
    db = AppDatabase.memory();
    settings = SettingsStore(db);
    store = SettingsProofreadingRuleStore(db);
  });

  tearDown(() async => db.close());

  test(
    'number groups round-trip, change fingerprints and reject corrupt values',
    () async {
      ProofreadingRule numbered({int? group}) => _rule(
        'numbered',
        kind: ProofreadingRuleKind.chapter,
        target: ProofreadingRuleTarget.headingLine,
        action: ProofreadingRuleAction.chapterCandidate,
        mode: ProofreadingMatchMode.safeRegex,
        pattern: r'^(1)(2):(夜雨😀)$',
        titleCaptureGroup: 3,
        numberCaptureGroup: group,
        positiveExamples: const ['12:夜雨😀'],
      );
      final legacy = numbered();
      final original = numbered(group: 1);
      final changed = numbered(group: 2);
      expect(
        proofreadingRuleFingerprint(original),
        isNot(proofreadingRuleFingerprint(legacy)),
      );
      expect(
        proofreadingRuleFingerprint(original),
        isNot(proofreadingRuleFingerprint(changed)),
      );
      expect((jsonDecode(proofreadingRuleFingerprint(original)) as List).last, {
        'number_capture_group': 1,
      });
      await store.save(original);
      final reopened = SettingsProofreadingRuleStore(db);
      final loaded = (await reopened.loadForBook('book-a')).single;
      expect(loaded.numberCaptureGroup, 1);
      expect(loaded.matchSample('12:夜雨😀').single.mappedNumber, 1);
      expect(loaded.matchSample('12:夜雨😀').single.numberText, '1');
      await reopened.save(changed, expectedRules: {'numbered': loaded});
      await expectLater(
        reopened.runIfCurrent({'numbered': loaded}, () {}),
        throwsA(isA<ValidationFailure>()),
      );
      final payload = jsonDecode(
        (await settings.read(SettingsProofreadingRuleStore.settingsKey))!,
      ) as Map<String, dynamic>;
      final entry = (payload['rules'] as List).single as Map<String, dynamic>;
      for (final invalid in <Object?>[null, true, 1.0, -1, 4, '1']) {
        entry['number_capture_group'] = invalid;
        final damaged = jsonEncode(payload);
        await settings.write(
          SettingsProofreadingRuleStore.settingsKey,
          damaged,
        );
        await expectLater(
          store.loadForBook('book-a'),
          throwsA(isA<StorageFailure>()),
        );
        await expectLater(store.save(original), throwsA(isA<StorageFailure>()));
        expect(
          await settings.read(SettingsProofreadingRuleStore.settingsKey),
          damaged,
        );
      }
      entry.remove('number_capture_group');
      await settings.write(
        SettingsProofreadingRuleStore.settingsKey,
        jsonEncode(payload),
      );
      expect(
        (await store.loadForBook('book-a')).single.numberCaptureGroup,
        isNull,
      );
      await store.save(legacy);
      expect(
        await settings.read(SettingsProofreadingRuleStore.settingsKey),
        isNot(contains('number_capture_group')),
      );
    },
  );

  test(
    'volume level round-trips without colliding with capture fingerprint',
    () async {
      ProofreadingRule chapterRule({int level = 2, int? group}) => _rule(
        'chapter',
        kind: ProofreadingRuleKind.chapter,
        target: ProofreadingRuleTarget.headingLine,
        action: ProofreadingRuleAction.chapterCandidate,
        mode: ProofreadingMatchMode.safeRegex,
        pattern: r'^(卷二)',
        positiveExamples: const ['卷二'],
        headingLevel: level,
        titleCaptureGroup: group,
      );
      final volume = chapterRule(level: 1);
      final capture = chapterRule(group: 1);
      expect(
        proofreadingRuleFingerprint(volume),
        isNot(proofreadingRuleFingerprint(capture)),
      );
      expect(
        proofreadingRuleFingerprint(chapterRule()),
        isNot(proofreadingRuleFingerprint(volume)),
      );
      await store.save(volume);
      final loaded = (await SettingsProofreadingRuleStore(
        db,
      ).loadForBook('book-a')).single;
      expect(loaded.headingLevel, 1);
      expect(
        proofreadingRuleFingerprint(loaded),
        proofreadingRuleFingerprint(volume),
      );
      final payload = jsonDecode(
        (await settings.read(SettingsProofreadingRuleStore.settingsKey))!,
      ) as Map<String, dynamic>;
      final entry = (payload['rules'] as List).single as Map<String, dynamic>;
      expect(entry['heading_level'], 1);
      for (final invalid in <Object?>[null, true, 1.0, 0, 3, '1']) {
        entry['heading_level'] = invalid;
        final damaged = jsonEncode(payload);
        await settings.write(
          SettingsProofreadingRuleStore.settingsKey,
          damaged,
        );
        await expectLater(
          store.loadForBook('book-a'),
          throwsA(isA<StorageFailure>()),
        );
        await expectLater(store.save(volume), throwsA(isA<StorageFailure>()));
        expect(
          await settings.read(SettingsProofreadingRuleStore.settingsKey),
          damaged,
        );
      }
      entry['heading_level'] = 2;
      await settings.write(
        SettingsProofreadingRuleStore.settingsKey,
        jsonEncode(payload),
      );
      expect((await store.loadForBook('book-a')).single.headingLevel, 2);
      await store.save(chapterRule());
      expect(
        await settings.read(SettingsProofreadingRuleStore.settingsKey),
        isNot(contains('heading_level')),
      );
    },
  );

  test(
    'round-trips current rule fields through an isolated SQLite database',
    () async {
      final original = _rule(
        'rule-😀',
        source: ProofreadingRuleSource.ai,
        mode: ProofreadingMatchMode.safeRegex,
        pattern: r'广告\d+',
        positiveExamples: ['广告12 后续'],
      );
      await store.save(original);
      final reloaded = SettingsProofreadingRuleStore(db);
      final saved = (await reloaded.loadForBook('book-a')).single;
      expect(saved.id, original.id);
      expect(saved.name, original.name);
      expect(saved.kind, original.kind);
      expect(saved.enabled, isTrue);
      expect(saved.source, ProofreadingRuleSource.ai);
      expect(saved.scope, ProofreadingRuleScope.book);
      expect(saved.bookId, 'book-a');
      expect(saved.target, original.target);
      expect(saved.mode, ProofreadingMatchMode.safeRegex);
      expect(saved.pattern, original.pattern);
      expect(saved.caseSensitive, isTrue);
      expect(saved.action, original.action);
      expect(saved.priority, 7);
      expect(saved.positiveExamples, ['广告12 后续']);
      expect(saved.negativeExamples, ['普通剧情']);
      expect(saved.matchSample('广告12').single.endUtf16, 4);
      expect(
        jsonDecode(
          (await settings.read(SettingsProofreadingRuleStore.settingsKey))!,
        ),
        containsPair('schema_version', 1),
      );
    },
  );

  test('updates the same id in place, toggles enabled, and deletes', () async {
    await store.save(_rule('current'));
    await store.save(_rule('current', name: '暂停规则', enabled: false));
    final saved = (await store.loadForBook('book-a')).single;
    expect(saved.name, '暂停规则');
    expect(saved.enabled, isFalse);
    final raw = jsonDecode(
      (await settings.read(SettingsProofreadingRuleStore.settingsKey))!,
    ) as Map<String, dynamic>;
    expect(raw['rules'], hasLength(1));
    await store.delete('current');
    expect(await store.loadForBook('book-a'), isEmpty);
  });

  test(
    'returns only this book and saved global rules without executing them',
    () async {
      await store.save(_rule('a'));
      await store.save(_rule('b', bookId: 'book-b'));
      await store.save(_rule('global', scope: ProofreadingRuleScope.global));
      expect((await store.loadForBook('book-a')).map((rule) => rule.id), [
        'a',
        'global',
      ]);
      expect((await store.loadForBook('book-b')).map((rule) => rule.id), [
        'b',
        'global',
      ]);
      expect((await store.loadForBook('book-c')).map((rule) => rule.id), [
        'global',
      ]);
    },
  );

  test(
    'concurrent saves on one database retain every current definition',
    () async {
      await Future.wait([
        for (var index = 0; index < 24; index++)
          store.save(_rule('parallel-$index')),
      ]);
      expect(
        (await store.loadForBook('book-a')).map((rule) => rule.id).toSet(),
        {for (var index = 0; index < 24; index++) 'parallel-$index'},
      );
    },
  );

  test('fingerprint distinguishes every persisted rule field', () {
    final original = _rule('current');
    final fingerprint = proofreadingRuleFingerprint(original);
    final variants = [
      _rule('other'),
      _rule('current', name: '另一规则'),
      _rule(
        'current',
        kind: ProofreadingRuleKind.chapter,
        target: ProofreadingRuleTarget.headingLine,
        action: ProofreadingRuleAction.chapterCandidate,
      ),
      _rule('current', enabled: false),
      _rule('current', source: ProofreadingRuleSource.ai),
      _rule('current', scope: ProofreadingRuleScope.global),
      _rule('current', bookId: 'book-b'),
      _rule('current', target: ProofreadingRuleTarget.paragraph),
      _rule('current', mode: ProofreadingMatchMode.safeRegex),
      _rule('current', pattern: '阅读'),
      _rule('current', caseSensitive: false),
      _rule('current', action: ProofreadingRuleAction.advertisementCandidate),
      _rule('current', priority: 8),
      _rule('current', positiveExamples: ['点击阅读别处']),
      _rule('current', negativeExamples: ['另一段剧情']),
    ];
    for (final variant in variants) {
      expect(proofreadingRuleFingerprint(variant), isNot(fingerprint));
    }
  });

  test(
    'mapped chapter survives storage reopen and changes fingerprint',
    () async {
      final original = _rule(
        'chapter',
        kind: ProofreadingRuleKind.chapter,
        target: ProofreadingRuleTarget.headingLine,
        action: ProofreadingRuleAction.chapterCandidate,
        mode: ProofreadingMatchMode.safeRegex,
        pattern: r'^【([^】]+)】(夜雨😀)',
        titleCaptureGroup: 2,
        positiveExamples: const ['【卷二】夜雨😀'],
      );
      await store.save(original);
      final raw = jsonDecode(
        (await settings.read(SettingsProofreadingRuleStore.settingsKey))!,
      ) as Map<String, dynamic>;
      expect((raw['rules'] as List).single['title_capture_group'], 2);
      final reopened = SettingsProofreadingRuleStore(db);
      final saved = (await reopened.loadForBook('book-a')).single;
      expect(saved.titleCaptureGroup, 2);
      expect(saved.matchSample('【卷二】夜雨😀').single.mappedTitle, '夜雨😀');
      expect(
        proofreadingRuleFingerprint(saved),
        proofreadingRuleFingerprint(original),
      );

      final changed = _rule(
        'chapter',
        kind: ProofreadingRuleKind.chapter,
        target: ProofreadingRuleTarget.headingLine,
        action: ProofreadingRuleAction.chapterCandidate,
        mode: ProofreadingMatchMode.safeRegex,
        pattern: r'^【([^】]+)】(夜雨😀)',
        titleCaptureGroup: 1,
        positiveExamples: const ['【卷二】夜雨😀'],
      );
      expect(
        proofreadingRuleFingerprint(changed),
        isNot(proofreadingRuleFingerprint(saved)),
      );
      await reopened.save(changed, expectedRules: {'chapter': saved});
      await expectLater(
        reopened.runIfCurrent({'chapter': saved}, () {}),
        throwsA(isA<ValidationFailure>()),
      );
    },
  );

  test('mapped chapter survives closing and reopening its database', () async {
    final directory = await Directory.systemTemp.createTemp('bookloom-rule-');
    final file = File('${directory.path}/rules.sqlite');
    await db.close();
    try {
      db = AppDatabase.openAt(file);
      await SettingsProofreadingRuleStore(db).save(
        _rule(
          'persisted',
          kind: ProofreadingRuleKind.chapter,
          target: ProofreadingRuleTarget.headingLine,
          action: ProofreadingRuleAction.chapterCandidate,
          mode: ProofreadingMatchMode.safeRegex,
          pattern: r'^【([^】]+)】',
          titleCaptureGroup: 1,
          headingLevel: 1,
          positiveExamples: const ['【卷二】'],
        ),
      );
      await db.close();
      db = AppDatabase.openAt(file);
      final saved = (await SettingsProofreadingRuleStore(
        db,
      ).loadForBook('book-a')).single;
      expect(saved.titleCaptureGroup, 1);
      expect(saved.headingLevel, 1);
      expect(saved.matchSample('【卷二】').single.mappedTitle, '卷二');
    } finally {
      await db.close();
      db = AppDatabase.memory();
      await directory.delete(recursive: true);
    }
  });

  test('legacy JSON remains readable without adding a mapping key', () async {
    final legacy = _rule('legacy');
    await store.save(legacy);
    final raw = (await settings.read(
      SettingsProofreadingRuleStore.settingsKey,
    ))!;
    expect(raw, isNot(contains('title_capture_group')));
    expect(raw, isNot(contains('heading_level')));
    expect((await store.loadForBook('book-a')).single.headingLevel, 2);
    expect(
      (await SettingsProofreadingRuleStore(db).loadForBook('book-a'))
          .single
          .titleCaptureGroup,
      isNull,
    );
    expect(
      proofreadingRuleFingerprint(legacy),
      jsonEncode([
        legacy.id,
        legacy.name,
        legacy.kind.name,
        legacy.enabled,
        legacy.source.name,
        legacy.scope.name,
        legacy.bookId,
        legacy.target.name,
        legacy.mode.name,
        legacy.pattern,
        legacy.caseSensitive,
        legacy.action.name,
        legacy.priority,
        legacy.positiveExamples,
        legacy.negativeExamples,
      ]),
    );
  });

  test(
    'save CAS rejects a concurrent update and an expected absence',
    () async {
      final original = _rule('current');
      await store.save(original);
      final concurrent = _rule('current', name: '并发新值');
      await store.save(concurrent);
      await expectLater(
        store.save(
          _rule('current', name: '旧任务修改'),
          expectedRules: {'current': original},
        ),
        throwsA(isA<ValidationFailure>()),
      );
      expect((await store.loadForBook('book-a')).single.name, '并发新值');
      await expectLater(
        store.save(
          _rule('current', name: '错误创建'),
          expectedRules: {'current': null},
        ),
        throwsA(isA<ValidationFailure>()),
      );
      await store.save(
        _rule('current', name: '匹配更新'),
        expectedRules: {'current': concurrent},
      );
      expect((await store.loadForBook('book-a')).single.name, '匹配更新');
    },
  );

  test('delete CAS and stale guard preserve the latest definition', () async {
    final original = _rule('current');
    await store.save(original);
    final concurrent = _rule('current', name: '并发新值');
    await store.save(concurrent);
    await expectLater(
      store.delete('current', expectedRules: {'current': original}),
      throwsA(isA<ValidationFailure>()),
    );
    for (final failAt in [1, 2, 3]) {
      var calls = 0;
      await expectLater(
        store.delete(
          'current',
          expectedRules: {'current': concurrent},
          isCurrent: () => ++calls != failAt,
        ),
        throwsA(isA<ValidationFailure>()),
      );
      expect(calls, failAt);
      expect((await store.loadForBook('book-a')).single.name, '并发新值');
    }
    await store.delete('current', expectedRules: {'current': concurrent});
    expect(await store.loadForBook('book-a'), isEmpty);
  });

  test(
    'runIfCurrent invokes only a synchronous action on matching state',
    () async {
      final original = _rule('current');
      await store.save(original);
      var actions = 0;
      await store.runIfCurrent({
        'current': original,
        'absent': null,
      }, () => actions++);
      expect(actions, 1);
      await store.save(_rule('current', name: '新定义'));
      await expectLater(
        store.runIfCurrent({'current': original}, () => actions++),
        throwsA(isA<ValidationFailure>()),
      );
      await expectLater(
        store.runIfCurrent({'current': null}, () => actions++),
        throwsA(isA<ValidationFailure>()),
      );
      await expectLater(
        store.runIfCurrent(
          {'current': _rule('current', name: '新定义')},
          () => actions++,
          isCurrent: () => false,
        ),
        throwsA(isA<ValidationFailure>()),
      );
      expect(actions, 1);
    },
  );

  test('runIfCurrent keeps delayed database work in the caller zone', () async {
    final original = _rule('current');
    await store.save(original);
    const zoneKey = #ruleStoreCaller;
    await runZoned(() async {
      final callerZone = Zone.current;
      final transactionEnded = Completer<void>();
      final delayedWork = Completer<void>();
      await store.runIfCurrent({'current': original}, () {
        expect(Zone.current, same(callerZone));
        expect(Zone.current[zoneKey], 'caller');
        Timer(Duration.zero, () {
          try {
            expect(Zone.current, same(callerZone));
            Future<void>.delayed(Duration.zero, () async {
              await transactionEnded.future;
              expect(Zone.current, same(callerZone));
              await settings.write('rule-store.zone-probe', 'saved');
              expect(await settings.read('rule-store.zone-probe'), 'saved');
            }).then(delayedWork.complete, onError: delayedWork.completeError);
          } catch (error, stack) {
            delayedWork.completeError(error, stack);
          }
        });
      });
      transactionEnded.complete();
      await delayedWork.future.timeout(const Duration(seconds: 2));
    }, zoneValues: {zoneKey: 'caller'});
  });

  test('rejects ambiguous and oversized expected rule snapshots', () async {
    final original = _rule('current');
    await store.save(original);
    var actions = 0;
    await expectLater(
      store.runIfCurrent({}, () => actions++),
      throwsA(isA<ValidationFailure>()),
    );
    await expectLater(
      store.runIfCurrent({'wrong': original}, () => actions++),
      throwsA(isA<ValidationFailure>()),
    );
    await expectLater(
      store.runIfCurrent({
        for (var index = 0; index < 33; index++) 'missing-$index': null,
      }, () => actions++),
      throwsA(isA<ValidationFailure>()),
    );
    await expectLater(
      store.save(
        _rule('current', name: '错误更新'),
        expectedRules: {'wrong': original},
      ),
      throwsA(isA<ValidationFailure>()),
    );
    expect(actions, 0);
    expect((await store.loadForBook('book-a')).single.name, original.name);
  });

  test(
    'stale guard after delayed read keeps the previous definition',
    () async {
      await store.save(_rule('current'));
      final entered = Completer<void>();
      final release = Completer<void>();
      final blocker = db.transaction(() async {
        entered.complete();
        await release.future;
      });
      await entered.future;
      var current = true;
      final pending = store.save(
        _rule('current', name: '过期修改', enabled: false),
        isCurrent: () => current,
      );
      current = false;
      release.complete();
      await blocker;
      await expectLater(pending, throwsA(isA<ValidationFailure>()));
      final retained = (await store.loadForBook('book-a')).single;
      expect(retained.name, '清理推广语');
      expect(retained.enabled, isTrue);
    },
  );

  test(
    'guard is checked before write and after await; false rolls back',
    () async {
      await store.save(_rule('current'));
      for (final failAt in [2, 3]) {
        var calls = 0;
        await expectLater(
          store.save(
            _rule('current', name: '过期修改', enabled: false),
            isCurrent: () => ++calls != failAt,
          ),
          throwsA(isA<ValidationFailure>()),
        );
        expect(calls, failAt);
        final retained = (await store.loadForBook('book-a')).single;
        expect(retained.name, '清理推广语');
        expect(retained.enabled, isTrue);
      }
    },
  );

  test(
    'rejects malformed, ambiguous, unsafe, and built-in stored rules',
    () async {
      await store.save(_rule('valid'));
      final valid = jsonDecode(
        (await settings.read(SettingsProofreadingRuleStore.settingsKey))!,
      ) as Map<String, dynamic>;
      Future<void> reject(Object payload) async {
        final corrupted = jsonEncode(payload);
        await settings.write(
          SettingsProofreadingRuleStore.settingsKey,
          corrupted,
        );
        await expectLater(
          store.loadForBook('book-a'),
          throwsA(isA<StorageFailure>()),
        );
        await expectLater(
          store.save(_rule('new')),
          throwsA(isA<StorageFailure>()),
        );
        await expectLater(
          store.delete('valid'),
          throwsA(isA<StorageFailure>()),
        );
        expect(
          await settings.read(SettingsProofreadingRuleStore.settingsKey),
          corrupted,
        );
      }

      await reject({...valid, 'schema_version': 2});
      await reject({...valid, 'unexpected': true});
      await reject({
        ...valid,
        'rules': [valid['rules'][0], valid['rules'][0]],
      });
      final base = Map<String, dynamic>.from(valid['rules'][0] as Map);
      await reject({
        ...valid,
        'rules': [
          {...base, 'enabled': 'true'},
        ],
      });
      for (final bad in <Object?>[null, true, 1.0, -1, 1]) {
        await reject({
          ...valid,
          'rules': [
            {...base, 'title_capture_group': bad},
          ],
        });
      }
      await reject({
        ...valid,
        'rules': [
          {
            ...base,
            'kind': 'chapter',
            'target': 'heading_line',
            'action': 'chapter_candidate',
            'mode': 'safe_regex',
            'pattern': r'^(标题)',
            'title_capture_group': 2,
            'positive_examples': ['标题'],
          },
        ],
      });
      await reject({
        ...valid,
        'rules': [
          {...base, 'unexpected_mapping': 1},
        ],
      });
      await reject({
        ...valid,
        'rules': [
          {...base, 'target': 'unknown'},
        ],
      });
      await reject({
        ...valid,
        'rules': [
          {...base, 'source': 'builtIn'},
        ],
      });
      await reject({
        ...valid,
        'rules': [
          {
            ...base,
            'mode': 'safe_regex',
            'pattern': r'(a+)+',
            'positive_examples': ['aaaa'],
          },
        ],
      });
      await reject({
        ...valid,
        'rules': [
          {
            ...base,
            'positive_examples': ['未命中'],
          },
        ],
      });
      await settings.write(
        SettingsProofreadingRuleStore.settingsKey,
        '{"schema_version":1,"schema_version":1,"rules":[]}',
      );
      await expectLater(
        store.loadForBook('book-a'),
        throwsA(isA<StorageFailure>()),
      );
      await settings.write(
        SettingsProofreadingRuleStore.settingsKey,
        '{"schema_version":1,"rules":[{"id":"\\ud800"}]}',
      );
      await expectLater(
        store.loadForBook('book-a'),
        throwsA(isA<StorageFailure>()),
      );
    },
  );

  test(
    'rejects built-in save and never alters the current stored rule',
    () async {
      await store.save(_rule('current'));
      await expectLater(
        store.save(_rule('current', source: ProofreadingRuleSource.builtIn)),
        throwsA(isA<ValidationFailure>()),
      );
      expect(
        (await store.loadForBook('book-a')).single.source,
        ProofreadingRuleSource.user,
      );
    },
  );

  test('rejects stored JSON deeper than 32 object or array levels', () async {
    final deepArray = '${'[' * 33}0${']' * 33}';
    final deepObject = '${'{"child":' * 33}0${'}' * 33}';
    for (final nested in [deepArray, deepObject]) {
      final damaged = '{"schema_version":1,"rules":$nested}';
      await settings.write(SettingsProofreadingRuleStore.settingsKey, damaged);
      await expectLater(
        store.loadForBook('book-a'),
        throwsA(isA<StorageFailure>()),
      );
      await expectLater(
        store.save(_rule('new')),
        throwsA(isA<StorageFailure>()),
      );
      expect(
        await settings.read(SettingsProofreadingRuleStore.settingsKey),
        damaged,
      );
    }
  });

  test(
    'enforces rule count and JSON UTF-8 size without partial writes',
    () async {
      await store.save(_rule('base'));
      final valid = jsonDecode(
        (await settings.read(SettingsProofreadingRuleStore.settingsKey))!,
      ) as Map<String, dynamic>;
      final base = Map<String, dynamic>.from(valid['rules'][0] as Map);
      final fullRules = <Map<String, dynamic>>[
        for (
          var index = 0;
          index < SettingsProofreadingRuleStore.maxRules;
          index++
        )
          {...base, 'id': 'id-$index'},
      ];
      final full = {'schema_version': 1, 'rules': fullRules};
      await settings.write(
        SettingsProofreadingRuleStore.settingsKey,
        jsonEncode(full),
      );
      await expectLater(
        store.save(_rule('extra')),
        throwsA(isA<ValidationFailure>()),
      );
      expect(await store.loadForBook('book-a'), hasLength(256));
      await settings.write(
        SettingsProofreadingRuleStore.settingsKey,
        jsonEncode({
          ...full,
          'rules': [...fullRules, base],
        }),
      );
      await expectLater(
        store.loadForBook('book-a'),
        throwsA(isA<StorageFailure>()),
      );
      await settings.write(
        SettingsProofreadingRuleStore.settingsKey,
        ' ' * (SettingsProofreadingRuleStore.maxJsonBytes + 1),
      );
      await expectLater(
        store.loadForBook('book-a'),
        throwsA(isA<StorageFailure>()),
      );
    },
  );

  test('rejects a save that would exceed the JSON byte budget', () async {
    await store.save(_rule('base'));
    final valid = jsonDecode(
      (await settings.read(SettingsProofreadingRuleStore.settingsKey))!,
    ) as Map<String, dynamic>;
    final largeBase = {
      ...Map<String, dynamic>.from(valid['rules'][0] as Map),
      'pattern': 'x',
      'positive_examples': List<String>.filled(4, 'x' * 2000),
    };
    final largeRules = <Map<String, dynamic>>[];
    var bytes = utf8.encode('{"schema_version":1,"rules":[]}').length;
    while (largeRules.length < SettingsProofreadingRuleStore.maxRules) {
      final candidate = {...largeBase, 'id': 'large-${largeRules.length}'};
      final addedBytes =
          utf8.encode(jsonEncode(candidate)).length +
          (largeRules.isEmpty ? 0 : 1);
      if (bytes + addedBytes > SettingsProofreadingRuleStore.maxJsonBytes) {
        break;
      }
      largeRules.add(candidate);
      bytes += addedBytes;
    }
    expect(largeRules.length, lessThan(SettingsProofreadingRuleStore.maxRules));
    final stored = jsonEncode({'schema_version': 1, 'rules': largeRules});
    expect(
      utf8.encode(stored).length,
      lessThanOrEqualTo(SettingsProofreadingRuleStore.maxJsonBytes),
    );
    await settings.write(SettingsProofreadingRuleStore.settingsKey, stored);
    await expectLater(
      store.save(
        _rule(
          'extra',
          pattern: 'x',
          positiveExamples: List<String>.filled(4, 'x' * 2000),
        ),
      ),
      throwsA(isA<ValidationFailure>()),
    );
    expect(
      await settings.read(SettingsProofreadingRuleStore.settingsKey),
      stored,
    );
  });

  test(
    'exclude text round-trips and stays compatible with older values',
    () async {
      final excluded = _rule('excluded', excludePattern: '引用');
      await store.save(excluded);
      final saved = (await SettingsProofreadingRuleStore(
        db,
      ).loadForBook('book-a')).single;
      expect(saved.excludePattern, '引用');
      expect(
        proofreadingRuleFingerprint(saved),
        proofreadingRuleFingerprint(excluded),
      );
      final raw = jsonDecode(
        (await settings.read(SettingsProofreadingRuleStore.settingsKey))!,
      ) as Map<String, dynamic>;
      final entry = (raw['rules'] as List).single as Map<String, dynamic>;
      expect(entry['exclude'], '引用');

      final legacy = Map<String, dynamic>.from(entry)..remove('exclude');
      await settings.write(
        SettingsProofreadingRuleStore.settingsKey,
        jsonEncode({
          'schema_version': 1,
          'rules': [legacy],
        }),
      );
      expect((await store.loadForBook('book-a')).single.excludePattern, isNull);

      final damaged = Map<String, dynamic>.from(entry)..['exclude'] = 1;
      final damagedJson = jsonEncode({
        'schema_version': 1,
        'rules': [damaged],
      });
      await settings.write(
        SettingsProofreadingRuleStore.settingsKey,
        damagedJson,
      );
      await expectLater(
        store.loadForBook('book-a'),
        throwsA(isA<StorageFailure>()),
      );
      expect(
        await settings.read(SettingsProofreadingRuleStore.settingsKey),
        damagedJson,
      );
    },
  );

  test(
    'whole-line flag round-trips and defaults old values to false',
    () async {
      final exact = _rule(
        'exact',
        wholeLineOnly: true,
        positiveExamples: const ['点击阅读'],
      );
      await store.save(exact);
      final saved = (await SettingsProofreadingRuleStore(
        db,
      ).loadForBook('book-a')).single;
      expect(saved.wholeLineOnly, isTrue);
      expect(
        proofreadingRuleFingerprint(saved),
        proofreadingRuleFingerprint(exact),
      );
      final raw = jsonDecode(
        (await settings.read(SettingsProofreadingRuleStore.settingsKey))!,
      ) as Map<String, dynamic>;
      final entry = (raw['rules'] as List).single as Map<String, dynamic>;
      expect(entry['whole_line'], isTrue);

      final legacy = Map<String, dynamic>.from(entry)..remove('whole_line');
      await settings.write(
        SettingsProofreadingRuleStore.settingsKey,
        jsonEncode({
          'schema_version': 1,
          'rules': [legacy],
        }),
      );
      expect((await store.loadForBook('book-a')).single.wholeLineOnly, isFalse);

      final damaged = Map<String, dynamic>.from(entry)..['whole_line'] = 'yes';
      final damagedJson = jsonEncode({
        'schema_version': 1,
        'rules': [damaged],
      });
      await settings.write(
        SettingsProofreadingRuleStore.settingsKey,
        damagedJson,
      );
      await expectLater(
        store.loadForBook('book-a'),
        throwsA(isA<StorageFailure>()),
      );
    },
  );

  test('transfer codec round-trips rules and rejects invalid files', () {
    final rule = _rule(
      'transfer',
      excludePattern: '引用',
      wholeLineOnly: true,
      positiveExamples: const <String>['点击阅读'],
    );
    final encoded = encodeProofreadingRules(<ProofreadingRule>[rule]);
    final decoded = decodeProofreadingRules(encoded).single;
    expect(
      proofreadingRuleFingerprint(decoded),
      proofreadingRuleFingerprint(rule),
    );

    expect(
      () => decodeProofreadingRules('not json'),
      throwsA(isA<ValidationFailure>()),
    );
    expect(
      () => decodeProofreadingRules('{"schema_version":2,"rules":[]}'),
      throwsA(isA<ValidationFailure>()),
    );
    expect(
      () => encodeProofreadingRules(<ProofreadingRule>[
        _rule('built-in', source: ProofreadingRuleSource.builtIn),
      ]),
      throwsA(isA<ValidationFailure>()),
    );
    expect(
      () => encodeProofreadingRules(<ProofreadingRule>[
        for (var index = 0; index < 257; index++) _rule('rule-$index'),
      ]),
      throwsA(isA<ValidationFailure>()),
    );
  });

  test(
    'mergeMissing adds only absent definitions and never overwrites',
    () async {
      final existing = _rule('existing', name: '现有规则');
      await store.save(existing);
      final incoming = _rule('existing', name: '被改写的规则');
      final added = _rule('new-rule', name: '新增规则');

      final result = await store.mergeMissing(<ProofreadingRule>[
        incoming,
        added,
      ]);

      expect(result.addedIds, <String>['new-rule']);
      expect(result.skippedIds, <String>['existing']);
      final rules = await store.loadForBook('book-a');
      expect(
        rules.map((rule) => rule.id),
        containsAll(<String>['existing', 'new-rule']),
      );
      expect(rules.singleWhere((rule) => rule.id == 'existing').name, '现有规则');
      expect(rules.singleWhere((rule) => rule.id == 'new-rule').name, '新增规则');
    },
  );

  test('mergeMissing validates sources, duplicates and cancellation', () async {
    expect(
      () => store.mergeMissing(<ProofreadingRule>[
        _rule('built-in', source: ProofreadingRuleSource.builtIn),
      ]),
      throwsA(isA<ValidationFailure>()),
    );
    expect(
      () => store.mergeMissing(<ProofreadingRule>[
        _rule('duplicate'),
        _rule('duplicate'),
      ]),
      throwsA(isA<ValidationFailure>()),
    );
    await expectLater(
      store.mergeMissing(<ProofreadingRule>[
        _rule('cancelled'),
      ], isCurrent: () => false),
      throwsA(isA<ValidationFailure>()),
    );
    expect(await store.loadForBook('book-a'), isEmpty);
  });
}

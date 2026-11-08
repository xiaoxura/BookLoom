import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bookloom/core/editing/proofreading_rule.dart';
import 'package:bookloom/core/editing/rule_scan_changes.dart';
import 'package:bookloom/core/errors/app_failure.dart';
import 'package:bookloom/core/model/block.dart';
import 'package:bookloom/core/model/book.dart';
import 'package:bookloom/core/model/chapter.dart';
import 'package:bookloom/core/model/metadata.dart';
import 'package:bookloom/core/storage/app_database.dart'
    hide Block, Book, Chapter;
import 'package:bookloom/core/storage/book_repository.dart';
import 'package:bookloom/features/editor/application/editor_session.dart';
import 'package:bookloom/features/editor/application/rule_workbench_task.dart';
import 'package:bookloom/features/editor/data/proofreading_rule_store.dart';
import 'package:flutter_test/flutter_test.dart';

const _bookId = 'title-mapping-book';
const _headingA = '【第二章 😀归来】';
const _headingB = '第三章 海边';
const _headingD = '第四章 无映射标题';
const _sourceA = '旧稿甲前文🙂\r\n$_headingA\r\n第二章正文A🙂';
const _sourceB = '旧稿乙前文🙂\r\n$_headingB\r\n海边正文B🙂';
const _sourceD = '旧稿丁前文🙂\r\n$_headingD\r\n无映射正文🙂';
const _originalFile = '原始导入文件\r\n$_headingA\r\n$_headingB\r\n$_headingD';
const _imageBytes = <int>[0x89, 0x50, 0x4e, 0x47];

const _blocksA = <Block>[TextBlock(id: 'body-a', text: _sourceA)];
const _blocksB = <Block>[
  TextBlock(id: 'body-b', text: _sourceB),
  ImageBlock(id: 'image-b', assetId: 'image-asset', caption: '章内插图'),
  FootnoteBlock(id: 'footnote-b', text: '章内脚注', marker: '①'),
  DividerBlock(id: 'divider-b'),
  TextBlock(id: 'tail-b', text: '图片脚注后的正文'),
];
const _blocksC = <Block>[TextBlock(id: 'body-c', text: '未命中章节正文。')];
const _blocksD = <Block>[TextBlock(id: 'body-d', text: _sourceD)];

void main() {
  test(
    'saved title mappings preview and apply as one undoable book batch',
    () async {
      final fixture = await _Fixture.open();
      try {
        await fixture.task.load();
        fixture.task.putRule(_mappedRule());
        fixture.task.putRule(_wholeMatchRule());
        fixture.task.putRule(_unmappedRule());
        await fixture.task.scan();
        for (final id in ['mapped', 'whole-match', 'unmapped']) {
          await fixture.task.saveRule(id);
        }

        fixture.task.dispose();
        fixture.task = RuleWorkbenchTask(
          session: fixture.session,
          store: SettingsProofreadingRuleStore(fixture.database),
        );
        await fixture.task.load();
        final reloadedRules = {
          for (final rule in fixture.task.rules) rule.id: rule,
        };
        expect(reloadedRules['mapped']!.titleCaptureGroup, 1);
        expect(reloadedRules['whole-match']!.titleCaptureGroup, 0);
        expect(reloadedRules['unmapped']!.titleCaptureGroup, isNull);
        for (final rule in fixture.task.rules) {
          fixture.task.setRuleSelected(rule.id, true);
        }
        await fixture.task.scan();

        expect(fixture.task.trial!.coverage.chapters, 5);
        expect(fixture.task.matches, hasLength(3));
        final snapshot = await fixture.session.readRuleSnapshot();
        final previews = {
          for (final match in fixture.task.matches)
            match.match.chapterId: RuleScanChanges.describe(
              snapshot,
              match.match,
            ),
        };
        expect(previews.keys.toSet(), {'a', 'b', 'd'});
        expect(previews['a']!.headingTitle, '第二章 😀归来');
        expect(previews['a']!.titleLine, _headingA);
        expect(previews['a']!.sourceTextAfter, '旧稿甲前文🙂\r\n第二章正文A🙂');
        expect(previews['b']!.headingTitle, '第三章');
        expect(previews['b']!.titleLine, _headingB);
        expect(previews['d']!.headingTitle, _headingD);
        expect(previews['d']!.sourceTextAfter, '旧稿丁前文🙂\r\n无映射正文🙂');

        final beforeApplyRevision = fixture.session.saveSeq;
        expect(fixture.session.dirty, isFalse);
        expect(fixture.session.canUndo, isFalse);
        expect(
          (await fixture.repository.loadChapter(_bookId, 'a'))!.blocks,
          _blocksA,
        );
        expect(
          (await fixture.repository.loadChapter(_bookId, 'b'))!.blocks,
          _blocksB,
        );
        expect(
          (await fixture.repository.loadChapter(_bookId, 'd'))!.blocks,
          _blocksD,
        );

        await fixture.task.applySelected(
          fixture.task.matches.map((match) => match.id).toSet(),
        );

        expect(fixture.task.lastAppliedCount, 3);
        expect(fixture.session.saveSeq, beforeApplyRevision + 1);
        expect(fixture.session.canUndo, isTrue);
        final changed = fixture.session.book!.chapters;
        final newChapters = changed
            .where(
              (chapter) => !{'volume', 'a', 'b', 'c', 'd'}.contains(chapter.id),
            )
            .toList();
        expect(
          newChapters.map((chapter) => chapter.title),
          unorderedEquals(
            previews.values.map((preview) => preview.headingTitle),
          ),
        );
        expect(
          newChapters.every((chapter) => chapter.parentId == 'volume'),
          isTrue,
        );

        await fixture.session.undo();
        expect(fixture.session.book!.chapters, hasLength(5));
        expect(fixture.session.canUndo, isFalse);
        expect(fixture.session.canRedo, isTrue);
        expect(
          fixture.session.book!.chapters.map((chapter) => chapter.id).toSet(),
          {'volume', 'a', 'b', 'c', 'd'},
        );
        await fixture.session.redo();
        expect(fixture.session.book!.chapters, hasLength(8));
        expect(fixture.session.canRedo, isFalse);
        await fixture.session.flush();

        final persisted = (await fixture.repository.loadBook(_bookId))!;
        final persistedNew = persisted.chapters
            .where(
              (chapter) => !{'volume', 'a', 'b', 'c', 'd'}.contains(chapter.id),
            )
            .toList();
        expect(
          persistedNew.map((chapter) => chapter.title),
          unorderedEquals(
            previews.values.map((preview) => preview.headingTitle),
          ),
        );
        expect(
          persistedNew.every((chapter) => chapter.parentId == 'volume'),
          isTrue,
        );
        expect(
          persisted.chapters
              .singleWhere((chapter) => chapter.id == 'c')
              .parentId,
          'volume',
        );

        final bodies = <String, Chapter>{};
        for (final chapter in persisted.chapters.where(
          (item) => !item.isVolume,
        )) {
          bodies[chapter.id] = (await fixture.repository.loadChapter(
            _bookId,
            chapter.id,
          ))!;
        }
        expect(_textContent(bodies['a']!), contains('旧稿甲前文🙂'));
        expect(_textContent(bodies['b']!), contains('旧稿乙前文🙂'));
        expect(bodies['c']!.blocks, _blocksC);
        expect(_textContent(bodies['d']!), contains('旧稿丁前文🙂'));
        final allBodyText = bodies.values
            .expand((chapter) => chapter.blocks.whereType<TextBlock>())
            .map((block) => block.text)
            .join('\n');
        expect(allBodyText, isNot(contains(_headingA)));
        expect(allBodyText, isNot(contains(_headingB)));
        expect(allBodyText, isNot(contains(_headingD)));
        expect(allBodyText, contains('第二章正文A🙂'));
        expect(allBodyText, contains('海边正文B🙂'));
        expect(allBodyText, contains('无映射正文🙂'));

        final mappedChapter = persistedNew.singleWhere(
          (chapter) => chapter.title == '第三章',
        );
        final mappedBlocks = bodies[mappedChapter.id]!.blocks;
        expect(mappedBlocks.whereType<ImageBlock>(), [
          const ImageBlock(
            id: 'image-b',
            assetId: 'image-asset',
            caption: '章内插图',
          ),
        ]);
        expect(mappedBlocks.whereType<FootnoteBlock>(), [
          const FootnoteBlock(id: 'footnote-b', text: '章内脚注', marker: '①'),
        ]);
        expect(mappedBlocks.whereType<DividerBlock>(), [
          const DividerBlock(id: 'divider-b'),
        ]);
        expect(mappedBlocks.whereType<TextBlock>().map((block) => block.text), [
          '海边正文B🙂',
          '图片脚注后的正文',
        ]);

        final assets = await fixture.repository.loadAssets(_bookId);
        expect(assets.map((asset) => asset.id), ['image-asset']);
        expect(
          await (await fixture.repository.resolveAsset(assets.single))
              .readAsBytes(),
          _imageBytes,
        );
        final source = (await fixture.repository.loadSource(_bookId))!;
        expect(source.originalName, 'original.txt');
        expect(
          await (await fixture.repository.resolveSource(source)).readAsString(),
          _originalFile,
        );
      } finally {
        await fixture.dispose();
      }
    },
  );

  test('rule or body edits expire the trial before it can write', () async {
    final fixture = await _Fixture.open();
    try {
      await fixture.task.load();
      final originalRule = _staleRule(titleCaptureGroup: 1);
      fixture.task.putRule(originalRule);
      await fixture.task.scan();
      final originalMatch = fixture.task.matches.singleWhere(
        (match) => match.match.chapterId == 'a',
      );
      final originalRevision = fixture.session.saveSeq;

      fixture.task.putRule(_staleRule(titleCaptureGroup: 2));
      expect(fixture.task.hasCurrentTrial, isFalse);
      await fixture.task.applySelected({originalMatch.id});
      expect(fixture.task.failure, isA<ValidationFailure>());
      expect(fixture.session.saveSeq, originalRevision);
      expect(_textContent(fixture.session.activeChapter!), _sourceA);

      await fixture.task.scan();
      final bodyMatch = fixture.task.matches.singleWhere(
        (match) => match.match.chapterId == 'a',
      );
      expect(bodyMatch.match.mappedTitle, '😀归来');
      fixture.session.editBlockText('body-a', '人工编辑后的正文🙂');
      final editedRevision = fixture.session.saveSeq;
      expect(fixture.task.hasCurrentTrial, isFalse);

      await fixture.task.applySelected({bodyMatch.id});
      expect(fixture.task.failure, isA<ValidationFailure>());
      expect(fixture.session.saveSeq, editedRevision);
      expect(_textContent(fixture.session.activeChapter!), '人工编辑后的正文🙂');
      expect(fixture.session.canUndo, isTrue);
    } finally {
      await fixture.dispose();
    }
  });
  test(
    'volume batch preserves front resources and stops at directory boundaries',
    () async {
      for (final boundaryIsVolume in [true, false]) {
        const volumeText = '原章前文\r\n【第二卷 😀归来】\r\n卷前正文';
        final originalChapters = <Chapter>[
          const Chapter(id: 'volume', bookId: _bookId, title: '第一卷', level: 1),
          Chapter(
            id: 'a',
            bookId: _bookId,
            title: '源章',
            parentId: 'volume',
            blocks: [
              const TextBlock(id: 'body-a', text: volumeText),
              ..._blocksB.skip(1),
            ],
          ),
          const Chapter(
            id: 'b',
            bookId: _bookId,
            title: '后续章',
            parentId: 'volume',
            order: 1,
            blocks: [TextBlock(id: 'body-b', text: _sourceB)],
          ),
          const Chapter(
            id: 'c',
            bookId: _bookId,
            title: '后续未命中章',
            parentId: 'volume',
            order: 2,
            blocks: _blocksC,
          ),
          Chapter(
            id: 'boundary',
            bookId: _bookId,
            title: '已有边界',
            level: boundaryIsVolume ? 1 : 2,
            order: 1,
          ),
          Chapter(
            id: 'd',
            bookId: _bookId,
            title: '边界后正文',
            parentId: boundaryIsVolume ? 'boundary' : null,
            order: 2,
            blocks: _blocksD,
          ),
        ];
        final fixture = await _Fixture.open(chapters: originalChapters);
        try {
          await fixture.task.load();
          fixture.task.putRule(
            _chapterRule(
              id: 'volume-rule',
              pattern: r'【(第二卷 😀归来)】',
              positiveExamples: const ['【第二卷 😀归来】'],
              titleCaptureGroup: 1,
              headingLevel: 1,
            ),
          );
          fixture.task.putRule(_wholeMatchRule());
          await fixture.task.scan();
          await fixture.task.saveRule('volume-rule');
          await fixture.task.saveRule('whole-match');
          fixture.task.dispose();
          fixture.task = RuleWorkbenchTask(
            session: fixture.session,
            store: SettingsProofreadingRuleStore(fixture.database),
          );
          await fixture.task.load();
          expect(
            fixture.task.rules
                .singleWhere((rule) => rule.id == 'volume-rule')
                .headingLevel,
            1,
          );
          for (final rule in fixture.task.rules) {
            fixture.task.setRuleSelected(rule.id, true);
          }
          await fixture.task.scan();
          expect(fixture.task.matches, hasLength(2));
          final volumeMatch = fixture.task.matches.singleWhere(
            (item) => item.match.headingLevel == 1,
          );
          final preview = RuleScanChanges.describe(
            await fixture.session.readRuleSnapshot(),
            volumeMatch.match,
          );
          expect(preview.headingTitle, '第二卷 😀归来');
          final revision = fixture.session.saveSeq;
          expect(fixture.session.dirty, isFalse);
          expect(fixture.session.canUndo, isFalse);
          expect(
            (await fixture.repository.loadChapter(_bookId, 'a'))!.blocks,
            originalChapters[1].blocks,
          );
          expect(
            fixture.session.book!.chapters.map((chapter) => chapter.id),
            originalChapters.map((chapter) => chapter.id),
          );

          await fixture.task.applySelected(
            fixture.task.matches.map((item) => item.id).toSet(),
          );
          expect(fixture.task.failure, isNull);
          expect(fixture.task.lastAppliedCount, 2);
          expect(fixture.session.saveSeq, revision + 1);
          final applied = fixture.session.book!.chapters;
          final volume = applied.singleWhere(
            (chapter) => chapter.title == preview.headingTitle,
          );
          expect(volume.level, 1);
          expect(volume.parentId, isNull);
          expect(volume.blocks, isEmpty);
          final front = applied.singleWhere(
            (chapter) => chapter.parentId == volume.id && chapter.frontMatter,
          );
          expect(front.title, '');
          for (final id in ['b', 'c']) {
            expect(
              applied.singleWhere((chapter) => chapter.id == id).parentId,
              volume.id,
            );
          }
          expect(
            applied.singleWhere((chapter) => chapter.title == '第三章').parentId,
            volume.id,
          );
          expect(
            applied.singleWhere((chapter) => chapter.id == 'boundary').parentId,
            isNull,
          );
          expect(
            applied.singleWhere((chapter) => chapter.id == 'd').parentId,
            boundaryIsVolume ? 'boundary' : null,
          );

          await fixture.session.undo();
          expect(fixture.session.canUndo, isFalse);
          expect(
            fixture.session.book!.chapters.map((chapter) => chapter.id),
            originalChapters.map((chapter) => chapter.id),
          );
          expect(
            _textContent(fixture.session.activeChapter!),
            '$volumeText图片脚注后的正文',
          );
          await fixture.session.redo();
          await fixture.session.flush();
          await fixture.session.open(_bookId);
          final persisted = (await fixture.repository.loadBook(_bookId))!;
          expect(
            persisted.chapters
                .singleWhere((chapter) => chapter.id == volume.id)
                .level,
            1,
          );
          expect(
            persisted.chapters
                .singleWhere((chapter) => chapter.id == 'c')
                .parentId,
            volume.id,
          );
          final savedFront = (await fixture.repository.loadChapter(
            _bookId,
            front.id,
          ))!;
          expect(savedFront.frontMatter, isTrue);
          expect(savedFront.title, '');
          expect(savedFront.parentId, volume.id);
          expect(_textContent(savedFront), '卷前正文图片脚注后的正文');
          expect(savedFront.blocks.skip(1), _blocksB.skip(1));
          expect(
            _textContent((await fixture.repository.loadChapter(_bookId, 'a'))!),
            '原章前文\r\n',
          );
          final savedBodies = <Chapter>[];
          for (final chapter in persisted.chapters.where(
            (chapter) => !chapter.isVolume,
          )) {
            savedBodies.add(
              (await fixture.repository.loadChapter(_bookId, chapter.id))!,
            );
          }
          expect(
            savedBodies
                .expand((chapter) => chapter.blocks)
                .whereType<TextBlock>()
                .map((block) => block.text)
                .join(),
            isNot(contains('【第二卷')),
          );
          expect(
            _textContent((await fixture.repository.loadChapter(_bookId, 'd'))!),
            _sourceD,
          );
          final assets = await fixture.repository.loadAssets(_bookId);
          expect(
            await (await fixture.repository.resolveAsset(assets.single))
                .readAsBytes(),
            _imageBytes,
          );
          final source = (await fixture.repository.loadSource(_bookId))!;
          expect(
            await (await fixture.repository.resolveSource(source))
                .readAsString(),
            _originalFile,
          );
        } finally {
          await fixture.dispose();
        }
      }
    },
  );

  test('level changes and body edits reject stale volume trials', () async {
    final fixture = await _Fixture.open();
    try {
      await fixture.task.load();
      String? staleId;
      for (final level in [1, 2]) {
        fixture.task.putRule(
          _chapterRule(
            id: 'level-rule',
            pattern: r'【(第二章 😀归来)】',
            positiveExamples: const [_headingA],
            titleCaptureGroup: 1,
            headingLevel: level,
          ),
        );
        if (level == 1) {
          await fixture.task.scan();
          expect(fixture.task.matches.single.match.headingLevel, 1);
          staleId = fixture.task.matches.single.id;
        }
      }
      final revision = fixture.session.saveSeq;
      expect(fixture.task.hasCurrentTrial, isFalse);
      await fixture.task.applySelected({staleId!});
      expect(fixture.task.failure, isA<ValidationFailure>());
      expect(fixture.session.saveSeq, revision);
      expect(fixture.session.canUndo, isFalse);
      fixture.task.putRule(
        _chapterRule(
          id: 'level-rule',
          pattern: r'【(第二章 😀归来)】',
          positiveExamples: const [_headingA],
          titleCaptureGroup: 1,
          headingLevel: 1,
        ),
      );
      await fixture.task.scan();
      final bodyTrial = fixture.task.matches.single;
      fixture.session.editBlockText('body-a', '人工修改的卷前正文');
      final editedRevision = fixture.session.saveSeq;
      await fixture.task.applySelected({bodyTrial.id});
      expect(fixture.task.failure, isA<ValidationFailure>());
      expect(fixture.session.saveSeq, editedRevision);
      expect(_textContent(fixture.session.activeChapter!), '人工修改的卷前正文');
      expect(fixture.session.book!.chapters, hasLength(5));
    } finally {
      await fixture.dispose();
    }
  });
  test(
    'async commit guard preserves a newly loaded reparented chapter body',
    () async {
      final fixture = await _Fixture.open();
      try {
        await fixture.task.load();
        fixture.task.putRule(
          _chapterRule(
            id: 'guard-volume',
            pattern: r'【(第二章 😀归来)】',
            positiveExamples: const [_headingA],
            titleCaptureGroup: 1,
            headingLevel: 1,
          ),
        );
        await fixture.task.scan();
        final changes = RuleScanChanges.build(
          snapshot: await fixture.session.readRuleSnapshot(),
          sessionId: fixture.session.sessionId!,
          saveSeq: fixture.session.saveSeq,
          selectedMatches: [fixture.task.matches.single.match],
        );
        expect(changes.splitProposals.single.headingLevel, 1);
        expect(
          fixture.session.book!.chapters
              .singleWhere((chapter) => chapter.id == 'b')
              .blocks,
          isEmpty,
        );
        var guarded = false;
        await fixture.session.applyAiChanges(
          textProposals: changes.textProposals,
          splitProposals: changes.splitProposals,
          selectedIds: changes.selectedIds,
          commitGuard: (commit) async {
            await fixture.session.selectChapter('b');
            expect(fixture.session.activeChapter!.blocks, _blocksB);
            guarded = true;
            commit();
          },
        );
        expect(guarded, isTrue);
        final newVolume = fixture.session.book!.chapters.singleWhere(
          (chapter) => chapter.isVolume && chapter.id != 'volume',
        );
        expect(newVolume.title, '第二章 😀归来');
        expect(fixture.session.activeChapter!.id, 'b');
        expect(fixture.session.activeChapter!.parentId, newVolume.id);
        expect(fixture.session.activeChapter!.blocks, _blocksB);
        await fixture.session.undo();
        expect(fixture.session.activeChapter!.parentId, 'volume');
        expect(fixture.session.activeChapter!.blocks, _blocksB);
        expect(fixture.session.book!.chapters, hasLength(5));
        await fixture.session.redo();
        expect(fixture.session.activeChapter!.parentId, newVolume.id);
        expect(fixture.session.activeChapter!.blocks, _blocksB);
        await fixture.session.flush();
        await fixture.session.open(_bookId);
        await fixture.session.selectChapter('b');
        expect(fixture.session.activeChapter!.parentId, newVolume.id);
        expect(fixture.session.activeChapter!.blocks, _blocksB);
        final persisted = (await fixture.repository.loadChapter(_bookId, 'b'))!;
        expect(persisted.parentId, newVolume.id);
        expect(persisted.blocks, _blocksB);
        expect(
          (await fixture.repository.loadChapter(_bookId, 'c'))!.blocks,
          _blocksC,
        );
        final assets = await fixture.repository.loadAssets(_bookId);
        expect(
          await (await fixture.repository.resolveAsset(assets.single))
              .readAsBytes(),
          _imageBytes,
        );
        final source = (await fixture.repository.loadSource(_bookId))!;
        expect(
          await (await fixture.repository.resolveSource(source)).readAsString(),
          _originalFile,
        );
      } finally {
        await fixture.dispose();
      }
    },
  );
  test(
    'number mappings persist and apply exact chapter and volume titles',
    () async {
      const volumeSource = '旧卷前文\r\n【12 😀远航】\r\n卷前正文';
      const chapterSource = '旧章前文\n【十三 归来】\n章正文';
      final fixture = await _Fixture.open(
        chapters: [
          const Chapter(id: 'volume', bookId: _bookId, title: '第一卷', level: 1),
          const Chapter(
            id: 'a',
            bookId: _bookId,
            title: '原章节甲',
            parentId: 'volume',
            blocks: [TextBlock(id: 'body-a', text: volumeSource)],
          ),
          Chapter(
            id: 'b',
            bookId: _bookId,
            title: '原章节乙',
            parentId: 'volume',
            order: 1,
            blocks: [
              const TextBlock(id: 'body-b', text: chapterSource),
              ..._blocksB.skip(1),
            ],
          ),
          const Chapter(
            id: 'c',
            bookId: _bookId,
            title: '第九十九章 不猜编号',
            parentId: 'volume',
            order: 2,
            blocks: _blocksC,
          ),
        ],
      );
      try {
        await fixture.task.load();
        fixture.task.putRule(
          _chapterRule(
            id: 'number-volume',
            pattern: r'【(12) (😀远航)】',
            positiveExamples: const ['【12 😀远航】'],
            titleCaptureGroup: 2,
            numberCaptureGroup: 1,
            headingLevel: 1,
          ),
        );
        fixture.task.putRule(
          _chapterRule(
            id: 'number-chapter',
            pattern: r'【(十三) (归来)】',
            positiveExamples: const ['【十三 归来】'],
            titleCaptureGroup: 2,
            numberCaptureGroup: 1,
          ),
        );
        await fixture.task.scan();
        for (final id in ['number-volume', 'number-chapter']) {
          await fixture.task.saveRule(id);
        }
        fixture.task.dispose();
        fixture.task = RuleWorkbenchTask(
          session: fixture.session,
          store: SettingsProofreadingRuleStore(fixture.database),
        );
        await fixture.task.load();
        expect(fixture.task.rules, hasLength(2));
        for (final rule in fixture.task.rules) {
          expect(rule.numberCaptureGroup, 1);
          expect(rule.titleCaptureGroup, 2);
          fixture.task.setRuleSelected(rule.id, true);
        }
        await fixture.task.scan();
        final snapshot = await fixture.session.readRuleSnapshot();
        final byChapter = {
          for (final item in fixture.task.matches)
            item.match.chapterId: item.match,
        };
        expect(byChapter.keys, unorderedEquals(['a', 'b']));
        expect(byChapter['a']!.mappedNumber, 12);
        expect(byChapter['a']!.numberText, '12');
        expect(byChapter['a']!.mappedTitle, '😀远航');
        expect(byChapter['b']!.mappedNumber, 13);
        expect(byChapter['b']!.numberText, '十三');
        expect(byChapter['b']!.mappedTitle, '归来');
        expect(
          RuleScanChanges.describe(snapshot, byChapter['a']!).headingTitle,
          '第12卷 😀远航',
        );
        expect(
          RuleScanChanges.describe(snapshot, byChapter['b']!).headingTitle,
          '第13章 归来',
        );
        final revision = fixture.session.saveSeq;
        expect(fixture.session.dirty, isFalse);
        expect(fixture.session.canUndo, isFalse);
        expect(
          (await fixture.repository.loadChapter(_bookId, 'b'))!.blocks.first,
          const TextBlock(id: 'body-b', text: chapterSource),
        );
        await fixture.task.applySelected(
          fixture.task.matches.map((item) => item.id).toSet(),
        );
        expect(fixture.task.failure, isNull);
        expect(fixture.task.lastAppliedCount, 2);
        expect(fixture.session.saveSeq, revision + 1);
        final applied = fixture.session.book!.chapters;
        final volume = applied.singleWhere(
          (chapter) => chapter.title == '第12卷 😀远航',
        );
        final chapter = applied.singleWhere(
          (chapter) => chapter.title == '第13章 归来',
        );
        expect(volume.level, 1);
        expect(chapter.parentId, volume.id);
        expect(
          applied.singleWhere((chapter) => chapter.id == 'c').title,
          '第九十九章 不猜编号',
        );
        await fixture.session.undo();
        expect(fixture.session.book!.chapters, hasLength(4));
        expect(fixture.session.canUndo, isFalse);
        expect(_textContent(fixture.session.activeChapter!), volumeSource);
        await fixture.session.redo();
        await fixture.session.flush();
        await fixture.session.open(_bookId);
        await fixture.session.selectChapter(chapter.id);
        expect(fixture.session.activeChapter!.title, '第13章 归来');
        expect(fixture.session.activeChapter!.parentId, volume.id);
        expect(fixture.session.activeChapter!.blocks.skip(1), _blocksB.skip(1));
        expect(_textContent(fixture.session.activeChapter!), '章正文图片脚注后的正文');
        expect(
          _textContent((await fixture.repository.loadChapter(_bookId, 'a'))!),
          '旧卷前文\r\n',
        );
        expect(
          _textContent((await fixture.repository.loadChapter(_bookId, 'b'))!),
          '旧章前文\n',
        );
        final intro = fixture.session.book!.chapters.singleWhere(
          (chapter) => chapter.frontMatter,
        );
        expect(
          _textContent(
            (await fixture.repository.loadChapter(_bookId, intro.id))!,
          ),
          '卷前正文',
        );
        expect(
          (await fixture.repository.loadChapter(_bookId, 'c'))!.blocks,
          _blocksC,
        );
        final assets = await fixture.repository.loadAssets(_bookId);
        expect(
          await (await fixture.repository.resolveAsset(assets.single))
              .readAsBytes(),
          _imageBytes,
        );
        final source = (await fixture.repository.loadSource(_bookId))!;
        expect(
          await (await fixture.repository.resolveSource(source)).readAsString(),
          _originalFile,
        );
      } finally {
        await fixture.dispose();
      }
    },
  );

  test(
    'number mapping changes and body edits invalidate a real trial',
    () async {
      final fixture = await _Fixture.open();
      try {
        await fixture.task.load();
        final rule = _chapterRule(
          id: 'number-stale',
          pattern: r'【第(二)章 (😀归来)】',
          positiveExamples: const [_headingA],
          titleCaptureGroup: 2,
          numberCaptureGroup: 1,
        );
        fixture.task.putRule(rule);
        await fixture.task.scan();
        final staleId = fixture.task.matches.single.id;
        expect(fixture.task.matches.single.match.mappedNumber, 2);
        fixture.task.putRule(
          _chapterRule(
            id: 'number-stale',
            pattern: r'【第(二)章 (😀归来)】',
            positiveExamples: const [_headingA],
            titleCaptureGroup: 2,
          ),
        );
        final revision = fixture.session.saveSeq;
        await fixture.task.applySelected({staleId});
        expect(fixture.task.failure, isA<ValidationFailure>());
        expect(fixture.session.saveSeq, revision);
        expect(fixture.session.canUndo, isFalse);
        fixture.task.putRule(rule);
        await fixture.task.scan();
        final bodyStaleId = fixture.task.matches.single.id;
        fixture.session.editBlockText('body-a', '人工改稿：不允许旧编号写回');
        final editedRevision = fixture.session.saveSeq;
        await fixture.task.applySelected({bodyStaleId});
        expect(fixture.task.failure, isA<ValidationFailure>());
        expect(fixture.session.saveSeq, editedRevision);
        expect(_textContent(fixture.session.activeChapter!), '人工改稿：不允许旧编号写回');
        expect(fixture.session.book!.chapters, hasLength(5));
      } finally {
        await fixture.dispose();
      }
    },
  );
}

ProofreadingRule _mappedRule() => _chapterRule(
  id: 'mapped',
  pattern: r'【(第二章 😀归来)】',
  titleCaptureGroup: 1,
  positiveExamples: const [_headingA],
);

ProofreadingRule _wholeMatchRule() => _chapterRule(
  id: 'whole-match',
  pattern: '第三章',
  titleCaptureGroup: 0,
  positiveExamples: const ['第三章'],
);

ProofreadingRule _unmappedRule() => _chapterRule(
  id: 'unmapped',
  pattern: '第四章',
  positiveExamples: const ['第四章'],
);

ProofreadingRule _staleRule({required int titleCaptureGroup}) => _chapterRule(
  id: 'stale-mapping',
  pattern: r'【(第二章) (😀归来)】',
  titleCaptureGroup: titleCaptureGroup,
  positiveExamples: const [_headingA],
);

ProofreadingRule _chapterRule({
  required String id,
  required String pattern,
  required List<String> positiveExamples,
  int? titleCaptureGroup,
  int? numberCaptureGroup,
  int headingLevel = 2,
}) => ProofreadingRule.create(
  id: id,
  name: '章节标题映射',
  kind: ProofreadingRuleKind.chapter,
  source: ProofreadingRuleSource.user,
  bookId: _bookId,
  target: ProofreadingRuleTarget.headingLine,
  mode: ProofreadingMatchMode.safeRegex,
  pattern: pattern,
  titleCaptureGroup: titleCaptureGroup,
  numberCaptureGroup: numberCaptureGroup,
  headingLevel: headingLevel,
  caseSensitive: true,
  action: ProofreadingRuleAction.chapterCandidate,
  positiveExamples: positiveExamples,
  negativeExamples: const ['普通正文'],
);

String _textContent(Chapter chapter) =>
    chapter.blocks.whereType<TextBlock>().map((block) => block.text).join();

class _Fixture {
  _Fixture({
    required this.supportDirectory,
    required this.database,
    required this.repository,
    required this.session,
  }) : task = RuleWorkbenchTask(
         session: session,
         store: SettingsProofreadingRuleStore(database),
       );

  final Directory supportDirectory;
  final AppDatabase database;
  final BookRepository repository;
  final EditorSession session;
  RuleWorkbenchTask task;
  bool _closed = false;

  static Future<_Fixture> open({List<Chapter>? chapters}) async {
    final supportDirectory = await Directory.systemTemp.createTemp(
      'bookloom-title-mapping-',
    );
    final database = AppDatabase.memory();
    final repository = BookRepository(database, supportDirectory);
    final session = EditorSession(
      repository: repository,
      debounce: const Duration(milliseconds: 1200),
    );
    final fixture = _Fixture(
      supportDirectory: supportDirectory,
      database: database,
      repository: repository,
      session: session,
    );
    try {
      final now = DateTime.utc(2026, 11, 7);
      await repository.createBook(
        Book(
          id: _bookId,
          meta: BookMeta(title: '章节标题映射回归书'),
          createdAt: now,
          updatedAt: now,
          chapters:
              chapters ??
              const [
                Chapter(id: 'volume', bookId: _bookId, title: '第一卷', level: 1),
                Chapter(
                  id: 'a',
                  bookId: _bookId,
                  title: '原章节甲',
                  parentId: 'volume',
                  order: 0,
                  blocks: _blocksA,
                ),
                Chapter(
                  id: 'b',
                  bookId: _bookId,
                  title: '原章节乙',
                  parentId: 'volume',
                  order: 1,
                  blocks: _blocksB,
                ),
                Chapter(
                  id: 'c',
                  bookId: _bookId,
                  title: '未命中章节',
                  parentId: 'volume',
                  order: 2,
                  blocks: _blocksC,
                ),
                Chapter(
                  id: 'd',
                  bookId: _bookId,
                  title: '原章节丁',
                  parentId: 'volume',
                  order: 3,
                  blocks: _blocksD,
                ),
              ],
        ),
        source: SourceImport(
          format: 'txt',
          originalName: 'original.txt',
          openRead: () => Stream<List<int>>.value(utf8.encode(_originalFile)),
        ),
        assets: [
          AssetImport(
            id: 'image-asset',
            kind: 'image',
            mime: 'image/png',
            extension: 'png',
            maxBytes: 32,
            openRead: () => Stream<List<int>>.value(_imageBytes),
          ),
        ],
      );
      await session.open(_bookId);
      return fixture;
    } catch (_) {
      await fixture.dispose();
      rethrow;
    }
  }

  Future<void> dispose() async {
    if (_closed) return;
    _closed = true;
    task.dispose();
    try {
      await session.close();
    } finally {
      await database.close();
      await supportDirectory.delete(recursive: true);
    }
  }
}

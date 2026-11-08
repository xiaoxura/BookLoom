import 'dart:io';
import 'dart:ui' as ui;

import 'package:bookloom/core/model/block.dart';
import 'package:bookloom/core/model/book.dart';
import 'package:bookloom/core/model/chapter.dart';
import 'package:bookloom/core/model/layout_options.dart';
import 'package:bookloom/core/model/metadata.dart';
import 'package:bookloom/core/storage/app_database.dart'
    hide Block, Book, Chapter;
import 'package:bookloom/core/storage/book_repository.dart';
import 'package:bookloom/design/theme/app_theme.dart';
import 'package:bookloom/features/editor/application/editor_session.dart';
import 'package:bookloom/features/editor/presentation/book_settings_panel.dart';
import 'package:bookloom/features/preview/layout_paragraph.dart';
import 'package:bookloom/features/preview/reading_preview.dart';
import 'package:bookloom/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/workbench_ui_harness.dart';

void main() {
  final zh = lookupAppLocalizations(const Locale('zh'));
  setUpAll(() async {
    for (final entry in {
      'Noto Serif CJK SC': 'BOOKLOOM_TEST_SERIF_FONT',
      'Noto Sans CJK SC': 'BOOKLOOM_TEST_SANS_FONT',
    }.entries) {
      final path = Platform.environment[entry.value];
      if (path == null || path.isEmpty) continue;
      final file = File(path);
      final loader = FontLoader(entry.key)
        ..addFont(
          Future<ByteData>.value(
            ByteData.sublistView(await file.readAsBytes()),
          ),
        );
      await loader.load();
    }
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
  });

  testWidgets('layout sample updates at 320px and 2x without changing blocks', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final fixture = (await tester.runAsync(() async {
      final root = await Directory.systemTemp.createTemp(
        'bookloom-layout-sample-',
      );
      final database = AppDatabase.openAt(File('${root.path}/bookloom.sqlite'));
      final repository = BookRepository(database, root);
      return (root: root, database: database, repository: repository);
    }))!;
    final root = fixture.root;
    final database = fixture.database;
    final repository = fixture.repository;
    final files = WorkbenchUiFileService(
      sourceName: 'sample.txt',
      sourceBytes: Uint8List(0),
      exports: root,
    );
    final now = DateTime.utc(2026, 1, 1);
    final book = Book(
      id: 'layout-sample-book',
      meta: BookMeta(title: '海风', author: '林澈'),
      chapters: const [
        Chapter(
          id: 'layout-sample-chapter',
          bookId: 'layout-sample-book',
          title: '第一章',
          blocks: [TextBlock(id: 'layout-sample-block', text: '门边放着一封信。')],
        ),
      ],
      createdAt: now,
      updatedAt: now,
    );
    final session = EditorSession(repository: repository);
    var closed = false;
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      if (!closed) await tester.runAsync(session.close);
      await tester.runAsync(database.close);
      await tester.runAsync(() => root.delete(recursive: true));
    });
    await tester.runAsync(() => repository.createBook(book));
    await tester.runAsync(() => session.open(book.id));
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: AppTheme.light(),
        home: RepaintBoundary(
          key: const ValueKey('layout-sample-screen'),
          child: Scaffold(
            body: BookSettingsPanel(
              session: session,
              repository: repository,
              files: files,
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text(zh.bookWorkbenchMetadata).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text(zh.bookWorkbenchLayoutFonts).last);
    await tester.pumpAndSettle();
    await _captureSampleScreenshot(tester);

    final firstParagraph = find.byKey(
      const ValueKey('layout-sample-paragraph-0'),
    );
    final first = find.descendant(
      of: firstParagraph,
      matching: find.byType(Text),
    );
    final firstPadding = find.descendant(
      of: firstParagraph,
      matching: find.byType(Padding),
    );
    expect(find.text(zh.bookWorkbenchLayoutSampleTitle), findsOneWidget);
    expect(
      tester.widget<LayoutParagraph>(firstParagraph).text,
      zh.bookWorkbenchLayoutSampleFirst,
    );
    expect(
      (tester.widget<Text>(first).textSpan! as TextSpan).children!.first,
      isA<WidgetSpan>(),
    );
    expect(tester.widget<Text>(first).textAlign, TextAlign.justify);
    expect(tester.widget<Text>(first).style!.height, 1.75);
    expect(tester.widget<Text>(first).style!.fontFamily, 'Noto Serif CJK SC');
    expect(
      tester.widget<Text>(first).semanticsLabel,
      zh.bookWorkbenchLayoutSampleFirst,
    );
    final beforeIndent = _firstContentLeft(tester, first, 1);

    final indent = find.text(zh.bookWorkbenchTwoCharacterIndent);
    await tester.ensureVisible(indent);
    await tester.tap(indent);
    await tester.pump();
    expect(
      (tester.widget<Text>(first).textSpan! as TextSpan).children!.first,
      isA<TextSpan>(),
    );
    expect(
      beforeIndent - _firstContentLeft(tester, first, 0),
      closeTo(2 * 16.5 * 2, 1),
    );
    expect(session.book!.layout.indent, isFalse);
    expect((session.activeChapter!.blocks.first as TextBlock).text, '门边放着一封信。');

    final justify = find.text(zh.bookWorkbenchJustify);
    await tester.ensureVisible(justify);
    await tester.tap(justify);
    await tester.pump();
    expect(tester.widget<Text>(first).textAlign, TextAlign.start);

    final controls = find
        .descendant(
          of: find.byKey(const ValueKey('layout-controls')),
          matching: find.byType(Scrollable),
        )
        .first;
    final spacing = find.byKey(const ValueKey('layout-paragraph-spacing'));
    await tester.scrollUntilVisible(spacing, -120, scrollable: controls);
    await tester.pumpAndSettle();
    expect(spacing.hitTestable(), findsOneWidget);
    await tester.drag(spacing, const Offset(100, 0));
    await tester.pump();
    final gap = tester.widget<Padding>(firstPadding).padding as EdgeInsets;
    expect(gap.bottom, greaterThan(0));
    expect(
      gap.bottom,
      closeTo(16.5 * 2 * session.book!.layout.paragraphSpacing, 0.1),
    );

    final lineHeight = find.byKey(const ValueKey('layout-line-height'));
    await tester.scrollUntilVisible(lineHeight, -120, scrollable: controls);
    await tester.pumpAndSettle();
    expect(lineHeight.hitTestable(), findsOneWidget);
    await tester.drag(lineHeight, const Offset(100, 0));
    await tester.pump();
    expect(tester.widget<Text>(first).style!.height, greaterThan(1.75));

    final font = find.byType(DropdownButtonFormField<LayoutFont>);
    await tester.scrollUntilVisible(font, 120, scrollable: controls);
    await tester.pumpAndSettle();
    await tester.tap(font);
    await tester.pumpAndSettle();
    await tester.tap(find.text(zh.bookWorkbenchSans).last);
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(first).style!.fontFamily, 'Noto Sans CJK SC');
    expect(tester.takeException(), isNull);

    tester.view.physicalSize = const Size(320, 600);
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(tester.getRect(first).top, lessThan(600));

    tester.view.viewInsets = const FakeViewPadding(bottom: 240);
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(tester.getRect(first).top, lessThan(360));
    final sampleScroll = find
        .descendant(
          of: find.byKey(const ValueKey('layout-sample-card')),
          matching: find.byType(Scrollable),
        )
        .first;
    final samplePosition = tester.state<ScrollableState>(sampleScroll).position;
    expect(samplePosition.maxScrollExtent, greaterThan(0));
    samplePosition.jumpTo(samplePosition.maxScrollExtent);
    await tester.pump();
    final sampleCard = tester.getRect(
      find.byKey(const ValueKey('layout-sample-card')),
    );
    final scope = tester.getRect(find.text(zh.bookWorkbenchLayoutSampleScope));
    expect(scope.bottom, lessThanOrEqualTo(sampleCard.bottom + 1));
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(session.close);
    closed = true;
    final stored = await tester.runAsync(
      () => repository.loadChapter(book.id, book.chapters.first.id),
    );
    expect((stored!.blocks.first as TextBlock).text, '门边放着一封信。');
  }, timeout: const Timeout(Duration(seconds: 45)));

  testWidgets('reading preview uses the same scaled two-em indent', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(520, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    const paragraph = '雨停之后，街角的灯光映在石板路上。远处传来翻书的声音。';
    const chapter = Chapter(
      id: 'preview-chapter',
      bookId: 'preview-book',
      title: '第一章',
      blocks: [TextBlock(id: 'preview-block', text: paragraph)],
    );
    final now = DateTime.utc(2026, 1, 1);
    final book = Book(
      id: 'preview-book',
      meta: BookMeta(title: '海风', author: '林澈'),
      chapters: const [chapter],
      layout: LayoutOptions(paragraphSpacing: 0.5),
      createdAt: now,
      updatedAt: now,
    );
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: AppTheme.light(),
        home: Scaffold(
          body: ReadingPreview(book: book, chapter: chapter),
        ),
      ),
    );
    final layoutParagraph = find.byType(LayoutParagraph);
    await tester.ensureVisible(layoutParagraph);
    await tester.pump();
    final text = find.descendant(
      of: layoutParagraph,
      matching: find.byType(Text),
    );
    expect(tester.widget<LayoutParagraph>(layoutParagraph).text, paragraph);
    expect(tester.widget<Text>(text).semanticsLabel, paragraph);
    expect(tester.widget<Text>(text).textAlign, TextAlign.justify);
    expect(_firstContentLeft(tester, text, 1), closeTo(2 * 16.5 * 2, 1));
    final padding = tester.widget<Padding>(
      find.descendant(of: layoutParagraph, matching: find.byType(Padding)),
    );
    expect(
      (padding.padding as EdgeInsets).bottom,
      closeTo(16.5 * 2 * 0.5, 0.1),
    );
    expect(tester.takeException(), isNull);
  });
}

double _firstContentLeft(WidgetTester tester, Finder finder, int offset) {
  final paragraph = tester.renderObject<RenderParagraph>(
    find.descendant(of: finder, matching: find.byType(RichText)),
  );
  return paragraph
      .getBoxesForSelection(
        TextSelection(baseOffset: offset, extentOffset: offset + 1),
      )
      .single
      .left;
}

Future<void> _captureSampleScreenshot(WidgetTester tester) async {
  final path = Platform.environment['BOOKLOOM_LAYOUT_SAMPLE_SCREENSHOT'];
  if (path == null || path.isEmpty) return;
  tester.view.physicalSize = const Size(520, 900);
  await tester.pump();
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('layout-sample-screen')),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) throw StateError('Could not encode sample screenshot');
      await File(path).writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      );
    } finally {
      image.dispose();
    }
  });
  tester.view.physicalSize = const Size(320, 900);
  await tester.pump();
}

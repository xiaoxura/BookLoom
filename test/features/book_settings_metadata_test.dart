import 'dart:io';
import 'dart:typed_data';

import 'package:bookloom/core/model/book.dart';
import 'package:bookloom/core/model/metadata.dart';
import 'package:bookloom/core/storage/app_database.dart' hide Block, Book;
import 'package:bookloom/core/storage/book_repository.dart';
import 'package:bookloom/design/theme/app_theme.dart';
import 'package:bookloom/features/editor/application/editor_session.dart';
import 'package:bookloom/features/editor/presentation/book_settings_panel.dart';
import 'package:bookloom/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/workbench_ui_harness.dart';

void main() {
  final zh = lookupAppLocalizations(const Locale('zh'));

  testWidgets('description is basic info and extended info stays collapsed', (
    tester,
  ) async {
    final fixture = (await tester.runAsync(() async {
      final root = await Directory.systemTemp.createTemp(
        'bookloom-settings-meta-',
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
    final now = DateTime.utc(2026);
    final book = Book(
      id: 'settings-meta-book',
      meta: BookMeta(title: '海风', author: '林澈'),
      createdAt: now,
      updatedAt: now,
    );
    final session = EditorSession(repository: repository);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(session.close);
      await tester.runAsync(database.close);
      await tester.runAsync(() => root.delete(recursive: true));
    });
    await tester.runAsync(() => repository.createBook(book));
    await tester.runAsync(() => session.open(book.id));

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: AppTheme.light(),
        home: Scaffold(
          body: BookSettingsPanel(
            session: session,
            repository: repository,
            files: files,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.pumpAndSettle();

    // 简介 belongs to the basic section, above the 扩展信息 tile.
    expect(find.text(zh.editorDescription), findsOneWidget);
    expect(find.byKey(const ValueKey('book-extended-header')), findsOneWidget);
    // The extended fields are collapsed until the tile is expanded.
    expect(find.text(zh.editorSeries), findsNothing);

    await tester.tap(find.byKey(const ValueKey('book-extended-header')));
    await tester.pumpAndSettle();
    expect(find.text(zh.editorSeries), findsOneWidget);
    // Toggling again removes the fields from the tree entirely.
    await tester.tap(find.byKey(const ValueKey('book-extended-header')));
    await tester.pumpAndSettle();
    expect(find.text(zh.editorSeries), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

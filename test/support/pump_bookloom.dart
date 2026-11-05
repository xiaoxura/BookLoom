import 'dart:io';

import 'package:bookloom/app/app.dart';
import 'package:bookloom/app/providers.dart';
import 'package:bookloom/app/workbench_providers.dart';
import 'package:bookloom/core/platform/app_paths.dart';
import 'package:bookloom/core/storage/app_database.dart';
import 'package:bookloom/core/storage/book_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Dispose subscriptions before Flutter checks post-test timer invariants.
/// addTearDown runs after those checks, so it is only for file/database cleanup.
void testBookloomWidgets(
  String description,
  WidgetTesterCallback body, {
  Timeout? timeout,
}) {
  testWidgets(description, (tester) async {
    try {
      await body(tester);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(Duration.zero);
    }
  }, timeout: timeout);
}

/// Pumps the real app with an in-memory database and a temp data folder.
Future<void> pumpBookloom(
  WidgetTester tester, {
  Size size = const Size(1280, 900),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  // Tests assert Simplified Chinese copy, so pin the platform locale.
  tester.platformDispatcher.localesTestValue = <Locale>[const Locale('zh')];
  addTearDown(tester.platformDispatcher.clearLocalesTestValue);

  late final AppDatabase db;
  late final Directory temp;
  late final BookRepository repository;
  // Recovery touches real files. Let it finish outside the widget fake clock
  // before mounting the shelf's loading indicator.
  await tester.runAsync(() async {
    db = AppDatabase.memory();
    temp = await Directory.systemTemp.createTemp('bookloom_test');
    repository = BookRepository(db, temp);
    await repository.listSummaries();
  });
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
    await tester.runAsync(() async {
      await db.close();
      await temp.delete(recursive: true);
    });
    await tester.pump(Duration.zero);
  });

  final AppPaths paths = AppPaths(
    support: temp,
    books: temp,
    logs: temp,
    cache: temp,
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        appPathsProvider.overrideWithValue(paths),
        bookRepositoryProvider.overrideWithValue(repository),
      ],
      child: const BookloomApp(),
    ),
  );
  for (var attempt = 0; attempt < 30; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 1)),
    );
    await tester.pump();
    if (find.byType(CircularProgressIndicator).evaluate().isEmpty) break;
  }
  await tester.pumpAndSettle();
}

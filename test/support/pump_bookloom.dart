import 'dart:io';

import 'package:bookloom/app/app.dart';
import 'package:bookloom/app/providers.dart';
import 'package:bookloom/core/platform/app_paths.dart';
import 'package:bookloom/core/storage/app_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

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

  final AppDatabase db = AppDatabase.memory();
  addTearDown(db.close);

  final Directory temp = Directory.systemTemp.createTempSync('bookloom_test');
  addTearDown(() => temp.deleteSync(recursive: true));

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
      ],
      child: const BookloomApp(),
    ),
  );
  await tester.pumpAndSettle();
}

import 'package:bookloom/core/model/book.dart';
import 'package:bookloom/core/model/metadata.dart';
import 'package:bookloom/design/components/app_select_field.dart';
import 'package:bookloom/l10n/app_localizations.dart';
import 'package:flutter/foundation.dart'
    show debugDefaultTargetPlatformOverride;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/pump_bookloom.dart' as support show testBookloomWidgets;
import '../support/workbench_ui_harness.dart';

final AppLocalizations _zh = lookupAppLocalizations(const Locale('zh'));

void testBookloomWidgets(String description, WidgetTesterCallback body) {
  support.testBookloomWidgets(description, (tester) async {
    try {
      await body(tester);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}

void main() {
  testBookloomWidgets(
    'phone shelf sorts books and keeps toolbar actions usable',
    (WidgetTester tester) async {
      final harness = await WorkbenchUiHarness.pump(
        tester,
        size: const Size(363, 844),
        platform: TargetPlatform.android,
      );
      await _seedBooks(harness);
      await _pumpUntil(tester, () => find.text('C书').evaluate().isNotEmpty);

      final search = _searchField();
      final sort = _sortField();
      final import = find.widgetWithText(FilledButton, _zh.navImport);
      expect(sort, findsOneWidget);
      expect(find.byType(DropdownButton), findsNothing);
      final searchRect = tester.getRect(search);
      final sortRect = tester.getRect(
        find.descendant(of: sort, matching: find.byType(TextField)),
      );
      final importRect = tester.getRect(import);
      expect(
        find.byWidgetPredicate(
          (widget) => widget is AppSelectField && widget.compact,
        ),
        findsOneWidget,
      );
      expect(find.text(_zh.librarySortBy), findsNothing);
      expect(
        find.descendant(
          of: sort,
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Semantics &&
                widget.properties.label == _zh.librarySortBy,
          ),
        ),
        findsOneWidget,
      );
      expect(sortRect.top, greaterThan(searchRect.bottom));
      expect(sortRect.left, closeTo(searchRect.left, 1));
      expect(sortRect.width, inInclusiveRange(160, 180));
      expect(sortRect.height, 48);
      expect(importRect.height, 48);
      expect(importRect.right, closeTo(searchRect.right, 1));
      expect(importRect.center.dy, closeTo(sortRect.center.dy, 1));
      expect(importRect.top, closeTo(sortRect.top, 1));
      expect(importRect.bottom, closeTo(sortRect.bottom, 1));
      _expectBookOrder(tester, 'C书', 'B书');

      final searchFocus = tester
          .widget<EditableText>(
            find.descendant(of: search, matching: find.byType(EditableText)),
          )
          .focusNode;
      final outside = Offset(searchRect.left + 2, searchRect.bottom + 4);
      for (final kind in <PointerDeviceKind>[
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
      ]) {
        await tester.tap(search);
        await tester.pump();
        expect(searchFocus.hasFocus, isTrue);
        await tester.tapAt(outside, kind: kind);
        await tester.pump();
        expect(searchFocus.hasFocus, isFalse);
      }

      await _selectSort(tester, _zh.librarySortTitle);
      _expectBookOrder(tester, 'A书', 'B书');
      await _selectSort(tester, _zh.librarySortOpened);
      _expectBookOrder(tester, 'B书', 'C书');

      await tester.tap(search);
      await tester.pump();
      expect(searchFocus.hasFocus, isTrue);
      await tester.tap(import);
      await tester.pumpAndSettle();
      expect(find.text(_zh.importChooseFile), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testBookloomWidgets('wide shelf keeps import action at the right edge', (
    WidgetTester tester,
  ) async {
    final harness = await WorkbenchUiHarness.pump(
      tester,
      platform: TargetPlatform.linux,
    );
    await harness.seedBook();
    await _pumpUntil(tester, () => find.text('海风').evaluate().isNotEmpty);
    final searchRect = tester.getRect(_searchField());
    final importRect = tester.getRect(
      find.widgetWithText(FilledButton, _zh.navImport),
    );
    expect(importRect.left, greaterThan(searchRect.right));
    expect(
      importRect.right,
      closeTo(tester.getRect(find.byType(ListView).first).right, 1),
    );
    expect(tester.takeException(), isNull);
  });

  testBookloomWidgets('320px shelf keeps normal-size actions on one row', (
    WidgetTester tester,
  ) async {
    final harness = await WorkbenchUiHarness.pump(
      tester,
      size: const Size(320, 900),
      platform: TargetPlatform.android,
    );
    await harness.seedBook();
    await _pumpUntil(tester, () => find.text('海风').evaluate().isNotEmpty);
    final sortRect = tester.getRect(_sortField());
    final importRect = tester.getRect(
      find.widgetWithText(FilledButton, _zh.navImport),
    );
    expect(sortRect.width, inInclusiveRange(160, 180));
    expect(importRect.center.dy, closeTo(sortRect.center.dy, 1));
    expect(importRect.right, closeTo(300, 1));
    expect(tester.takeException(), isNull);
  });

  for (final platform in <TargetPlatform>[
    TargetPlatform.android,
    TargetPlatform.iOS,
  ]) {
    testBookloomWidgets(
      '$platform storage explains private data and keeps backup',
      (WidgetTester tester) async {
        final harness = await WorkbenchUiHarness.pump(
          tester,
          size: const Size(390, 844),
          platform: platform,
        );
        await _openStorage(tester);
        expect(find.text(_zh.settingsDataLocationMobileDesc), findsOneWidget);
        expect(find.text(harness.paths.support.path), findsNothing);
        expect(find.text(_zh.settingsCopyPath), findsNothing);
        expect(find.text(_zh.workbenchOpenData), findsOneWidget);
        await tester.tap(find.text(_zh.workbenchOpenData));
        await _pumpUntil(
          tester,
          () => find.text(_zh.dataWorkbenchBackupTitle).evaluate().isNotEmpty,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testBookloomWidgets('desktop storage copies the visible data path', (
    WidgetTester tester,
  ) async {
    final platformCalls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        platformCalls.add(call);
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final harness = await WorkbenchUiHarness.pump(
      tester,
      platform: TargetPlatform.linux,
    );
    await _openStorage(tester);
    expect(find.text(_zh.settingsDataLocationDesc), findsOneWidget);
    expect(find.text(harness.paths.support.path), findsOneWidget);
    expect(find.text(_zh.settingsDataLocationMobileDesc), findsNothing);
    await tester.tap(find.text(_zh.settingsCopyPath));
    await tester.pump();
    final copy = platformCalls.singleWhere(
      (call) => call.method == 'Clipboard.setData',
    );
    expect(
      (copy.arguments as Map<Object?, Object?>)['text'],
      harness.paths.support.path,
    );
    expect(find.text(_zh.settingsCopied), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testBookloomWidgets('320px shelf and storage fit at 2x text', (
    WidgetTester tester,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final harness = await WorkbenchUiHarness.pump(
      tester,
      size: const Size(320, 900),
      platform: TargetPlatform.android,
    );
    await harness.seedBook();
    await _pumpUntil(tester, () => find.text('海风').evaluate().isNotEmpty);
    final searchRect = tester.getRect(_searchField());
    final sortRect = tester.getRect(_sortField());
    final sortInputRect = tester.getRect(
      find.descendant(of: _sortField(), matching: find.byType(TextField)),
    );
    final importRect = tester.getRect(
      find.widgetWithText(FilledButton, _zh.navImport),
    );
    expect(sortRect.top, greaterThan(searchRect.bottom));
    expect(importRect.top, greaterThanOrEqualTo(sortRect.bottom));
    expect(sortInputRect.width, 220);
    expect(sortInputRect.height, greaterThan(48));
    expect(sortRect.right, lessThanOrEqualTo(searchRect.right));
    expect(importRect.right, lessThanOrEqualTo(320));
    expect(tester.takeException(), isNull);

    await _openStorage(tester);
    expect(find.text(_zh.settingsDataLocationMobileDesc), findsOneWidget);
    expect(find.text(_zh.workbenchOpenData), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Finder _searchField() => find.byWidgetPredicate(
  (widget) =>
      widget is TextField && widget.decoration?.hintText == _zh.librarySearch,
);

Finder _sortField() =>
    find.byWidgetPredicate((widget) => widget is AppSelectField);

void _expectBookOrder(WidgetTester tester, String first, String second) {
  expect(
    tester.getTopLeft(find.text(first)).dy,
    lessThan(tester.getTopLeft(find.text(second)).dy),
  );
}

Future<void> _selectSort(WidgetTester tester, String label) async {
  await tester.tap(
    find.descendant(of: _sortField(), matching: find.byType(TextField)),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

Future<void> _openStorage(WidgetTester tester) async {
  await tester.tap(find.text(_zh.navSettings).last);
  await tester.pumpAndSettle();
  final entry = find.text(_zh.settingsStorageTitle);
  await tester.ensureVisible(entry);
  await tester.tap(entry);
  await tester.pumpAndSettle();
}

Future<void> _seedBooks(WorkbenchUiHarness harness) async {
  for (final record in <({String id, String title, int edited, int opened})>[
    (id: 'alpha', title: 'A书', edited: 1, opened: 1),
    (id: 'beta', title: 'B书', edited: 2, opened: 5),
    (id: 'gamma', title: 'C书', edited: 3, opened: 4),
  ]) {
    await harness.tester.runAsync(
      () => harness.repository.createBook(
        Book(
          id: record.id,
          meta: BookMeta(title: record.title),
          createdAt: DateTime.utc(2026, 1, 1),
          updatedAt: DateTime.utc(2026, 1, record.edited),
          lastOpenedAt: DateTime.utc(2026, 1, record.opened),
        ),
      ),
    );
  }
}

Future<void> _pumpUntil(WidgetTester tester, bool Function() condition) async {
  for (var attempt = 0; attempt < 100; attempt++) {
    if (condition()) return;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
  }
  expect(condition(), isTrue, reason: 'Expected page state did not appear');
}

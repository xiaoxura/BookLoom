import 'package:bookloom/core/model/chapter.dart';
import 'package:bookloom/design/components/app_select_field.dart';
import 'package:bookloom/design/theme/app_theme.dart';
import 'package:bookloom/features/editor/presentation/chapter_management_dialogs.dart';
import 'package:bookloom/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../../support/pump_bookloom.dart';

const _chapters = <Chapter>[
  Chapter(id: 'v1', bookId: 'book', title: '第一卷', level: 1),
  Chapter(id: 'a', bookId: 'book', title: '第一章', parentId: 'v1'),
  Chapter(id: 'v2', bookId: 'book', title: '第二卷', level: 1),
  Chapter(id: 'b', bookId: 'book', title: '第二章', parentId: 'v2'),
];

void main() {
  final l10n = lookupAppLocalizations(const Locale('zh'));

  testBookloomWidgets('new volume rejects blank titles and trims submission', (
    tester,
  ) async {
    String? result;
    await _open(tester, (context) async {
      result = await showNewVolumeDialog(context);
    });
    final button = find.widgetWithText(FilledButton, l10n.editorCreate);
    expect(tester.widget<FilledButton>(button).onPressed, isNull);
    await tester.enterText(find.byType(TextField), '  ');
    await tester.pump();
    expect(tester.widget<FilledButton>(button).onPressed, isNull);
    await tester.enterText(find.byType(TextField), '  第三卷  ');
    await tester.pump();
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(result, '第三卷');
    expect(tester.takeException(), isNull);
  });

  testBookloomWidgets(
    'new chapter defaults after active chapter and can insert before first',
    (tester) async {
      NewChapterRequest? result;
      await _open(tester, (context) async {
        result = await showNewChapterDialog(
          context,
          chapters: _chapters,
          activeChapterId: 'a',
        );
      });
      await tester.enterText(_title(l10n), '补充章节');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, l10n.editorCreate));
      await tester.pumpAndSettle();
      expect(result, (
        title: '补充章节',
        volumeId: 'v1',
        beforeChapterId: null,
        afterChapterId: 'a',
      ));

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.enterText(_title(l10n), '卷首补章');
      await _choose(tester, l10n.editorTargetVolume, '第二卷');
      final position = find.byWidgetPredicate(
        (widget) =>
            widget is AppSelectField<String> &&
            widget.label == l10n.editorInsertPosition,
      );
      expect(
        tester
            .widget<AppSelectField<String>>(position)
            .entries
            .map((entry) => entry.value),
        <String>['', 'b'],
      );
      await _choose(tester, l10n.editorInsertPosition, l10n.editorBeforeFirst);
      await tester.tap(find.widgetWithText(FilledButton, l10n.editorCreate));
      await tester.pumpAndSettle();
      expect(result, (
        title: '卷首补章',
        volumeId: 'v2',
        beforeChapterId: 'b',
        afterChapterId: null,
      ));
      expect(tester.takeException(), isNull);
    },
  );

  testBookloomWidgets(
    'unassigned chapters can be inserted before or after volumes',
    (tester) async {
      const volumes = <Chapter>[
        Chapter(id: 'v1', bookId: 'book', title: '第一卷', level: 1),
        Chapter(id: 'v2', bookId: 'book', title: '第二卷', level: 1),
      ];
      NewChapterRequest? result;
      await _open(tester, (context) async {
        result = await showNewChapterDialog(context, chapters: volumes);
      });
      final position = find.byWidgetPredicate(
        (widget) =>
            widget is AppSelectField<String> &&
            widget.label == l10n.editorInsertPosition,
      );
      expect(
        tester
            .widget<AppSelectField<String>>(position)
            .entries
            .map((entry) => entry.value),
        <String>['', 'v1', 'v2'],
      );
      await tester.enterText(_title(l10n), '两卷之间');
      await _choose(
        tester,
        l10n.editorInsertPosition,
        l10n.editorAfterChapter('第一卷'),
      );
      await tester.tap(find.widgetWithText(FilledButton, l10n.editorCreate));
      await tester.pumpAndSettle();
      expect(result, (
        title: '两卷之间',
        volumeId: null,
        beforeChapterId: null,
        afterChapterId: 'v1',
      ));

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.enterText(_title(l10n), '首卷之前');
      await _choose(tester, l10n.editorInsertPosition, l10n.editorBeforeFirst);
      await tester.tap(find.widgetWithText(FilledButton, l10n.editorCreate));
      await tester.pumpAndSettle();
      expect(result, (
        title: '首卷之前',
        volumeId: null,
        beforeChapterId: 'v1',
        afterChapterId: null,
      ));
      expect(tester.takeException(), isNull);
    },
  );

  testBookloomWidgets(
    'batch move selects chapters only and cancellation produces no request',
    (tester) async {
      MoveChaptersRequest? result;
      await _open(tester, (context) async {
        result = await showMoveChaptersDialog(
          context,
          chapters: _chapters,
          initialVolumeId: 'v2',
        );
      });
      expect(find.byType(CheckboxListTile), findsNWidgets(2));
      final move = find.widgetWithText(FilledButton, l10n.editorMove);
      expect(tester.widget<FilledButton>(move).onPressed, isNull);
      await tester.tap(find.text(l10n.editorSelectAll));
      await tester.pump();
      await tester.tap(move);
      await tester.pumpAndSettle();
      expect(result!.volumeId, 'v2');
      expect(result!.chapterIds, {'a', 'b'});
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.editorSelectAll));
      await tester.pump();
      await tester.tap(find.text(l10n.editorClearSelection));
      await tester.pump();
      expect(tester.widget<FilledButton>(move).onPressed, isNull);
      await tester.tap(find.text(l10n.commonCancel));
      await tester.pumpAndSettle();
      expect(result, isNull);
      expect(tester.takeException(), isNull);
    },
  );

  for (final type in ['chapter', 'move']) {
    testBookloomWidgets('$type dialog fits 320px with 2x text', (tester) async {
      await _open(
        tester,
        (context) async {
          if (type == 'chapter') {
            await showNewChapterDialog(context, chapters: _chapters);
          } else {
            await showMoveChaptersDialog(context, chapters: _chapters);
          }
        },
        size: const Size(320, 720),
        scale: 2,
      );
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text(l10n.commonCancel));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}

Finder _title(AppLocalizations l10n) => find.byWidgetPredicate(
  (widget) =>
      widget is TextField &&
      widget.decoration?.labelText == l10n.editorChapterTitle,
);

Future<void> _choose(WidgetTester tester, String label, String choice) async {
  final field = find.byWidgetPredicate(
    (widget) => widget is AppSelectField<String> && widget.label == label,
  );
  await tester.ensureVisible(field);
  await tester.tap(
    find.descendant(of: field, matching: find.byType(TextField)),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text(choice).last);
  await tester.pumpAndSettle();
}

Future<void> _open(
  WidgetTester tester,
  Future<void> Function(BuildContext) open, {
  Size size = const Size(520, 900),
  double scale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => Scaffold(
          body: TextButton(
            onPressed: () => open(context),
            child: const Text('open'),
          ),
        ),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    MaterialApp.router(
      theme: AppTheme.light(),
      locale: const Locale('zh'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      routerConfig: router,
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

import 'package:bookloom/app/shell/app_shell.dart' show debugForceMobileShell;
import 'package:bookloom/core/formatting/document_export.dart';
import 'package:bookloom/core/settings/appearance.dart';
import 'package:bookloom/design/components/app_select_field.dart';
import 'package:bookloom/design/theme/app_theme.dart';
import 'package:bookloom/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../support/pump_bookloom.dart';

void main() {
  final zh = lookupAppLocalizations(const Locale('zh'));

  testWidgets(
    'Android root menu advertises Back only while open',
    (WidgetTester tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      final List<bool> frameworkHandlesBack = <bool>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (MethodCall call) async {
          if (call.method == 'SystemNavigator.setFrameworkHandlesBack') {
            frameworkHandlesBack.add(call.arguments as bool);
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );

      ExportFormat selected = ExportFormat.epub3;
      var showField = true;
      late StateSetter updateRoot;
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) => StatefulBuilder(
              builder: (context, update) {
                updateRoot = update;
                return Scaffold(
                  body: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        if (showField)
                          AppSelectField<ExportFormat>(
                            label: 'Default export format',
                            initialSelection: selected,
                            entries: const [
                              DropdownMenuEntry(
                                value: ExportFormat.epub3,
                                label: 'EPUB 3',
                              ),
                              DropdownMenuEntry(
                                value: ExportFormat.epub2,
                                label: 'EPUB 2',
                              ),
                            ],
                            onSelected: (value) => selected = value ?? selected,
                          ),
                        const Text('Outside menu'),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        MaterialApp.router(routerConfig: router, theme: AppTheme.light()),
      );
      expect(frameworkHandlesBack.last, isFalse);

      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();
      expect(find.text('EPUB 2'), findsOneWidget);
      expect(frameworkHandlesBack.last, isTrue);

      expect(await tester.binding.handlePopRoute(), isTrue);
      await tester.pumpAndSettle();
      expect(find.text('EPUB 2'), findsNothing);
      expect(selected, ExportFormat.epub3);
      expect(frameworkHandlesBack.last, isFalse);

      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();
      expect(frameworkHandlesBack.last, isTrue);
      await tester.tapAt(const Offset(700, 500));
      await tester.pumpAndSettle();
      expect(frameworkHandlesBack.last, isFalse);

      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();
      expect(frameworkHandlesBack.last, isTrue);
      await tester.tap(find.text('EPUB 2').last);
      await tester.pumpAndSettle();
      expect(selected, ExportFormat.epub2);
      expect(frameworkHandlesBack.last, isFalse);

      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();
      expect(frameworkHandlesBack.last, isTrue);
      updateRoot(() => showField = false);
      await tester.pumpAndSettle();
      expect(frameworkHandlesBack.last, isFalse);
      expect(tester.takeException(), isNull);
    },
    variant: const TargetPlatformVariant(<TargetPlatform>{
      TargetPlatform.android,
    }),
  );

  testWidgets('system Back closes the menu before popping its route', (
    WidgetTester tester,
  ) async {
    ExportFormat selected = ExportFormat.epub3;
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () => context.push('/chooser'),
                child: const Text('Open chooser'),
              ),
            ),
          ),
        ),
        GoRoute(
          path: '/chooser',
          builder: (context, state) => Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(16),
              child: AppSelectField<ExportFormat>(
                label: 'Default export format',
                initialSelection: selected,
                entries: const [
                  DropdownMenuEntry(value: ExportFormat.epub3, label: 'EPUB 3'),
                  DropdownMenuEntry(value: ExportFormat.epub2, label: 'EPUB 2'),
                ],
                onSelected: (value) => selected = value ?? selected,
              ),
            ),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      MaterialApp.router(routerConfig: router, theme: AppTheme.light()),
    );
    await tester.tap(find.text('Open chooser'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    expect(find.text('EPUB 2'), findsOneWidget);

    expect(await tester.binding.handlePopRoute(), isTrue);
    await tester.pumpAndSettle();
    expect(find.text('EPUB 2'), findsNothing);
    expect(find.text('Default export format'), findsOneWidget);
    expect(selected, ExportFormat.epub3);

    expect(await tester.binding.handlePopRoute(), isTrue);
    await tester.pumpAndSettle();
    expect(find.text('Open chooser'), findsOneWidget);
    expect(selected, ExportFormat.epub3);
  });

  testBookloomWidgets(
    '363px settings show all theme choices without scrolling',
    (WidgetTester tester) async {
      debugForceMobileShell = true;
      addTearDown(() => debugForceMobileShell = false);
      await pumpBookloom(tester, size: const Size(363, 800));
      await tester.tap(find.text(zh.navSettings).last);
      await tester.pumpAndSettle();
      // Theme controls live on their own page behind the settings index.
      await tester.tap(find.text(zh.settingsAppearance));
      await tester.pumpAndSettle();

      final Finder themeControl = find.byWidgetPredicate(
        (widget) => widget is SegmentedButton<AppThemeMode>,
      );
      expect(tester.getSize(themeControl).height, greaterThanOrEqualTo(48));
      final Finder viewport = find.ancestor(
        of: themeControl,
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is SingleChildScrollView &&
              widget.scrollDirection == Axis.horizontal,
        ),
      );
      final Rect visible = tester.getRect(viewport);
      for (final label in <String>[
        zh.themeSystem,
        zh.themeLight,
        zh.themeDark,
      ]) {
        final Finder segment = find.ancestor(
          of: find.text(label),
          matching: find.byType(TextButton),
        );
        final Rect bounds = tester.getRect(segment);
        expect(bounds.left, greaterThanOrEqualTo(visible.left));
        expect(bounds.right, lessThanOrEqualTo(visible.right));
        expect(find.text(label).hitTestable(), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    },
  );

  testBookloomWidgets('320px settings keep scaled choices reachable', (
    WidgetTester tester,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    debugForceMobileShell = true;
    addTearDown(() => debugForceMobileShell = false);
    await pumpBookloom(tester, size: const Size(320, 900));

    await tester.tap(find.text(zh.navSettings).last);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.tap(find.text(zh.settingsAppearance));
    await tester.pumpAndSettle();

    final Finder systemLabel = find.text(zh.themeSystem);
    final RenderParagraph systemText = tester.renderObject(systemLabel);
    expect(
      systemText.getBoxesForSelection(
        TextSelection(baseOffset: 0, extentOffset: zh.themeSystem.length),
      ),
      hasLength(1),
    );

    final Finder darkLabel = find.text(zh.themeDark);
    await tester.ensureVisible(darkLabel);
    await tester.pumpAndSettle();
    expect(darkLabel.hitTestable(), findsOneWidget);
    await tester.tap(darkLabel);
    await tester.pumpAndSettle();
    final Finder themeControl = find.byWidgetPredicate(
      (widget) => widget is SegmentedButton<AppThemeMode>,
    );
    expect(
      tester.widget<SegmentedButton<AppThemeMode>>(themeControl).selected,
      contains(AppThemeMode.dark),
    );
    expect(tester.takeException(), isNull);

    final Finder formatMenu = find.byWidgetPredicate(
      (widget) => widget is DropdownMenu<ExportFormat>,
    );
    // Leave the appearance page and open the defaults page instead.
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text(zh.settingsDefaultsTitle));
    await tester.pumpAndSettle();
    await tester.ensureVisible(formatMenu);
    await tester.pumpAndSettle();
    final Finder input = find.descendant(
      of: formatMenu,
      matching: find.byType(TextField),
    );
    expect(tester.getSize(input).width, lessThan(320));
    await tester.tap(input);
    await tester.pumpAndSettle();
    expect(find.text('EPUB 2'), findsOneWidget);
    expect(await tester.binding.handlePopRoute(), isTrue);
    await tester.pumpAndSettle();
    // The settings index stays mounted under the pushed page, so the section
    // title is present more than once.
    expect(find.text(zh.settingsDefaultsTitle), findsWidgets);
    expect(find.text('EPUB 2'), findsNothing);
    expect(tester.widget<TextField>(input).controller?.text, 'EPUB 3');

    await tester.tap(input);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Markdown').last);
    await tester.pumpAndSettle();
    expect(find.text('Markdown').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

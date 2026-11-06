import 'dart:ui' as ui;

import 'package:bookloom/app/shell/app_shell.dart' show debugForceMobileShell;
import 'package:bookloom/design/components/app_mark.dart';
import 'package:bookloom/design/components/app_page.dart';
import 'package:bookloom/design/components/glass_surface.dart';
import 'package:bookloom/design/tokens/app_metrics.dart';
import 'package:bookloom/l10n/app_localizations.dart';
import 'package:flutter/foundation.dart'
    show debugDefaultTargetPlatformOverride;
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/pump_bookloom.dart';

void main() {
  final AppLocalizations zh = lookupAppLocalizations(const Locale('zh'));

  /// Desktop keeps the rail at every width, so narrow-window tests that want
  /// the phone chrome have to ask for it explicitly.
  Future<void> pumpMobileShell(
    WidgetTester tester, {
    Size size = const Size(520, 900),
  }) async {
    debugForceMobileShell = true;
    addTearDown(() => debugForceMobileShell = false);
    await pumpBookloom(tester, size: size);
  }

  testBookloomWidgets('desktop shell shows the sidebar and the empty shelf', (
    WidgetTester tester,
  ) async {
    await pumpBookloom(tester);

    expect(find.text(zh.navLibrary), findsWidgets);
    expect(find.text(zh.navImport), findsWidgets);
    expect(find.text(zh.navSettings), findsWidgets);
    // About lives under settings now, so the rail has three entries.
    expect(find.text(zh.navAbout), findsNothing);
    expect(find.text(zh.libraryEmptyTitle), findsOneWidget);
    expect(find.text(zh.libraryEmptyMessage), findsOneWidget);
    expect(find.text(zh.libraryEmptyAction), findsOneWidget);
    expect(find.byKey(const Key('bottom-navigation')), findsNothing);

    // The sidebar footer no longer carries copy; the shelf owns the bottom.
    // Branches are preloaded, so the first switch to another tab does not pay
    // a first-build cost: the settings page already exists offstage.
    expect(
      find.text(zh.settingsAppearance, skipOffstage: false),
      findsOneWidget,
    );
  });

  testBookloomWidgets('empty shelf action opens the import page', (
    WidgetTester tester,
  ) async {
    await pumpBookloom(tester);

    await tester.tap(find.text(zh.libraryEmptyAction));
    await tester.pumpAndSettle();

    expect(find.text(zh.importChooseFile), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testBookloomWidgets('sidebar navigation switches to the import page', (
    WidgetTester tester,
  ) async {
    await pumpBookloom(tester);

    await tester.tap(find.text(zh.navImport).first);
    await tester.pumpAndSettle();

    expect(find.text(zh.importFormatsTitle), findsOneWidget);
    expect(
      find.text(zh.importFormatAvailable(zh.importFormatTxt)),
      findsOneWidget,
    );
    // Guidance stays: each format explains what it will do.
    expect(find.text(zh.importFormatTxtDesc), findsOneWidget);
  });

  testBookloomWidgets('settings page exposes appearance and data sections', (
    WidgetTester tester,
  ) async {
    await pumpBookloom(tester);

    await tester.tap(find.text(zh.navSettings).first);
    await tester.pumpAndSettle();

    expect(find.text(zh.settingsAppearance), findsOneWidget);
    // The settings tab is an index: sections live on their own pages now.
    expect(find.text(zh.settingsStorageTitle), findsOneWidget);
    expect(find.text(zh.settingsDefaultsTitle), findsOneWidget);
    // Entry rows keep their one-line explanations.
    expect(find.text(zh.settingsAppearanceDesc), findsOneWidget);
    // Project facts moved to their own page.
    expect(find.text(zh.aboutHeading), findsNothing);
  });

  testBookloomWidgets('about page lists version, license and tech stack', (
    WidgetTester tester,
  ) async {
    await pumpBookloom(tester);

    // About lives under settings now; open it through the settings index.
    await tester.tap(find.text(zh.navSettings).first);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text(zh.navAbout));
    await tester.pumpAndSettle();
    await tester.tap(find.text(zh.navAbout));
    await tester.pumpAndSettle();

    expect(find.text(zh.aboutHeading), findsOneWidget);
    expect(find.text(zh.aboutTech), findsOneWidget);
    expect(find.text(zh.aboutOpenSource), findsOneWidget);
    // The licence shows twice: the hero pill and the repository card.
    expect(find.text('AGPL-3.0'), findsWidgets);
    expect(find.text(zh.techFlutter), findsOneWidget);
    expect(find.text(zh.aboutChangelog), findsNothing);
  });

  testBookloomWidgets('page margins swallow clicks instead of the barrier', (
    WidgetTester tester,
  ) async {
    final List<MethodCall> platformCalls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (MethodCall call) async {
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

    await pumpBookloom(tester);
    // The 16px shell gutter has no widget of its own. Without the invisible
    // page hit surface a tap here falls through to the route's colourless,
    // non-dismissible ModalBarrier, which answers with the system alert sound
    // (the Windows "ding").
    await tester.tapAt(const Offset(8, 8));
    await tester.pumpAndSettle();

    expect(
      platformCalls.where(
        (MethodCall call) =>
            call.method == 'SystemSound.play' &&
            call.arguments == 'SystemSoundType.alert',
      ),
      isEmpty,
    );
  });

  testBookloomWidgets('page scrollbar rides the page edge, not the content', (
    WidgetTester tester,
  ) async {
    // Scrollbars are added by the desktop scroll behaviour only.
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      await pumpBookloom(tester, size: const Size(1440, 700));

      await tester.tap(find.text(zh.navSettings).first);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text(zh.navAbout));
      await tester.pumpAndSettle();
      await tester.tap(find.text(zh.navAbout));
      await tester.pumpAndSettle();

      final Rect page = tester.getRect(find.byType(AppPage).last);
      final Rect scrollbar = tester.getRect(find.byType(Scrollbar).last);
      // The body scrolls at the page edge even though the content stays at the
      // readable measure, so the thumb never hugs the cards.
      expect(scrollbar.width, greaterThan(AppLayout.contentMaxWidth));
      expect(scrollbar.right, closeTo(page.right, 0.5));
      expect(tester.takeException(), isNull);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testBookloomWidgets('tech stack keeps two columns on a narrow desktop', (
    WidgetTester tester,
  ) async {
    // The old breakpoint dropped the grid to one column here even though the
    // stacked tech card had the full page width to itself.
    await pumpBookloom(tester, size: const Size(900, 900));

    // The rail is icon-only this narrow, so reach settings through its tooltip.
    await tester.tap(find.byTooltip(zh.navSettings));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text(zh.navAbout));
    await tester.pumpAndSettle();
    await tester.tap(find.text(zh.navAbout));
    await tester.pumpAndSettle();

    final Offset flutter = tester.getTopLeft(find.text(zh.techFlutter));
    final Offset dart = tester.getTopLeft(find.text(zh.techDart));
    expect(dart.dy, flutter.dy);
    expect(dart.dx, greaterThan(flutter.dx));
    expect(tester.takeException(), isNull);
  });

  testBookloomWidgets('desktop rail auto-collapses on a narrow window', (
    WidgetTester tester,
  ) async {
    await pumpBookloom(tester, size: const Size(1280, 900));
    // Wide: icons and labels.
    expect(find.text(zh.navSettings), findsWidgets);
    expect(find.byKey(const Key('bottom-navigation')), findsNothing);

    tester.view.physicalSize = const Size(980, 900);
    await tester.pump();
    await tester.pumpAndSettle();

    // Narrow desktop still keeps the rail, but only its icons: navigation
    // never moves to the bottom on a desktop window.
    expect(find.byKey(const Key('bottom-navigation')), findsNothing);
    expect(find.text(zh.navSettings), findsNothing);
    expect(find.text(zh.libraryEmptyTitle), findsOneWidget);

    tester.view.physicalSize = const Size(1280, 900);
    await tester.pump();
    await tester.pumpAndSettle();

    // Widening again brings the labels back on its own.
    expect(find.text(zh.navSettings), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testBookloomWidgets('rail toggle collapses and expands on demand', (
    WidgetTester tester,
  ) async {
    await pumpBookloom(tester, size: const Size(1280, 900));
    expect(find.text(zh.navSettings), findsWidgets);

    await tester.tap(find.byKey(const Key('rail-collapse')));
    await tester.pumpAndSettle();
    expect(find.text(zh.navSettings), findsNothing);

    // Collapsed, the mark swaps to the expand chevron only under the pointer.
    final TestGesture mouse = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
    );
    await mouse.addPointer();
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(find.byType(AppMark)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('rail-expand')));
    await tester.pumpAndSettle();
    expect(find.text(zh.navSettings), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testBookloomWidgets('batch task page offers a way back', (
    WidgetTester tester,
  ) async {
    await pumpBookloom(tester, size: const Size(1280, 900));
    await tester.tap(find.text(zh.navImport).first);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text(zh.workbenchOpenBatch));
    await tester.pumpAndSettle();
    await tester.tap(find.text(zh.workbenchOpenBatch));
    await tester.pumpAndSettle();

    expect(find.text(zh.dataWorkbenchBatchTitle), findsOneWidget);
    expect(find.byType(BackButton), findsOneWidget);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text(zh.dataWorkbenchBatchTitle), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testBookloomWidgets('narrow layout uses the bottom navigation bar', (
    WidgetTester tester,
  ) async {
    await pumpMobileShell(tester);

    expect(find.byKey(const Key('bottom-navigation')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('bottom-navigation')),
        matching: find.byType(Text),
      ),
      findsNWidgets(3),
    );
    // The phone bar keeps three entries; About is reached through settings.
    expect(find.text(zh.navAbout), findsNothing);
    expect(find.text(zh.libraryEmptyTitle), findsOneWidget);

    await tester.tap(find.text(zh.navSettings).last);
    await tester.pump();
    expect(find.text(zh.settingsAppearance), findsOneWidget);
    expect(find.text(zh.libraryEmptyTitle), findsNothing);
    expect(
      find.text(zh.libraryEmptyTitle, skipOffstage: false),
      findsOneWidget,
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testBookloomWidgets('mobile chrome excludes system insets from glass', (
    WidgetTester tester,
  ) async {
    tester.view.padding = const FakeViewPadding(top: 30, bottom: 24);
    tester.view.viewPadding = const FakeViewPadding(top: 30, bottom: 24);
    await pumpMobileShell(tester, size: const Size(363, 800));

    final Finder bar = find.byKey(const Key('bottom-navigation'));
    final Finder glass = find.ancestor(
      of: bar,
      matching: find.byType(GlassSurface),
    );
    expect(tester.getSize(bar).height, AppLayout.bottomBarHeight);
    expect(tester.getSize(glass).height, AppLayout.bottomBarHeight);
    expect(tester.getBottomLeft(glass).dy, 800 - 24 - AppSpacing.md);
    expect(
      tester.getTopLeft(find.text(zh.libraryEmptyTitle)).dy,
      greaterThan(30),
    );

    await tester.tap(find.text(zh.navSettings).last);
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.text(zh.settingsAppearance)).dy,
      greaterThan(30),
    );
    await tester.ensureVisible(find.text(zh.navAbout));
    await tester.pumpAndSettle();
    await tester.tap(find.text(zh.navAbout));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text(zh.aboutHeading)).dy, greaterThan(30));
    expect(tester.takeException(), isNull);
  });

  for (final width in <double>[320, 363, 520]) {
    for (final textScale in <double>[1, 2]) {
      testBookloomWidgets(
        'phone navigation centers compact items at ${width}px ${textScale}x',
        (WidgetTester tester) async {
          tester.platformDispatcher.textScaleFactorTestValue = textScale;
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          await pumpMobileShell(tester, size: Size(width, 800));

          final bar = find.byKey(const Key('bottom-navigation'));
          final glass = find.ancestor(
            of: bar,
            matching: find.byType(GlassSurface),
          );
          expect(tester.getCenter(glass).dx, closeTo(width / 2, 0.01));
          expect(
            tester.getSize(glass).width,
            lessThanOrEqualTo(AppLayout.bottomBarMaxWidth),
          );
          if (textScale == 1) {
            expect(tester.getSize(bar).height, 56);
          } else {
            expect(tester.getSize(bar).height, greaterThan(56));
          }

          final items = find.descendant(
            of: bar,
            matching: find.byType(InkWell),
          );
          expect(items, findsNWidgets(3));
          for (var index = 0; index < 3; index++) {
            final item = items.at(index);
            final icon = find.descendant(of: item, matching: find.byType(Icon));
            final label = find.descendant(
              of: item,
              matching: find.byType(Text),
            );
            final target = tester.getRect(item);
            expect(target.width, greaterThanOrEqualTo(48));
            expect(target.height, greaterThanOrEqualTo(48));
            expect(tester.getCenter(icon).dx, closeTo(target.center.dx, 0.01));
            expect(tester.getCenter(label).dx, closeTo(target.center.dx, 0.01));
            expect(target.contains(tester.getTopLeft(icon)), isTrue);
            expect(target.contains(tester.getBottomRight(label)), isTrue);
          }
          await tester.tap(items.at(1));
          await tester.pumpAndSettle();
          expect(find.text(zh.importChooseFile), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testBookloomWidgets('settings opens permission checks and returns', (
    WidgetTester tester,
  ) async {
    await pumpMobileShell(tester);
    await tester.tap(find.text(zh.navSettings).last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text(zh.settingsPermissions));
    await tester.pumpAndSettle();
    await tester.tap(find.text(zh.settingsPermissions));
    await tester.pump();
    await tester.pump(AppMotion.page + const Duration(milliseconds: 50));

    expect(find.text(zh.permissionsIntro), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pump();
    await tester.pump(AppMotion.page + const Duration(milliseconds: 50));
    expect(find.text(zh.settingsAppearance), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testBookloomWidgets('settings opens about and returns to settings', (
    WidgetTester tester,
  ) async {
    await pumpMobileShell(tester);
    await tester.tap(find.text(zh.navSettings).last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text(zh.navAbout));
    await tester.pumpAndSettle();
    await tester.tap(find.text(zh.navAbout));
    await tester.pumpAndSettle();

    expect(find.text(zh.aboutHeading), findsOneWidget);
    // Settings sections are nested in the settings branch, so the phone bar
    // stays visible while reading them.
    expect(find.byKey(const Key('bottom-navigation')), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    expect(find.text(zh.settingsAppearance), findsOneWidget);
    expect(find.byKey(const Key('bottom-navigation')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testBookloomWidgets(
    'pushed page canvas hides shell during both transition halves',
    (WidgetTester tester) async {
      await pumpMobileShell(tester);
      // Batch still opens above the shell (settings sections no longer do), so
      // it is the page that must paint an opaque canvas over the bar.
      await tester.tap(find.text(zh.navImport).last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text(zh.workbenchOpenBatch));
      await tester.pumpAndSettle();

      // Sample the selected navigation surface inside the centered bar.
      final Rect bar = tester.getRect(
        find.byKey(const Key('bottom-navigation')),
      );
      final Rect stripe = Rect.fromLTWH(
        bar.center.dx - bar.width / 6 + AppSpacing.sm,
        bar.top + AppSpacing.md,
        AppSpacing.xs,
        bar.height - AppSpacing.xl,
      );
      final Uint8List shell = await _capturePixels(tester, stripe);

      await tester.tap(find.text(zh.workbenchOpenBatch));
      // The first pump dispatches the router change; the second paints the
      // newly mounted route at the start of its transition.
      await tester.pump();
      await tester.pump();
      expect(find.text(zh.dataWorkbenchBatchTitle), findsOneWidget);
      final Uint8List enteringStart = await _capturePixels(tester, stripe);
      await tester.pump(const Duration(milliseconds: 120));
      final Uint8List enteringMiddle = await _capturePixels(tester, stripe);
      await tester.pump(AppMotion.page);
      final Uint8List pushed = await _capturePixels(tester, stripe);

      expect(_meanRgbDifference(shell, pushed), greaterThan(3));
      expect(_meanRgbDifference(enteringStart, pushed), lessThan(1));
      expect(_meanRgbDifference(enteringMiddle, pushed), lessThan(1));

      await tester.tap(find.byType(BackButton));
      await tester.pump();
      final Uint8List returningStart = await _capturePixels(tester, stripe);
      await tester.pump(const Duration(milliseconds: 120));
      final Uint8List returningMiddle = await _capturePixels(tester, stripe);
      await tester.pump(AppMotion.page);
      final Uint8List restoredShell = await _capturePixels(tester, stripe);

      expect(_meanRgbDifference(returningStart, pushed), lessThan(1));
      expect(_meanRgbDifference(returningMiddle, pushed), lessThan(1));
      expect(_meanRgbDifference(restoredShell, shell), lessThan(1));
      expect(tester.takeException(), isNull);
    },
  );

  testBookloomWidgets(
    'settings subpage canvas hides index during both transition halves',
    (WidgetTester tester) async {
      await pumpBookloom(tester);
      await tester.tap(find.text(zh.navSettings).first);
      await tester.pumpAndSettle();

      final Rect stripe = tester.getRect(find.text(zh.settingsHelp));
      final Uint8List index = await _capturePixels(tester, stripe);

      await tester.tap(find.text(zh.settingsAppearance));
      await tester.pump();
      await tester.pump();
      final Uint8List enteringStart = await _capturePixels(tester, stripe);
      await tester.pump(const Duration(milliseconds: 120));
      final Uint8List enteringMiddle = await _capturePixels(tester, stripe);
      await tester.pumpAndSettle();
      final Uint8List subpage = await _capturePixels(tester, stripe);

      expect(_meanRgbDifference(index, subpage), greaterThan(1));
      expect(_meanRgbDifference(enteringStart, subpage), lessThan(1));
      expect(_meanRgbDifference(enteringMiddle, subpage), lessThan(1));

      await tester.tap(find.byType(BackButton));
      await tester.pump();
      final Uint8List returningStart = await _capturePixels(tester, stripe);
      await tester.pump(const Duration(milliseconds: 120));
      final Uint8List returningMiddle = await _capturePixels(tester, stripe);
      await tester.pumpAndSettle();
      final Uint8List restoredIndex = await _capturePixels(tester, stripe);

      expect(_meanRgbDifference(returningStart, subpage), lessThan(1));
      expect(_meanRgbDifference(returningMiddle, subpage), lessThan(1));
      expect(_meanRgbDifference(restoredIndex, index), lessThan(1));
      expect(tester.takeException(), isNull);
    },
  );

  testBookloomWidgets('design system gallery opens from the about page', (
    WidgetTester tester,
  ) async {
    await pumpBookloom(tester);

    // About is a settings section now.
    await tester.tap(find.text(zh.navSettings).first);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text(zh.navAbout));
    await tester.pumpAndSettle();
    await tester.tap(find.text(zh.navAbout));
    await tester.pumpAndSettle();

    // The equal-height tech card makes the page a little taller; scroll the
    // footer link into view before tapping it.
    await tester.ensureVisible(find.text(zh.aboutDesignSystem));
    await tester.pumpAndSettle();
    await tester.tap(find.text(zh.aboutDesignSystem));
    await tester.pumpAndSettle();

    expect(find.text(zh.designSectionColors), findsOneWidget);
    expect(find.text(zh.designSectionGlass), findsOneWidget);
    expect(find.byIcon(Icons.arrow_back), findsOneWidget);
  });

  testBookloomWidgets(
    'settings and about remain usable at 320px with 2x text',
    (WidgetTester tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await pumpMobileShell(tester, size: const Size(320, 720));
      expect(find.text(zh.libraryEmptyMessage), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.text(zh.navSettings).last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text(zh.navAbout));
      await tester.pumpAndSettle();
      await tester.tap(find.text(zh.navAbout));
      await tester.pumpAndSettle();
      expect(find.text(zh.aboutHeading), findsOneWidget);
      expect(find.text(zh.appDescription), findsOneWidget);
      expect(find.text(zh.aboutChangelog), findsNothing);
      expect(find.byType(BackButton), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.ensureVisible(find.text(zh.aboutDesignSystem));
      await tester.pumpAndSettle();
      await tester.tap(find.text(zh.aboutDesignSystem));
      await tester.pumpAndSettle();
      expect(find.text(zh.designSectionColors), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

Future<Uint8List> _capturePixels(WidgetTester tester, Rect bounds) async {
  final RenderView renderView = tester.binding.renderViews.single;
  final ContainerLayer layer = renderView.debugLayer!;
  final Size viewSize = renderView.size;
  final Uint8List? pixels = await tester.runAsync(() async {
    final ui.Scene scene = layer.buildScene(ui.SceneBuilder());
    try {
      final ui.Image image = await scene.toImage(
        viewSize.width.ceil(),
        viewSize.height.ceil(),
      );
      try {
        final ByteData? data = await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        );
        if (data == null) throw StateError('Could not capture route pixels');
        final Uint8List raw = data.buffer.asUint8List(
          data.offsetInBytes,
          data.lengthInBytes,
        );
        final int left = bounds.left.round();
        final int top = bounds.top.round();
        final int width = bounds.width.round();
        final int height = bounds.height.round();
        final Uint8List cropped = Uint8List(width * height * 4);
        for (var row = 0; row < height; row++) {
          final int source = ((top + row) * image.width + left) * 4;
          cropped.setRange(row * width * 4, (row + 1) * width * 4, raw, source);
        }
        return cropped;
      } finally {
        image.dispose();
      }
    } finally {
      scene.dispose();
    }
  });
  if (pixels == null) throw StateError('Could not capture route pixels');
  return pixels;
}

double _meanRgbDifference(Uint8List first, Uint8List second) {
  assert(first.length == second.length && first.length % 4 == 0);
  var difference = 0;
  for (var index = 0; index < first.length; index += 4) {
    difference += (first[index] - second[index]).abs();
    difference += (first[index + 1] - second[index + 1]).abs();
    difference += (first[index + 2] - second[index + 2]).abs();
  }
  return difference / (first.length / 4 * 3);
}

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:bookloom/design/components/glass_surface.dart';
import 'package:bookloom/design/tokens/app_metrics.dart';
import 'package:bookloom/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/pump_bookloom.dart';

void main() {
  final AppLocalizations zh = lookupAppLocalizations(const Locale('zh'));

  testBookloomWidgets('desktop shell shows the sidebar and the empty shelf', (
    WidgetTester tester,
  ) async {
    await pumpBookloom(tester);

    expect(find.text(zh.navLibrary), findsWidgets);
    expect(find.text(zh.navImport), findsWidgets);
    expect(find.text(zh.navSettings), findsWidgets);
    expect(find.text(zh.navAbout), findsWidgets);
    expect(find.text(zh.libraryEmptyTitle), findsOneWidget);
    expect(find.text(zh.libraryEmptyMessage), findsOneWidget);
    expect(find.text(zh.libraryEmptyAction), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);

    // The sidebar footer no longer carries copy; the shelf owns the bottom.
    // Branches are preloaded, so the first switch to another tab does not pay
    // a first-build cost: the settings page already exists offstage.
    expect(
      find.text(zh.settingsThemeMode, skipOffstage: false),
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
    expect(find.text(zh.settingsDataLocation), findsOneWidget);
    // Settings keep their one-line explanations.
    expect(find.text(zh.settingsGlassDesc), findsOneWidget);
    // Project facts moved to their own page.
    expect(find.text(zh.aboutHeading), findsNothing);
  });

  testBookloomWidgets('about page lists version, license and tech stack', (
    WidgetTester tester,
  ) async {
    await pumpBookloom(tester);

    await tester.tap(find.text(zh.navAbout).first);
    await tester.pumpAndSettle();

    expect(find.text(zh.aboutHeading), findsOneWidget);
    expect(find.text(zh.aboutTech), findsOneWidget);
    expect(find.text(zh.aboutOpenSource), findsOneWidget);
    expect(find.text('AGPL-3.0'), findsOneWidget);
    expect(find.text(zh.techFlutter), findsOneWidget);
    expect(find.text(zh.aboutChangelog), findsNothing);
  });

  testBookloomWidgets('narrow layout uses the bottom navigation bar', (
    WidgetTester tester,
  ) async {
    await pumpBookloom(tester, size: const Size(520, 900));

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).destinations,
      hasLength(3),
    );
    expect(find.text(zh.navAbout), findsNothing);
    expect(find.text(zh.libraryEmptyTitle), findsOneWidget);

    await tester.tap(find.text(zh.navSettings).last);
    await tester.pump();
    expect(find.text(zh.settingsThemeMode), findsOneWidget);
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
    await pumpBookloom(tester, size: const Size(363, 800));

    final Finder bar = find.byType(NavigationBar);
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

  testBookloomWidgets('settings opens permission checks and returns', (
    WidgetTester tester,
  ) async {
    await pumpBookloom(tester, size: const Size(520, 900));
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
    expect(find.text(zh.settingsThemeMode), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testBookloomWidgets('settings opens about and returns to settings', (
    WidgetTester tester,
  ) async {
    await pumpBookloom(tester, size: const Size(520, 900));
    await tester.tap(find.text(zh.navSettings).last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text(zh.navAbout));
    await tester.pumpAndSettle();
    await tester.tap(find.text(zh.navAbout));
    await tester.pumpAndSettle();

    expect(find.text(zh.aboutHeading), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    expect(find.text(zh.settingsThemeMode), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testBookloomWidgets(
    'pushed page canvas hides shell during both transition halves',
    (WidgetTester tester) async {
      await pumpBookloom(tester, size: const Size(520, 900));
      await tester.tap(find.text(zh.navSettings).last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text(zh.navAbout));
      await tester.pumpAndSettle();

      // The stripe lies inside the old glass bar but outside AppPage's 20px
      // content inset. On a pushed page it should show only the paper canvas.
      final Rect bar = tester.getRect(find.byType(NavigationBar));
      final Rect stripe = Rect.fromLTWH(16, bar.top + 12, 4, bar.height - 24);
      final Uint8List shell = await _capturePixels(tester, stripe);

      await tester.tap(find.text(zh.navAbout));
      // The first pump dispatches the router change; the second paints the
      // newly mounted route at the start of its transition.
      await tester.pump();
      await tester.pump();
      expect(find.text(zh.aboutHeading), findsOneWidget);
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

  testBookloomWidgets('design system gallery opens from the about page', (
    WidgetTester tester,
  ) async {
    await pumpBookloom(tester);

    await tester.tap(find.text(zh.navAbout).first);
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
      await pumpBookloom(tester, size: const Size(320, 720));
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

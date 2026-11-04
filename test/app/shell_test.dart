import 'package:bookloom/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/pump_bookloom.dart';

void main() {
  final AppLocalizations zh = lookupAppLocalizations(const Locale('zh'));

  testWidgets('desktop shell shows the sidebar and the empty shelf', (
    WidgetTester tester,
  ) async {
    await pumpBookloom(tester);

    expect(find.text(zh.navLibrary), findsWidgets);
    expect(find.text(zh.navImport), findsWidgets);
    expect(find.text(zh.navSettings), findsWidgets);
    expect(find.text(zh.navAbout), findsWidgets);
    expect(find.text(zh.libraryEmptyTitle), findsOneWidget);
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

  testWidgets('sidebar navigation switches to the import page', (
    WidgetTester tester,
  ) async {
    await pumpBookloom(tester);

    await tester.tap(find.text(zh.navImport).first);
    await tester.pumpAndSettle();

    expect(find.text(zh.importFormatsTitle), findsOneWidget);
    expect(find.text(zh.importStatusNext), findsOneWidget);
    // Guidance stays: each format explains what it will do.
    expect(find.text(zh.importFormatTxtDesc), findsOneWidget);
  });

  testWidgets('settings page exposes appearance and data sections', (
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
    expect(find.text(zh.aboutStoryLocalTitle), findsNothing);
  });

  testWidgets('about page lists version, license and tech stack', (
    WidgetTester tester,
  ) async {
    await pumpBookloom(tester);

    await tester.tap(find.text(zh.navAbout).first);
    await tester.pumpAndSettle();

    expect(find.text(zh.aboutStoryLocalTitle), findsOneWidget);
    expect(find.text(zh.aboutTech), findsOneWidget);
    expect(find.text('AGPL-3.0'), findsOneWidget);
    expect(find.text('Flutter 3.47'), findsOneWidget);
    expect(find.text(zh.aboutRepoAction), findsOneWidget);
  });

  testWidgets('narrow layout uses the bottom navigation bar', (
    WidgetTester tester,
  ) async {
    await pumpBookloom(tester, size: const Size(520, 900));

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text(zh.libraryEmptyTitle), findsOneWidget);

    await tester.tap(find.text(zh.navSettings).last);
    await tester.pumpAndSettle();
    expect(find.text(zh.settingsThemeMode), findsOneWidget);
  });

  testWidgets('design system gallery opens from the about page', (
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
}

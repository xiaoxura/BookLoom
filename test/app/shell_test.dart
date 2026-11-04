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
    expect(find.text(zh.libraryEmptyTitle), findsOneWidget);
    expect(find.text(zh.libraryEmptyAction), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);

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
    expect(find.text(zh.settingsDesignSystem), findsOneWidget);
    // Settings keep their one-line explanations.
    expect(find.text(zh.settingsGlassDesc), findsOneWidget);
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

  testWidgets('design system gallery opens from settings', (
    WidgetTester tester,
  ) async {
    await pumpBookloom(tester);

    await tester.tap(find.text(zh.navSettings).first);
    await tester.pumpAndSettle();

    await tester.tap(find.text(zh.settingsOpen));
    await tester.pumpAndSettle();

    expect(find.text(zh.designSectionColors), findsOneWidget);
    expect(find.text(zh.designSectionGlass), findsOneWidget);
    expect(find.byIcon(Icons.arrow_back), findsOneWidget);
  });
}

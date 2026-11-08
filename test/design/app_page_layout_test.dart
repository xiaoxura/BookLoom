import 'package:bookloom/design/components/app_page.dart';
import 'package:bookloom/design/tokens/app_metrics.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final width in <double>[320, 1280, 2560]) {
    testWidgets('workspace uses available width at $width', (tester) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      const bodyKey = ValueKey('workspace-body');
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AppPage(
              scrollable: false,
              maxContentWidth: double.infinity,
              child: SizedBox.expand(key: bodyKey),
            ),
          ),
        ),
      );
      final horizontal = width < 720 ? 20 : AppLayout.pagePadding;
      expect(tester.getSize(find.byKey(bodyKey)).width, width - 2 * horizontal);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('reading and settings pages retain their readable measure', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(2560, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    const bodyKey = ValueKey('reading-body');
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AppPage(
            scrollable: false,
            child: SizedBox.expand(key: bodyKey),
          ),
        ),
      ),
    );
    expect(
      tester.getSize(find.byKey(bodyKey)).width,
      AppLayout.contentMaxWidth,
    );
    expect(tester.getCenter(find.byKey(bodyKey)).dx, 1280);
    expect(tester.takeException(), isNull);
  });
}

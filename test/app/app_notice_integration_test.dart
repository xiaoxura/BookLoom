import 'package:bookloom/app/shell/app_shell.dart' show debugForceMobileShell;
import 'package:bookloom/design/components/app_surface.dart';
import 'package:bookloom/design/tokens/app_metrics.dart';
import 'package:flutter/foundation.dart'
    show debugDefaultTargetPlatformOverride;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/pump_bookloom.dart';

void main() {
  testBookloomWidgets('real desktop shell centers a bounded notice', (
    WidgetTester tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    await pumpBookloom(tester, size: const Size(2560, 900));

    final BuildContext page = tester.element(find.byType(AppSurface).first);
    ScaffoldMessenger.of(page)
        .showSnackBar(const SnackBar(content: Text('请先选择封面图片。')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final Finder material = find.descendant(
      of: find.byType(SnackBar),
      matching: find.byType(Material),
    );
    final Rect notice = tester.getRect(material.first);
    final Rect scaffold = tester.getRect(find.byType(Scaffold).first);
    expect(notice.width, 440);
    expect(notice.center.dx, scaffold.center.dx);
    expect(notice.left, greaterThanOrEqualTo(scaffold.left + AppSpacing.lg));
    expect(notice.right, lessThanOrEqualTo(scaffold.right - AppSpacing.lg));
    expect(tester.takeException(), isNull);
  });

  testBookloomWidgets('real mobile shell shows notice above its bottom bar', (
    WidgetTester tester,
  ) async {
    debugForceMobileShell = true;
    addTearDown(() => debugForceMobileShell = false);
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await pumpBookloom(tester, size: const Size(320, 720));

    final BuildContext page = tester.element(find.byType(AppSurface).first);
    ScaffoldMessenger.of(page)
        .showSnackBar(const SnackBar(content: Text('请先选择封面图片。')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final Finder material = find.descendant(
      of: find.byType(SnackBar),
      matching: find.byType(Material),
    );
    final Rect notice = tester.getRect(material.first);
    final Rect bar = tester.getRect(find.byKey(const Key('bottom-navigation')));
    expect(notice.width, 288);
    expect(notice.center.dx, 160);
    expect(notice.bottom, lessThanOrEqualTo(bar.top - AppSpacing.lg));
    expect(tester.takeException(), isNull);
  });
}

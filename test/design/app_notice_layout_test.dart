import 'package:bookloom/design/components/app_notice_layout.dart';
import 'package:bookloom/design/theme/app_theme.dart';
import 'package:bookloom/design/tokens/app_colors.dart';
import 'package:bookloom/design/tokens/app_metrics.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const String _coverNotice = '请先选择封面图片。';

Finder get _noticeMaterial =>
    find.descendant(of: find.byType(SnackBar), matching: find.byType(Material));

Future<GlobalKey<ScaffoldMessengerState>> _pumpNoticeHost(
  WidgetTester tester, {
  required Size size,
  required ThemeData theme,
  bool bottomBar = false,
  double? scaffoldWidth,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final messengerKey = GlobalKey<ScaffoldMessengerState>();
  await tester.pumpWidget(
    MaterialApp(
      scaffoldMessengerKey: messengerKey,
      theme: theme,
      builder: (context, child) =>
          AppNoticeLayout(child: child ?? const SizedBox.shrink()),
      home: Align(
        alignment: Alignment.centerRight,
        child: SizedBox(
          width: scaffoldWidth,
          child: Scaffold(
            resizeToAvoidBottomInset: false,
            body: const SizedBox.expand(),
            bottomNavigationBar: bottomBar
                ? const SizedBox(height: AppLayout.bottomBarHeight)
                : null,
          ),
        ),
      ),
    ),
  );
  return messengerKey;
}

Future<void> _showNotice(
  WidgetTester tester,
  ScaffoldMessengerState messenger,
  String message, {
  SnackBarAction? action,
}) async {
  messenger.showSnackBar(SnackBar(content: Text(message), action: action));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  for (final (String name, ThemeData theme, AppColors colors)
      in <(String, ThemeData, AppColors)>[
        (
          'light',
          AppTheme.light().copyWith(platform: TargetPlatform.linux),
          AppColors.light,
        ),
        (
          'dark',
          AppTheme.dark().copyWith(platform: TargetPlatform.linux),
          AppColors.dark,
        ),
      ]) {
    testWidgets('$name notice stays centered on a 2560px desktop', (
      WidgetTester tester,
    ) async {
      final messengerKey = await _pumpNoticeHost(
        tester,
        size: const Size(2560, 900),
        theme: theme,
      );
      var actionCount = 0;
      await _showNotice(
        tester,
        messengerKey.currentState!,
        _coverNotice,
        action: SnackBarAction(label: '知道了', onPressed: () => actionCount++),
      );

      final Rect notice = tester.getRect(_noticeMaterial.first);
      expect(notice.width, 440);
      expect(notice.center.dx, 1280);
      expect(notice.bottom, lessThanOrEqualTo(900 - AppSpacing.lg));
      expect(tester.widget<Material>(_noticeMaterial.first).color, colors.ink);
      expect(
        DefaultTextStyle.of(tester.element(find.text(_coverNotice)))
            .style
            .color,
        colors.canvas,
      );
      expect(
        DefaultTextStyle.of(tester.element(find.text('知道了'))).style.color,
        colors.canvas,
      );
      await tester.tap(find.text('知道了'));
      await tester.pump();
      expect(actionCount, 1);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('320px notice wraps at 2x text scale without clipping', (
    WidgetTester tester,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final messengerKey = await _pumpNoticeHost(
      tester,
      size: const Size(320, 720),
      theme: AppTheme.light().copyWith(platform: TargetPlatform.android),
    );
    const message = '请先选择封面图片。所选图片将作为书籍封面显示在书架上。';
    await _showNotice(tester, messengerKey.currentState!, message);

    final Rect notice = tester.getRect(_noticeMaterial);
    final Rect content = tester.getRect(find.text(message));
    expect(notice.width, 288);
    expect(notice.left, 16);
    expect(notice.right, 304);
    expect(notice.height, greaterThan(80));
    expect(notice.contains(content.topLeft), isTrue);
    expect(notice.contains(content.bottomRight), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('500px Android notice still caps at 440px', (
    WidgetTester tester,
  ) async {
    final messengerKey = await _pumpNoticeHost(
      tester,
      size: const Size(500, 720),
      theme: AppTheme.light().copyWith(platform: TargetPlatform.android),
    );
    await _showNotice(tester, messengerKey.currentState!, _coverNotice);

    final Rect notice = tester.getRect(_noticeMaterial);
    expect(notice.width, 440);
    expect(notice.center.dx, 250);
    expect(tester.takeException(), isNull);
  });

  testWidgets('narrow desktop notice fits its inset page scaffold', (
    WidgetTester tester,
  ) async {
    final messengerKey = await _pumpNoticeHost(
      tester,
      size: const Size(320, 720),
      theme: AppTheme.light().copyWith(platform: TargetPlatform.linux),
      scaffoldWidth: 216,
    );
    expect(
      Theme.of(tester.element(find.byType(Scaffold))).snackBarTheme.width,
      184,
    );
    await _showNotice(tester, messengerKey.currentState!, _coverNotice);

    final Rect notice = tester.getRect(_noticeMaterial);
    expect(notice.width, 184);
    expect(notice.left, 120);
    expect(notice.right, 304);
    expect(tester.takeException(), isNull);
  });

  testWidgets('floating notice clears the system safe area', (
    WidgetTester tester,
  ) async {
    tester.view.padding = const FakeViewPadding(bottom: 24);
    tester.view.viewPadding = const FakeViewPadding(bottom: 24);
    final messengerKey = await _pumpNoticeHost(
      tester,
      size: const Size(320, 720),
      theme: AppTheme.light().copyWith(platform: TargetPlatform.android),
    );
    await _showNotice(tester, messengerKey.currentState!, _coverNotice);

    expect(
      tester.getRect(_noticeMaterial).bottom,
      lessThanOrEqualTo(720 - 24 - AppSpacing.lg),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('floating notice clears the bottom bar and keyboard', (
    WidgetTester tester,
  ) async {
    tester.view.padding = const FakeViewPadding(bottom: 24);
    tester.view.viewPadding = const FakeViewPadding(bottom: 24);
    final messengerKey = await _pumpNoticeHost(
      tester,
      size: const Size(320, 720),
      theme: AppTheme.light().copyWith(platform: TargetPlatform.android),
      bottomBar: true,
    );
    await _showNotice(tester, messengerKey.currentState!, _coverNotice);

    expect(
      tester.getRect(_noticeMaterial).bottom,
      lessThanOrEqualTo(720 - AppLayout.bottomBarHeight - AppSpacing.lg),
    );
    tester.view.viewInsets = const FakeViewPadding(bottom: 280);
    tester.view.padding = FakeViewPadding.zero;
    await tester.pump();
    expect(
      tester.getRect(_noticeMaterial).bottom,
      lessThanOrEqualTo(720 - 280 - AppSpacing.lg),
    );
    expect(tester.takeException(), isNull);
  });
}

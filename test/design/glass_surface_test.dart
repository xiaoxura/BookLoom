import 'package:bookloom/core/settings/appearance.dart';
import 'package:bookloom/design/components/glass_surface.dart';
import 'package:bookloom/design/theme/app_theme.dart';
import 'package:bookloom/design/tokens/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('off glass stays opaque without blur even with overrides', (
    WidgetTester tester,
  ) async {
    for (final (ThemeData theme, AppColors colors, bool forcedOff)
        in <(ThemeData, AppColors, bool)>[
          (AppTheme.light(glass: GlassQuality.off), AppColors.light, false),
          (AppTheme.dark(glass: GlassQuality.off), AppColors.dark, false),
          (AppTheme.light(), AppColors.light, true),
          (AppTheme.dark(), AppColors.dark, true),
        ]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Scaffold(
            body: Center(
              child: GlassSurface(
                quality: forcedOff ? GlassQuality.off : null,
                blurSigma: 32,
                tintAlpha: 0.1,
                showShadow: false,
                child: const SizedBox(width: 100, height: 100),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final Finder pane = find.byType(GlassSurface);
      expect(
        find.descendant(of: pane, matching: find.byType(BackdropFilter)),
        findsNothing,
      );
      final ColoredBox tint = tester.widget<ColoredBox>(
        find.descendant(of: pane, matching: find.byType(ColoredBox)),
      );
      expect(tint.color, colors.surface);
      expect(tint.color.a, 1);
    }
  });
}

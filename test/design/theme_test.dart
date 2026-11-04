import 'package:bookloom/core/settings/appearance.dart';
import 'package:bookloom/design/theme/app_theme.dart';
import 'package:bookloom/design/theme/app_tokens.dart';
import 'package:bookloom/design/tokens/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

double _contrast(Color a, Color b) {
  final double la = a.computeLuminance();
  final double lb = b.computeLuminance();
  final double hi = la > lb ? la : lb;
  final double lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  group('AppTheme', () {
    test('exposes tokens for both brightnesses', () {
      final ThemeData light = AppTheme.light();
      final ThemeData dark = AppTheme.dark();
      final AppTokens lightTokens = light.extension<AppTokens>()!;
      final AppTokens darkTokens = dark.extension<AppTokens>()!;

      expect(lightTokens.colors.canvas, AppColors.light.canvas);
      expect(darkTokens.colors.canvas, AppColors.dark.canvas);
      expect(light.brightness, Brightness.light);
      expect(dark.brightness, Brightness.dark);
    });

    test('glass quality drives blur tokens', () {
      expect(
        AppTheme.light(glass: GlassQuality.off)
            .extension<AppTokens>()!
            .glass
            .blurSigma,
        0,
      );
      expect(
        AppTheme.light(glass: GlassQuality.soft)
            .extension<AppTokens>()!
            .glass
            .blurSigma,
        greaterThan(0),
      );
      expect(
        AppTheme.light(glass: GlassQuality.strong)
            .extension<AppTokens>()!
            .glass
            .isBlurred,
        isTrue,
      );
    });

    test('text colors meet WCAG AA on the paper canvas', () {
      for (final (String name, AppColors colors) in <(String, AppColors)>[
        ('light', AppColors.light),
        ('dark', AppColors.dark),
      ]) {
        expect(
          _contrast(colors.ink, colors.canvas),
          greaterThanOrEqualTo(7),
          reason: '$name ink should reach AAA',
        );
        expect(
          _contrast(colors.inkSecondary, colors.canvas),
          greaterThanOrEqualTo(4.5),
          reason: '$name secondary text should reach AA',
        );
        expect(
          _contrast(colors.inkMuted, colors.canvas),
          greaterThanOrEqualTo(4.5),
          reason: '$name muted text should reach AA',
        );
        expect(
          _contrast(colors.accent, colors.canvas),
          greaterThanOrEqualTo(4.5),
          reason: '$name accent link text should reach AA',
        );
        expect(
          _contrast(colors.accentContrast, colors.accent),
          greaterThanOrEqualTo(4.5),
          reason: '$name text on accent should reach AA',
        );
        expect(
          _contrast(colors.danger, colors.canvas),
          greaterThanOrEqualTo(4.5),
          reason: '$name danger text should reach AA',
        );
      }
    });
  });
}

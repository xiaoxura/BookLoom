import 'package:bookloom/core/settings/appearance.dart';
import 'package:bookloom/design/theme/app_theme.dart';
import 'package:bookloom/design/theme/app_tokens.dart';
import 'package:bookloom/design/tokens/app_colors.dart';
import 'package:bookloom/design/tokens/glass.dart';
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
      for (final (
            String name,
            AppColors colors,
            ThemeData Function({GlassQuality glass}) theme,
          )
          in <(String, AppColors, ThemeData Function({GlassQuality glass}))>[
            ('light', AppColors.light, AppTheme.light),
            ('dark', AppColors.dark, AppTheme.dark),
          ]) {
        final GlassTokens off = theme(glass: GlassQuality.off)
            .extension<AppTokens>()!
            .glass;
        final GlassTokens soft = theme(glass: GlassQuality.soft)
            .extension<AppTokens>()!
            .glass;
        final GlassTokens strong = theme(glass: GlassQuality.strong)
            .extension<AppTokens>()!
            .glass;

        expect(off.isBlurred, isFalse, reason: '$name off must not blur');
        expect(off.blurSigma, 0);
        expect(off.fill.a, 1, reason: '$name off must be opaque');
        expect(off.tint, colors.surface);
        expect(soft.isBlurred, isTrue);
        expect(strong.isBlurred, isTrue);
        expect(strong.blurSigma, greaterThan(soft.blurSigma));
        expect(soft.tintAlpha, greaterThan(strong.tintAlpha));
        expect(strong.highlight.a, greaterThan(soft.highlight.a));
        expect(soft.tint, colors.surface);
        expect(strong.tint, colors.surface);
      }
    });

    test('disabled icon buttons are muted in both themes', () {
      for (final theme in [AppTheme.light(), AppTheme.dark()]) {
        final colors = theme.extension<AppTokens>()!.colors;
        final foreground = theme.iconButtonTheme.style!.foregroundColor!;
        expect(foreground.resolve({}), colors.inkSecondary);
        expect(
          foreground.resolve({WidgetState.disabled}),
          colors.inkMuted.withValues(alpha: 0.38),
        );
        expect(
          foreground.resolve({WidgetState.disabled, WidgetState.hovered}),
          foreground.resolve({WidgetState.disabled}),
        );
      }
    });

    test('canvas atmosphere colors interpolate with the theme', () {
      final AppColors midpoint = AppColors.lerp(
        AppColors.light,
        AppColors.dark,
        0.5,
      );
      expect(midpoint.canvasMist, isNot(AppColors.light.canvasMist));
      expect(midpoint.canvasMist, isNot(AppColors.dark.canvasMist));
      expect(midpoint.canvasBloom, isNot(AppColors.light.canvasBloom));
      expect(midpoint.canvasBloom, isNot(AppColors.dark.canvasBloom));
    });

    test('text colors stay readable on canvas washes and glass', () {
      for (final (String name, AppColors colors) in <(String, AppColors)>[
        ('light', AppColors.light),
        ('dark', AppColors.dark),
      ]) {
        // The peak wash opacities match AppCanvas. Testing both gradient ends
        // covers the lightest and darkest base under each wash. The overlap
        // conservatively assumes both washes peak at the same point.
        final List<(String, Color)> backdrops = <(String, Color)>[];
        for (final (String baseName, Color base) in <(String, Color)>[
          ('canvas', colors.canvas),
          ('canvasAlt', colors.canvasAlt),
        ]) {
          final Color mist = Color.alphaBlend(
            colors.canvasMist.withValues(alpha: 0.60),
            base,
          );
          final Color bloom = Color.alphaBlend(
            colors.canvasBloom.withValues(alpha: 0.70),
            base,
          );
          final Color overlap = Color.alphaBlend(
            colors.canvasBloom.withValues(alpha: 0.70),
            mist,
          );
          backdrops.addAll(<(String, Color)>[
            (baseName, base),
            ('$baseName/mist', mist),
            ('$baseName/bloom', bloom),
            ('$baseName/overlap', overlap),
          ]);
        }
        final bool dark = name == 'dark';
        final GlassTokens soft = GlassTokens.forQuality(
          GlassQuality.soft,
          dark: dark,
        );
        final GlassTokens strong = GlassTokens.forQuality(
          GlassQuality.strong,
          dark: dark,
        );

        for (final (String backdropName, Color backdrop) in backdrops) {
          for (final (String layerName, Color background) in <(String, Color)>[
            ('bare', backdrop),
            ('soft', Color.alphaBlend(soft.fill, backdrop)),
            ('strong', Color.alphaBlend(strong.fill, backdrop)),
          ]) {
            for (final (String role, Color foreground, double minimum)
                in <(String, Color, double)>[
                  ('ink', colors.ink, 7),
                  ('secondary', colors.inkSecondary, 4.5),
                  ('muted', colors.inkMuted, 4.5),
                  ('accent', colors.accent, 4.5),
                  ('danger', colors.danger, 4.5),
                ]) {
              expect(
                _contrast(foreground, background),
                greaterThanOrEqualTo(minimum),
                reason: '$name $role on $backdropName/$layerName',
              );
            }
          }
        }

        expect(
          _contrast(colors.accentContrast, colors.accent),
          greaterThanOrEqualTo(4.5),
          reason: '$name text on accent should reach AA',
        );
      }
    });
  });
}

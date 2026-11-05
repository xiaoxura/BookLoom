import 'dart:ui' show lerpDouble;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../../core/settings/appearance.dart';
import 'app_colors.dart';

@immutable
class GlassTokens {
  const GlassTokens({
    required this.quality,
    required this.blurSigma,
    required this.tint,
    required this.tintAlpha,
    required this.border,
    required this.highlight,
    required this.shadow,
  });

  final GlassQuality quality;

  /// Backdrop blur radius. 0 when [quality] is [GlassQuality.off].
  final double blurSigma;

  /// Base color of the frosted pane.
  final Color tint;

  /// How strongly [tint] covers the backdrop. Higher = calmer, more legible.
  final double tintAlpha;

  /// 1px border around the pane.
  final Color border;

  /// Inner top highlight that sells the "pane of glass" read.
  final Color highlight;

  final List<BoxShadow> shadow;

  bool get isBlurred => quality.isBlurred && blurSigma > 0;

  /// Tint with the quality's alpha applied. The off state stays opaque even
  /// while theme extensions interpolate between glass qualities.
  Color get fill =>
      tint.withValues(alpha: quality == GlassQuality.off ? 1 : tintAlpha);

  static GlassTokens forQuality(GlassQuality quality, {required bool dark}) {
    final colors = dark ? AppColors.dark : AppColors.light;
    final shadow = BoxShadow(
      color: colors.shadow.withValues(alpha: dark ? 0.30 : 0.12),
      blurRadius: 32,
      spreadRadius: -10,
      offset: const Offset(0, 12),
    );

    return switch (quality) {
      GlassQuality.off => GlassTokens(
        quality: quality,
        blurSigma: 0,
        tint: colors.surface,
        tintAlpha: 1,
        border: colors.hairline,
        highlight: const Color(0x00000000),
        shadow: [shadow],
      ),
      GlassQuality.soft => GlassTokens(
        quality: quality,
        blurSigma: 12,
        tint: colors.surface,
        tintAlpha: dark ? 0.74 : 0.76,
        border: (dark ? colors.ink : colors.surfaceRaised).withValues(
          alpha: dark ? 0.14 : 0.78,
        ),
        highlight: (dark ? colors.ink : colors.surfaceRaised).withValues(
          alpha: dark ? 0.06 : 0.12,
        ),
        shadow: [shadow],
      ),
      GlassQuality.strong => GlassTokens(
        quality: quality,
        blurSigma: 32,
        tint: colors.surface,
        tintAlpha: dark ? 0.50 : 0.46,
        border: (dark ? colors.ink : colors.surfaceRaised).withValues(
          alpha: dark ? 0.20 : 0.88,
        ),
        highlight: (dark ? colors.ink : colors.surfaceRaised).withValues(
          alpha: dark ? 0.10 : 0.20,
        ),
        shadow: [shadow],
      ),
    };
  }

  static GlassTokens lerp(GlassTokens a, GlassTokens b, double t) =>
      GlassTokens(
        quality: t < 0.5 ? a.quality : b.quality,
        blurSigma: lerpDouble(a.blurSigma, b.blurSigma, t)!,
        tint: Color.lerp(a.tint, b.tint, t)!,
        tintAlpha: lerpDouble(a.tintAlpha, b.tintAlpha, t)!,
        border: Color.lerp(a.border, b.border, t)!,
        highlight: Color.lerp(a.highlight, b.highlight, t)!,
        shadow: BoxShadow.lerpList(a.shadow, b.shadow, t) ?? b.shadow,
      );
}

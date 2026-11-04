import 'dart:ui' show lerpDouble;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../../core/settings/appearance.dart';

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

  /// Tint with the quality's alpha applied.
  Color get fill => tint.withValues(alpha: tintAlpha);

  static GlassTokens forQuality(GlassQuality quality, {required bool dark}) {
    final shadow = BoxShadow(
      color: (dark ? const Color(0xFF000000) : const Color(0xFF2A241B))
          .withValues(alpha: dark ? 0.45 : 0.15),
      blurRadius: 40,
      spreadRadius: -12,
      offset: const Offset(0, 16),
    );

    return switch (quality) {
      GlassQuality.off => GlassTokens(
        quality: quality,
        blurSigma: 0,
        tint: dark ? const Color(0xFF1C1A17) : const Color(0xFFFBF8F2),
        tintAlpha: dark ? 0.94 : 0.96,
        border: dark ? const Color(0xFF35302A) : const Color(0xFFDFD7C8),
        highlight: const Color(0x00000000),
        shadow: [shadow],
      ),
      GlassQuality.soft => GlassTokens(
        quality: quality,
        blurSigma: 12,
        tint: dark ? const Color(0xFF26221D) : const Color(0xFFFFFDF8),
        tintAlpha: dark ? 0.70 : 0.74,
        border: (dark ? const Color(0xFFFFFFFF) : const Color(0xFF1B1916))
            .withValues(alpha: dark ? 0.08 : 0.08),
        highlight: (dark ? const Color(0xFFFFFFFF) : const Color(0xFFFFFFFF))
            .withValues(alpha: dark ? 0.06 : 0.55),
        shadow: [shadow],
      ),
      GlassQuality.strong => GlassTokens(
        quality: quality,
        blurSigma: 32,
        tint: dark ? const Color(0xFF2A2621) : const Color(0xFFFFFDFA),
        tintAlpha: dark ? 0.50 : 0.46,
        border: (dark ? const Color(0xFFFFFFFF) : const Color(0xFF1B1916))
            .withValues(alpha: dark ? 0.12 : 0.11),
        highlight: const Color(0xFFFFFFFF)
            .withValues(alpha: dark ? 0.12 : 0.78),
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

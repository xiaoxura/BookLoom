import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// Semantic color roles for the whole app.
///
/// Nothing outside this file should hard-code a hex value. Screens read colors
/// through `context.colors`, which is backed by a [ThemeExtension], so switching
/// palettes (or adding a high-contrast variant) stays a one-file change.
@immutable
class AppColors {
  const AppColors({
    required this.canvas,
    required this.canvasAlt,
    required this.canvasMist,
    required this.canvasBloom,
    required this.surface,
    required this.surfaceRaised,
    required this.surfaceSunken,
    required this.ink,
    required this.inkSecondary,
    required this.inkMuted,
    required this.hairline,
    required this.accent,
    required this.accentContrast,
    required this.accentSoft,
    required this.success,
    required this.warning,
    required this.danger,
    required this.shadow,
  });

  /// Page background, bottom of the canvas gradient.
  final Color canvas;

  /// Page background, top of the canvas gradient.
  final Color canvasAlt;

  /// Cool atmospheric shade behind floating chrome.
  final Color canvasMist;

  /// Soft bloom in the canvas background.
  final Color canvasBloom;

  /// Opaque base for cards and panels sitting on [canvas].
  final Color surface;

  /// Highest opaque layer (inputs, raised cards).
  final Color surfaceRaised;

  /// Recessed areas (track, code blocks, wells).
  final Color surfaceSunken;

  /// Primary text: near-black ink.
  final Color ink;

  /// Secondary text: captions, meta lines.
  final Color inkSecondary;

  /// Tertiary text: hints, disabled labels. Meets WCAG AA on [canvas].
  final Color inkMuted;

  /// 1px rules, borders, separators.
  final Color hairline;

  /// Brand / interactive accent.
  final Color accent;

  /// Text and icons drawn on top of [accent].
  final Color accentContrast;

  /// Tinted fill behind selected navigation, chips, badges.
  final Color accentSoft;

  final Color success;
  final Color warning;
  final Color danger;

  /// Tint used by soft shadows.
  final Color shadow;

  static const AppColors light = AppColors(
    canvas: Color(0xFFEEF2F6),
    canvasAlt: Color(0xFFFAFBFC),
    canvasMist: Color(0xFFB7CDE0),
    canvasBloom: Color(0xFFD8E5E4),
    surface: Color(0xFFF9FAFB),
    surfaceRaised: Color(0xFFFFFFFF),
    surfaceSunken: Color(0xFFE7EDF2),
    ink: Color(0xFF1B2530),
    inkSecondary: Color(0xFF495B6C),
    inkMuted: Color(0xFF526170),
    hairline: Color(0xFFD9E0E7),
    accent: Color(0xFF2F4E66),
    accentContrast: Color(0xFFF7FAFC),
    accentSoft: Color(0xFFDDE6EC),
    success: Color(0xFF3B6F55),
    warning: Color(0xFF94641C),
    danger: Color(0xFFA13C33),
    shadow: Color(0xFF243748),
  );

  static const AppColors dark = AppColors(
    canvas: Color(0xFF111820),
    canvasAlt: Color(0xFF1A232D),
    canvasMist: Color(0xFF2B455C),
    canvasBloom: Color(0xFF233E40),
    surface: Color(0xFF1C252F),
    surfaceRaised: Color(0xFF25303C),
    surfaceSunken: Color(0xFF0F161D),
    ink: Color(0xFFEDF2F7),
    inkSecondary: Color(0xFFBDC8D2),
    inkMuted: Color(0xFF96A7B7),
    hairline: Color(0xFF33414F),
    accent: Color(0xFF9CBBD1),
    accentContrast: Color(0xFF10202B),
    accentSoft: Color(0xFF22323D),
    success: Color(0xFF7FB79A),
    warning: Color(0xFFD3A45E),
    danger: Color(0xFFDE8B80),
    shadow: Color(0xFF000000),
  );

  static AppColors lerp(AppColors a, AppColors b, double t) => AppColors(
    canvas: Color.lerp(a.canvas, b.canvas, t)!,
    canvasAlt: Color.lerp(a.canvasAlt, b.canvasAlt, t)!,
    canvasMist: Color.lerp(a.canvasMist, b.canvasMist, t)!,
    canvasBloom: Color.lerp(a.canvasBloom, b.canvasBloom, t)!,
    surface: Color.lerp(a.surface, b.surface, t)!,
    surfaceRaised: Color.lerp(a.surfaceRaised, b.surfaceRaised, t)!,
    surfaceSunken: Color.lerp(a.surfaceSunken, b.surfaceSunken, t)!,
    ink: Color.lerp(a.ink, b.ink, t)!,
    inkSecondary: Color.lerp(a.inkSecondary, b.inkSecondary, t)!,
    inkMuted: Color.lerp(a.inkMuted, b.inkMuted, t)!,
    hairline: Color.lerp(a.hairline, b.hairline, t)!,
    accent: Color.lerp(a.accent, b.accent, t)!,
    accentContrast: Color.lerp(a.accentContrast, b.accentContrast, t)!,
    accentSoft: Color.lerp(a.accentSoft, b.accentSoft, t)!,
    success: Color.lerp(a.success, b.success, t)!,
    warning: Color.lerp(a.warning, b.warning, t)!,
    danger: Color.lerp(a.danger, b.danger, t)!,
    shadow: Color.lerp(a.shadow, b.shadow, t)!,
  );
}

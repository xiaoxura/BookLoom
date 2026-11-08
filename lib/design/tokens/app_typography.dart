import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Type system: an editorial pairing of a warm serif (titles, brand) with a
/// neutral sans (UI, meta). Both stacks list the usual CJK families so the
/// same tokens survive Linux, Windows, Android and later Apple.
abstract final class AppTypography {
  /// Latin + CJK sans stack. First family wins where installed.
  static const List<String> sansFallback = <String>[
    'Noto Sans CJK SC',
    'Noto Sans SC',
    'Source Han Sans SC',
    'PingFang SC',
    'Hiragino Sans GB',
    'Microsoft YaHei',
    'Segoe UI',
    'Roboto',
  ];

  /// Latin + CJK serif stack, used for headings and reading surfaces.
  static const List<String> serifFallback = <String>[
    'Noto Serif CJK SC',
    'Noto Serif SC',
    'Source Han Serif SC',
    'Songti SC',
    'STSong',
    'SimSun',
    'Georgia',
  ];

  static const String sans = 'Noto Sans CJK SC';
  static const String serif = 'Noto Serif CJK SC';

  /// Reading/editor body font sizes; [reading] and the body line-length cap
  /// both derive from these.
  static const double readingFont = 16.5;
  static const double readingFontCompact = 15.5;

  /// Reading/editor body: roomy leading, slight tracking for CJK mixed text.
  static TextStyle reading(AppColors c, {bool compact = false}) =>
      _sans(
        size: compact ? readingFontCompact : readingFont,
        height: compact ? 1.75 : 1.9,
        weight: FontWeight.w400,
        color: c.ink,
        tracking: 0.15,
      ).copyWith(fontFamily: serif, fontFamilyFallback: serifFallback);

  static TextTheme textTheme(AppColors c) {
    TextStyle s(double size, double h, FontWeight w, Color color, double t) =>
        _sans(size: size, height: h, weight: w, color: color, tracking: t);
    TextStyle f(double size, double h, FontWeight w, Color color, double t) =>
        _serif(size: size, height: h, weight: w, color: color, tracking: t);

    return TextTheme(
      displayLarge: f(40, 1.18, FontWeight.w600, c.ink, -0.6),
      displayMedium: f(32, 1.22, FontWeight.w600, c.ink, -0.4),
      displaySmall: f(28, 1.25, FontWeight.w600, c.ink, -0.3),
      headlineLarge: f(25, 1.3, FontWeight.w600, c.ink, -0.2),
      headlineMedium: f(21, 1.35, FontWeight.w600, c.ink, -0.1),
      headlineSmall: f(18, 1.4, FontWeight.w600, c.ink, 0),
      titleLarge: f(16.5, 1.45, FontWeight.w600, c.ink, 0),
      titleMedium: s(15, 1.45, FontWeight.w600, c.ink, 0.05),
      titleSmall: s(13.5, 1.4, FontWeight.w600, c.inkSecondary, 0.1),
      bodyLarge: s(15, 1.75, FontWeight.w400, c.ink, 0.1),
      bodyMedium: s(14, 1.7, FontWeight.w400, c.inkSecondary, 0.1),
      bodySmall: s(12.5, 1.6, FontWeight.w400, c.inkMuted, 0.15),
      labelLarge: s(13.5, 1.4, FontWeight.w500, c.ink, 0.2),
      labelMedium: s(12, 1.35, FontWeight.w500, c.inkSecondary, 0.3),
      labelSmall: s(11, 1.3, FontWeight.w500, c.inkMuted, 0.5),
    );
  }

  static TextStyle _sans({
    required double size,
    required double height,
    required FontWeight weight,
    required Color color,
    required double tracking,
  }) => TextStyle(
    fontFamily: sans,
    fontFamilyFallback: sansFallback,
    fontSize: size,
    height: height,
    fontWeight: weight,
    letterSpacing: tracking,
    color: color,
  );

  static TextStyle _serif({
    required double size,
    required double height,
    required FontWeight weight,
    required Color color,
    required double tracking,
  }) => TextStyle(
    fontFamily: serif,
    fontFamilyFallback: serifFallback,
    fontSize: size,
    height: height,
    fontWeight: weight,
    letterSpacing: tracking,
    color: color,
  );
}

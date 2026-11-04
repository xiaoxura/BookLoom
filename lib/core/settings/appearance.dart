import 'package:flutter/foundation.dart';

/// Persisted appearance preference. Pure Dart so `core` stays Flutter-free;
/// the app layer maps [AppThemeMode] onto Material's `ThemeMode`.
enum AppThemeMode { system, light, dark }

/// How much frost the floating layers get.
///
/// Frosted glass is an *accent material*, not a theme: text is always drawn on
/// an opaque or near-opaque paper surface, and only chrome (sidebar, bars,
/// popovers, dialogs) is allowed to blur the backdrop. See
/// `docs/07-design-system.md` for the reasoning and the cost model.
enum GlassQuality {
  /// No blur at all; chrome falls back to opaque paper. Cheapest and fastest.
  off,

  /// Small blur, higher tint alpha. Good default on low-end laptops and phones.
  soft,

  /// Full frost: larger blur radius, lower tint alpha, hairline highlight.
  strong;

  bool get isBlurred => this != GlassQuality.off;
}

@immutable
class Appearance {
  const Appearance({
    this.themeMode = AppThemeMode.system,
    this.glass = GlassQuality.strong,
  });

  final AppThemeMode themeMode;
  final GlassQuality glass;

  static const Appearance defaults = Appearance();

  Appearance copyWith({AppThemeMode? themeMode, GlassQuality? glass}) =>
      Appearance(
        themeMode: themeMode ?? this.themeMode,
        glass: glass ?? this.glass,
      );

  @override
  bool operator ==(Object other) =>
      other is Appearance &&
      other.themeMode == themeMode &&
      other.glass == glass;

  @override
  int get hashCode => Object.hash(themeMode, glass);
}

import 'package:flutter/foundation.dart';

/// Persisted appearance preference. Pure Dart so `core` stays Flutter-free;
/// the app layer maps [AppThemeMode] onto Material's `ThemeMode`.
enum AppThemeMode { system, light, dark }

@immutable
class Appearance {
  const Appearance({this.themeMode = AppThemeMode.system});

  final AppThemeMode themeMode;

  static const Appearance defaults = Appearance();

  Appearance copyWith({AppThemeMode? themeMode}) =>
      Appearance(themeMode: themeMode ?? this.themeMode);

  @override
  bool operator ==(Object other) =>
      other is Appearance && other.themeMode == themeMode;

  @override
  int get hashCode => themeMode.hashCode;
}

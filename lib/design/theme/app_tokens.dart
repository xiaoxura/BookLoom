import 'package:flutter/material.dart';

import '../tokens/app_colors.dart';

/// Aggregated design tokens, exposed as a [ThemeExtension] so widgets can read
/// them without importing the raw palette and so theme switches animate.
@immutable
class AppTokens extends ThemeExtension<AppTokens> {
  const AppTokens({required this.colors});

  final AppColors colors;

  @override
  AppTokens copyWith({AppColors? colors}) =>
      AppTokens(colors: colors ?? this.colors);

  @override
  AppTokens lerp(covariant AppTokens? other, double t) {
    if (other == null) return this;
    return AppTokens(colors: AppColors.lerp(colors, other.colors, t));
  }
}

extension AppThemeContext on BuildContext {
  AppTokens get tokens => Theme.of(this).extension<AppTokens>()!;
  AppColors get colors => tokens.colors;
}

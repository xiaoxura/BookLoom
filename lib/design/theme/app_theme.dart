import 'package:flutter/material.dart';

import '../../core/settings/appearance.dart';

import '../tokens/app_colors.dart';
import '../tokens/app_metrics.dart';
import '../tokens/app_typography.dart';
import '../tokens/glass.dart';
import 'app_tokens.dart';

/// The single place where Material components are styled.
///
/// Screens should not restyle buttons, inputs or cards locally; if something is
/// missing here, add it here so every screen inherits the same look.
abstract final class AppTheme {
  static ThemeData light({GlassQuality glass = GlassQuality.strong}) =>
      _build(Brightness.light, AppColors.light, glass);

  static ThemeData dark({GlassQuality glass = GlassQuality.strong}) =>
      _build(Brightness.dark, AppColors.dark, glass);

  static ThemeData _build(
    Brightness brightness,
    AppColors colors,
    GlassQuality glassQuality,
  ) {
    final isDark = brightness == Brightness.dark;
    final scheme =
        ColorScheme.fromSeed(
          seedColor: colors.accent,
          brightness: brightness,
          dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
        ).copyWith(
          primary: colors.accent,
          onPrimary: colors.accentContrast,
          primaryContainer: colors.accentSoft,
          onPrimaryContainer: colors.accent,
          secondary: colors.inkSecondary,
          onSecondary: colors.surface,
          surface: colors.surface,
          onSurface: colors.ink,
          surfaceContainerHighest: colors.surfaceSunken,
          surfaceContainerHigh: colors.surface,
          outline: colors.hairline,
          outlineVariant: colors.hairline,
          error: colors.danger,
          onError: colors.surface,
          shadow: colors.shadow,
        );

    final textTheme = AppTypography.textTheme(colors);
    final radiusMd = BorderRadius.circular(AppRadius.md);
    final radiusLg = BorderRadius.circular(AppRadius.lg);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      textTheme: textTheme,
      extensions: <ThemeExtension<dynamic>>[
        AppTokens(
          colors: colors,
          glass: GlassTokens.forQuality(glassQuality, dark: isDark),
        ),
      ],
      scaffoldBackgroundColor: Colors.transparent,
      canvasColor: colors.canvas,
      dividerTheme: DividerThemeData(
        color: colors.hairline,
        thickness: 1,
        space: 1,
      ),
      iconTheme: IconThemeData(color: colors.inkSecondary, size: 20),
      splashFactory: InkRipple.splashFactory,
      visualDensity: VisualDensity.standard,
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        foregroundColor: colors.ink,
        titleTextStyle: textTheme.headlineSmall,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStatePropertyAll(colors.accent),
          foregroundColor: WidgetStatePropertyAll(colors.accentContrast),
          overlayColor: WidgetStatePropertyAll(
            colors.accentContrast.withValues(alpha: 0.12),
          ),
          minimumSize: const WidgetStatePropertyAll(Size(0, 42)),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: AppSpacing.lg + 4, vertical: 10),
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: radiusMd),
          ),
          textStyle: WidgetStatePropertyAll(textTheme.labelLarge),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStatePropertyAll(colors.ink),
          side: WidgetStatePropertyAll(
            BorderSide(color: colors.hairline, width: 1),
          ),
          overlayColor: WidgetStatePropertyAll(
            colors.ink.withValues(alpha: 0.04),
          ),
          minimumSize: const WidgetStatePropertyAll(Size(0, 42)),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: AppSpacing.lg + 4, vertical: 10),
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: radiusMd),
          ),
          textStyle: WidgetStatePropertyAll(textTheme.labelLarge),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStatePropertyAll(colors.accent),
          overlayColor: WidgetStatePropertyAll(
            colors.accent.withValues(alpha: 0.06),
          ),
          minimumSize: const WidgetStatePropertyAll(Size(0, 36)),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 8),
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: radiusMd),
          ),
          textStyle: WidgetStatePropertyAll(textTheme.labelLarge),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return colors.inkMuted.withValues(alpha: 0.38);
            }
            return colors.inkSecondary;
          }),
          overlayColor: WidgetStatePropertyAll(
            colors.ink.withValues(alpha: 0.05),
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: radiusMd),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colors.surfaceRaised.withValues(alpha: isDark ? 0.06 : 0.55),
        hintStyle: textTheme.bodyMedium?.copyWith(color: colors.inkMuted),
        labelStyle: textTheme.bodyMedium?.copyWith(color: colors.inkSecondary),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg - 2,
          vertical: AppSpacing.md + 2,
        ),
        border: OutlineInputBorder(
          borderRadius: radiusMd,
          borderSide: BorderSide(color: colors.hairline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: radiusMd,
          borderSide: BorderSide(color: colors.hairline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: radiusMd,
          borderSide: BorderSide(color: colors.accent, width: 1.4),
        ),
      ),
      dropdownMenuTheme: DropdownMenuThemeData(
        textStyle: textTheme.bodyMedium?.copyWith(color: colors.ink),
        inputDecorationTheme: InputDecorationThemeData(
          filled: true,
          fillColor: colors.surfaceRaised,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          border: OutlineInputBorder(
            borderRadius: radiusMd,
            borderSide: BorderSide(color: colors.hairline),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: radiusMd,
            borderSide: BorderSide(color: colors.hairline),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: radiusMd,
            borderSide: BorderSide(color: colors.accent, width: 1.4),
          ),
        ),
        menuStyle: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(colors.surfaceRaised),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          elevation: const WidgetStatePropertyAll(0),
          side: WidgetStatePropertyAll(BorderSide(color: colors.hairline)),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: radiusMd),
          ),
          padding: const WidgetStatePropertyAll(EdgeInsets.all(AppSpacing.xs)),
        ),
      ),
      menuButtonTheme: MenuButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStatePropertyAll(colors.ink),
          backgroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.focused)
                ? colors.accentSoft
                : Colors.transparent,
          ),
          overlayColor: WidgetStatePropertyAll(
            colors.accent.withValues(alpha: 0.07),
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: radiusMd),
          ),
          minimumSize: const WidgetStatePropertyAll(Size(0, 44)),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: AppSpacing.md),
          ),
        ),
      ),
      cardTheme: CardThemeData(
        color: colors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: radiusLg,
          side: BorderSide(color: colors.hairline),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: colors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: radiusLg),
        titleTextStyle: textTheme.headlineSmall,
        contentTextStyle: textTheme.bodyLarge,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: colors.ink,
        actionTextColor: colors.canvas,
        contentTextStyle: textTheme.bodyMedium?.copyWith(color: colors.canvas),
        elevation: 0,
        insetPadding: const EdgeInsets.all(AppSpacing.lg),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
      ),
      // Tooltips follow the paper language: a surface chip with a hairline and
      // the app's small type. The default dark bubble read as a black blob.
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          border: Border.all(color: colors.hairline),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: colors.ink.withValues(alpha: 0.10),
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        textStyle: textTheme.bodySmall?.copyWith(
          color: colors.ink,
          fontSize: 12,
          height: 1.35,
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm + 2,
          vertical: 5,
        ),
        margin: const EdgeInsets.all(8),
        verticalOffset: 18,
        waitDuration: const Duration(milliseconds: 400),
        showDuration: const Duration(seconds: 5),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: Colors.transparent,
        side: BorderSide(color: colors.hairline),
        labelStyle: textTheme.labelMedium,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
        showCheckmark: false,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return colors.accentContrast;
          }
          return isDark ? colors.inkMuted : colors.surfaceRaised;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return colors.accent;
          return colors.surfaceSunken;
        }),
        trackOutlineColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? Colors.transparent
              : colors.hairline,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        indicatorColor: colors.accentSoft,
        elevation: 0,
        height: AppLayout.bottomBarHeight,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return textTheme.labelSmall?.copyWith(
            color: selected ? colors.accent : colors.inkMuted,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            size: 21,
            color: selected ? colors.accent : colors.inkMuted,
          );
        }),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: Colors.transparent,
        indicatorColor: colors.accentSoft,
        selectedIconTheme: IconThemeData(color: colors.accent, size: 21),
        unselectedIconTheme: IconThemeData(color: colors.inkMuted, size: 21),
        selectedLabelTextStyle: textTheme.labelLarge?.copyWith(
          color: colors.accent,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelTextStyle: textTheme.labelLarge?.copyWith(
          color: colors.inkSecondary,
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return colors.accentSoft;
            }
            return Colors.transparent;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) return colors.accent;
            return colors.inkSecondary;
          }),
          side: WidgetStatePropertyAll(BorderSide(color: colors.hairline)),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: radiusMd),
          ),
          textStyle: WidgetStatePropertyAll(textTheme.labelMedium),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: 10),
          ),
          visualDensity: VisualDensity.standard,
        ),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: colors.inkSecondary,
        textColor: colors.ink,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.xs,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStatePropertyAll(
          colors.inkMuted.withValues(alpha: 0.35),
        ),
        radius: const Radius.circular(AppRadius.pill),
        thickness: const WidgetStatePropertyAll(6),
        crossAxisMargin: 2,
        mainAxisMargin: 4,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: colors.accent,
        linearTrackColor: colors.surfaceSunken,
        circularTrackColor: colors.surfaceSunken,
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: colors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          side: BorderSide(color: colors.hairline),
        ),
        textStyle: textTheme.bodyMedium,
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: colors.ink,
        unselectedLabelColor: colors.inkMuted,
        indicatorColor: colors.accent,
        dividerColor: colors.hairline,
        labelStyle: textTheme.labelLarge,
        unselectedLabelStyle: textTheme.labelLarge,
      ),
    );
  }
}

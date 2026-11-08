import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../tokens/app_metrics.dart';

class AppNoticeLayout extends StatelessWidget {
  const AppNoticeLayout({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final MediaQueryData mediaQuery = MediaQuery.of(context);
    final ThemeData theme = Theme.of(context);
    final bool mobile =
        theme.platform == TargetPlatform.android ||
        theme.platform == TargetPlatform.iOS;
    final double shellWidth = mobile
        ? 0
        : AppLayout.sidebarCollapsedWidth + 3 * AppLayout.shellGutter;
    final double width = math.min(
      AppLayout.noticeMaxWidth,
      math.max(0.0, mediaQuery.size.width - shellWidth - 2 * AppSpacing.lg),
    );
    final double safeBottom = math.max(
      mediaQuery.viewPadding.bottom,
      mediaQuery.viewInsets.bottom,
    );

    return MediaQuery(
      data: mediaQuery.copyWith(
        viewPadding: mediaQuery.viewPadding.copyWith(bottom: safeBottom),
      ),
      child: Theme(
        data: theme.copyWith(
          snackBarTheme: theme.snackBarTheme.copyWith(width: width),
        ),
        child: child,
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';
import '../tokens/app_colors.dart';
import '../tokens/app_metrics.dart';

/// Shared Bookloom logo for the sidebar and about page.
/// A paper backing preserves the original brand colors in both themes.
class AppMark extends StatelessWidget {
  const AppMark({super.key, this.size = 38});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(size * 0.12),
      decoration: BoxDecoration(
        color: AppColors.light.surface,
        borderRadius: BorderRadius.circular(size * 0.28),
      ),
      child: Image.asset(
        'assets/brand/bookloom-logo.png',
        fit: BoxFit.contain,
        filterQuality: FilterQuality.medium,
        // Both callers already display the app name beside the mark.
        excludeFromSemantics: true,
      ),
    );
  }
}

/// Wordmark: Chinese name over the latin name, tuned for [AppMark].
class AppWordmark extends StatelessWidget {
  const AppWordmark({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          '书织',
          style: compact
              ? theme.textTheme.titleLarge
              : theme.textTheme.headlineSmall,
        ),
        const SizedBox(height: 2),
        Text(
          'BOOKLOOM',
          style: theme.textTheme.labelSmall?.copyWith(
            fontSize: compact ? 9 : 10,
            letterSpacing: compact ? 2.4 : 3,
            color: colors.inkMuted,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

/// Padding-independent spacing constant for the wordmark tile.
const double kAppMarkRadius = AppRadius.sm + 2;

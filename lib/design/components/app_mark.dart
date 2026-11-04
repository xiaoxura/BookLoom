import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';
import '../tokens/app_metrics.dart';
import '../tokens/app_typography.dart';

/// The app mark: a warm accent tile with the serif 「书」 glyph.
/// Used by the sidebar brand and the about page, so the two never drift apart.
class AppMark extends StatelessWidget {
  const AppMark({super.key, this.size = 38});

  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.28),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            colors.accent,
            Color.lerp(colors.accent, colors.ink, 0.35)!,
          ],
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: colors.accent.withValues(alpha: 0.28),
            blurRadius: size * 0.37,
            offset: Offset(0, size * 0.16),
            spreadRadius: -size * 0.1,
          ),
        ],
      ),
      child: Center(
        child: Text(
          '书',
          style: TextStyle(
            fontFamily: AppTypography.serif,
            fontFamilyFallback: AppTypography.serifFallback,
            fontSize: size * 0.5,
            height: 1,
            fontWeight: FontWeight.w600,
            color: colors.accentContrast,
          ),
        ),
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

import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';
import '../tokens/app_metrics.dart';

/// Standard page frame: eyebrow + serif title + subtitle + actions, then a
/// scrollable body constrained to a readable measure.
class AppPage extends StatelessWidget {
  const AppPage({
    super.key,
    required this.title,
    this.subtitle,
    this.eyebrow,
    this.actions = const <Widget>[],
    required this.child,
    this.scrollable = true,
    this.leading,
  });

  final String title;
  final String? subtitle;
  final String? eyebrow;
  final List<Widget> actions;
  final Widget child;
  final bool scrollable;

  /// Optional control rendered before the title (e.g. a back button on pages
  /// pushed above the shell).
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool compact = constraints.maxWidth < 720;
        final double horizontal = compact ? 20 : AppLayout.pagePadding;
        return Padding(
          padding: EdgeInsets.fromLTRB(
            horizontal,
            compact ? 20 : 28,
            horizontal,
            0,
          ),
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: AppLayout.contentMaxWidth,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  _PageHeader(
                    eyebrow: eyebrow,
                    title: title,
                    subtitle: subtitle,
                    actions: actions,
                    compact: compact,
                    leading: leading,
                  ),
                  SizedBox(height: compact ? AppSpacing.lg : AppSpacing.xl),
                  Expanded(
                    child: scrollable
                        ? SingleChildScrollView(
                            padding: const EdgeInsets.only(
                              bottom: AppSpacing.xxxl,
                            ),
                            child: child,
                          )
                        : child,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _PageHeader extends StatelessWidget {
  const _PageHeader({
    required this.eyebrow,
    required this.title,
    required this.subtitle,
    required this.actions,
    required this.compact,
    this.leading,
  });

  final String? eyebrow;
  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final bool compact;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.colors;

    final Widget heading = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (eyebrow != null) ...<Widget>[
          Text(
            eyebrow!,
            style: theme.textTheme.labelSmall?.copyWith(
              color: colors.accent,
              letterSpacing: 1.6,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppSpacing.xs + 2),
        ],
        Text(
          title,
          style: theme.textTheme.headlineLarge?.copyWith(
            fontSize: compact ? 24 : 27,
          ),
        ),
        if (subtitle != null) ...<Widget>[
          const SizedBox(height: AppSpacing.xs + 2),
          Text(
            subtitle!,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.inkSecondary,
            ),
          ),
        ],
      ],
    );

    if (actions.isEmpty) return heading;

    final Widget actionRow = Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      alignment: WrapAlignment.end,
      children: actions,
    );

    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          heading,
          const SizedBox(height: AppSpacing.md),
          actionRow,
        ],
      );
    }

    if (leading != null) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(top: 2, right: AppSpacing.md),
            child: leading,
          ),
          Expanded(child: heading),
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: <Widget>[
        Expanded(child: heading),
        const SizedBox(width: AppSpacing.lg),
        actionRow,
      ],
    );
  }
}

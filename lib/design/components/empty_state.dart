import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';
import '../tokens/app_metrics.dart';

/// Centered empty state used by the library, the editor and the importer.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.title,
    required this.message,
    this.illustration,
    this.actions = const <Widget>[],
    this.hint,
  });

  final String title;
  final String message;
  final Widget? illustration;
  final List<Widget> actions;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.colors;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 432),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.xl,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (illustration != null) ...<Widget>[
                illustration!,
                const SizedBox(height: AppSpacing.xl + 4),
              ],
              Text(
                title,
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineMedium,
              ),
              const SizedBox(height: AppSpacing.md - 2),
              Text(
                message,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: colors.inkSecondary,
                  height: 1.75,
                ),
              ),
              if (actions.isNotEmpty) ...<Widget>[
                const SizedBox(height: AppSpacing.xl),
                Wrap(
                  spacing: AppSpacing.sm + 2,
                  runSpacing: AppSpacing.sm,
                  alignment: WrapAlignment.center,
                  children: actions,
                ),
              ],
              if (hint != null) ...<Widget>[
                const SizedBox(height: AppSpacing.lg),
                Text(
                  hint!,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

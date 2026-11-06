import 'package:flutter/material.dart';

import '../../../design/theme/app_tokens.dart';
import '../../../design/tokens/app_metrics.dart';

/// Shared building blocks for the settings index and its sub-pages. They used
/// to be private to `settings_page.dart`; the settings surface is growing into
/// several pages, so the card/row idiom lives here.
class SettingsSectionTitle extends StatelessWidget {
  const SettingsSectionTitle(this.title, {super.key});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(
        left: AppSpacing.xxs,
        bottom: AppSpacing.sm + 2,
      ),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
          letterSpacing: 0.6,
          color: context.colors.inkMuted,
        ),
      ),
    );
  }
}

class SettingsCard extends StatelessWidget {
  const SettingsCard({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        side: BorderSide(color: context.colors.hairline),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }
}

/// A row that navigates to another settings page.
class SettingsEntry extends StatelessWidget {
  const SettingsEntry({
    super.key,
    required this.icon,
    required this.title,
    required this.onTap,
    this.description,
  });

  final IconData icon;
  final String title;
  final String? description;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.xxs,
      ),
      leading: Icon(icon, size: 20, color: context.colors.inkSecondary),
      title: Text(title, style: Theme.of(context).textTheme.titleMedium),
      subtitle: description == null
          ? null
          : Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xxs),
              child: Text(
                description!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: context.colors.inkSecondary,
                  height: 1.5,
                ),
              ),
            ),
      trailing: Icon(
        Icons.chevron_right,
        size: 20,
        color: context.colors.inkMuted,
      ),
      onTap: onTap,
    );
  }
}

class SettingsCardDivider extends StatelessWidget {
  const SettingsCardDivider({super.key});

  @override
  Widget build(BuildContext context) => Divider(
    height: 1,
    color: context.colors.hairline,
    indent: AppSpacing.lg,
    endIndent: AppSpacing.lg,
  );
}

class SettingsRow extends StatelessWidget {
  const SettingsRow({
    super.key,
    required this.title,
    required this.control,
    this.description,
    this.stack = false,
    this.scrollableControl = false,
  });

  final String title;

  /// One-line explanation of what the setting does. Keep it short and useful;
  /// this is guidance, not filler.
  final String? description;
  final Widget control;

  /// Force the control onto its own line (used for wide controls like paths).
  final bool stack;
  final bool scrollableControl;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.colors;

    final Widget label = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(title, style: theme.textTheme.titleMedium),
        if (description != null) ...<Widget>[
          const SizedBox(height: AppSpacing.xxs + 2),
          Text(
            description!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.inkSecondary,
              height: 1.6,
            ),
          ),
        ],
      ],
    );

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.lg,
      ),
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final bool narrow = stack || constraints.maxWidth < 560;
          if (narrow) {
            final Widget narrowControl = scrollableControl
                ? SizedBox(
                    width: constraints.maxWidth,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: control,
                    ),
                  )
                : control;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                label,
                const SizedBox(height: AppSpacing.md),
                narrowControl,
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              Expanded(child: label),
              const SizedBox(width: AppSpacing.xl),
              control,
            ],
          );
        },
      ),
    );
  }
}

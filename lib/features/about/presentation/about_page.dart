import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/app_info.dart';
import '../../../design/components/app_page.dart';
import '../../../design/theme/app_tokens.dart';
import '../../../design/tokens/app_metrics.dart';
import '../../../l10n/app_localizations.dart';

/// Project facts: version, license, source, tech stack, and the way into the
/// living style guide.
class AboutPage extends ConsumerWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colors = context.colors;

    return AppPage(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _SectionTitle(l10n.aboutProject),
          _Card(
            children: <Widget>[
              _InfoRow(
                title: l10n.aboutVersion,
                control: Text(
                  '${AppInfo.displayVersion} (${AppInfo.buildNumber})',
                  style: theme.textTheme.bodyMedium,
                ),
              ),
              const _CardDivider(),
              _InfoRow(
                title: l10n.aboutLicense,
                control: Text(
                  AppInfo.license,
                  style: theme.textTheme.bodyMedium,
                ),
              ),
              const _CardDivider(),
              _InfoRow(
                title: l10n.aboutAuthor,
                control: Text(
                  AppInfo.author,
                  style: theme.textTheme.bodyMedium,
                ),
              ),
              const _CardDivider(),
              _LinkRow(title: l10n.aboutRepo, url: AppInfo.repository),
              const _CardDivider(),
              _LinkRow(title: l10n.aboutWebsite, url: AppInfo.website),
            ],
          ),
          const SizedBox(height: AppSpacing.xxl),
          _SectionTitle(l10n.aboutTech),
          _Card(
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.sm,
                      children: const <Widget>[
                        _TechChip('Flutter 3.47'),
                        _TechChip('Dart 3'),
                        _TechChip('Riverpod'),
                        _TechChip('go_router'),
                        _TechChip('Drift'),
                        _TechChip('SQLite'),
                        _TechChip('window_manager'),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      l10n.aboutTechNote,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.inkSecondary,
                        height: 1.6,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xxl),
          _SectionTitle(l10n.aboutInterface),
          _Card(
            children: <Widget>[
              _InfoRow(
                title: l10n.aboutDesignSystem,
                description: l10n.aboutDesignSystemDesc,
                control: OutlinedButton(
                  onPressed: () => context.push('/design'),
                  child: Text(l10n.aboutOpen),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
        ],
      ),
    );
  }
}

class _TechChip extends StatelessWidget {
  const _TechChip(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md - 2,
        vertical: 5,
      ),
      decoration: BoxDecoration(
        color: colors.surfaceSunken,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall
            ?.copyWith(color: colors.inkSecondary, letterSpacing: 0.3),
      ),
    );
  }
}

class _LinkRow extends StatelessWidget {
  const _LinkRow({required this.title, required this.url});

  final String title;
  final String url;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.colors;
    final l10n = AppLocalizations.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.lg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(title, style: theme.textTheme.titleMedium),
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: <Widget>[
              Expanded(
                child: SelectableText(
                  url,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.accent,
                    height: 1.6,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              TextButton.icon(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: url));
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context)
                      .showSnackBar(SnackBar(content: Text(l10n.aboutCopied)));
                },
                icon: const Icon(Icons.copy_rounded, size: 15),
                label: Text(l10n.aboutCopyLink),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);

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
        style: Theme.of(context).textTheme.titleSmall
            ?.copyWith(letterSpacing: 0.6, color: context.colors.inkMuted),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: context.colors.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }
}

class _CardDivider extends StatelessWidget {
  const _CardDivider();

  @override
  Widget build(BuildContext context) => Divider(
    height: 1,
    color: context.colors.hairline,
    indent: AppSpacing.lg,
    endIndent: AppSpacing.lg,
  );
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.title,
    required this.control,
    this.description,
  });

  final String title;
  final Widget control;
  final String? description;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.colors;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.lg,
      ),
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
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
          if (constraints.maxWidth < 520) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                label,
                const SizedBox(height: AppSpacing.md),
                control,
              ],
            );
          }
          return Row(
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

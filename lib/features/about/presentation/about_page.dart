import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/app_info.dart';
import '../../../core/platform/external_links.dart';
import '../../../design/components/app_mark.dart';
import '../../../design/components/app_page.dart';
import '../../../design/theme/app_tokens.dart';
import '../../../design/tokens/app_metrics.dart';
import '../../../design/tokens/app_typography.dart';
import '../../../l10n/app_localizations.dart';

/// About: identity, two short why-cards, tech stack, links — the same shape as
/// the qingdh about panel, translated into paper tokens.
class AboutPage extends ConsumerWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;

    return AppPage(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const _HeroCard(),
          const SizedBox(height: AppSpacing.lg),
          LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final List<Widget> cards = <Widget>[
                _StoryCard(
                  title: l10n.aboutStoryLocalTitle,
                  body: l10n.aboutStoryLocalBody,
                ),
                _StoryCard(
                  title: l10n.aboutStoryStructureTitle,
                  body: l10n.aboutStoryStructureBody,
                ),
              ];
              if (constraints.maxWidth < 720) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    cards[0],
                    const SizedBox(height: AppSpacing.md),
                    cards[1],
                  ],
                );
              }
              // Equal-height pair: IntrinsicHeight gives the two cards a shared
              // height without forcing an unbounded row inside the scroll view.
              return IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Expanded(child: cards[0]),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(child: cards[1]),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: AppSpacing.xxl),
          _SectionLabel(l10n.aboutTech),
          const SizedBox(height: AppSpacing.sm + 2),
          const Wrap(
            spacing: AppSpacing.xs + 2,
            runSpacing: AppSpacing.xs + 2,
            children: <Widget>[
              _Tag('Flutter 3.47'),
              _Tag('Dart 3'),
              _Tag('Riverpod'),
              _Tag('go_router'),
              _Tag('Drift'),
              _Tag('SQLite'),
              _Tag('window_manager'),
            ],
          ),
          const SizedBox(height: AppSpacing.sm + 2),
          Text(
            l10n.aboutTechNote,
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: colors.inkSecondary, height: 1.7),
          ),
          const SizedBox(height: AppSpacing.xxl),
          _SectionLabel(l10n.aboutLinks),
          const SizedBox(height: AppSpacing.sm + 2),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: <Widget>[
              _LinkButton(
                icon: Icons.code,
                label: l10n.aboutRepoAction,
                onPressed: () => ExternalLinks.open(AppInfo.repository),
              ),
              _LinkButton(
                icon: Icons.public,
                label: l10n.aboutWebsiteAction,
                onPressed: () => ExternalLinks.open(AppInfo.website),
              ),
              _LinkButton(
                icon: Icons.balance,
                label: l10n.aboutLicenseAction,
                onPressed: () => ExternalLinks.open(
                  '${AppInfo.repository}/blob/main/LICENSE',
                ),
              ),
              _LinkButton(
                icon: Icons.palette_outlined,
                label: l10n.aboutDesignSystem,
                onPressed: () => context.push('/design'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xxl),
          Text(
            '© 2026 ${AppInfo.author} · ${AppInfo.license}',
            style: Theme.of(context).textTheme.labelSmall
                ?.copyWith(color: colors.inkMuted, letterSpacing: 0.4),
          ),
          const SizedBox(height: AppSpacing.xl),
        ],
      ),
    );
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.colors;
    final l10n = AppLocalizations.of(context);

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg + 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: colors.hairline),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            Color.lerp(colors.surface, colors.accentSoft, 0.55)!,
            colors.surface,
          ],
          stops: const <double>[0, 0.7],
        ),
      ),
      child: Row(
        children: <Widget>[
          const AppMark(size: 54),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: <Widget>[
                    Flexible(
                      child: Text(
                        l10n.appName,
                        style: theme.textTheme.headlineMedium?.copyWith(
                          fontFamily: AppTypography.serif,
                          fontFamilyFallback: AppTypography.serifFallback,
                          fontSize: 22,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    _Pill('v${AppInfo.version}'),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  l10n.appTagline,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colors.inkSecondary,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Wrap(
                  spacing: AppSpacing.xs + 2,
                  runSpacing: AppSpacing.xs,
                  children: <Widget>[
                    _Badge(AppInfo.license),
                    _Badge(l10n.aboutBadgeLocal),
                    _Badge('Flutter'),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StoryCard extends StatelessWidget {
  const _StoryCard({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md + 2),
        border: Border.all(color: colors.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(title, style: theme.textTheme.titleMedium),
          const SizedBox(height: AppSpacing.xs + 2),
          Text(
            body,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.inkSecondary,
              height: 1.7,
            ),
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: colors.surfaceSunken,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: colors.hairline),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall
            ?.copyWith(color: colors.inkMuted, letterSpacing: 0.2),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: colors.surface.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: colors.hairline),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall
            ?.copyWith(color: colors.inkMuted),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: colors.hairline),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall
            ?.copyWith(color: colors.inkSecondary, letterSpacing: 0.2),
      ),
    );
  }
}

class _LinkButton extends StatelessWidget {
  const _LinkButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 15, color: context.colors.inkSecondary),
      label: Text(label),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: Theme.of(context).textTheme.titleSmall
          ?.copyWith(letterSpacing: 0.6, color: context.colors.inkMuted),
    );
  }
}

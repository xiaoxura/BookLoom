import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/app_info.dart';
import '../../../core/platform/external_links.dart';
import '../../../design/components/app_mark.dart';
import '../../../design/components/app_page.dart';
import '../../../design/theme/app_tokens.dart';
import '../../../design/tokens/app_metrics.dart';
import '../../../design/tokens/app_typography.dart';
import '../../../l10n/app_localizations.dart';

/// Product information at a readable width inside the standard page frame.
class AboutPage extends StatelessWidget {
  const AboutPage({super.key, this.showBackButton = false});

  final bool showBackButton;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;

    return AppPage(
      leading: showBackButton
          ? BackButton(onPressed: () => context.pop())
          : null,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 960),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const _Hero(),
              const SizedBox(height: AppSpacing.xl),
              const _RepoCard(),
              const SizedBox(height: AppSpacing.lg),
              LayoutBuilder(
                builder: (BuildContext context, BoxConstraints constraints) {
                  final Widget tech = _TechCard(
                    items: <_TechItem>[
                      _TechItem(
                        icon: Icons.flutter_dash,
                        label: l10n.techFlutter,
                        description: l10n.techFlutterDesc,
                      ),
                      _TechItem(
                        glyph: 'D',
                        label: l10n.techDart,
                        description: l10n.techDartDesc,
                      ),
                      _TechItem(
                        icon: Icons.account_tree_outlined,
                        label: l10n.techRiverpod,
                        description: l10n.techRiverpodDesc,
                      ),
                      _TechItem(
                        icon: Icons.table_rows_outlined,
                        label: l10n.techDrift,
                        description: l10n.techDriftDesc,
                      ),
                      _TechItem(
                        icon: Icons.alt_route,
                        label: l10n.techRouter,
                        description: l10n.techRouterDesc,
                      ),
                      _TechItem(
                        icon: Icons.desktop_windows_outlined,
                        label: l10n.techWindow,
                        description: l10n.techWindowDesc,
                      ),
                    ],
                  );
                  if (constraints.maxWidth < 760) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        tech,
                        const SizedBox(height: AppSpacing.lg),
                        const _AuthorCard(),
                      ],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Expanded(flex: 3, child: tech),
                      const SizedBox(width: AppSpacing.lg),
                      const Expanded(flex: 2, child: _AuthorCard()),
                    ],
                  );
                },
              ),
              const SizedBox(height: AppSpacing.xl),
              Divider(color: colors.hairline, height: 1),
              const SizedBox(height: AppSpacing.sm),
              const _Footer(),
            ],
          ),
        ),
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colors = context.colors;

    final Widget copy = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          l10n.aboutHeading,
          style: theme.textTheme.headlineLarge?.copyWith(
            fontFamily: AppTypography.sans,
            fontFamilyFallback: AppTypography.sansFallback,
            fontSize: 24,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          l10n.appDescription,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colors.inkSecondary,
          ),
        ),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          l10n.aboutLocalNote,
          style: theme.textTheme.bodySmall?.copyWith(color: colors.inkMuted),
        ),
        const SizedBox(height: AppSpacing.md),
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.xs,
          ),
          decoration: BoxDecoration(
            color: colors.surfaceSunken,
            borderRadius: BorderRadius.circular(AppRadius.pill),
          ),
          child: Text(
            l10n.aboutVersionLabel(AppInfo.version),
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.inkSecondary,
            ),
          ),
        ),
      ],
    );

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        if (constraints.maxWidth < 600) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const AppMark(size: 64),
                  const SizedBox(width: AppSpacing.lg),
                  Expanded(child: copy),
                ],
              ),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const AppMark(size: 72),
            const SizedBox(width: AppSpacing.lg),
            Expanded(child: copy),
          ],
        );
      },
    );
  }
}

class _RepoCard extends StatelessWidget {
  const _RepoCard();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colors = context.colors;

    return Material(
      color: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        side: BorderSide(color: colors.hairline),
      ),
      clipBehavior: Clip.antiAlias,
      child: Semantics(
        label:
            '${l10n.aboutOpenSource}, ${AppInfo.repository}, ${AppInfo.license}',
        link: true,
        child: InkWell(
          onTap: () => ExternalLinks.open(AppInfo.repository),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                final Widget repoText = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      l10n.aboutOpenSource,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: colors.ink,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      AppInfo.repository,
                      softWrap: true,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colors.accent,
                      ),
                    ),
                  ],
                );
                final Widget license = Text(
                  AppInfo.license,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.inkMuted,
                  ),
                );
                if (constraints.maxWidth < 520) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Icon(Icons.code, size: 20, color: colors.accent),
                          const SizedBox(width: AppSpacing.md),
                          Expanded(child: repoText),
                          const SizedBox(width: AppSpacing.sm),
                          Icon(
                            Icons.arrow_outward,
                            size: 18,
                            color: colors.accent,
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.md),
                      license,
                    ],
                  );
                }
                return Row(
                  children: <Widget>[
                    Icon(Icons.code, size: 20, color: colors.accent),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(child: repoText),
                    const SizedBox(width: AppSpacing.lg),
                    license,
                    const SizedBox(width: AppSpacing.md),
                    Icon(Icons.arrow_outward, size: 18, color: colors.accent),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _TechCard extends StatelessWidget {
  const _TechCard({required this.items});

  final List<_TechItem> items;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return _InfoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _SectionHeading(l10n.aboutTech),
          const SizedBox(height: AppSpacing.xl),
          LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final int columns = constraints.maxWidth < 440 ? 1 : 2;
              final double gap = AppSpacing.lg;
              final double itemWidth =
                  (constraints.maxWidth - gap * (columns - 1)) / columns;
              return Wrap(
                spacing: gap,
                runSpacing: AppSpacing.xl,
                children: <Widget>[
                  for (final _TechItem item in items)
                    SizedBox(width: itemWidth, child: item),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _TechItem extends StatelessWidget {
  const _TechItem({
    required this.label,
    required this.description,
    this.icon,
    this.glyph,
  });

  final String label;
  final String description;
  final IconData? icon;
  final String? glyph;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.colors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: colors.surfaceSunken,
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: glyph != null
              ? Text(
                  glyph!,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: colors.accent,
                    fontWeight: FontWeight.w700,
                  ),
                )
              : Icon(icon, size: 18, color: colors.accent),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                label,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.ink,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                description,
                softWrap: true,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.inkMuted,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AuthorCard extends StatelessWidget {
  const _AuthorCard();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colors = context.colors;
    return _InfoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _SectionHeading(l10n.aboutDeveloper),
          const SizedBox(height: AppSpacing.xl),
          Text(
            AppInfo.author,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.ink,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            l10n.aboutBio,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.inkSecondary,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Divider(color: colors.hairline, height: 1),
          const SizedBox(height: AppSpacing.sm),
          _ActionLink(
            label: l10n.aboutHomepage,
            onTap: () => ExternalLinks.open(AppInfo.website),
          ),
          _ActionLink(
            label: l10n.aboutContact,
            onTap: () => ExternalLinks.open('${AppInfo.repository}/issues'),
          ),
          _ActionLink(
            label: l10n.aboutViewLicense,
            onTap: () =>
                ExternalLinks.open('${AppInfo.repository}/blob/main/LICENSE'),
          ),
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Material(
      color: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        side: BorderSide(color: colors.hairline),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: child,
      ),
    );
  }
}

class _ActionLink extends StatelessWidget {
  const _ActionLink({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      label: label,
      link: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 42),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    label,
                    style: Theme.of(context).textTheme.labelLarge
                        ?.copyWith(color: colors.accent),
                  ),
                ),
                Icon(Icons.arrow_outward, size: 16, color: colors.accent),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colors = context.colors;
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: AppSpacing.lg,
      runSpacing: AppSpacing.xs,
      children: <Widget>[
        Text(
          '© 2026 ${AppInfo.author} · ${AppInfo.license}',
          style: theme.textTheme.bodySmall?.copyWith(color: colors.inkMuted),
        ),
        _FooterLink(
          label: l10n.aboutDesignSystem,
          onTap: () => context.push('/design'),
        ),
      ],
    );
  }
}

class _FooterLink extends StatelessWidget {
  const _FooterLink({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      label: label,
      link: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 42),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  label,
                  style: Theme.of(context).textTheme.labelLarge
                      ?.copyWith(color: colors.accent),
                ),
                const SizedBox(width: AppSpacing.xs),
                Icon(Icons.arrow_forward, size: 16, color: colors.accent),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
        color: context.colors.ink,
        fontSize: 16,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

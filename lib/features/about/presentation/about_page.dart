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

/// About, laid out like the qingyun client: hero with an eyebrow and a large
/// mark, a two-column detail area (tech stack + developer), and a quiet footer.
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
          _Hero(),
          const SizedBox(height: AppSpacing.xxl + AppSpacing.lg),
          LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final Widget tech = _TechColumn(
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

              if (constraints.maxWidth < 860) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    tech,
                    const SizedBox(height: AppSpacing.xxl),
                    const _AuthorColumn(),
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(flex: 17, child: tech),
                  const SizedBox(width: AppSpacing.xxl),
                  Expanded(flex: 10, child: const _AuthorColumn()),
                ],
              );
            },
          ),
          const SizedBox(height: AppSpacing.xxl),
          Divider(color: colors.hairline, height: 1),
          const SizedBox(height: AppSpacing.lg),
          _Footer(),
          const SizedBox(height: AppSpacing.lg),
        ],
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colors = context.colors;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'ABOUT',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colors.accent,
                  letterSpacing: 3,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: AppSpacing.sm + 2),
              Text(
                l10n.aboutHeading,
                style: theme.textTheme.displaySmall?.copyWith(
                  fontFamily: AppTypography.serif,
                  fontFamilyFallback: AppTypography.serifFallback,
                  fontSize: 30,
                ),
              ),
              const SizedBox(height: AppSpacing.xs + 2),
              Text(
                l10n.appTagline,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.inkSecondary,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: <Widget>[
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: colors.surface,
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                      border: Border.all(color: colors.hairline),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: colors.success,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 7),
                        Text(
                          l10n.aboutVersionLabel(AppInfo.version),
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: colors.inkSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  OutlinedButton(
                    onPressed: () =>
                        ExternalLinks.open('${AppInfo.repository}/releases'),
                    child: Text(l10n.aboutChangelog),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.xl),
        const AppMark(size: 112),
      ],
    );
  }
}

class _TechColumn extends StatelessWidget {
  const _TechColumn({required this.items});

  final List<_TechItem> items;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colors = context.colors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _SectionHeading(l10n.aboutTech),
        const SizedBox(height: AppSpacing.xs + 2),
        Text(
          l10n.aboutTechIntro,
          style: theme.textTheme.bodySmall?.copyWith(
            color: colors.inkSecondary,
            height: 1.7,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final int columns = constraints.maxWidth < 520 ? 1 : 2;
            final double gap = AppSpacing.lg;
            final double itemWidth =
                (constraints.maxWidth - gap * (columns - 1)) / columns;
            return Wrap(
              spacing: gap,
              runSpacing: AppSpacing.lg,
              children: <Widget>[
                for (final _TechItem item in items)
                  SizedBox(width: itemWidth, child: item),
              ],
            );
          },
        ),
        const SizedBox(height: AppSpacing.xxl),
        const _RepoCard(),
      ],
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
      children: <Widget>[
        Container(
          width: 34,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(AppRadius.sm + 1),
            border: Border.all(color: colors.hairline),
          ),
          child: glyph != null
              ? Text(
                  glyph!,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: colors.accent,
                    fontWeight: FontWeight.w700,
                  ),
                )
              : Icon(icon, size: 17, color: colors.accent),
        ),
        const SizedBox(width: AppSpacing.md - 2),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                label,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: colors.ink,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                description,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
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

class _RepoCard extends StatelessWidget {
  const _RepoCard();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colors = context.colors;

    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: () => ExternalLinks.open(AppInfo.repository),
        borderRadius: BorderRadius.circular(AppRadius.md + 2),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.lg - 2,
          ),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(AppRadius.md + 2),
            border: Border.all(color: colors.hairline),
          ),
          child: Row(
            children: <Widget>[
              Icon(Icons.code, size: 20, color: colors.inkSecondary),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      l10n.aboutOpenSource,
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 1),
                    Text(
                      AppInfo.repository.replaceFirst(
                        RegExp(r'^https?://'),
                        '',
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.accent,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                AppInfo.license,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colors.inkMuted,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Icon(Icons.arrow_outward, size: 16, color: colors.inkMuted),
            ],
          ),
        ),
      ),
    );
  }
}

class _AuthorColumn extends StatelessWidget {
  const _AuthorColumn();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colors = context.colors;

    return Container(
      padding: const EdgeInsets.only(left: AppSpacing.xl),
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: colors.hairline)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _SectionHeading(l10n.aboutDeveloper),
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: <Widget>[
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: colors.accentSoft,
                ),
                child: Text(
                  'X',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: colors.accent,
                    fontSize: 17,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(AppInfo.author, style: theme.textTheme.titleMedium),
                    const SizedBox(height: 1),
                    Text(
                      l10n.aboutBio,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.inkMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.xs,
            children: <Widget>[
              _TextLink(
                label: l10n.aboutHomepage,
                onTap: () => ExternalLinks.open(AppInfo.website),
              ),
              _TextLink(
                label: l10n.aboutContact,
                onTap: () => ExternalLinks.open('${AppInfo.repository}/issues'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
          Divider(color: colors.hairline, height: 1),
          const SizedBox(height: AppSpacing.lg),
          Text(
            l10n.aboutThanks,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.inkSecondary,
              height: 1.7,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          _TextLink(
            label: l10n.aboutViewLicense,
            onTap: () =>
                ExternalLinks.open('${AppInfo.repository}/blob/main/LICENSE'),
          ),
        ],
      ),
    );
  }
}

class _TextLink extends StatelessWidget {
  const _TextLink({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.xs),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              label,
              style: Theme.of(context).textTheme.labelMedium
                  ?.copyWith(color: colors.accent),
            ),
            const SizedBox(width: 3),
            Icon(Icons.arrow_outward, size: 12, color: colors.accent),
          ],
        ),
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colors = context.colors;

    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: AppSpacing.lg,
      runSpacing: AppSpacing.sm,
      children: <Widget>[
        Text(
          '© 2026 ${AppInfo.author} · ${AppInfo.license}',
          style: theme.textTheme.labelSmall?.copyWith(
            color: colors.inkMuted,
            letterSpacing: 0.3,
          ),
        ),
        Wrap(
          spacing: AppSpacing.lg,
          children: <Widget>[
            _TextLink(
              label: l10n.aboutDesignSystem,
              onTap: () => context.push('/design'),
            ),
            _TextLink(
              label: l10n.aboutChangelog,
              onTap: () => ExternalLinks.open('${AppInfo.repository}/releases'),
            ),
          ],
        ),
      ],
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
      style: Theme.of(context).textTheme.titleMedium?.copyWith(fontSize: 16),
    );
  }
}

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

/// Inner width below which the tech grid drops to a single column. Two items
/// need the 36px icon, its gap and a readable description side by side; the
/// number is measured inside the card, not on the page.
const double _techTwoColumnWidth = 400;

/// Product information at a readable width inside the standard page frame.
class AboutPage extends StatelessWidget {
  const AboutPage({super.key, this.showBackButton = false});

  final bool showBackButton;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;

    return AppPage(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 960),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _Hero(showBackButton: showBackButton),
              const SizedBox(height: AppSpacing.xl),
              const _RepoCard(),
              const SizedBox(height: AppSpacing.lg),
              LayoutBuilder(
                builder: (BuildContext context, BoxConstraints constraints) {
                  final double pageWidth = constraints.maxWidth;
                  // Width the tech card gets when the two cards share a row.
                  final double rowTechWidth =
                      (pageWidth - AppSpacing.lg) * 3 / 5;
                  // Keep the row only while its tech card still fits a pair;
                  // otherwise the cards stack and the full width goes to the
                  // grid. This keeps the grid from collapsing to one column
                  // while the (non-row) card obviously has room for two.
                  final bool stacked =
                      rowTechWidth - AppSpacing.xl * 2 < _techTwoColumnWidth;
                  final double techWidth = stacked ? pageWidth : rowTechWidth;
                  final int techColumns =
                      techWidth - AppSpacing.xl * 2 >= _techTwoColumnWidth
                      ? 2
                      : 1;
                  final Widget tech = _TechCard(
                    columns: techColumns,
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
                  if (stacked) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        tech,
                        const SizedBox(height: AppSpacing.lg),
                        const _AuthorCard(),
                      ],
                    );
                  }
                  // Equal card heights: the shorter card stretches to the tech
                  // card's height. Safe here because the tech card no longer
                  // contains a LayoutBuilder (intrinsics cannot probe one).
                  return IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        Expanded(flex: 3, child: tech),
                        const SizedBox(width: AppSpacing.lg),
                        const Expanded(flex: 2, child: _AuthorCard()),
                      ],
                    ),
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
  const _Hero({this.showBackButton = false});

  /// Pushed About pages carry their own back control. It floats over the
  /// top-left corner instead of taking a row, so the centred stack starts right
  /// under the page padding.
  final bool showBackButton;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colors = context.colors;

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool narrow = constraints.maxWidth < 600;
        final double logoSize = narrow ? 64 : 72;

        return Stack(
          children: <Widget>[
            SizedBox(
              width: double.infinity,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: <Widget>[
                  AppMark(size: logoSize),
                  const SizedBox(height: AppSpacing.lg + AppSpacing.xs),
                  Text(
                    l10n.aboutHeading,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineLarge?.copyWith(
                      fontFamily: AppTypography.sans,
                      fontFamilyFallback: AppTypography.sansFallback,
                      fontSize: narrow ? 22 : 24,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm + AppSpacing.xxs),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: <Widget>[
                      _MetaPill(
                        label: l10n.aboutVersionLabel(AppInfo.version),
                        background: colors.accent,
                        foreground: colors.accentContrast,
                      ),
                      _MetaPill(
                        label: AppInfo.license,
                        background: colors.surfaceSunken,
                        foreground: colors.inkSecondary,
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: Column(
                      children: <Widget>[
                        Text(
                          l10n.appDescription,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colors.inkSecondary,
                            height: 1.6,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          l10n.aboutLocalNote,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.inkMuted,
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (showBackButton)
              Positioned(
                left: 0,
                top: 0,
                child: BackButton(onPressed: () => context.pop()),
              ),
          ],
        );
      },
    );
  }
}

/// Small rounded label used by the hero (version, licence).
class _MetaPill extends StatelessWidget {
  const _MetaPill({
    required this.label,
    required this.background,
    required this.foreground,
  });

  final String label;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.bodySmall
            ?.copyWith(color: foreground, fontWeight: FontWeight.w600),
      ),
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
  const _TechCard({required this.items, required this.columns});

  final List<_TechItem> items;

  /// 2 on a wide page, 1 when the card is too narrow for a pair. Computed by
  /// the page from the width the card will get, not by a LayoutBuilder here,
  /// so the card can participate in IntrinsicHeight.
  final int columns;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final List<Widget> rows = <Widget>[];
    for (int start = 0; start < items.length; start += columns) {
      final List<_TechItem> slice = items.sublist(
        start,
        (start + columns).clamp(0, items.length),
      );
      rows.add(
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.xl),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              for (int column = 0; column < columns; column++) ...<Widget>[
                if (column > 0) const SizedBox(width: AppSpacing.lg),
                Expanded(
                  child: column < slice.length
                      ? slice[column]
                      : const SizedBox.shrink(),
                ),
              ],
            ],
          ),
        ),
      );
    }

    return _InfoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _SectionHeading(l10n.aboutTech),
          const SizedBox(height: AppSpacing.xl),
          ...rows,
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

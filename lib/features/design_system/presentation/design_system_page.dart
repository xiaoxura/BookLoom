import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/settings/appearance.dart';
import '../../../design/components/app_page.dart';
import '../../../design/components/glass_surface.dart';
import '../../../design/theme/app_tokens.dart';
import '../../../design/tokens/app_metrics.dart';
import '../../../l10n/app_localizations.dart';

/// Living style guide. Not a product screen: it exists so visual changes can be
/// reviewed in one place instead of hunting through feature pages.
class DesignSystemPage extends ConsumerWidget {
  const DesignSystemPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;

    return AppPage(
      eyebrow: 'BOOKLOOM',
      title: l10n.designTitle,
      subtitle: l10n.designSubtitle,
      leading: IconButton(
        tooltip: MaterialLocalizations.of(context).backButtonTooltip,
        onPressed: () =>
            context.canPop() ? context.pop() : context.go('/library'),
        icon: const Icon(Icons.arrow_back, size: 19),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _Section(
            title: l10n.designSectionColors,
            description: l10n.designSectionColorsDesc,
            child: Wrap(
              spacing: AppSpacing.md,
              runSpacing: AppSpacing.md,
              children: <Widget>[
                _Swatch('canvas', colors.canvas),
                _Swatch('canvasAlt', colors.canvasAlt),
                _Swatch('surface', colors.surface),
                _Swatch('surfaceRaised', colors.surfaceRaised),
                _Swatch('surfaceSunken', colors.surfaceSunken),
                _Swatch('ink', colors.ink),
                _Swatch('inkSecondary', colors.inkSecondary),
                _Swatch('inkMuted', colors.inkMuted),
                _Swatch('hairline', colors.hairline),
                _Swatch('accent', colors.accent),
                _Swatch('accentSoft', colors.accentSoft),
                _Swatch('success', colors.success),
                _Swatch('warning', colors.warning),
                _Swatch('danger', colors.danger),
              ],
            ),
          ),
          _Section(
            title: l10n.designSectionType,
            description: l10n.designSectionTypeDesc,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _TypeSample(
                  'displayMedium',
                  Theme.of(context).textTheme.displayMedium,
                  l10n.designTypeHeading,
                ),
                _TypeSample(
                  'headlineMedium',
                  Theme.of(context).textTheme.headlineMedium,
                  l10n.designTypeHeading,
                ),
                _TypeSample(
                  'titleLarge',
                  Theme.of(context).textTheme.titleLarge,
                  l10n.designSampleCardTitle,
                ),
                _TypeSample(
                  'titleMedium',
                  Theme.of(context).textTheme.titleMedium,
                  l10n.designSampleCardTitle,
                ),
                _TypeSample(
                  'bodyLarge',
                  Theme.of(context).textTheme.bodyLarge,
                  l10n.designTypeBody,
                ),
                _TypeSample(
                  'bodyMedium',
                  Theme.of(context).textTheme.bodyMedium,
                  l10n.designSampleCardBody,
                ),
                _TypeSample(
                  'bodySmall',
                  Theme.of(context).textTheme.bodySmall,
                  l10n.designSampleCardBody,
                ),
                _TypeSample(
                  'labelLarge',
                  Theme.of(context).textTheme.labelLarge,
                  l10n.designLabelPrimary,
                ),
                const SizedBox(height: AppSpacing.md),
                Container(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  decoration: BoxDecoration(
                    color: colors.surface,
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                    border: Border.all(color: colors.hairline),
                  ),
                  child: Text(
                    '　　${l10n.designTypeBody}',
                    style: AppTypographyReading.of(context),
                  ),
                ),
              ],
            ),
          ),
          _Section(
            title: l10n.designSectionSpacing,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Wrap(
                  spacing: AppSpacing.lg,
                  runSpacing: AppSpacing.sm,
                  children: <Widget>[
                    for (final (String label, double value)
                        in <(String, double)>[
                          ('xxs', AppSpacing.xxs),
                          ('xs', AppSpacing.xs),
                          ('sm', AppSpacing.sm),
                          ('md', AppSpacing.md),
                          ('lg', AppSpacing.lg),
                          ('xl', AppSpacing.xl),
                          ('xxl', AppSpacing.xxl),
                          ('xxxl', AppSpacing.xxxl),
                        ])
                      _MetricBar(label: label, value: value),
                  ],
                ),
                const SizedBox(height: AppSpacing.xl),
                Wrap(
                  spacing: AppSpacing.md,
                  runSpacing: AppSpacing.md,
                  children: <Widget>[
                    for (final (String label, double value)
                        in <(String, double)>[
                          ('xs', AppRadius.xs),
                          ('sm', AppRadius.sm),
                          ('md', AppRadius.md),
                          ('lg', AppRadius.lg),
                          ('xl', AppRadius.xl),
                        ])
                      _RadiusSample(label: label, radius: value),
                  ],
                ),
              ],
            ),
          ),
          _Section(
            title: l10n.designSectionGlass,
            description: l10n.designSectionGlassDesc,
            child: Container(
              padding: const EdgeInsets.all(AppSpacing.lg),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppRadius.lg),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: <Color>[
                    colors.accent.withValues(alpha: 0.35),
                    colors.accentSoft,
                    colors.canvas,
                  ],
                ),
              ),
              child: Wrap(
                spacing: AppSpacing.md,
                runSpacing: AppSpacing.md,
                children: <Widget>[
                  for (final GlassQuality quality in GlassQuality.values)
                    SizedBox(
                      width: 236,
                      child: GlassSurface(
                        quality: quality,
                        padding: const EdgeInsets.all(AppSpacing.lg),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              quality.name,
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(
                                    letterSpacing: 1.4,
                                    color: colors.accent,
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                            const SizedBox(height: AppSpacing.xs + 2),
                            Text(
                              l10n.designGlassPanelTitle,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: AppSpacing.xs),
                            Text(
                              l10n.designGlassPanelBody,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: colors.inkSecondary,
                                    height: 1.6,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          _Section(
            title: l10n.designSectionComponents,
            description: l10n.designSectionComponentsDesc,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Wrap(
                  spacing: AppSpacing.md,
                  runSpacing: AppSpacing.md,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: <Widget>[
                    FilledButton(
                      onPressed: () {},
                      child: Text(l10n.designLabelPrimary),
                    ),
                    OutlinedButton(
                      onPressed: () {},
                      child: Text(l10n.designLabelSecondary),
                    ),
                    TextButton(
                      onPressed: () {},
                      child: Text(l10n.designLabelText),
                    ),
                    const FilledButton(
                      onPressed: null,
                      child: Text('禁用 / Disabled'),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                Wrap(
                  spacing: AppSpacing.md,
                  runSpacing: AppSpacing.md,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: <Widget>[
                    SizedBox(
                      width: 240,
                      child: TextField(
                        decoration: InputDecoration(
                          hintText: l10n.designPlaceholderInput,
                        ),
                      ),
                    ),
                    Chip(label: Text(l10n.designLabelChip)),
                    Chip(
                      avatar: Icon(
                        Icons.lock_outline,
                        size: 14,
                        color: colors.inkMuted,
                      ),
                      label: Text(l10n.designLabelChip),
                    ),
                    const _SwitchDemo(),
                    SegmentedButton<int>(
                      showSelectedIcon: false,
                      segments: <ButtonSegment<int>>[
                        ButtonSegment<int>(
                          value: 0,
                          label: Text(l10n.themeLight),
                        ),
                        ButtonSegment<int>(
                          value: 1,
                          label: Text(l10n.themeDark),
                        ),
                      ],
                      selected: const <int>{0},
                      onSelectionChanged: (Set<int> _) {},
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                Container(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  decoration: BoxDecoration(
                    color: colors.surface,
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                    border: Border.all(color: colors.hairline),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        l10n.designSampleCardTitle,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        l10n.designSampleCardBody,
                        style: Theme.of(context).textTheme.bodyMedium
                            ?.copyWith(color: colors.inkSecondary),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xxl),
        ],
      ),
    );
  }
}

/// Reading style exposed for the gallery without leaking typography internals.
abstract final class AppTypographyReading {
  static TextStyle of(BuildContext context) =>
      Theme.of(context).textTheme.bodyLarge!.copyWith(
        fontFamily: 'Noto Serif CJK SC',
        fontFamilyFallback: const <String>[
          'Noto Serif SC',
          'Source Han Serif SC',
          'Songti SC',
          'SimSun',
          'Georgia',
        ],
        fontSize: 17,
        height: 1.95,
        letterSpacing: 0.2,
        color: context.colors.ink,
      );
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child, this.description});

  final String title;
  final String? description;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xxl + AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(title, style: theme.textTheme.titleLarge),
          if (description != null) ...<Widget>[
            const SizedBox(height: AppSpacing.xs),
            Text(
              description!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: context.colors.inkSecondary,
                height: 1.6,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          child,
        ],
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch(this.label, this.color);

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final String hex =
        '#${color.toARGB32().toRadixString(16).substring(2).toUpperCase()}';
    return SizedBox(
      width: 104,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            height: 54,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(AppRadius.sm),
              border: Border.all(color: context.colors.hairline),
            ),
          ),
          const SizedBox(height: AppSpacing.sm - 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall
                ?.copyWith(color: context.colors.inkSecondary),
          ),
          Text(hex, style: Theme.of(context).textTheme.labelSmall),
        ],
      ),
    );
  }
}

class _TypeSample extends StatelessWidget {
  const _TypeSample(this.label, this.style, this.sample);

  final String label;
  final TextStyle? style;
  final String sample;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: <Widget>[
          SizedBox(
            width: 132,
            child: Text(label, style: Theme.of(context).textTheme.labelSmall),
          ),
          Expanded(child: Text(sample, style: style)),
        ],
      ),
    );
  }
}

class _MetricBar extends StatelessWidget {
  const _MetricBar({required this.label, required this.value});

  final String label;
  final double value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Container(
          width: value,
          height: 10,
          decoration: BoxDecoration(
            color: context.colors.accent,
            borderRadius: BorderRadius.circular(AppRadius.xs),
          ),
        ),
        const SizedBox(height: AppSpacing.xs + 2),
        Text(
          '$label · ${value.toInt()}',
          style: Theme.of(context).textTheme.labelSmall,
        ),
      ],
    );
  }
}

class _RadiusSample extends StatelessWidget {
  const _RadiusSample({required this.label, required this.radius});

  final String label;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      children: <Widget>[
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: colors.hairline),
          ),
        ),
        const SizedBox(height: AppSpacing.xs + 2),
        Text(
          '$label · ${radius.toInt()}',
          style: Theme.of(context).textTheme.labelSmall,
        ),
      ],
    );
  }
}

class _SwitchDemo extends StatefulWidget {
  const _SwitchDemo();

  @override
  State<_SwitchDemo> createState() => _SwitchDemoState();
}

class _SwitchDemoState extends State<_SwitchDemo> {
  bool _value = true;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Switch(
          value: _value,
          onChanged: (bool v) => setState(() => _value = v),
        ),
        const SizedBox(width: AppSpacing.sm - 2),
        Text(
          AppLocalizations.of(context).designLabelSwitch,
          style: Theme.of(context).textTheme.labelMedium,
        ),
      ],
    );
  }
}

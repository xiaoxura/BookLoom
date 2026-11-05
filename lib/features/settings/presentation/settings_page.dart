import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../core/settings/appearance.dart';
import '../../../design/components/app_page.dart';
import '../../../design/theme/app_tokens.dart';
import '../../../design/tokens/app_metrics.dart';
import '../../../l10n/app_localizations.dart';
import 'workbench_defaults.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final appearance = ref.watch(appearanceProvider);
    final controller = ref.read(appearanceProvider.notifier);
    final String dataPath = ref.watch(appPathsProvider).support.path;
    final bool showThemeIcons =
        MediaQuery.sizeOf(context).width >=
        AppLayout.themeControlIconBreakpoint;

    return AppPage(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _SectionTitle(l10n.settingsAppearance),
          _SettingsCard(
            children: <Widget>[
              _SettingRow(
                title: l10n.settingsThemeMode,
                scrollableControl: true,
                control: SegmentedButton<AppThemeMode>(
                  showSelectedIcon: false,
                  segments: <ButtonSegment<AppThemeMode>>[
                    ButtonSegment<AppThemeMode>(
                      value: AppThemeMode.system,
                      label: Text(l10n.themeSystem, softWrap: false),
                      icon: showThemeIcons
                          ? const Icon(Icons.brightness_auto_outlined, size: 17)
                          : null,
                    ),
                    ButtonSegment<AppThemeMode>(
                      value: AppThemeMode.light,
                      label: Text(l10n.themeLight, softWrap: false),
                      icon: showThemeIcons
                          ? const Icon(Icons.light_mode_outlined, size: 17)
                          : null,
                    ),
                    ButtonSegment<AppThemeMode>(
                      value: AppThemeMode.dark,
                      label: Text(l10n.themeDark, softWrap: false),
                      icon: showThemeIcons
                          ? const Icon(Icons.dark_mode_outlined, size: 17)
                          : null,
                    ),
                  ],
                  selected: <AppThemeMode>{appearance.themeMode},
                  onSelectionChanged: (Set<AppThemeMode> selection) =>
                      controller.setThemeMode(selection.first),
                ),
              ),
              const _CardDivider(),
              _SettingRow(
                title: l10n.settingsGlass,
                description: l10n.settingsGlassDesc,
                scrollableControl: true,
                control: SegmentedButton<GlassQuality>(
                  showSelectedIcon: false,
                  segments: <ButtonSegment<GlassQuality>>[
                    ButtonSegment<GlassQuality>(
                      value: GlassQuality.off,
                      label: Text(l10n.glassOff),
                    ),
                    ButtonSegment<GlassQuality>(
                      value: GlassQuality.soft,
                      label: Text(l10n.glassSoft),
                    ),
                    ButtonSegment<GlassQuality>(
                      value: GlassQuality.strong,
                      label: Text(l10n.glassStrong),
                    ),
                  ],
                  selected: <GlassQuality>{appearance.glass},
                  onSelectionChanged: (Set<GlassQuality> selection) =>
                      controller.setGlass(selection.first),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xxl),
          const _SettingsCard(
            children: [
              Padding(
                padding: EdgeInsets.all(AppSpacing.lg),
                child: WorkbenchDefaults(),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xxl),
          _SectionTitle(l10n.settingsData),
          _SettingsCard(
            children: <Widget>[
              _SettingRow(
                title: l10n.settingsDataLocation,
                description: l10n.settingsDataLocationDesc,
                stack: true,
                control: Row(
                  children: <Widget>[
                    Expanded(
                      child: SelectableText(
                        dataPath,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: context.colors.inkSecondary,
                          height: 1.6,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    TextButton.icon(
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(text: dataPath));
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(l10n.settingsCopied)),
                        );
                      },
                      icon: const Icon(Icons.copy_rounded, size: 15),
                      label: Text(l10n.settingsCopyPath),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: () => context.push('/data'),
              icon: const Icon(Icons.backup_outlined),
              label: Text(l10n.workbenchOpenData),
            ),
          ),
          const SizedBox(height: AppSpacing.xxl),
          _SettingsCard(
            children: <Widget>[
              ListTile(
                leading: const Icon(Icons.shield_outlined),
                title: Text(l10n.settingsPermissions),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/permissions'),
              ),
              const _CardDivider(),
              ListTile(
                leading: const Icon(Icons.info_outline),
                title: Text(l10n.navAbout),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/about-info'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
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

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        side: BorderSide(color: context.colors.hairline),
      ),
      child: Column(children: children),
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

class _SettingRow extends StatelessWidget {
  const _SettingRow({
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

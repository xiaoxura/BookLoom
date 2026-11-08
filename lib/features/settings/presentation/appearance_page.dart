import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../core/settings/appearance.dart';
import '../../../design/components/app_page.dart';
import '../../../design/tokens/app_metrics.dart';
import '../../../l10n/app_localizations.dart';
import 'settings_widgets.dart';

/// Theme mode. Split out of the settings index so the index
/// stays a list of destinations instead of growing into one long page.
class AppearancePage extends ConsumerWidget {
  const AppearancePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final appearance = ref.watch(appearanceProvider);
    final controller = ref.read(appearanceProvider.notifier);
    final bool showThemeIcons =
        MediaQuery.sizeOf(context).width >=
        AppLayout.themeControlIconBreakpoint;

    return AppPage(
      title: l10n.settingsAppearance,
      leading: BackButton(onPressed: () => context.pop()),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SettingsCard(
            children: <Widget>[
              SettingsRow(
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
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
        ],
      ),
    );
  }
}

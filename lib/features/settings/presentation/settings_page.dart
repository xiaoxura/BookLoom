import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../design/components/app_page.dart';
import '../../../design/tokens/app_metrics.dart';
import '../../../l10n/app_localizations.dart';
import 'settings_widgets.dart';

/// The settings tab is an index of destinations. Each section lives on its own
/// page so this list can keep growing without turning into a long scroll.
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return AppPage(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SettingsSectionTitle(l10n.settingsPreferences),
          SettingsCard(
            children: <Widget>[
              SettingsEntry(
                icon: Icons.palette_outlined,
                title: l10n.settingsAppearance,
                description: l10n.settingsAppearanceDesc,
                onTap: () => context.push('/settings/appearance'),
              ),
              const SettingsCardDivider(),
              SettingsEntry(
                icon: Icons.tune_outlined,
                title: l10n.settingsDefaultsTitle,
                description: l10n.settingsDefaultsDesc,
                onTap: () => context.push('/settings/defaults'),
              ),
              const SettingsCardDivider(),
              SettingsEntry(
                icon: Icons.auto_awesome_outlined,
                title: l10n.aiSettingsTitle,
                description: l10n.aiSettingsDescription,
                onTap: () => context.push('/settings/ai'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xxl),
          SettingsSectionTitle(l10n.settingsMaintenance),
          SettingsCard(
            children: <Widget>[
              SettingsEntry(
                icon: Icons.folder_outlined,
                title: l10n.settingsStorageTitle,
                description: l10n.settingsStorageDesc,
                onTap: () => context.push('/settings/storage'),
              ),
              const SettingsCardDivider(),
              SettingsEntry(
                icon: Icons.monitor_heart_outlined,
                title: l10n.settingsDiagnostics,
                description: l10n.settingsDiagnosticsDesc,
                onTap: () => context.push('/settings/diagnostics'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xxl),
          SettingsSectionTitle(l10n.settingsHelp),
          SettingsCard(
            children: <Widget>[
              SettingsEntry(
                icon: Icons.shield_outlined,
                title: l10n.settingsPermissions,
                onTap: () => context.push('/settings/permissions'),
              ),
              const SettingsCardDivider(),
              SettingsEntry(
                icon: Icons.info_outline,
                title: l10n.navAbout,
                onTap: () => context.push('/settings/about'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
        ],
      ),
    );
  }
}

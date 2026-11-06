import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../design/components/app_page.dart';
import '../../../design/tokens/app_metrics.dart';
import '../../../l10n/app_localizations.dart';
import 'settings_widgets.dart';
import 'workbench_defaults.dart';

/// Defaults applied to books imported from now on.
class DefaultsPage extends StatelessWidget {
  const DefaultsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AppPage(
      title: l10n.settingsDefaultsTitle,
      leading: BackButton(onPressed: () => context.pop()),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const SettingsCard(
            children: <Widget>[
              Padding(
                padding: EdgeInsets.all(AppSpacing.lg),
                child: WorkbenchDefaults(),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
        ],
      ),
    );
  }
}

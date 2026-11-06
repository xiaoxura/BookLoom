import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../design/components/app_page.dart';
import '../../../design/theme/app_tokens.dart';
import '../../../design/tokens/app_metrics.dart';
import '../../../l10n/app_localizations.dart';
import 'settings_widgets.dart';

/// Where the library lives, and the entry to batch runs and backups.
class StoragePage extends ConsumerWidget {
  const StoragePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final String dataPath = ref.watch(appPathsProvider).support.path;

    return AppPage(
      title: l10n.settingsStorageTitle,
      leading: BackButton(onPressed: () => context.pop()),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SettingsCard(
            children: <Widget>[
              SettingsRow(
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
          const SizedBox(height: AppSpacing.xl),
        ],
      ),
    );
  }
}

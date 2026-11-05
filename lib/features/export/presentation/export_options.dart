import 'package:bookloom/core/formatting/document_export.dart';
import 'package:bookloom/features/export/presentation/device_help.dart';
import 'package:bookloom/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

String exportFormatLabel(ExportFormat format) => switch (format) {
  ExportFormat.epub3 => 'EPUB 3',
  ExportFormat.epub2 => 'EPUB 2',
  ExportFormat.docx => 'DOCX',
  ExportFormat.html => 'HTML',
  ExportFormat.txt => 'TXT',
  ExportFormat.markdown => 'Markdown',
};

Future<ExportFormat?> chooseExportFormat(
  BuildContext context, {
  ExportFormat initialFormat = ExportFormat.epub3,
  bool forSharing = false,
}) => showModalBottomSheet<ExportFormat>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (context) =>
      _ExportOptions(initialFormat: initialFormat, forSharing: forSharing),
);

class _ExportOptions extends StatefulWidget {
  const _ExportOptions({required this.initialFormat, required this.forSharing});
  final ExportFormat initialFormat;
  final bool forSharing;

  @override
  State<_ExportOptions> createState() => _ExportOptionsState();
}

class _ExportOptionsState extends State<_ExportOptions> {
  late ExportFormat _format = widget.initialFormat;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final description = switch (_format) {
      ExportFormat.epub3 ||
      ExportFormat.epub2 => l10n.exportWorkbenchEpubDescription,
      ExportFormat.docx => l10n.exportWorkbenchDocxDescription,
      ExportFormat.html => l10n.exportWorkbenchHtmlDescription,
      ExportFormat.txt ||
      ExportFormat.markdown => l10n.exportWorkbenchTextDescription,
    };
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        24,
        24,
        24,
        24 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.forSharing
                  ? l10n.exportWorkbenchShareTitle
                  : l10n.exportWorkbenchExportTitle,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<ExportFormat>(
              initialValue: _format,
              decoration: InputDecoration(
                labelText: l10n.exportWorkbenchFormatLabel,
              ),
              items: [
                for (final value in ExportFormat.values)
                  DropdownMenuItem(
                    value: value,
                    child: Text(exportFormatLabel(value)),
                  ),
              ],
              onChanged: (value) => setState(() => _format = value ?? _format),
            ),
            const SizedBox(height: 16),
            Text(description),
            const SizedBox(height: 16),
            TextButton.icon(
              onPressed: () => showDeviceHelp(context),
              icon: const Icon(Icons.help_outline),
              label: Text(l10n.exportWorkbenchDeviceHelpAction),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => Navigator.pop(context, _format),
              child: Text(
                widget.forSharing
                    ? l10n.exportWorkbenchShareAction
                    : l10n.exportWorkbenchSaveAction,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

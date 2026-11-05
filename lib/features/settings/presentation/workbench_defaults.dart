import 'package:bookloom/app/providers.dart';
import 'package:bookloom/core/formatting/document_export.dart';
import 'package:bookloom/core/model/layout_options.dart';
import 'package:bookloom/core/settings/workbench_preferences.dart';
import 'package:bookloom/design/components/app_select_field.dart';
import 'package:bookloom/design/tokens/app_metrics.dart';
import 'package:bookloom/features/export/presentation/export_options.dart';
import 'package:bookloom/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class WorkbenchDefaults extends ConsumerStatefulWidget {
  const WorkbenchDefaults({super.key});

  @override
  ConsumerState<WorkbenchDefaults> createState() => _WorkbenchDefaultsState();
}

class _WorkbenchDefaultsState extends ConsumerState<WorkbenchDefaults> {
  WorkbenchPreferences? _value;
  String? _error;
  bool _saving = false;
  WorkbenchPreferences? _pendingSave;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final value = await WorkbenchPreferences.read(
        ref.read(settingsStoreProvider),
      );
      if (mounted) setState(() => _value = value);
    } on Object catch (error) {
      if (mounted) setState(() => _error = '$error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final value = _value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.bookWorkbenchNewBookDefaults,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(l10n.bookWorkbenchDefaultsScope),
        if (value == null && _error == null) const LinearProgressIndicator(),
        if (value != null) ...[
          const SizedBox(height: AppSpacing.lg),
          AppSelectField<ExportFormat>(
            label: l10n.bookWorkbenchDefaultExportFormat,
            initialSelection: value.exportFormat,
            entries: [
              for (final format in ExportFormat.values)
                DropdownMenuEntry(
                  value: format,
                  label: exportFormatLabel(format),
                ),
            ],
            onSelected: (format) => _save(
              WorkbenchPreferences(
                layout: value.layout,
                exportFormat: format ?? value.exportFormat,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          AppSelectField<LayoutFont>(
            label: l10n.bookWorkbenchDefaultFontRole,
            initialSelection: value.layout.font,
            entries: [
              DropdownMenuEntry(
                value: LayoutFont.serif,
                label: l10n.bookWorkbenchSerif,
              ),
              DropdownMenuEntry(
                value: LayoutFont.sans,
                label: l10n.bookWorkbenchSans,
              ),
              DropdownMenuEntry(
                value: LayoutFont.kai,
                label: l10n.bookWorkbenchKai,
              ),
            ],
            onSelected: (font) => _save(
              WorkbenchPreferences(
                layout: value.layout.copyWith(font: font),
                exportFormat: value.exportFormat,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            l10n.bookWorkbenchDefaultsLineHeight(
              value.layout.lineHeight.toStringAsFixed(2),
            ),
          ),
          Slider(
            value: value.layout.lineHeight,
            min: 1.3,
            max: 2.4,
            divisions: 22,
            onChanged: _saving
                ? null
                : (height) => setState(
                    () => _value = WorkbenchPreferences(
                      layout: value.layout.copyWith(lineHeight: height),
                      exportFormat: value.exportFormat,
                    ),
                  ),
            onChangeEnd: _saving ? null : (_) => _save(_value!),
          ),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.bookWorkbenchDefaultsIndent),
            value: value.layout.indent,
            onChanged: _saving
                ? null
                : (indent) => _save(
                    WorkbenchPreferences(
                      layout: value.layout.copyWith(indent: indent),
                      exportFormat: value.exportFormat,
                    ),
                  ),
          ),
        ],
        SizedBox(
          height: AppSpacing.xs,
          child: _saving ? const LinearProgressIndicator() : null,
        ),
        if (_error != null)
          Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
      ],
    );
  }

  Future<void> _save(WorkbenchPreferences value) async {
    setState(() {
      _value = value;
      _pendingSave = value;
      _error = null;
    });
    if (_saving) return;
    setState(() => _saving = true);
    final store = ref.read(settingsStoreProvider);
    try {
      // While a write is in flight, retain the latest complete preference
      // value. The controls stay enabled as the dropdown route dismisses.
      while (_pendingSave != null) {
        final next = _pendingSave!;
        _pendingSave = null;
        try {
          await next.write(store);
          if (mounted) setState(() => _error = null);
        } on Object catch (error) {
          if (mounted) setState(() => _error = '$error');
        }
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

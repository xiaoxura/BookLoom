import 'dart:convert';

import '../formatting/document_export.dart';
import '../model/layout_options.dart';
import '../storage/settings_store.dart';

class WorkbenchPreferences {
  WorkbenchPreferences({
    LayoutOptions? layout,
    this.exportFormat = ExportFormat.epub3,
  }) : layout = layout ?? LayoutOptions();

  final LayoutOptions layout;
  final ExportFormat exportFormat;
  static const _key = 'workbench.defaults';

  static Future<WorkbenchPreferences> read(SettingsStore store) async {
    final text = await store.read(_key);
    if (text == null) return WorkbenchPreferences();
    try {
      final data = jsonDecode(text) as Map<String, Object?>;
      return WorkbenchPreferences(
        layout: data['layout'] is Map<String, Object?>
            ? LayoutOptions.fromJson(data['layout']! as Map<String, Object?>)
            : null,
        exportFormat: ExportFormat.values.firstWhere(
          (value) => value.name == data['exportFormat'],
          orElse: () => ExportFormat.epub3,
        ),
      );
    } on FormatException {
      return WorkbenchPreferences();
    } on TypeError {
      return WorkbenchPreferences();
    }
  }

  Future<void> write(SettingsStore store) => store.write(
    _key,
    jsonEncode({'layout': layout.toJson(), 'exportFormat': exportFormat.name}),
  );
}

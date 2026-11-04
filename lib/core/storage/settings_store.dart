import '../settings/appearance.dart';
import 'app_database.dart';
import 'tables.dart';

/// Thin typed wrapper over the `settings` key/value table.
class SettingsStore {
  SettingsStore(this._db);

  final AppDatabase _db;

  static const String _themeModeKey = 'appearance.themeMode';
  static const String _glassKey = 'appearance.glass';

  Future<String?> read(String key) async {
    final row = await (_db.select(
      _db.settings,
    )..where((Settings t) => t.key.equals(key))).getSingleOrNull();
    return row?.value;
  }

  Future<void> write(String key, String value) async {
    await _db
        .into(_db.settings)
        .insertOnConflictUpdate(
          SettingsCompanion.insert(key: key, value: value),
        );
  }

  Future<Appearance> readAppearance() async {
    final rows = await _db.select(_db.settings).get();
    final Map<String, String> values = <String, String>{
      for (final row in rows) row.key: row.value,
    };
    return Appearance(
      themeMode: _themeModeFrom(values[_themeModeKey]),
      glass: _glassFrom(values[_glassKey]),
    );
  }

  Future<void> writeAppearance(Appearance appearance) async {
    await _db.transaction(() async {
      await write(_themeModeKey, appearance.themeMode.name);
      await write(_glassKey, appearance.glass.name);
    });
  }

  static AppThemeMode _themeModeFrom(String? wire) =>
      AppThemeMode.values.firstWhere(
        (AppThemeMode m) => m.name == wire,
        orElse: () => AppThemeMode.system,
      );

  static GlassQuality _glassFrom(String? wire) =>
      GlassQuality.values.firstWhere(
        (GlassQuality g) => g.name == wire,
        orElse: () => GlassQuality.strong,
      );
}

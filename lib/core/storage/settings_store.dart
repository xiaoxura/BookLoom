import '../settings/appearance.dart';
import 'app_database.dart';
import 'tables.dart';

/// Thin typed wrapper over the `settings` key/value table.
class SettingsStore {
  SettingsStore(this._db);

  final AppDatabase _db;

  static const String _themeModeKey = 'appearance.themeMode';

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
    return Appearance(themeMode: _themeModeFrom(values[_themeModeKey]));
  }

  Future<void> writeAppearance(Appearance appearance) async {
    await write(_themeModeKey, appearance.themeMode.name);
  }

  static AppThemeMode _themeModeFrom(String? wire) =>
      AppThemeMode.values.firstWhere(
        (AppThemeMode m) => m.name == wire,
        orElse: () => AppThemeMode.system,
      );
}

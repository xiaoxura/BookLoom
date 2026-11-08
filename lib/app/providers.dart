import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/platform/app_paths.dart';
import '../core/settings/appearance.dart';
import '../core/storage/app_database.dart';
import '../core/storage/settings_store.dart';

/// Overridden in `main.dart` after bootstrap resolves the real paths.
final Provider<AppPaths> appPathsProvider = Provider<AppPaths>(
  (Ref ref) =>
      throw StateError('appPathsProvider must be overridden at startup'),
  name: 'appPaths',
);

/// Overridden in `main.dart` with the opened database (or an in-memory one in
/// tests).
final Provider<AppDatabase> databaseProvider = Provider<AppDatabase>(
  (Ref ref) =>
      throw StateError('databaseProvider must be overridden at startup'),
  name: 'database',
);

final Provider<SettingsStore> settingsStoreProvider = Provider<SettingsStore>(
  (Ref ref) => SettingsStore(ref.watch(databaseProvider)),
  name: 'settingsStore',
);

/// Appearance read from disk before the first frame, so the app never flashes
/// the wrong theme.
final Provider<Appearance> initialAppearanceProvider = Provider<Appearance>(
  (Ref ref) => Appearance.defaults,
  name: 'initialAppearance',
);

final NotifierProvider<AppearanceController, Appearance> appearanceProvider =
    NotifierProvider<AppearanceController, Appearance>(
      AppearanceController.new,
      name: 'appearance',
    );

class AppearanceController extends Notifier<Appearance> {
  @override
  Appearance build() => ref.read(initialAppearanceProvider);

  Future<void> setThemeMode(AppThemeMode mode) async {
    if (state.themeMode == mode) return;
    state = state.copyWith(themeMode: mode);
    await _persist();
  }

  /// Cycles system → light → dark, used by the sidebar shortcut.
  Future<void> cycleThemeMode() {
    const List<AppThemeMode> order = <AppThemeMode>[
      AppThemeMode.system,
      AppThemeMode.light,
      AppThemeMode.dark,
    ];
    final int next = (order.indexOf(state.themeMode) + 1) % order.length;
    return setThemeMode(order[next]);
  }

  Future<void> _persist() async {
    try {
      await ref.read(settingsStoreProvider).writeAppearance(state);
    } on Object {
      // Preference writes are best effort; the in-memory value stays correct.
    }
  }
}

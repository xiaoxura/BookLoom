import 'package:logging/logging.dart';

import '../core/errors/app_failure.dart';
import '../core/logging/app_logging.dart';
import '../core/platform/app_paths.dart';
import '../core/settings/appearance.dart';
import '../core/storage/app_database.dart';
import '../core/storage/settings_store.dart';

/// Everything the widget tree needs, resolved before the first frame.
class BootstrapResult {
  const BootstrapResult({
    required this.paths,
    required this.database,
    required this.appearance,
  });

  final AppPaths paths;
  final AppDatabase database;
  final Appearance appearance;
}

final Logger _logger = Logger('bootstrap');

/// Opens directories, logging, the database and the persisted appearance.
///
/// Throws [AppFailure] with a user-facing message when startup cannot continue.
Future<BootstrapResult> bootstrap() async {
  try {
    final AppPaths paths = await AppPaths.resolve();
    await AppLogging.init(directory: paths.logs);
    final AppDatabase database = AppDatabase.openAt(paths.databaseFile);
    final Appearance appearance = await SettingsStore(database)
        .readAppearance();
    _logger.info('startup ok (schema v${database.schemaVersion})');
    return BootstrapResult(
      paths: paths,
      database: database,
      appearance: appearance,
    );
  } on AppFailure {
    rethrow;
  } on Object catch (error, stack) {
    _logger.severe('startup failed: $error', error, stack);
    throw StorageFailure('本地数据无法打开。', cause: error, stackTrace: stack);
  }
}

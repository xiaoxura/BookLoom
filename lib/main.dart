import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'app/bootstrap.dart';
import 'app/error_handling.dart';
import 'app/providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  installErrorHandlers();

  try {
    final BootstrapResult boot = await bootstrap();
    runApp(
      ProviderScope(
        overrides: [
          appPathsProvider.overrideWithValue(boot.paths),
          databaseProvider.overrideWithValue(boot.database),
          initialAppearanceProvider.overrideWithValue(boot.appearance),
        ],
        child: const BookloomApp(),
      ),
    );
  } on Object catch (error, stack) {
    runApp(StartupFailureApp(failure: asAppFailure(error, stack)));
  }
}

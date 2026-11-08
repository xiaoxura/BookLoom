import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../features/editor/application/ai_proofreading_task.dart';
import '../features/editor/application/editor_session.dart';
import '../features/settings/application/ai_configuration_service.dart';
import '../features/settings/data/ai_configuration_store.dart';
import '../features/settings/data/ai_http_client.dart';
import '../features/settings/data/secure_ai_credential_store.dart';
import 'providers.dart';
import 'workbench_providers.dart';

final Provider<AiConfigurationService> aiConfigurationServiceProvider =
    Provider<AiConfigurationService>(
      (Ref ref) => AiConfigurationService(
        cfgStore: AiSettingsConfigurationStore(ref.watch(databaseProvider)),
        credentials: SecureAiCredentialStore(),
        createClient: AiHttpClient.new,
      ),
      name: 'aiConfigurationService',
    );

final aiProofreadingTaskProvider = ChangeNotifierProvider.autoDispose
    .family<AiProofreadingTask, EditorSession>((ref, session) {
      return AiProofreadingTask(
        session: session,
        loadConfiguration: () =>
            ref.read(aiConfigurationServiceProvider).load(),
        credentials: SecureAiCredentialStore(),
        createClient: AiHttpClient.new,
        jobs: ref.read(backgroundJobsProvider),
      );
    }, name: 'aiProofreadingTask');

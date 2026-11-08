import 'package:flutter_riverpod/legacy.dart';

import '../features/editor/application/ai_rule_creation_task.dart';
import '../features/editor/application/editor_session.dart';
import '../features/settings/data/ai_http_client.dart';
import '../features/settings/data/secure_ai_credential_store.dart';
import 'ai_providers.dart';
import 'rule_providers.dart';

final aiRuleCreationTaskProvider = ChangeNotifierProvider.autoDispose
    .family<AiRuleCreationTask, EditorSession>((ref, session) {
      return AiRuleCreationTask(
        session: session,
        loadConfiguration: () =>
            ref.read(aiConfigurationServiceProvider).load(),
        loadRelatedRules: (bookId) =>
            ref.read(proofreadingRuleStoreProvider).loadForBook(bookId),
        credentials: SecureAiCredentialStore(),
        createClient: AiHttpClient.new,
      );
    }, name: 'aiRuleCreationTask');

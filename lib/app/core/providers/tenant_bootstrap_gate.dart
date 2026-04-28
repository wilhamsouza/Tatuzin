import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/app_database.dart';
import '../errors/app_exceptions.dart';
import '../session/session_provider.dart';
import '../utils/app_logger.dart';

Future<String> requireTenantBootstrapReady(Ref ref, String label) async {
  final session = ref.watch(appSessionProvider);
  final runtimeKey = ref.watch(sessionRuntimeKeyProvider);

  if (!session.isAuthenticated) {
    AppLogger.info(
      '[TenantBootstrap] ready true | provider=$label | '
      'scope=${session.scope.name} | runtime_key=$runtimeKey',
    );
    return runtimeKey;
  }

  AppLogger.info(
    '[TenantBootstrap] ready false | provider=$label | '
    'scope=${session.scope.name} | runtime_key=$runtimeKey',
  );
  final startupState = await ref.watch(appStartupProvider.future);
  if (!startupState.isSuccess) {
    AppLogger.error(
      '[TenantBootstrap] ready false | provider=$label | '
      'runtime_key=$runtimeKey | reason=${startupState.status.name}',
    );
    throw AppStartupException(
      startupState.message,
      cause: startupState.debugDetails,
    );
  }

  final currentRuntimeKey = ref.read(sessionRuntimeKeyProvider);
  if (currentRuntimeKey != runtimeKey) {
    AppLogger.info(
      '[TenantBootstrap] ready false | provider=$label | '
      'runtime_key_changed_from=$runtimeKey | runtime_key_changed_to=$currentRuntimeKey',
    );
    throw StateError(
      'A sessao mudou enquanto $label aguardava o tenant. '
      'O provider sera recalculado com a chave atual.',
    );
  }

  AppLogger.info(
    '[TenantBootstrap] ready true | provider=$label | '
    'scope=${session.scope.name} | runtime_key=$runtimeKey',
  );
  return runtimeKey;
}

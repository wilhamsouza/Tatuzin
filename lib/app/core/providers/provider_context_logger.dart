import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_environment.dart';
import '../database/app_database.dart';
import '../session/session_provider.dart';
import '../utils/app_logger.dart';
import 'app_data_refresh_provider.dart';

void logProviderContext(Ref ref, String label) {
  final session = ref.read(appSessionProvider);
  final environment = ref.read(appEnvironmentProvider);
  final isolationKey = _safeIsolationKey(ref);
  final runtimeKey = _safeRuntimeKey(ref);
  final refreshKey = ref.read(appDataRefreshProvider);
  final databaseName = isolationKey == null
      ? 'n/a'
      : AppDatabase.databaseNameForIsolationKey(isolationKey);

  AppLogger.info(
    '[Modo] provider $label iniciou | scope=${session.scope.name} | '
    'connected=${session.isRemoteAuthenticated} | '
    'data_mode=${environment.dataMode.name} | '
    'remote_sync_enabled=${environment.remoteSyncEnabled} | '
    'user_present=${session.user.hasRemoteIdentity} | '
    'company_present=${session.company.hasRemoteIdentity} | '
    'tenant_key=${isolationKey ?? 'n/a'} | '
    'session_runtime_key=$runtimeKey | '
    'app_data_refresh_key=$refreshKey | '
    'database_name=$databaseName',
  );
}

String? _safeIsolationKey(Ref ref) {
  try {
    return ref.read(sessionIsolationKeyProvider);
  } catch (_) {
    return null;
  }
}

String _safeRuntimeKey(Ref ref) {
  try {
    return ref.read(sessionRuntimeKeyProvider);
  } catch (_) {
    return 'invalid_session_runtime_key';
  }
}

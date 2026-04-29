import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

import '../config/app_environment.dart';
import '../constants/app_constants.dart';
import '../errors/app_exceptions.dart';
import '../providers/app_data_refresh_provider.dart';
import '../session/app_session.dart';
import '../session/company_context.dart';
import '../session/session_provider.dart';
import '../utils/app_logger.dart';
import 'migrations.dart';

typedef AppStartupRemotePreflight = Future<void> Function(AppSession session);
typedef AppStartupOpenDatabase = Future<void> Function(String isolationKey);

class _AppStartupTrace {
  String? lastCompletedStep;
  String? pendingStep;
  String? companyRemoteId;
  String? tenantIsolationKey;

  void logBootstrapStarted({
    required AppSession session,
    required AppEnvironment environment,
    required String sessionRuntimeKey,
    required int appDataRefreshKey,
  }) {
    companyRemoteId = session.company.remoteId?.trim();
    final isolationKey = _safeIsolationKeyFor(session);
    AppLogger.info(
      'bootstrap_started | duration_ms=0 | scope=${session.scope.name} | '
      'authenticated=${session.isAuthenticated} | '
      'mode=${environment.dataMode.name} | '
      'remote_sync_enabled=${environment.remoteSyncEnabled} | '
      'user_present=${session.user.hasRemoteIdentity} | '
      'company_present=${session.company.hasRemoteIdentity} | '
      'company_remote_id=${_valueOrNotAvailable(companyRemoteId)} | '
      'tenant_key=${_valueOrNotAvailable(isolationKey)} | '
      'session_runtime_key=$sessionRuntimeKey | '
      'app_data_refresh_key=$appDataRefreshKey | '
      'database_name=${_safeDatabaseNameFor(isolationKey)}',
    );
  }

  String? _safeIsolationKeyFor(AppSession session) {
    try {
      return SessionIsolation.keyFor(session);
    } catch (_) {
      return null;
    }
  }

  String _safeDatabaseNameFor(String? isolationKey) {
    if (isolationKey == null || isolationKey.trim().isEmpty) {
      return 'n/a';
    }
    return AppDatabase.databaseNameForIsolationKey(isolationKey);
  }

  void logStepStarted(
    String step, {
    String? companyRemoteId,
    String? tenantIsolationKey,
    String? userRemoteId,
  }) {
    pendingStep = step;
    this.companyRemoteId = companyRemoteId?.trim() ?? this.companyRemoteId;
    this.tenantIsolationKey = tenantIsolationKey ?? this.tenantIsolationKey;

    AppLogger.info(
      '$step | duration_ms=0 | '
      'company_remote_id=${_valueOrNotAvailable(this.companyRemoteId)} | '
      'tenant_key=${_valueOrNotAvailable(this.tenantIsolationKey)} | '
      'user_remote_id=${_valueOrNotAvailable(userRemoteId)}',
    );
  }

  void logStepCompleted(
    String step,
    Stopwatch stopwatch, {
    String? companyRemoteId,
    String? tenantIsolationKey,
    String? userRemoteId,
  }) {
    pendingStep = null;
    lastCompletedStep = step;
    this.companyRemoteId = companyRemoteId?.trim() ?? this.companyRemoteId;
    this.tenantIsolationKey = tenantIsolationKey ?? this.tenantIsolationKey;

    AppLogger.info(
      '$step | duration_ms=${stopwatch.elapsedMilliseconds} | '
      'company_remote_id=${_valueOrNotAvailable(this.companyRemoteId)} | '
      'tenant_key=${_valueOrNotAvailable(this.tenantIsolationKey)} | '
      'user_remote_id=${_valueOrNotAvailable(userRemoteId)}',
    );
  }

  void logStepFailure(
    String step,
    Stopwatch stopwatch, {
    required Object error,
    StackTrace? stackTrace,
    String? reason,
  }) {
    AppLogger.error(
      'bootstrap_failed | step=$step | duration_ms=${stopwatch.elapsedMilliseconds} | '
      'company_remote_id=${_valueOrNotAvailable(companyRemoteId)} | '
      'tenant_key=${_valueOrNotAvailable(tenantIsolationKey)} | '
      'last_completed_step=${_valueOrNotAvailable(lastCompletedStep)} | '
      'pending_step=${_valueOrNotAvailable(pendingStep)} | '
      'reason=${reason ?? error.toString()}',
      error: error,
      stackTrace: stackTrace,
    );
  }

  String buildDebugDetails({String? reason}) {
    final parts = <String>[
      if (reason != null && reason.trim().isNotEmpty) reason.trim(),
      'last_completed=${lastCompletedStep ?? 'n/a'}',
      'pending=${pendingStep ?? 'n/a'}',
      'company_remote_id=${companyRemoteId ?? 'n/a'}',
      'tenant_key=${tenantIsolationKey ?? 'n/a'}',
    ];
    return parts.join(' | ');
  }

  String _valueOrNotAvailable(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return 'n/a';
    }
    return trimmed;
  }
}

final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final isolationKey = ref.watch(sessionIsolationKeyProvider);
  final database = AppDatabase.forIsolationKey(isolationKey);
  ref.onDispose(() {
    unawaited(database.close());
  });
  return database;
});

final appStartupTimeoutProvider = Provider<Duration>((ref) {
  return const Duration(seconds: 90);
});

final appStartupApiStepTimeoutProvider = Provider<Duration>((ref) {
  return const Duration(seconds: 8);
});

final appStartupLocalDatabaseTimeoutProvider = Provider<Duration>((ref) {
  return const Duration(seconds: 20);
});

final appStartupRemotePreflightProvider = Provider<AppStartupRemotePreflight>((
  ref,
) {
  return (session) async {};
});

final appStartupOpenDatabaseProvider = Provider<AppStartupOpenDatabase>((ref) {
  final inFlight = <String, Future<void>>{};
  return (isolationKey) async {
    final existing = inFlight[isolationKey];
    if (existing != null) {
      AppLogger.info(
        'tenant_database_open_joined | tenant_key=$isolationKey | '
        'database_name=${AppDatabase.databaseNameForIsolationKey(isolationKey)}',
      );
      return existing;
    }

    final future = AppDatabase.openForIsolationKey(isolationKey);
    inFlight[isolationKey] = future;
    try {
      await future;
    } finally {
      inFlight.remove(isolationKey);
    }
  };
});

final appStartupProvider = FutureProvider<AppStartupState>((ref) async {
  final session = ref.watch(appSessionProvider);
  final environment = ref.watch(appEnvironmentProvider);
  final timeout = ref.watch(appStartupTimeoutProvider);
  final apiStepTimeout = ref.watch(appStartupApiStepTimeoutProvider);
  final localDatabaseTimeout = ref.watch(
    appStartupLocalDatabaseTimeoutProvider,
  );
  final remotePreflight = ref.watch(appStartupRemotePreflightProvider);
  final openDatabase = ref.watch(appStartupOpenDatabaseProvider);
  final appDataRefreshKey = ref.read(appDataRefreshProvider);
  final sessionRuntimeKey = _safeSessionRuntimeKey(session);
  final trace = _AppStartupTrace();

  try {
    return await _runAppStartup(
      session: session,
      environment: environment,
      remotePreflight: remotePreflight,
      openDatabase: openDatabase,
      apiStepTimeout: apiStepTimeout,
      localDatabaseTimeout: localDatabaseTimeout,
      appDataRefreshKey: appDataRefreshKey,
      sessionRuntimeKey: sessionRuntimeKey,
      trace: trace,
    ).timeout(
      timeout,
      onTimeout: () {
        final state = AppStartupState.timeout(
          debugDetails: trace.buildDebugDetails(
            reason: 'bootstrap_timeout_after_${timeout.inSeconds}_seconds',
          ),
          lastCompletedStep: trace.lastCompletedStep,
          pendingStep: trace.pendingStep,
        );
        _logBootstrapFailure(state);
        return state;
      },
    );
  } catch (error, stackTrace) {
    final state = AppStartupState.unknownError(
      debugDetails: trace.buildDebugDetails(reason: error.toString()),
      lastCompletedStep: trace.lastCompletedStep,
      pendingStep: trace.pendingStep,
    );
    _logBootstrapFailure(state, error: error, stackTrace: stackTrace);
    return state;
  }
});

Future<AppStartupState> _runAppStartup({
  required AppSession session,
  required AppEnvironment environment,
  required AppStartupRemotePreflight remotePreflight,
  required AppStartupOpenDatabase openDatabase,
  required Duration apiStepTimeout,
  required Duration localDatabaseTimeout,
  required int appDataRefreshKey,
  required String sessionRuntimeKey,
  required _AppStartupTrace trace,
}) async {
  trace.logBootstrapStarted(
    session: session,
    environment: environment,
    sessionRuntimeKey: sessionRuntimeKey,
    appDataRefreshKey: appDataRefreshKey,
  );
  _runSynchronousBootstrapStep(
    trace: trace,
    startedEvent: 'auth_session_load_started',
    completedEvent: 'auth_session_loaded',
    companyRemoteId: session.company.remoteId,
    userRemoteId: session.user.remoteId,
    action: () {},
  );

  if (session.isRemoteAuthenticated) {
    final remoteValidation = _validateRemoteSession(session, trace);
    if (remoteValidation != null) {
      _logBootstrapFailure(remoteValidation);
      return remoteValidation;
    }
  }

  final isolationKey = _resolveTenantIsolationKey(session, trace);
  if (isolationKey == null) {
    final state = AppStartupState.needsCompany(
      message:
          'Sua conta entrou, mas a empresa ativa nao retornou um tenant valido.',
      debugDetails: trace.buildDebugDetails(
        reason: 'tenant_key_resolve_failed',
      ),
      lastCompletedStep: trace.lastCompletedStep,
      pendingStep: trace.pendingStep,
    );
    _logBootstrapFailure(state);
    return state;
  }

  try {
    await remotePreflight(session).timeout(apiStepTimeout);
  } on AuthenticationException catch (error, stackTrace) {
    final state = AppStartupState.apiError(
      message:
          'Nao foi possivel validar sua sessao remota agora. Entre novamente para continuar.',
      debugDetails: trace.buildDebugDetails(reason: error.toString()),
      lastCompletedStep: trace.lastCompletedStep,
      pendingStep: trace.pendingStep,
    );
    _logBootstrapFailure(state, error: error, stackTrace: stackTrace);
    return state;
  } on NetworkRequestException catch (error, stackTrace) {
    final state = AppStartupState.apiError(
      message:
          'Nao foi possivel falar com a API do Tatuzin agora. Tente novamente em instantes.',
      debugDetails: trace.buildDebugDetails(reason: error.toString()),
      lastCompletedStep: trace.lastCompletedStep,
      pendingStep: trace.pendingStep,
    );
    _logBootstrapFailure(state, error: error, stackTrace: stackTrace);
    return state;
  } on TimeoutException catch (error, stackTrace) {
    final state = AppStartupState.apiError(
      message:
          'A API do Tatuzin demorou demais para concluir a validacao inicial. Tente novamente em instantes.',
      debugDetails: trace.buildDebugDetails(reason: 'api_preflight_timeout'),
      lastCompletedStep: trace.lastCompletedStep,
      pendingStep: trace.pendingStep,
    );
    _logBootstrapFailure(state, error: error, stackTrace: stackTrace);
    return state;
  }

  if (session.isAuthenticated) {
    final databaseState = await _openTenantDatabase(
      session: session,
      isolationKey: isolationKey,
      openDatabase: openDatabase,
      timeout: localDatabaseTimeout,
      trace: trace,
    );
    if (databaseState != null) {
      _logBootstrapFailure(databaseState);
      return databaseState;
    }
  }

  final navigationStopwatch = Stopwatch()..start();
  trace.logStepCompleted(
    'navigation_shell_ready',
    navigationStopwatch,
    companyRemoteId: session.company.remoteId,
    tenantIsolationKey: isolationKey,
    userRemoteId: session.user.remoteId,
  );
  return AppStartupState.success(
    debugDetails: trace.buildDebugDetails(
      reason: 'shell_ready_without_global_database_open',
    ),
    lastCompletedStep: trace.lastCompletedStep,
    pendingStep: trace.pendingStep,
  );
}

Future<AppStartupState?> _openTenantDatabase({
  required AppSession session,
  required String isolationKey,
  required AppStartupOpenDatabase openDatabase,
  required Duration timeout,
  required _AppStartupTrace trace,
}) async {
  final stopwatch = Stopwatch()..start();
  trace.logStepStarted(
    'tenant_database_open_started',
    companyRemoteId: session.company.remoteId,
    tenantIsolationKey: isolationKey,
    userRemoteId: session.user.remoteId,
  );

  try {
    AppLogger.info(
      'tenant_database_open_requested | tenant_key=$isolationKey | '
      'database_name=${AppDatabase.databaseNameForIsolationKey(isolationKey)} | '
      'slow_warning_seconds=${timeout.inSeconds}',
    );
    await _awaitWithSlowWarning(
      openDatabase(isolationKey),
      timeout,
      () => AppLogger.warn(
        '[DB] tenant_database_open_slow_warning | tenant_key=$isolationKey | '
        'database_name=${AppDatabase.databaseNameForIsolationKey(isolationKey)} | '
        'elapsed_seconds=${timeout.inSeconds}',
      ),
    );
    trace.logStepCompleted(
      'tenant_database_opened',
      stopwatch,
      companyRemoteId: session.company.remoteId,
      tenantIsolationKey: isolationKey,
      userRemoteId: session.user.remoteId,
    );
    return null;
  } catch (error, stackTrace) {
    trace.logStepFailure(
      'tenant_database_open_started',
      stopwatch,
      error: error,
      stackTrace: stackTrace,
      reason: 'tenant_database_open_failed',
    );
    AppLogger.error(
      '[DB] tenant_database_open_failed | tenant_key=$isolationKey | '
      'database_name=${AppDatabase.databaseNameForIsolationKey(isolationKey)}',
      error: error,
      stackTrace: stackTrace,
    );
    return AppStartupState.localDatabaseError(
      debugDetails: trace.buildDebugDetails(
        reason:
            'tenant_database_open_failed | database_name=${AppDatabase.databaseNameForIsolationKey(isolationKey)}',
      ),
      lastCompletedStep: trace.lastCompletedStep,
      pendingStep: trace.pendingStep,
    );
  }
}

Future<T> _awaitWithSlowWarning<T>(
  Future<T> future,
  Duration warningAfter,
  void Function() onSlow,
) {
  var completed = false;
  Timer? timer;
  if (warningAfter > Duration.zero) {
    timer = Timer(warningAfter, () {
      if (!completed) {
        onSlow();
      }
    });
  }

  return future.whenComplete(() {
    completed = true;
    timer?.cancel();
  });
}

AppStartupState? _validateRemoteSession(
  AppSession session,
  _AppStartupTrace trace,
) {
  final user = session.user;
  final company = session.company;

  try {
    _runSynchronousBootstrapStep(
      trace: trace,
      startedEvent: 'current_user_load_started',
      completedEvent: 'current_user_loaded',
      companyRemoteId: company.remoteId,
      userRemoteId: user.remoteId,
      action: () {
        if (!user.hasRemoteIdentity) {
          throw const AuthenticationException(
            'remote_authenticated_session_without_user_remote_id',
          );
        }
      },
    );
  } on AuthenticationException {
    return AppStartupState.apiError(
      message:
          'Sua sessao foi autenticada, mas os dados do usuario retornaram incompletos.',
      debugDetails: trace.buildDebugDetails(
        reason: 'remote_authenticated_session_without_user_remote_id',
      ),
      lastCompletedStep: trace.lastCompletedStep,
      pendingStep: trace.pendingStep,
    );
  }

  try {
    _runSynchronousBootstrapStep(
      trace: trace,
      startedEvent: 'companies_current_load_started',
      completedEvent: 'companies_current_loaded',
      companyRemoteId: company.remoteId,
      userRemoteId: user.remoteId,
      action: () {
        if (!company.hasRemoteIdentity) {
          throw const ValidationException(
            'remote_authenticated_session_without_company_remote_id',
          );
        }
      },
    );
  } on ValidationException {
    return AppStartupState.needsCompany(
      message:
          'Sua conta entrou, mas nenhuma empresa ativa valida foi retornada pela API.',
      debugDetails: trace.buildDebugDetails(
        reason: 'remote_authenticated_session_without_company_remote_id',
      ),
      lastCompletedStep: trace.lastCompletedStep,
      pendingStep: trace.pendingStep,
    );
  }

  _runSynchronousBootstrapStep(
    trace: trace,
    startedEvent: 'active_company_select_started',
    completedEvent: 'active_company_selected',
    companyRemoteId: company.remoteId,
    userRemoteId: user.remoteId,
    action: () {},
  );

  final licenseValidation = _validateCompanyLicense(company, trace);
  if (licenseValidation != null) {
    return licenseValidation;
  }

  return null;
}

AppStartupState? _validateCompanyLicense(
  CompanyContext company,
  _AppStartupTrace trace,
) {
  try {
    _runSynchronousBootstrapStep(
      trace: trace,
      startedEvent: 'license_validation_started',
      completedEvent: 'license_validated',
      companyRemoteId: company.remoteId,
      action: () {
        if (company.isTrialLicense || company.isActiveLicense) {
          return;
        }
        if (company.isSuspendedLicense) {
          throw const ValidationException('license_status=suspended');
        }
        if (company.isExpiredLicense) {
          throw const ValidationException('license_status=expired');
        }
        throw ValidationException(
          'license_status=${company.licenseStatus ?? 'missing'}',
        );
      },
    );
    return null;
  } on ValidationException catch (error) {
    final reason = error.message;
    if (reason == 'license_status=suspended') {
      return AppStartupState.blockedLicense(
        message:
            'A licenca desta empresa esta suspensa. Revise a conta no Tatuzin Cloud antes de continuar.',
        debugDetails: trace.buildDebugDetails(reason: reason),
        lastCompletedStep: trace.lastCompletedStep,
        pendingStep: trace.pendingStep,
      );
    }

    if (reason == 'license_status=expired') {
      return AppStartupState.blockedLicense(
        message:
            'A licenca desta empresa expirou. Revise a conta no Tatuzin Cloud antes de continuar.',
        debugDetails: trace.buildDebugDetails(reason: reason),
        lastCompletedStep: trace.lastCompletedStep,
        pendingStep: trace.pendingStep,
      );
    }

    return AppStartupState.blockedLicense(
      message:
          'A empresa retornou sem uma licenca valida para abrir o ambiente remoto com seguranca.',
      debugDetails: trace.buildDebugDetails(reason: reason),
      lastCompletedStep: trace.lastCompletedStep,
      pendingStep: trace.pendingStep,
    );
  }
}

String? _resolveTenantIsolationKey(AppSession session, _AppStartupTrace trace) {
  trace.logStepStarted(
    'tenant_key_resolve_started',
    companyRemoteId: session.company.remoteId,
    userRemoteId: session.user.remoteId,
  );
  final stopwatch = Stopwatch()..start();
  try {
    final isolationKey = SessionIsolation.keyFor(session);
    trace.logStepCompleted(
      'tenant_key_resolved',
      stopwatch,
      companyRemoteId: session.company.remoteId,
      tenantIsolationKey: isolationKey,
      userRemoteId: session.user.remoteId,
    );
    return isolationKey;
  } catch (error, stackTrace) {
    trace.logStepFailure(
      'tenant_key_resolve_started',
      stopwatch,
      error: error,
      stackTrace: stackTrace,
      reason: 'tenant_key_resolve_failed',
    );
    AppLogger.error(
      'tenant_key_resolve_failed | company_remote_id=${session.company.remoteId ?? 'n/a'}',
      error: error,
      stackTrace: stackTrace,
    );
    return null;
  }
}

void _logBootstrapFailure(
  AppStartupState state, {
  Object? error,
  StackTrace? stackTrace,
}) {
  AppLogger.error(
    'bootstrap_failed | reason=${state.status.name} | '
    'last_completed_step=${state.lastCompletedStep ?? 'n/a'} | '
    'pending_step=${state.pendingStep ?? 'n/a'} | '
    'message=${state.message} | debug=${state.debugDetails ?? 'n/a'}',
    error: error,
    stackTrace: stackTrace,
  );
}

String _safeSessionRuntimeKey(AppSession session) {
  try {
    return SessionIsolation.runtimeKeyFor(session);
  } catch (_) {
    return 'invalid_session_runtime_key';
  }
}

void _runSynchronousBootstrapStep({
  required _AppStartupTrace trace,
  required String startedEvent,
  required String completedEvent,
  required void Function() action,
  String? companyRemoteId,
  String? tenantIsolationKey,
  String? userRemoteId,
}) {
  trace.logStepStarted(
    startedEvent,
    companyRemoteId: companyRemoteId,
    tenantIsolationKey: tenantIsolationKey,
    userRemoteId: userRemoteId,
  );
  final stopwatch = Stopwatch()..start();
  try {
    action();
    trace.logStepCompleted(
      completedEvent,
      stopwatch,
      companyRemoteId: companyRemoteId,
      tenantIsolationKey: tenantIsolationKey,
      userRemoteId: userRemoteId,
    );
  } catch (error, stackTrace) {
    trace.logStepFailure(
      startedEvent,
      stopwatch,
      error: error,
      stackTrace: stackTrace,
    );
    rethrow;
  }
}

enum AppStartupStatus {
  loading,
  success,
  needsCompany,
  blockedLicense,
  localDatabaseError,
  apiError,
  timeout,
  unknownError,
}

class AppStartupState {
  const AppStartupState._({
    required this.status,
    required this.title,
    required this.message,
    this.debugDetails,
    this.lastCompletedStep,
    this.pendingStep,
  });

  const AppStartupState.success({
    String? debugDetails,
    String? lastCompletedStep,
    String? pendingStep,
  }) : this._(
         status: AppStartupStatus.success,
         title: 'Tatuzin pronto',
         message: 'O ambiente local foi preparado com seguranca.',
         debugDetails: debugDetails,
         lastCompletedStep: lastCompletedStep,
         pendingStep: pendingStep,
       );

  factory AppStartupState.needsCompany({
    required String message,
    String? debugDetails,
    String? lastCompletedStep,
    String? pendingStep,
  }) {
    return AppStartupState._(
      status: AppStartupStatus.needsCompany,
      title: 'Empresa ativa pendente',
      message: message,
      debugDetails: debugDetails,
      lastCompletedStep: lastCompletedStep,
      pendingStep: pendingStep,
    );
  }

  factory AppStartupState.blockedLicense({
    required String message,
    String? debugDetails,
    String? lastCompletedStep,
    String? pendingStep,
  }) {
    return AppStartupState._(
      status: AppStartupStatus.blockedLicense,
      title: 'Licenca precisa de atencao',
      message: message,
      debugDetails: debugDetails,
      lastCompletedStep: lastCompletedStep,
      pendingStep: pendingStep,
    );
  }

  factory AppStartupState.localDatabaseError({
    String? message,
    String? debugDetails,
    String? lastCompletedStep,
    String? pendingStep,
  }) {
    return AppStartupState._(
      status: AppStartupStatus.localDatabaseError,
      title: 'Falha ao abrir a base local',
      message:
          message ??
          'Nao foi possivel preparar o banco local desta empresa. Tente novamente ou saia da conta para reiniciar a sessao.',
      debugDetails: debugDetails,
      lastCompletedStep: lastCompletedStep,
      pendingStep: pendingStep,
    );
  }

  factory AppStartupState.apiError({
    required String message,
    String? debugDetails,
    String? lastCompletedStep,
    String? pendingStep,
  }) {
    return AppStartupState._(
      status: AppStartupStatus.apiError,
      title: 'Falha ao validar a conta',
      message: message,
      debugDetails: debugDetails,
      lastCompletedStep: lastCompletedStep,
      pendingStep: pendingStep,
    );
  }

  factory AppStartupState.timeout({
    String? debugDetails,
    String? lastCompletedStep,
    String? pendingStep,
  }) {
    final waitingForDatabase = pendingStep == 'tenant_database_open_started';
    return AppStartupState._(
      status: AppStartupStatus.timeout,
      title: waitingForDatabase
          ? 'O banco local demorou demais para abrir'
          : 'O preparo demorou mais do que o esperado',
      message: waitingForDatabase
          ? 'O banco local desta empresa demorou demais para abrir. Seus dados serao preservados. Tente novamente ou saia da conta.'
          : 'O Tatuzin nao conseguiu concluir a preparacao inicial a tempo. Tente novamente ou saia da conta para reiniciar a sessao.',
      debugDetails: debugDetails,
      lastCompletedStep: lastCompletedStep,
      pendingStep: pendingStep,
    );
  }

  factory AppStartupState.unknownError({
    String? debugDetails,
    String? lastCompletedStep,
    String? pendingStep,
  }) {
    return AppStartupState._(
      status: AppStartupStatus.unknownError,
      title: 'Falha inesperada ao preparar o Tatuzin',
      message:
          'Nao foi possivel concluir a preparacao inicial com seguranca. Tente novamente ou saia da conta.',
      debugDetails: debugDetails,
      lastCompletedStep: lastCompletedStep,
      pendingStep: pendingStep,
    );
  }

  final AppStartupStatus status;
  final String title;
  final String message;
  final String? debugDetails;
  final String? lastCompletedStep;
  final String? pendingStep;

  bool get isSuccess => status == AppStartupStatus.success;
}

class _DbOpenTrace {
  _DbOpenTrace({required this.databaseName, required this.databasePath});

  static const _watchdogInterval = Duration(seconds: 10);

  final String databaseName;
  final String databasePath;
  String _lastStage = 'created';
  Timer? _watchdog;

  void startWatchdog() {
    _watchdog?.cancel();
    _watchdog = Timer.periodic(_watchdogInterval, (_) {
      AppLogger.warn(
        '[DB_OPEN_TRACE] still_waiting last_stage=$_lastStage | '
        'database_name=$databaseName',
      );
    });
  }

  void mark(String stage, {String? details}) {
    _lastStage = stage;
    final buffer = StringBuffer('[DB_OPEN_TRACE] $stage');
    if (details != null && details.trim().isNotEmpty) {
      buffer.write(' ${details.trim()}');
    }
    buffer.write(' | database_name=$databaseName');
    AppLogger.info(buffer.toString());
  }

  void logFileState() {
    AppLogger.info(_buildFileStateMessage());
  }

  void logNonDestructiveDiagnostic() {
    AppLogger.warn(_buildFileStateMessage());
    AppLogger.warn(
      '[DB_OPEN_TRACE] diagnostic_skipped reason=primary_open_pending | '
      'database_name=$databaseName | last_stage=$_lastStage',
    );
  }

  void dispose() {
    _watchdog?.cancel();
    _watchdog = null;
  }

  String _buildFileStateMessage() {
    final database = _fileState(databasePath);
    final wal = _fileState('$databasePath-wal');
    final shm = _fileState('$databasePath-shm');
    return '[DB_OPEN_TRACE] file_state | database_name=$databaseName | '
        'exists=${database.exists} db_bytes=${database.bytes} '
        'wal_exists=${wal.exists} wal_bytes=${wal.bytes} '
        'shm_exists=${shm.exists} shm_bytes=${shm.bytes}';
  }

  static _FileState _fileState(String path) {
    try {
      final file = File(path);
      if (!file.existsSync()) {
        return const _FileState(exists: false, bytes: 0);
      }
      return _FileState(exists: true, bytes: file.lengthSync());
    } catch (error) {
      AppLogger.warn('[DB_OPEN_TRACE] file_state_unavailable error=$error');
      return const _FileState(exists: false, bytes: 0);
    }
  }
}

class _FileState {
  const _FileState({required this.exists, required this.bytes});

  final bool exists;
  final int bytes;
}

class AppDatabase {
  AppDatabase._({required String databaseName}) : _databaseName = databaseName;

  static const _databasePathTimeout = Duration(seconds: 5);
  static const _databaseOpenTimeout = Duration(seconds: 20);
  static const _pragmaTimeout = Duration(seconds: 5);
  static const _migrationTimeout = Duration(seconds: 20);
  static const _verificationTimeout = Duration(seconds: 5);
  static final Map<String, AppDatabase> _instances = <String, AppDatabase>{};

  factory AppDatabase.forIsolationKey(String isolationKey) {
    final databaseName = databaseNameForIsolationKey(isolationKey);
    return _instances.putIfAbsent(
      databaseName,
      () => AppDatabase._(databaseName: databaseName),
    );
  }

  static final AppDatabase instance = AppDatabase.forIsolationKey(
    SessionIsolation.localKey,
  );

  static Future<void> openForIsolationKey(String isolationKey) async {
    await AppDatabase.forIsolationKey(isolationKey).database;
  }

  static Future<void> closeForIsolationKey(String isolationKey) async {
    final databaseName = databaseNameForIsolationKey(isolationKey);
    final cached = _instances[databaseName];
    if (cached == null) {
      return;
    }
    await cached.close();
  }

  static String databaseNameForIsolationKey(String isolationKey) {
    if (isolationKey == SessionIsolation.localKey) {
      return AppConstants.databaseName;
    }

    final baseName = path.basenameWithoutExtension(AppConstants.databaseName);
    final extension = path.extension(AppConstants.databaseName);
    final sanitized = _sanitizeIsolationKey(isolationKey);
    return '${baseName}_$sanitized$extension';
  }

  static Future<void> deleteDatabaseForIsolationKeyForTesting(
    String isolationKey,
  ) async {
    final databasesPath = await getDatabasesPath().timeout(
      _databasePathTimeout,
    );
    final databasePath = path.join(
      databasesPath,
      databaseNameForIsolationKey(isolationKey),
    );
    final cached = _instances.remove(databaseNameForIsolationKey(isolationKey));
    await cached?.close();
    await databaseFactory.deleteDatabase(databasePath);
  }

  final String _databaseName;
  Database? _database;
  Future<Database>? _openingDatabase;

  Future<Database> get database async {
    if (_database != null) {
      return _database!;
    }

    final openingDatabase = _openingDatabase;
    if (openingDatabase != null) {
      return openingDatabase;
    }

    final future = _openDatabase();
    _openingDatabase = future;
    try {
      final database = await future;
      if (identical(_openingDatabase, future)) {
        _openingDatabase = null;
      }
      return database;
    } finally {
      if (identical(_openingDatabase, future) && _database == null) {
        _openingDatabase = null;
      }
    }
  }

  Future<Database> _openDatabase() async {
    final openStopwatch = Stopwatch()..start();
    _DbOpenTrace? trace;
    try {
      AppLogger.info('[DB] open_path_started | database_name=$_databaseName');
      final databasesPath = await getDatabasesPath().timeout(
        _databasePathTimeout,
        onTimeout: () => throw TimeoutException('getDatabasesPath_timeout'),
      );
      final databasePath = path.join(databasesPath, _databaseName);
      AppLogger.info(
        '[DB] open_path_finished | database_name=$_databaseName | '
        'duration_ms=${openStopwatch.elapsedMilliseconds}',
      );
      trace = _DbOpenTrace(
        databaseName: _databaseName,
        databasePath: databasePath,
      )..startWatchdog();
      trace.logFileState();

      AppLogger.info('Opening database at $databasePath');
      AppLogger.info('Database bootstrap started');
      AppLogger.info('[DB] open_started | database_name=$_databaseName');
      trace.mark('before_open_database');

      _database = await _awaitWithSlowWarning(
        openDatabase(
          databasePath,
          version: AppConstants.databaseVersion,
          onConfigure: (db) async {
            trace?.mark('on_configure_started');
            AppLogger.info(
              '[DB] open_configure_started | database_name=$_databaseName',
            );
            await _runBootstrapStep(
              'onConfigure > PRAGMA foreign_keys = ON',
              () => _enableForeignKeys(db),
              timeout: _pragmaTimeout,
            );
            await _runBootstrapStep(
              'onConfigure > PRAGMA journal_mode = WAL',
              () => _configureJournalMode(db),
              timeout: _pragmaTimeout,
            );
            AppLogger.info(
              '[DB] open_configure_finished | database_name=$_databaseName',
            );
            trace?.mark('on_configure_finished');
          },
          onCreate: (db, version) async {
            trace?.mark('on_create_started');
            AppLogger.info(
              '[DB] open_create_started | database_name=$_databaseName | '
              'version=$version',
            );
            await _runBootstrapStep(
              'onCreate > schema version $version',
              () async {
                AppLogger.info('Creating database schema version $version');
                await db.transaction((txn) async {
                  await AppMigrations.runCreate(txn, version);
                });
              },
              timeout: _migrationTimeout,
            );
            AppLogger.info(
              '[DB] open_create_finished | database_name=$_databaseName | '
              'version=$version',
            );
            trace?.mark('on_create_finished');
          },
          onUpgrade: (db, oldVersion, newVersion) async {
            trace?.mark(
              'on_upgrade_started',
              details: 'old=$oldVersion new=$newVersion',
            );
            AppLogger.info(
              '[DB] open_migration_started | database_name=$_databaseName | '
              'from=$oldVersion | to=$newVersion',
            );
            await _runBootstrapStep(
              'onUpgrade > schema v$oldVersion to v$newVersion',
              () async {
                AppLogger.info(
                  'Upgrading database from v$oldVersion to v$newVersion',
                );
                await db.transaction((txn) async {
                  await AppMigrations.runUpgrade(txn, oldVersion, newVersion);
                });
              },
              timeout: _migrationTimeout,
            );
            AppLogger.info(
              '[DB] open_migration_finished | database_name=$_databaseName | '
              'from=$oldVersion | to=$newVersion',
            );
            trace?.mark('on_upgrade_finished');
          },
          onOpen: (db) async {
            trace?.mark('on_open_started');
            AppLogger.info(
              '[DB] open_on_open_started | database_name=$_databaseName',
            );
            await _runBootstrapStep('onOpen > final verification', () async {
              AppLogger.info('Database opened successfully');
              final foreignKeyResult = await db.rawQuery('PRAGMA foreign_keys');
              final foreignKeysEnabled = _readPragmaValue(foreignKeyResult);
              AppLogger.info(
                'PRAGMA foreign_keys verification returned $foreignKeysEnabled',
              );
              if (foreignKeysEnabled != '1') {
                throw StateError(
                  'foreign_keys remained disabled after opening the database '
                  '(result=$foreignKeysEnabled)',
                );
              }
            }, timeout: _verificationTimeout);
            AppLogger.info(
              '[DB] open_on_open_finished | database_name=$_databaseName',
            );
            trace?.mark('on_open_finished');
          },
        ),
        _databaseOpenTimeout,
        () {
          AppLogger.warn(
            '[DB] open_slow_warning | database_name=$_databaseName | '
            'elapsed_seconds=${_databaseOpenTimeout.inSeconds}',
          );
          trace?.logNonDestructiveDiagnostic();
        },
      );

      trace.mark('after_open_database');
      trace.mark('post_bootstrap_started');
      trace.mark('post_bootstrap_finished');
      AppLogger.info(
        '[DB] open_finished | database_name=$_databaseName | '
        'duration_ms=${openStopwatch.elapsedMilliseconds}',
      );

      return _database!;
    } catch (error, stackTrace) {
      _database = null;
      _instances.remove(_databaseName);

      if (error is DatabaseInitializationException) {
        AppLogger.error(
          'Database initialization aborted during bootstrap',
          error: error,
          stackTrace: stackTrace,
        );
        rethrow;
      }

      AppLogger.error(
        'Database initialization failed',
        error: error,
        stackTrace: stackTrace,
      );
      throw DatabaseInitializationException(
        'Nao foi possivel inicializar o banco de dados local',
        cause: error,
      );
    } finally {
      trace?.dispose();
    }
  }

  Future<void> close() async {
    final openingDatabase = _openingDatabase;
    if (_database == null && openingDatabase != null) {
      AppLogger.warn(
        '[DB] database_close_deferred_opening | database_name=$_databaseName',
      );
      return;
    }

    if (_database == null) {
      return;
    }

    await _database!.close();
    _instances.remove(_databaseName);
    _database = null;
    _openingDatabase = null;
    AppLogger.info('Database connection closed');
  }

  Future<void> _enableForeignKeys(Database db) async {
    AppLogger.info('Executing PRAGMA foreign_keys = ON with execute()');
    await db.execute('PRAGMA foreign_keys = ON');

    final result = await db.rawQuery('PRAGMA foreign_keys');
    final value = _readPragmaValue(result);

    AppLogger.info('PRAGMA foreign_keys returned $value');

    if (value != '1') {
      throw StateError(
        'PRAGMA foreign_keys verification failed with result=$value',
      );
    }
  }

  Future<void> _configureJournalMode(Database db) async {
    AppLogger.info('Executing PRAGMA journal_mode = WAL with rawQuery()');

    try {
      final walResult = await db.rawQuery('PRAGMA journal_mode = WAL');
      final walMode = _readPragmaValue(walResult);

      AppLogger.info('PRAGMA journal_mode = WAL returned $walMode');

      if (walMode == null || walMode.isEmpty) {
        throw StateError('PRAGMA journal_mode = WAL returned no result');
      }
    } catch (error, stackTrace) {
      AppLogger.warn(
        'PRAGMA journal_mode = WAL failed; attempting DELETE fallback | '
        'error=$error',
      );
      AppLogger.error(
        'WAL journal mode could not be enabled',
        error: error,
        stackTrace: stackTrace,
      );

      final fallbackResult = await db.rawQuery('PRAGMA journal_mode = DELETE');
      final fallbackMode = _readPragmaValue(fallbackResult);

      AppLogger.warn('PRAGMA journal_mode fallback returned $fallbackMode');

      if (fallbackMode == null || fallbackMode.isEmpty) {
        throw StateError(
          'PRAGMA journal_mode fallback to DELETE returned no result',
        );
      }
    }
  }

  Future<void> _runBootstrapStep(
    String step,
    Future<void> Function() action, {
    Duration? timeout,
  }) async {
    final stopwatch = Stopwatch()..start();
    AppLogger.info('Database bootstrap step started: $step | duration_ms=0');

    try {
      await action().timeout(
        timeout ?? _migrationTimeout,
        onTimeout: () => throw TimeoutException('database_step_timeout:$step'),
      );
      AppLogger.info(
        'Database bootstrap step completed: $step | duration_ms=${stopwatch.elapsedMilliseconds}',
      );
    } catch (error, stackTrace) {
      AppLogger.error(
        'Database bootstrap step failed: $step | duration_ms=${stopwatch.elapsedMilliseconds}',
        error: error,
        stackTrace: stackTrace,
      );
      throw DatabaseInitializationException(
        'Nao foi possivel inicializar o banco de dados local na etapa: $step',
        cause: error,
      );
    }
  }

  String? _readPragmaValue(List<Map<String, Object?>> rows) {
    if (rows.isEmpty) {
      return null;
    }

    final firstRow = rows.first;
    if (firstRow.isEmpty) {
      return null;
    }

    return firstRow.values.first?.toString();
  }

  static String _sanitizeIsolationKey(String isolationKey) {
    final sanitized = isolationKey
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9._-]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');

    return sanitized.isEmpty ? SessionIsolation.localKey : sanitized;
  }
}

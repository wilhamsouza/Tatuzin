import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

import '../constants/app_constants.dart';
import '../errors/app_exceptions.dart';
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

  void logBootstrapStarted(AppSession session) {
    companyRemoteId = session.company.remoteId?.trim();
    AppLogger.info(
      'bootstrap_started | duration_ms=0 | scope=${session.scope.name} | '
      'authenticated=${session.isAuthenticated} | '
      'company_remote_id=${_valueOrNotAvailable(companyRemoteId)}',
    );
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
  return const Duration(seconds: 30);
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
  return (isolationKey) async {
    await AppDatabase.openForIsolationKey(isolationKey);
  };
});

final appStartupProvider = FutureProvider<AppStartupState>((ref) async {
  final session = ref.watch(appSessionProvider);
  final timeout = ref.watch(appStartupTimeoutProvider);
  final apiStepTimeout = ref.watch(appStartupApiStepTimeoutProvider);
  final remotePreflight = ref.watch(appStartupRemotePreflightProvider);
  final trace = _AppStartupTrace();

  try {
    return await _runAppStartup(
      session: session,
      remotePreflight: remotePreflight,
      apiStepTimeout: apiStepTimeout,
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
  required AppStartupRemotePreflight remotePreflight,
  required Duration apiStepTimeout,
  required _AppStartupTrace trace,
}) async {
  trace.logBootstrapStarted(session);
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
    return AppStartupState._(
      status: AppStartupStatus.timeout,
      title: 'O preparo demorou mais do que o esperado',
      message:
          'O Tatuzin nao conseguiu concluir a preparacao inicial a tempo. Tente novamente ou saia da conta para reiniciar a sessao.',
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
      return await future;
    } finally {
      if (identical(_openingDatabase, future)) {
        _openingDatabase = null;
      }
    }
  }

  Future<Database> _openDatabase() async {
    try {
      final databasesPath = await getDatabasesPath().timeout(
        _databasePathTimeout,
        onTimeout: () => throw TimeoutException('getDatabasesPath_timeout'),
      );
      final databasePath = path.join(databasesPath, _databaseName);

      AppLogger.info('Opening database at $databasePath');
      AppLogger.info('Database bootstrap started');

      _database =
          await openDatabase(
            databasePath,
            version: AppConstants.databaseVersion,
            onConfigure: (db) async {
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
            },
            onCreate: (db, version) async {
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
            },
            onUpgrade: (db, oldVersion, newVersion) async {
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
            },
            onOpen: (db) async {
              await _runBootstrapStep('onOpen > final verification', () async {
                AppLogger.info('Database opened successfully');
                final foreignKeyResult = await db.rawQuery(
                  'PRAGMA foreign_keys',
                );
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
            },
          ).timeout(
            _databaseOpenTimeout,
            onTimeout: () => throw TimeoutException('openDatabase_timeout'),
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
    }
  }

  Future<void> close() async {
    final openingDatabase = _openingDatabase;
    if (_database == null && openingDatabase != null) {
      try {
        final database = await openingDatabase;
        await database.close();
      } catch (_) {
        // Ignore close errors during disposal of an abandoned bootstrap.
      } finally {
        _instances.remove(_databaseName);
        _openingDatabase = null;
        _database = null;
      }
      AppLogger.info('Database connection closed');
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

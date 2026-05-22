import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/constants/app_constants.dart';
import 'core/database/app_database.dart';
import 'core/providers/app_data_refresh_provider.dart';
import 'core/session/auth_provider.dart';
import 'core/session/session_provider.dart';
import 'core/session/session_reset.dart';
import 'core/sync/auto_sync_coordinator.dart';
import 'core/sync/sync_providers.dart';
import 'core/utils/app_logger.dart';
import 'core/widgets/app_async_value_view.dart';
import 'routes/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/app_theme_mode_controller.dart';
import '../modules/billing/presentation/providers/billing_checkout_return.dart';
import '../modules/billing/presentation/providers/billing_providers.dart';
import '../modules/billing/presentation/widgets/pro_trial_offer_gate.dart';
import '../modules/dashboard/presentation/providers/dashboard_providers.dart';

class ErpPdvApp extends ConsumerStatefulWidget {
  const ErpPdvApp({super.key});

  @override
  ConsumerState<ErpPdvApp> createState() => _ErpPdvAppState();
}

class _ErpPdvAppState extends ConsumerState<ErpPdvApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ref.read(sessionContextResetProvider);
    ref.read(authControllerProvider);
    ref.read(autoSyncCoordinatorProvider);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(autoSyncCoordinatorProvider).onAppResumed();
      unawaited(_refreshBillingAfterCheckoutReturn());
    }
  }

  Future<void> _refreshBillingAfterCheckoutReturn() async {
    try {
      final shouldRefresh = await BillingCheckoutReturnStorage()
          .consumePending();
      if (!mounted || !shouldRefresh) {
        return;
      }

      AppLogger.info('[Billing] checkout_return_resume_refresh_started');
      await ref.read(billingControllerProvider.notifier).refreshStatus();
      if (!mounted) {
        return;
      }
      ref.read(appDataRefreshProvider.notifier).state++;
      ref.invalidate(operationalDashboardSnapshotProvider);
      AppLogger.info('[Billing] checkout_return_resume_refresh_finished');
    } catch (error, stackTrace) {
      AppLogger.error(
        '[Billing] checkout_return_resume_refresh_failed',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final startup = ref.watch(appStartupProvider);
    final themeMode = ref.watch(appMaterialThemeModeProvider);

    return startup.when(
      data: (startupState) {
        if (!startupState.isSuccess) {
          return MaterialApp(
            title: AppConstants.appName,
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light(),
            darkTheme: AppTheme.dark(),
            themeMode: themeMode,
            home: AppAsyncValueView.error(
              title: startupState.title,
              message: startupState.message,
              actionLabel: 'Tentar novamente',
              onAction: () => unawaited(_retryStartup()),
              secondaryActionLabel: 'Sair da conta',
              onSecondaryAction: _signOutFromBootstrapError,
              detailsMessage: kDebugMode
                  ? _buildStartupDebugDetails(startupState)
                  : null,
            ),
          );
        }

        final router = ref.watch(appRouterProvider);

        return MaterialApp.router(
          title: AppConstants.appName,
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: themeMode,
          routerConfig: router,
          builder: (context, child) =>
              ProTrialOfferGate(child: child ?? const SizedBox.shrink()),
        );
      },
      loading: () => MaterialApp(
        title: AppConstants.appName,
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: themeMode,
        home: const AppAsyncValueView.loading(
          title: 'Preparando o Tatuzin',
          message:
              'Inicializando o app e verificando a base local com seguranca.',
        ),
      ),
      error: (error, stackTrace) => MaterialApp(
        title: AppConstants.appName,
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: themeMode,
        home: AppAsyncValueView.error(
          title: 'Falha ao iniciar o Tatuzin',
          message:
              'Nao foi possivel concluir a preparacao inicial com seguranca.',
          actionLabel: 'Tentar novamente',
          onAction: () => unawaited(_retryStartup()),
          secondaryActionLabel: 'Sair da conta',
          onSecondaryAction: _signOutFromBootstrapError,
          detailsMessage: kDebugMode ? error.toString() : null,
        ),
      ),
    );
  }

  Future<void> _retryStartup() async {
    final session = ref.read(appSessionProvider);
    String? isolationKey;
    try {
      isolationKey = SessionIsolation.keyFor(session);
    } catch (_) {
      isolationKey = null;
    }

    AppLogger.info(
      '[TenantBootstrap] retry_started | tenant_key=${isolationKey ?? 'n/a'}',
    );

    // Retrying must attach to an opening tenant database instead of closing it.
    // Closing during sqflite open can race with the bootstrap future and leave
    // the next startup waiting on a connection that is immediately disposed.
    ref.invalidate(appStartupProvider);
    AppLogger.info(
      '[TenantBootstrap] retry_finished | tenant_key=${isolationKey ?? 'n/a'}',
    );
  }

  Future<void> _signOutFromBootstrapError() async {
    final session = ref.read(appSessionProvider);
    String? isolationKey;
    try {
      isolationKey = SessionIsolation.keyFor(session);
    } catch (_) {
      isolationKey = null;
    }

    final autoSyncCoordinator = ref.read(autoSyncCoordinatorProvider);
    final syncBatchRunner = ref.read(syncBatchRunnerProvider);

    autoSyncCoordinator.cancelPending();
    ref.read(appSessionProvider.notifier).signOutToLocalMode();
    ref.invalidate(appStartupProvider);
    unawaited(
      _finishBootstrapSignOutCleanup(
        autoSyncCoordinator: autoSyncCoordinator,
        syncBatchRunner: syncBatchRunner,
        SessionSignOutResetSnapshot(
          pendingSyncCount: 0,
          hadActiveSync: false,
          tenantIsolationKey: isolationKey,
          databaseClosed: false,
        ),
      ),
    );
  }

  Future<void> _finishBootstrapSignOutCleanup(
    SessionSignOutResetSnapshot snapshot, {
    required AutoSyncCoordinator autoSyncCoordinator,
    required SyncBatchRunner syncBatchRunner,
  }) async {
    try {
      await autoSyncCoordinator.stopForSessionReset(
        timeout: const Duration(seconds: 1),
      );
      await syncBatchRunner.stopForSessionReset(
        timeout: const Duration(seconds: 1),
      );
    } catch (_) {
      autoSyncCoordinator.cancelPending();
    }

    await Future<void>.delayed(Duration.zero);
    await closeSessionDatabaseForReset(snapshot);
    if (mounted) {
      ref.invalidate(appDatabaseProvider);
    }
  }

  String _buildStartupDebugDetails(AppStartupState startupState) {
    final lines = <String>[
      'Bootstrap: ${startupState.status.name}',
      'Ultima etapa concluida: ${startupState.lastCompletedStep ?? 'nenhuma'}',
      'Parou em: ${startupState.pendingStep ?? 'nenhuma'}',
    ];

    final debugDetails = startupState.debugDetails?.trim();
    if (debugDetails != null && debugDetails.isNotEmpty) {
      lines.add(debugDetails);
    }

    return lines.join('\n');
  }
}

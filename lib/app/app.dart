import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/constants/app_constants.dart';
import 'core/database/app_database.dart';
import 'core/session/auth_provider.dart';
import 'core/session/session_reset.dart';
import 'core/sync/sync_providers.dart';
import 'core/widgets/app_async_value_view.dart';
import 'routes/app_router.dart';
import 'theme/app_theme.dart';

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
    }
  }

  @override
  Widget build(BuildContext context) {
    final startup = ref.watch(appStartupProvider);

    return startup.when(
      data: (_) {
        final router = ref.watch(appRouterProvider);

        return MaterialApp.router(
          title: AppConstants.appName,
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(),
          routerConfig: router,
        );
      },
      loading: () => MaterialApp(
        title: AppConstants.appName,
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
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
        home: AppAsyncValueView.error(
          title: 'Falha ao iniciar o Tatuzin',
          message: error.toString(),
          actionLabel: 'Tentar novamente',
          onAction: () => ref.invalidate(appStartupProvider),
        ),
      ),
    );
  }
}

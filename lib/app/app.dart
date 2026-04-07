import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/constants/app_constants.dart';
import 'core/database/app_database.dart';
import 'core/widgets/app_async_value_view.dart';
import 'routes/app_router.dart';
import 'theme/app_theme.dart';

class ErpPdvApp extends ConsumerWidget {
  const ErpPdvApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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

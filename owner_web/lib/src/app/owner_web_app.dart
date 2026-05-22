import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/owner_theme.dart';
import '../theme/owner_theme_controller.dart';
import 'owner_web_router.dart';

class OwnerWebApp extends ConsumerWidget {
  const OwnerWebApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(ownerRouterProvider);
    final themeMode = ref.watch(ownerMaterialThemeModeProvider);
    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      title: 'Tatuzin Owner',
      theme: OwnerTheme.light(),
      darkTheme: OwnerTheme.dark(),
      themeMode: themeMode,
      routerConfig: router,
    );
  }
}

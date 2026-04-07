import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'admin_web_router.dart';
import '../theme/admin_theme.dart';

class AdminWebApp extends ConsumerWidget {
  const AdminWebApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(adminRouterProvider);
    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      title: 'Tatuzin Admin',
      theme: AdminTheme.light(),
      routerConfig: router,
    );
  }
}

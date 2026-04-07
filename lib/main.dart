import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'app/core/config/app_environment.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final initialEnvironment = await AppEnvironmentStorage.load();

  runApp(
    ProviderScope(
      overrides: [
        initialAppEnvironmentProvider.overrideWith((ref) => initialEnvironment),
      ],
      child: const ErpPdvApp(),
    ),
  );
}

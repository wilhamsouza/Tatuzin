import 'package:tatuzin/app/app.dart';
import 'package:tatuzin/app/core/database/app_database.dart';
import 'package:tatuzin/app/core/theme/app_theme.dart';
import 'package:tatuzin/app/core/theme/app_theme_mode_controller.dart';
import 'package:tatuzin/modules/account/presentation/pages/settings_page.dart';
import 'package:tatuzin/modules/account/presentation/providers/account_cloud_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('preferencia padrao de tema e system', () async {
    const storage = SharedPreferencesAppThemePreferenceStorage();

    expect(await storage.load(), AppThemeMode.system);
  });

  test('alterar tema para dark persiste localmente', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container.read(appThemeModeControllerProvider.future);
    await container
        .read(appThemeModeControllerProvider.notifier)
        .setThemeMode(AppThemeMode.dark);

    final preferences = await SharedPreferences.getInstance();
    expect(
      preferences.getString(
        SharedPreferencesAppThemePreferenceStorage.preferenceKey,
      ),
      'dark',
    );
    expect(
      container.read(appThemeModeControllerProvider).valueOrNull,
      AppThemeMode.dark,
    );
  });

  test('alterar tema para light persiste localmente', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container.read(appThemeModeControllerProvider.future);
    await container
        .read(appThemeModeControllerProvider.notifier)
        .setThemeMode(AppThemeMode.light);

    final preferences = await SharedPreferences.getInstance();
    expect(
      preferences.getString(
        SharedPreferencesAppThemePreferenceStorage.preferenceKey,
      ),
      'light',
    );
    expect(
      container.read(appThemeModeControllerProvider).valueOrNull,
      AppThemeMode.light,
    );
  });

  testWidgets('MaterialApp recebe ThemeMode salvo', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      SharedPreferencesAppThemePreferenceStorage.preferenceKey: 'dark',
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appStartupProvider.overrideWith(
            (ref) async => const AppStartupState.success(),
          ),
        ],
        child: const ErpPdvApp(),
      ),
    );
    await tester.pumpAndSettle();

    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.themeMode, ThemeMode.dark);
    expect(app.darkTheme, isNotNull);
  });

  testWidgets('Configuracoes mostra opcoes de aparencia', (tester) async {
    final storage = _MemoryAppThemePreferenceStorage();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appThemePreferenceStorageProvider.overrideWithValue(storage),
          internalMobileSurfaceAccessProvider.overrideWith(
            (ref) => const InternalMobileSurfaceAccess(
              canOpenTechnicalSystem: false,
              canOpenAdminCloud: false,
            ),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          home: const SettingsPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Apar\u00eancia'), findsOneWidget);
    expect(find.text('Tema do app'), findsOneWidget);
    expect(find.text('Usar tema do sistema'), findsOneWidget);
    expect(find.text('Claro'), findsOneWidget);
    expect(find.text('Escuro'), findsOneWidget);

    await tester.tap(find.text('Escuro'));
    await tester.pumpAndSettle();

    expect(storage.savedMode, AppThemeMode.dark);
  });

  testWidgets('modo escuro renderiza tela basica sem exception', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appThemePreferenceStorageProvider.overrideWithValue(
            _MemoryAppThemePreferenceStorage(initialMode: AppThemeMode.dark),
          ),
          internalMobileSurfaceAccessProvider.overrideWith(
            (ref) => const InternalMobileSurfaceAccess(
              canOpenTechnicalSystem: false,
              canOpenAdminCloud: false,
            ),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: ThemeMode.dark,
          home: const SettingsPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Escuro'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _MemoryAppThemePreferenceStorage implements AppThemePreferenceStorage {
  _MemoryAppThemePreferenceStorage({this.initialMode = AppThemeMode.system});

  final AppThemeMode initialMode;
  AppThemeMode? savedMode;

  @override
  Future<AppThemeMode> load() async => savedMode ?? initialMode;

  @override
  Future<void> save(AppThemeMode mode) async {
    savedMode = mode;
  }
}

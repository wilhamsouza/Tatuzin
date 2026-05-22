import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppThemeMode {
  system,
  light,
  dark;

  static AppThemeMode fromStorageValue(String? value) {
    return switch (value) {
      'light' => AppThemeMode.light,
      'dark' => AppThemeMode.dark,
      'system' || _ => AppThemeMode.system,
    };
  }

  ThemeMode get materialThemeMode {
    return switch (this) {
      AppThemeMode.system => ThemeMode.system,
      AppThemeMode.light => ThemeMode.light,
      AppThemeMode.dark => ThemeMode.dark,
    };
  }

  String get storageValue {
    return switch (this) {
      AppThemeMode.system => 'system',
      AppThemeMode.light => 'light',
      AppThemeMode.dark => 'dark',
    };
  }

  String get label {
    return switch (this) {
      AppThemeMode.system => 'Usar tema do sistema',
      AppThemeMode.light => 'Claro',
      AppThemeMode.dark => 'Escuro',
    };
  }
}

abstract interface class AppThemePreferenceStorage {
  Future<AppThemeMode> load();

  Future<void> save(AppThemeMode mode);
}

class SharedPreferencesAppThemePreferenceStorage
    implements AppThemePreferenceStorage {
  const SharedPreferencesAppThemePreferenceStorage();

  static const String preferenceKey = 'app.theme_mode';

  @override
  Future<AppThemeMode> load() async {
    final preferences = await SharedPreferences.getInstance();
    return AppThemeMode.fromStorageValue(preferences.getString(preferenceKey));
  }

  @override
  Future<void> save(AppThemeMode mode) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(preferenceKey, mode.storageValue);
  }
}

final appThemePreferenceStorageProvider = Provider<AppThemePreferenceStorage>((
  ref,
) {
  return const SharedPreferencesAppThemePreferenceStorage();
});

final appThemeModeControllerProvider =
    AsyncNotifierProvider<AppThemeModeController, AppThemeMode>(
      AppThemeModeController.new,
    );

final appMaterialThemeModeProvider = Provider<ThemeMode>((ref) {
  return ref
      .watch(appThemeModeControllerProvider)
      .maybeWhen(
        data: (mode) => mode.materialThemeMode,
        orElse: () => ThemeMode.system,
      );
});

class AppThemeModeController extends AsyncNotifier<AppThemeMode> {
  @override
  Future<AppThemeMode> build() {
    return ref.read(appThemePreferenceStorageProvider).load();
  }

  Future<void> setThemeMode(AppThemeMode mode) async {
    final previous = state.valueOrNull ?? AppThemeMode.system;
    state = AsyncData(mode);

    try {
      await ref.read(appThemePreferenceStorageProvider).save(mode);
    } catch (error, stackTrace) {
      state = AsyncData(previous);
      Error.throwWithStackTrace(error, stackTrace);
    }
  }
}

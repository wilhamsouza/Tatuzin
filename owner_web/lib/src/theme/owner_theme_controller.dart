import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

final ownerThemeModeControllerProvider =
    AsyncNotifierProvider<OwnerThemeModeController, ThemeMode>(
      OwnerThemeModeController.new,
    );

final ownerMaterialThemeModeProvider = Provider<ThemeMode>((ref) {
  return ref
      .watch(ownerThemeModeControllerProvider)
      .maybeWhen(data: (mode) => mode, orElse: () => ThemeMode.system);
});

class OwnerThemeModeController extends AsyncNotifier<ThemeMode> {
  static const _storageKey = 'tatuzin_owner_theme_mode';

  @override
  Future<ThemeMode> build() async {
    final preferences = await SharedPreferences.getInstance();
    return _parse(preferences.getString(_storageKey));
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    state = AsyncData(mode);
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_storageKey, mode.name);
  }

  static ThemeMode _parse(String? value) {
    switch (value?.trim().toLowerCase()) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      case 'system':
      default:
        return ThemeMode.system;
    }
  }
}

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/entities/kitchen_printer_config.dart';
import '../domain/repositories/kitchen_printer_settings_repository.dart';

class SharedPreferencesKitchenPrinterSettingsRepository
    implements KitchenPrinterSettingsRepository {
  static const String _defaultPrinterKey =
      'pedidos.kitchen_printer.default_config';

  @override
  Future<void> clearDefault() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_defaultPrinterKey);
  }

  @override
  Future<KitchenPrinterConfig?> loadDefault() async {
    final preferences = await SharedPreferences.getInstance();
    final rawValue = preferences.getString(_defaultPrinterKey)?.trim();
    if (rawValue == null || rawValue.isEmpty) {
      return null;
    }

    final decoded = jsonDecode(rawValue);
    if (decoded is! Map<String, dynamic>) {
      return null;
    }
    return KitchenPrinterConfig.fromJson(decoded);
  }

  @override
  Future<void> saveDefault(KitchenPrinterConfig config) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      _defaultPrinterKey,
      jsonEncode(config.toJson()),
    );
  }
}

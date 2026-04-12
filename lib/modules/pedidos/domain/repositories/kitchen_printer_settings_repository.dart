import '../entities/kitchen_printer_config.dart';

abstract interface class KitchenPrinterSettingsRepository {
  Future<KitchenPrinterConfig?> loadDefault();

  Future<void> saveDefault(KitchenPrinterConfig config);

  Future<void> clearDefault();
}

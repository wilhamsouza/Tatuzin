import '../entities/bluetooth_printer_device.dart';

abstract interface class BluetoothPrinterDiscoveryRepository {
  Future<BluetoothPrinterDiscoveryResult> listPrinters();
}

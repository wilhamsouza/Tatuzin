class BluetoothPrinterDevice {
  const BluetoothPrinterDevice({required this.name, required this.address});

  final String name;
  final String address;
}

enum BluetoothPrinterDiscoveryStatus {
  available,
  permissionDenied,
  bluetoothOff,
  unsupported,
  failed,
}

class BluetoothPrinterDiscoveryResult {
  const BluetoothPrinterDiscoveryResult({
    required this.status,
    required this.devices,
    required this.message,
  });

  final BluetoothPrinterDiscoveryStatus status;
  final List<BluetoothPrinterDevice> devices;
  final String message;

  bool get canShowDevices =>
      status == BluetoothPrinterDiscoveryStatus.available && devices.isNotEmpty;
}

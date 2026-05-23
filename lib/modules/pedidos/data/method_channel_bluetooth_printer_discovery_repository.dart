import 'package:flutter/services.dart';

import '../domain/entities/bluetooth_printer_device.dart';
import '../domain/repositories/bluetooth_printer_discovery_repository.dart';

class MethodChannelBluetoothPrinterDiscoveryRepository
    implements BluetoothPrinterDiscoveryRepository {
  MethodChannelBluetoothPrinterDiscoveryRepository({
    MethodChannel channel = const MethodChannel('tatuzin/printers'),
  }) : _channel = channel;

  final MethodChannel _channel;

  @override
  Future<BluetoothPrinterDiscoveryResult> listPrinters() async {
    try {
      final response = await _channel.invokeMethod<Map<Object?, Object?>>(
        'listBluetoothPrinters',
      );
      if (response == null) {
        return const BluetoothPrinterDiscoveryResult(
          status: BluetoothPrinterDiscoveryStatus.unsupported,
          devices: [],
          message:
              'Nao foi possivel acessar o Bluetooth neste dispositivo. Informe o endereco manualmente.',
        );
      }

      final status = _statusFromValue(response['status'] as String?);
      final rawDevices = response['devices'];
      final devices = rawDevices is List
          ? rawDevices
                .whereType<Map<Object?, Object?>>()
                .map(
                  (device) => BluetoothPrinterDevice(
                    name: (device['name'] as String?)?.trim().isNotEmpty == true
                        ? (device['name'] as String).trim()
                        : 'Impressora Bluetooth',
                    address: (device['address'] as String? ?? '').trim(),
                  ),
                )
                .where((device) => device.address.isNotEmpty)
                .toList(growable: false)
          : const <BluetoothPrinterDevice>[];

      return BluetoothPrinterDiscoveryResult(
        status: status,
        devices: devices,
        message: _messageForStatus(status, devices),
      );
    } on PlatformException catch (error) {
      final status = _statusFromValue(error.code);
      return BluetoothPrinterDiscoveryResult(
        status: status,
        devices: const [],
        message: _messageForStatus(status, const []),
      );
    } on MissingPluginException {
      return const BluetoothPrinterDiscoveryResult(
        status: BluetoothPrinterDiscoveryStatus.unsupported,
        devices: [],
        message:
            'Busca Bluetooth indisponivel nesta plataforma. Informe o endereco manualmente.',
      );
    } catch (_) {
      return const BluetoothPrinterDiscoveryResult(
        status: BluetoothPrinterDiscoveryStatus.failed,
        devices: [],
        message:
            'Nao foi possivel procurar impressoras. Verifique se a impressora esta ligada e pareada.',
      );
    }
  }

  BluetoothPrinterDiscoveryStatus _statusFromValue(String? value) {
    switch (value) {
      case 'available':
        return BluetoothPrinterDiscoveryStatus.available;
      case 'permissionDenied':
        return BluetoothPrinterDiscoveryStatus.permissionDenied;
      case 'bluetoothOff':
        return BluetoothPrinterDiscoveryStatus.bluetoothOff;
      case 'unsupported':
        return BluetoothPrinterDiscoveryStatus.unsupported;
      default:
        return BluetoothPrinterDiscoveryStatus.failed;
    }
  }

  String _messageForStatus(
    BluetoothPrinterDiscoveryStatus status,
    List<BluetoothPrinterDevice> devices,
  ) {
    switch (status) {
      case BluetoothPrinterDiscoveryStatus.available:
        return devices.isEmpty
            ? 'Nenhuma impressora Bluetooth encontrada. Verifique se a impressora esta ligada e pareada.'
            : '${devices.length} impressora(s) Bluetooth encontrada(s).';
      case BluetoothPrinterDiscoveryStatus.permissionDenied:
        return 'Permita o acesso ao Bluetooth para procurar impressoras pareadas.';
      case BluetoothPrinterDiscoveryStatus.bluetoothOff:
        return 'Ative o Bluetooth e tente novamente.';
      case BluetoothPrinterDiscoveryStatus.unsupported:
        return 'Busca Bluetooth indisponivel neste dispositivo. Informe o endereco manualmente.';
      case BluetoothPrinterDiscoveryStatus.failed:
        return 'Verifique se a impressora esta ligada e pareada.';
    }
  }
}

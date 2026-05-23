import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/core/widgets/app_input.dart';
import '../../domain/entities/bluetooth_printer_device.dart';
import '../../domain/entities/kitchen_printer_config.dart';
import '../providers/order_print_providers.dart';
import '../support/order_ui_support.dart';

class KitchenPrinterConfigDialog extends ConsumerStatefulWidget {
  const KitchenPrinterConfigDialog({super.key, this.initialConfig});

  final KitchenPrinterConfig? initialConfig;

  @override
  ConsumerState<KitchenPrinterConfigDialog> createState() =>
      _KitchenPrinterConfigDialogState();
}

class _KitchenPrinterConfigDialogState
    extends ConsumerState<KitchenPrinterConfigDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _hostController;
  late final TextEditingController _portController;
  late final TextEditingController _bluetoothController;
  late KitchenPrinterConnectionType _connectionType;
  var _showManualBluetooth = false;
  var _isSearchingBluetooth = false;
  String? _bluetoothSearchMessage;
  List<BluetoothPrinterDevice> _bluetoothDevices = const [];

  @override
  void initState() {
    super.initState();
    _connectionType =
        widget.initialConfig?.connectionType ??
        KitchenPrinterConnectionType.bluetooth;
    _showManualBluetooth =
        widget.initialConfig?.bluetoothAddress?.trim().isNotEmpty == true;
    _nameController = TextEditingController(
      text:
          widget.initialConfig?.displayName ?? operationalOrderPrinterNameLabel,
    );
    _hostController = TextEditingController(
      text: widget.initialConfig?.host ?? '',
    );
    _portController = TextEditingController(
      text: '${widget.initialConfig?.port ?? 9100}',
    );
    _bluetoothController = TextEditingController(
      text: widget.initialConfig?.bluetoothAddress ?? '',
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _hostController.dispose();
    _portController.dispose();
    _bluetoothController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final configState = ref.watch(kitchenPrinterConfigControllerProvider);
    final testState = ref.watch(kitchenPrinterTestControllerProvider);
    final busy =
        configState.isLoading || testState.isLoading || _isSearchingBluetooth;

    return AlertDialog(
      title: const Text(operationalOrderPrinterDialogTitle),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Escolha como o Tatuzin deve enviar as impressoes.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 4),
              Text(
                'Esta configuracao e usada para listas de separacao e pedidos. Comprovantes comerciais continuam no fluxo de PDF e compartilhamento.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 14),
              AppInput(
                controller: _nameController,
                labelText: 'Nome da impressora',
              ),
              const SizedBox(height: 12),
              SegmentedButton<KitchenPrinterConnectionType>(
                segments: const [
                  ButtonSegment<KitchenPrinterConnectionType>(
                    value: KitchenPrinterConnectionType.bluetooth,
                    icon: Icon(Icons.bluetooth_rounded),
                    label: Text('Bluetooth'),
                  ),
                  ButtonSegment<KitchenPrinterConnectionType>(
                    value: KitchenPrinterConnectionType.network,
                    icon: Icon(Icons.wifi_rounded),
                    label: Text('Rede Wi-Fi'),
                  ),
                ],
                selected: <KitchenPrinterConnectionType>{_connectionType},
                onSelectionChanged: busy
                    ? null
                    : (selection) {
                        setState(() => _connectionType = selection.first);
                      },
              ),
              const SizedBox(height: 12),
              if (_connectionType == KitchenPrinterConnectionType.bluetooth)
                _buildBluetoothSection(context, busy)
              else
                _buildNetworkSection(context, busy),
            ],
          ),
        ),
      ),
      actions: [
        if (widget.initialConfig != null)
          TextButton(
            onPressed: busy ? null : _clearConfig,
            child: const Text('Remover'),
          ),
        TextButton(
          onPressed: busy ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancelar'),
        ),
        OutlinedButton.icon(
          onPressed: busy ? null : _printTest,
          icon: testState.isLoading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.receipt_long_rounded),
          label: Text(testState.isLoading ? 'Testando...' : 'Testar impressao'),
        ),
        FilledButton(
          onPressed: busy ? null : _saveConfig,
          child: configState.isLoading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Salvar'),
        ),
      ],
    );
  }

  Widget _buildBluetoothSection(BuildContext context, bool busy) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: busy ? null : _searchBluetoothPrinters,
            icon: _isSearchingBluetooth
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.search_rounded),
            label: Text(
              _isSearchingBluetooth
                  ? 'Procurando...'
                  : 'Procurar impressoras Bluetooth',
            ),
          ),
        ),
        if (_bluetoothSearchMessage != null) ...[
          const SizedBox(height: 10),
          Text(
            _bluetoothSearchMessage!,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
        const SizedBox(height: 8),
        Text(
          'A busca usa as impressoras Bluetooth pareadas no Android. Se a impressora nao aparecer, verifique se ela esta ligada e pareada.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        if (_bluetoothDevices.isNotEmpty) ...[
          const SizedBox(height: 10),
          ..._bluetoothDevices.map(
            (device) => Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                enabled: !busy,
                leading: Icon(
                  _bluetoothController.text.trim() == device.address
                      ? Icons.check_circle_rounded
                      : Icons.print_rounded,
                ),
                title: Text(device.name),
                subtitle: Text(device.address),
                onTap: busy ? null : () => _selectBluetoothDevice(device),
              ),
            ),
          ),
        ],
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: busy
              ? null
              : () => setState(() {
                  _showManualBluetooth = !_showManualBluetooth;
                }),
          icon: Icon(
            _showManualBluetooth
                ? Icons.expand_less_rounded
                : Icons.expand_more_rounded,
          ),
          label: const Text(
            'Configuracao avancada: informar endereco manualmente',
          ),
        ),
        if (_showManualBluetooth) ...[
          const SizedBox(height: 8),
          AppInput(
            controller: _bluetoothController,
            labelText: 'Endereco Bluetooth',
            hintText: 'Ex.: 00:11:22:33:44:55',
          ),
          const SizedBox(height: 8),
          Text(
            'Use o endereco manual somente quando a impressora nao aparecer na busca ou quando o suporte orientar.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ],
    );
  }

  Widget _buildNetworkSection(BuildContext context, bool busy) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppInput(
          controller: _hostController,
          labelText: 'IP da impressora',
          hintText: 'Ex.: 192.168.0.120',
          keyboardType: TextInputType.url,
        ),
        const SizedBox(height: 10),
        AppInput(
          controller: _portController,
          labelText: 'Porta',
          hintText: '9100',
          keyboardType: TextInputType.number,
        ),
        const SizedBox(height: 10),
        Text(
          'A impressora de rede precisa estar no mesmo Wi-Fi. A porta padrao de impressoras termicas ESC/POS costuma ser 9100.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: busy ? null : _showNetworkDiscoveryUnavailable,
          icon: const Icon(Icons.travel_explore_rounded),
          label: const Text('Procurar na rede'),
        ),
      ],
    );
  }

  Future<void> _searchBluetoothPrinters() async {
    setState(() {
      _isSearchingBluetooth = true;
      _bluetoothSearchMessage = null;
      _bluetoothDevices = const [];
    });

    final result = await ref
        .read(bluetoothPrinterDiscoveryRepositoryProvider)
        .listPrinters();
    if (!mounted) {
      return;
    }
    setState(() {
      _isSearchingBluetooth = false;
      _bluetoothDevices = result.devices;
      _bluetoothSearchMessage = result.message;
    });
  }

  void _selectBluetoothDevice(BluetoothPrinterDevice device) {
    setState(() {
      _nameController.text = device.name;
      _bluetoothController.text = device.address;
      _showManualBluetooth = false;
      _bluetoothSearchMessage =
          'Impressora ${device.name} selecionada. O endereco foi preenchido automaticamente.';
    });
  }

  KitchenPrinterConfig? _buildConfig() {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      _showMessage('Informe um nome para a impressora.');
      return null;
    }

    if (_connectionType == KitchenPrinterConnectionType.network) {
      final host = _hostController.text.trim();
      final portText = _portController.text.trim();
      final port = int.tryParse(portText.isEmpty ? '9100' : portText);
      if (host.isEmpty) {
        _showMessage(
          'Informe o IP da impressora. Ela precisa estar no mesmo Wi-Fi.',
        );
        return null;
      }
      if (port == null || port < 1 || port > 65535) {
        _showMessage('Informe uma porta valida. A sugestao padrao e 9100.');
        return null;
      }
      return KitchenPrinterConfig(
        displayName: name,
        connectionType: _connectionType,
        host: host,
        port: port,
      );
    }

    final bluetoothAddress = _bluetoothController.text.trim();
    if (bluetoothAddress.isEmpty) {
      _showMessage(
        'Selecione uma impressora Bluetooth ou informe o endereco manualmente.',
      );
      return null;
    }
    if (!_looksLikeBluetoothAddress(bluetoothAddress)) {
      _showMessage(
        'Endereco Bluetooth invalido. Use o formato 00:11:22:33:44:55.',
      );
      setState(() => _showManualBluetooth = true);
      return null;
    }

    return KitchenPrinterConfig(
      displayName: name,
      connectionType: _connectionType,
      bluetoothAddress: bluetoothAddress,
    );
  }

  Future<void> _saveConfig() async {
    final config = _buildConfig();
    if (config == null) {
      return;
    }

    try {
      await ref
          .read(kitchenPrinterConfigControllerProvider.notifier)
          .save(config);
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showMessage('Falha ao salvar impressora: $error');
    }
  }

  Future<void> _printTest() async {
    final config = _buildConfig();
    if (config == null) {
      return;
    }

    try {
      await ref
          .read(kitchenPrinterTestControllerProvider.notifier)
          .printTest(config);
      if (!mounted) {
        return;
      }
      _showMessage('Teste de impressao enviado.');
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showMessage('Falha no teste: $error');
    }
  }

  Future<void> _clearConfig() async {
    try {
      await ref.read(kitchenPrinterConfigControllerProvider.notifier).clear();
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showMessage('Falha ao remover configuracao: $error');
    }
  }

  void _showNetworkDiscoveryUnavailable() {
    _showMessage(
      'A descoberta automatica de rede ainda nao esta disponivel. Informe IP e porta; a impressora precisa estar no mesmo Wi-Fi.',
    );
  }

  bool _looksLikeBluetoothAddress(String value) {
    return RegExp(r'^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$').hasMatch(value);
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

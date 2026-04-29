import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/core/widgets/app_input.dart';
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

  @override
  void initState() {
    super.initState();
    _connectionType =
        widget.initialConfig?.connectionType ??
        KitchenPrinterConnectionType.network;
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
    final busy = configState.isLoading || testState.isLoading;

    return AlertDialog(
      title: const Text(operationalOrderPrinterDialogTitle),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Configure a impressora operacional do modulo de pedidos. O fluxo ja suporta teste, envio e reimpressao.',
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
                  value: KitchenPrinterConnectionType.network,
                  icon: Icon(Icons.router_rounded),
                  label: Text('Rede'),
                ),
                ButtonSegment<KitchenPrinterConnectionType>(
                  value: KitchenPrinterConnectionType.bluetooth,
                  icon: Icon(Icons.bluetooth_rounded),
                  label: Text('Bluetooth'),
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
            if (_connectionType == KitchenPrinterConnectionType.network) ...[
              AppInput(
                controller: _hostController,
                labelText: 'IP ou host',
                hintText: 'Ex.: 192.168.0.120',
              ),
              const SizedBox(height: 10),
              AppInput(
                controller: _portController,
                labelText: 'Porta TCP',
                hintText: '9100',
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 10),
              Text(
                'Ideal para impressora termica ESC/POS em rede local.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ] else ...[
              AppInput(
                controller: _bluetoothController,
                labelText: 'Endereco Bluetooth',
                hintText: 'Ex.: 00:11:22:33:44:55',
              ),
              const SizedBox(height: 10),
              Text(
                'A configuracao Bluetooth ja fica salva e pronta para o plug da camada nativa de envio.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
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
          label: const Text('Testar'),
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

  KitchenPrinterConfig? _buildConfig() {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      _showMessage('Informe um nome para a impressora.');
      return null;
    }

    if (_connectionType == KitchenPrinterConnectionType.network) {
      final host = _hostController.text.trim();
      final port = int.tryParse(_portController.text.trim()) ?? 9100;
      if (host.isEmpty) {
        _showMessage('Informe o IP ou host da impressora em rede.');
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
      _showMessage('Informe o endereco Bluetooth da impressora.');
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

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

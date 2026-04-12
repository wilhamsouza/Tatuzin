import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/core/widgets/app_input.dart';
import '../../domain/entities/kitchen_printer_config.dart';
import '../providers/order_print_providers.dart';

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

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: widget.initialConfig?.displayName ?? 'Impressora cozinha',
    );
    _hostController = TextEditingController(
      text: widget.initialConfig?.host ?? '',
    );
    _portController = TextEditingController(
      text: '${widget.initialConfig?.port ?? 9100}',
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _hostController.dispose();
    _portController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controllerState = ref.watch(kitchenPrinterConfigControllerProvider);

    return AlertDialog(
      title: const Text('Impressora da cozinha'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Configure uma impressora ESC/POS em rede. A base ja fica preparada para expansao futura de Bluetooth.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 14),
            AppInput(
              controller: _nameController,
              labelText: 'Nome da impressora',
            ),
            const SizedBox(height: 10),
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
              'Conexao desta entrega: TCP/IP. Bluetooth permanece preparado na arquitetura e pode ser conectado depois sem mudar a UI de pedidos.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
      actions: [
        if (widget.initialConfig != null)
          TextButton(
            onPressed: controllerState.isLoading ? null : _clearConfig,
            child: const Text('Remover'),
          ),
        TextButton(
          onPressed: controllerState.isLoading
              ? null
              : () => Navigator.of(context).pop(false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: controllerState.isLoading ? null : _saveConfig,
          child: controllerState.isLoading
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

  Future<void> _saveConfig() async {
    final name = _nameController.text.trim();
    final host = _hostController.text.trim();
    final port = int.tryParse(_portController.text.trim()) ?? 9100;

    if (name.isEmpty || host.isEmpty) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('Informe o nome e o IP da impressora.')),
        );
      return;
    }

    try {
      await ref
          .read(kitchenPrinterConfigControllerProvider.notifier)
          .save(
            KitchenPrinterConfig(
              displayName: name,
              connectionType: KitchenPrinterConnectionType.network,
              host: host,
              port: port,
            ),
          );
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text('Falha ao salvar impressora: $error')),
        );
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
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text('Falha ao remover configuracao: $error')),
        );
    }
  }
}

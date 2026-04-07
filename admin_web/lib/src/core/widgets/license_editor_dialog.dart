import 'package:flutter/material.dart';

import '../models/admin_models.dart';

class LicenseEditorResult {
  const LicenseEditorResult({
    required this.plan,
    required this.status,
    required this.startsAt,
    required this.expiresAt,
    required this.syncEnabled,
    required this.maxDevices,
  });

  final String plan;
  final String status;
  final DateTime? startsAt;
  final DateTime? expiresAt;
  final bool syncEnabled;
  final int? maxDevices;
}

Future<LicenseEditorResult?> showLicenseEditorDialog({
  required BuildContext context,
  required AdminLicenseSnapshot license,
}) {
  return showDialog<LicenseEditorResult>(
    context: context,
    builder: (dialogContext) => _LicenseEditorDialog(license: license),
  );
}

class _LicenseEditorDialog extends StatefulWidget {
  const _LicenseEditorDialog({required this.license});

  final AdminLicenseSnapshot license;

  @override
  State<_LicenseEditorDialog> createState() => _LicenseEditorDialogState();
}

class _LicenseEditorDialogState extends State<_LicenseEditorDialog> {
  late final TextEditingController _planController;
  late final TextEditingController _maxDevicesController;
  late final TextEditingController _startsAtController;
  late final TextEditingController _expiresAtController;

  late String _status;
  late bool _syncEnabled;
  late DateTime? _startsAt;
  late DateTime? _expiresAt;

  @override
  void initState() {
    super.initState();
    _status = widget.license.status;
    _syncEnabled = widget.license.syncEnabled;
    _startsAt = widget.license.startsAt;
    _expiresAt = widget.license.expiresAt;
    _planController = TextEditingController(text: widget.license.plan);
    _maxDevicesController = TextEditingController(
      text: widget.license.maxDevices?.toString() ?? '',
    );
    _startsAtController = TextEditingController(text: _formatDate(_startsAt));
    _expiresAtController = TextEditingController(text: _formatDate(_expiresAt));
  }

  @override
  void dispose() {
    _planController.dispose();
    _maxDevicesController.dispose();
    _startsAtController.dispose();
    _expiresAtController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Editar licenca'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 540),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _planController,
                decoration: const InputDecoration(
                  labelText: 'Plano',
                  hintText: 'trial, essencial, premium...',
                ),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _status,
                decoration: const InputDecoration(labelText: 'Status'),
                items: const [
                  DropdownMenuItem(value: 'trial', child: Text('Trial')),
                  DropdownMenuItem(value: 'active', child: Text('Ativa')),
                  DropdownMenuItem(value: 'suspended', child: Text('Suspensa')),
                  DropdownMenuItem(value: 'expired', child: Text('Expirada')),
                ],
                onChanged: (value) {
                  if (value == null) {
                    return;
                  }
                  setState(() {
                    _status = value;
                  });
                },
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _DateField(
                      label: 'Inicio',
                      controller: _startsAtController,
                      onPick: () async {
                        final picked = await _pickDate(context, _startsAt);
                        if (picked == null) {
                          return;
                        }
                        setState(() {
                          _startsAt = picked;
                          _startsAtController.text = _formatDate(picked);
                        });
                      },
                      onClear: null,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _DateField(
                      label: 'Expira em',
                      controller: _expiresAtController,
                      onPick: () async {
                        final picked = await _pickDate(context, _expiresAt);
                        if (picked == null) {
                          return;
                        }
                        setState(() {
                          _expiresAt = picked;
                          _expiresAtController.text = _formatDate(picked);
                        });
                      },
                      onClear: () {
                        setState(() {
                          _expiresAt = null;
                          _expiresAtController.clear();
                        });
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _maxDevicesController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Maximo de dispositivos',
                  hintText: 'Opcional',
                ),
              ),
              const SizedBox(height: 16),
              SwitchListTile.adaptive(
                value: _syncEnabled,
                contentPadding: EdgeInsets.zero,
                title: const Text('Sync cloud habilitada'),
                subtitle: const Text(
                  'Quando desativado, a empresa continua local, mas os recursos cloud ficam bloqueados.',
                ),
                onChanged: (value) {
                  setState(() {
                    _syncEnabled = value;
                  });
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () {
            final plan = _planController.text.trim();
            if (plan.isEmpty) {
              return;
            }

            Navigator.of(context).pop(
              LicenseEditorResult(
                plan: plan,
                status: _status,
                startsAt: _startsAt,
                expiresAt: _expiresAt,
                syncEnabled: _syncEnabled,
                maxDevices: int.tryParse(_maxDevicesController.text.trim()),
              ),
            );
          },
          child: const Text('Salvar'),
        ),
      ],
    );
  }

  Future<DateTime?> _pickDate(BuildContext context, DateTime? initialDate) {
    final now = DateTime.now();
    return showDatePicker(
      context: context,
      firstDate: DateTime(now.year - 10),
      lastDate: DateTime(now.year + 20),
      initialDate: initialDate ?? now,
    );
  }

  String _formatDate(DateTime? value) {
    if (value == null) {
      return '';
    }
    final day = value.day.toString().padLeft(2, '0');
    final month = value.month.toString().padLeft(2, '0');
    return '$day/$month/${value.year}';
  }
}

class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.controller,
    required this.onPick,
    required this.onClear,
  });

  final String label;
  final TextEditingController controller;
  final VoidCallback onPick;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    return TextField(
      readOnly: true,
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        suffixIcon: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (onClear != null && controller.text.isNotEmpty)
              IconButton(
                onPressed: onClear,
                tooltip: 'Limpar',
                icon: const Icon(Icons.close_rounded),
              ),
            IconButton(
              onPressed: onPick,
              tooltip: 'Selecionar data',
              icon: const Icon(Icons.calendar_month_rounded),
            ),
          ],
        ),
      ),
      onTap: onPick,
    );
  }
}

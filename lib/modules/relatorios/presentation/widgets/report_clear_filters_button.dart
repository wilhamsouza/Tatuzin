import 'package:flutter/material.dart';

class ReportClearFiltersButton extends StatelessWidget {
  const ReportClearFiltersButton({
    super.key,
    required this.onPressed,
    this.enabled = true,
  });

  final VoidCallback onPressed;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: enabled ? onPressed : null,
      icon: const Icon(Icons.filter_alt_off_outlined),
      label: const Text('Limpar filtros'),
    );
  }
}

import 'package:flutter/material.dart';

class ReportResetPageButton extends StatelessWidget {
  const ReportResetPageButton({
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
      icon: const Icon(Icons.restart_alt_rounded),
      label: const Text('Resetar pagina'),
    );
  }
}

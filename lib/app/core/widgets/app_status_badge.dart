import 'package:flutter/material.dart';

enum AppStatusTone { neutral, info, success, warning, danger }

class AppStatusBadge extends StatelessWidget {
  const AppStatusBadge({
    super.key,
    required this.label,
    this.tone = AppStatusTone.neutral,
    this.icon,
  });

  final String label;
  final AppStatusTone tone;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final colors = _colors(colorScheme);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.$1,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 16, color: colors.$2),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: TextStyle(color: colors.$2, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }

  (Color, Color) _colors(ColorScheme scheme) {
    switch (tone) {
      case AppStatusTone.info:
        return (scheme.primaryContainer, scheme.onPrimaryContainer);
      case AppStatusTone.success:
        return (const Color(0xFFDCFCE7), const Color(0xFF166534));
      case AppStatusTone.warning:
        return (const Color(0xFFFEF3C7), const Color(0xFF92400E));
      case AppStatusTone.danger:
        return (scheme.errorContainer, scheme.onErrorContainer);
      case AppStatusTone.neutral:
        return (scheme.surfaceContainerHigh, scheme.onSurfaceVariant);
    }
  }
}

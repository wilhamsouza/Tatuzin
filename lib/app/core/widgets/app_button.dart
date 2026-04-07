import 'package:flutter/material.dart';

class AppButton extends StatelessWidget {
  const AppButton.primary({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.compact = false,
    this.expand = false,
  }) : _variant = _AppButtonVariant.primary;

  const AppButton.secondary({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.compact = false,
    this.expand = false,
  }) : _variant = _AppButtonVariant.secondary;

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool compact;
  final bool expand;
  final _AppButtonVariant _variant;

  @override
  Widget build(BuildContext context) {
    final child = icon == null
        ? Text(label)
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: compact ? 18 : 20),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          );

    final button = _variant == _AppButtonVariant.primary
        ? FilledButton(
            onPressed: onPressed,
            style: compact
                ? FilledButton.styleFrom(
                    minimumSize: const Size(0, 44),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                  )
                : null,
            child: child,
          )
        : OutlinedButton(
            onPressed: onPressed,
            style: compact
                ? OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 44),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                  )
                : null,
            child: child,
          );

    if (!expand) {
      return button;
    }

    return SizedBox(width: double.infinity, child: button);
  }
}

enum _AppButtonVariant { primary, secondary }

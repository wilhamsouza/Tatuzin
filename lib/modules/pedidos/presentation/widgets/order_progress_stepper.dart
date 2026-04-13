import 'package:flutter/material.dart';

import '../../domain/entities/operational_order.dart';

class OrderProgressStepper extends StatelessWidget {
  const OrderProgressStepper({super.key, required this.status});

  final OperationalOrderStatus status;

  static const List<(OperationalOrderStatus, String)> _steps =
      <(OperationalOrderStatus, String)>[
        (OperationalOrderStatus.open, 'Enviado'),
        (OperationalOrderStatus.inPreparation, 'Em preparo'),
        (OperationalOrderStatus.ready, 'Pronto'),
        (OperationalOrderStatus.delivered, 'Entregue'),
      ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (status == OperationalOrderStatus.canceled) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: colorScheme.errorContainer,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Icon(Icons.cancel_rounded, color: colorScheme.onErrorContainer),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Pedido cancelado. O fluxo operacional foi interrompido.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onErrorContainer,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      );
    }

    final currentIndex = _progressIndex(status);
    return Row(
      children: [
        for (var index = 0; index < _steps.length; index++) ...[
          Expanded(
            child: _OrderProgressNode(
              label: _steps[index].$2,
              isCompleted: index <= currentIndex,
              isCurrent: index == currentIndex,
            ),
          ),
          if (index < _steps.length - 1)
            Expanded(
              child: Container(
                height: 2,
                margin: const EdgeInsets.symmetric(horizontal: 6),
                color: index < currentIndex
                    ? colorScheme.primary
                    : colorScheme.outlineVariant,
              ),
            ),
        ],
      ],
    );
  }

  int _progressIndex(OperationalOrderStatus status) {
    switch (status) {
      case OperationalOrderStatus.draft:
      case OperationalOrderStatus.open:
        return 0;
      case OperationalOrderStatus.inPreparation:
        return 1;
      case OperationalOrderStatus.ready:
        return 2;
      case OperationalOrderStatus.delivered:
        return 3;
      case OperationalOrderStatus.canceled:
        return 0;
    }
  }
}

class _OrderProgressNode extends StatelessWidget {
  const _OrderProgressNode({
    required this.label,
    required this.isCompleted,
    required this.isCurrent,
  });

  final String label;
  final bool isCompleted;
  final bool isCurrent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final backgroundColor = isCompleted
        ? colorScheme.primary
        : colorScheme.surfaceContainerHighest;
    final foregroundColor = isCompleted
        ? colorScheme.onPrimary
        : colorScheme.onSurfaceVariant;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: isCurrent ? 32 : 28,
          height: isCurrent ? 32 : 28,
          decoration: BoxDecoration(
            color: backgroundColor,
            shape: BoxShape.circle,
            boxShadow: isCurrent
                ? [
                    BoxShadow(
                      color: colorScheme.primary.withValues(alpha: 0.18),
                      blurRadius: 14,
                      offset: const Offset(0, 6),
                    ),
                  ]
                : null,
          ),
          child: Icon(
            isCompleted ? Icons.check_rounded : Icons.circle_outlined,
            size: 16,
            color: foregroundColor,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          textAlign: TextAlign.center,
          style: theme.textTheme.labelSmall?.copyWith(
            color: isCompleted
                ? colorScheme.onSurface
                : colorScheme.onSurfaceVariant,
            fontWeight: isCurrent ? FontWeight.w800 : FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

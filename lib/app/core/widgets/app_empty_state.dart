import 'package:flutter/material.dart';

import 'app_state_card.dart';

class AppEmptyState extends StatelessWidget {
  const AppEmptyState({
    super.key,
    required this.title,
    required this.message,
    this.icon,
    this.actionLabel,
    this.onAction,
    this.compact = false,
  });

  final String title;
  final String message;
  final IconData? icon;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return AppStateCard(
      title: title,
      message: message,
      icon: icon ?? Icons.inbox_outlined,
      actionLabel: actionLabel,
      onAction: onAction,
      compact: compact,
    );
  }
}

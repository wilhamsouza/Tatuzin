import 'package:flutter/material.dart';

import 'app_status_badge.dart';

class AppStatusChip extends StatelessWidget {
  const AppStatusChip({
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
    return AppStatusBadge(label: label, tone: tone, icon: icon);
  }
}

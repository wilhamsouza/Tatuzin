import 'package:flutter/material.dart';

import '../../../../app/core/widgets/app_quick_action_card.dart';
import '../../../../app/theme/app_design_tokens.dart';

class ReportShortcutCard extends StatelessWidget {
  const ReportShortcutCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
    this.palette,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;
  final AppTonePalette? palette;

  @override
  Widget build(BuildContext context) {
    return AppQuickActionCard(
      title: title,
      subtitle: subtitle,
      icon: icon,
      onTap: onTap,
      palette: palette,
    );
  }
}

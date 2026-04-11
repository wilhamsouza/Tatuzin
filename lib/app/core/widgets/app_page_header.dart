import 'package:flutter/material.dart';

import 'app_card.dart';
import 'app_section_title.dart';
import 'app_status_badge.dart';

class AppPageHeader extends StatelessWidget {
  const AppPageHeader({
    super.key,
    required this.title,
    required this.subtitle,
    this.badgeLabel,
    this.badgeIcon,
    this.trailing,
    this.emphasized = false,
  });

  final String title;
  final String subtitle;
  final String? badgeLabel;
  final IconData? badgeIcon;
  final Widget? trailing;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return AppCard(
      padding: const EdgeInsets.all(12),
      borderRadius: 16,
      color: emphasized
          ? colorScheme.primaryContainer.withValues(alpha: 0.62)
          : colorScheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (badgeLabel?.isNotEmpty ?? false) ...[
            AppStatusBadge(
              label: badgeLabel!,
              tone: emphasized ? AppStatusTone.warning : AppStatusTone.info,
              icon: badgeIcon,
            ),
            const SizedBox(height: 6),
          ],
          AppSectionTitle(title: title, subtitle: subtitle, trailing: trailing),
        ],
      ),
    );
  }
}

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
      padding: const EdgeInsets.all(20),
      borderRadius: 24,
      color: emphasized ? null : colorScheme.surface,
      gradient: emphasized
          ? LinearGradient(
              colors: [colorScheme.primary, colorScheme.secondary],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (badgeLabel?.isNotEmpty ?? false) ...[
            AppStatusBadge(
              label: badgeLabel!,
              tone: emphasized ? AppStatusTone.neutral : AppStatusTone.info,
              icon: badgeIcon,
            ),
            const SizedBox(height: 14),
          ],
          AppSectionTitle(
            title: title,
            subtitle: subtitle,
            trailing: trailing,
            onDarkBackground: emphasized,
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../../theme/app_design_tokens.dart';
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
    final tokens = context.appColors;
    final layout = context.appLayout;

    return AppCard(
      padding: EdgeInsets.all(layout.headerPadding),
      tone: emphasized ? AppCardTone.brand : AppCardTone.standard,
      color: emphasized ? tokens.brand.surface : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (badgeLabel?.isNotEmpty ?? false) ...[
            AppStatusBadge(
              label: badgeLabel!,
              tone: emphasized ? AppStatusTone.warning : AppStatusTone.info,
              icon: badgeIcon,
            ),
            SizedBox(height: layout.space3),
          ],
          AppSectionTitle(title: title, subtitle: subtitle, trailing: trailing),
        ],
      ),
    );
  }
}

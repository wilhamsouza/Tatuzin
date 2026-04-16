import 'package:flutter/material.dart';

import '../../theme/app_design_tokens.dart';
import 'app_card.dart';

class AppListTileCard extends StatelessWidget {
  const AppListTileCard({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.badges = const <Widget>[],
    this.footer,
    this.onTap,
    this.tone = AppCardTone.standard,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final List<Widget> badges;
  final Widget? footer;
  final VoidCallback? onTap;
  final AppCardTone tone;

  @override
  Widget build(BuildContext context) {
    final layout = context.appLayout;
    final theme = Theme.of(context);

    return AppCard(
      onTap: onTap,
      tone: tone,
      padding: EdgeInsets.all(layout.cardPadding - 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (leading != null) ...[
                leading!,
                SizedBox(width: layout.space6),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (subtitle?.isNotEmpty ?? false) ...[
                      SizedBox(height: layout.space2),
                      Text(
                        subtitle!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing != null) ...[
                SizedBox(width: layout.space4),
                trailing!,
              ],
            ],
          ),
          if (badges.isNotEmpty) ...[
            SizedBox(height: layout.space5),
            Wrap(
              spacing: layout.space3,
              runSpacing: layout.space3,
              children: badges,
            ),
          ],
          if (footer != null) ...[SizedBox(height: layout.space5), footer!],
        ],
      ),
    );
  }
}

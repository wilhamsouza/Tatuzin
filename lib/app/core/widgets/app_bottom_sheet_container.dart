import 'package:flutter/material.dart';

import '../../theme/app_design_tokens.dart';

class AppBottomSheetContainer extends StatelessWidget {
  const AppBottomSheetContainer({
    super.key,
    required this.child,
    this.title,
    this.subtitle,
    this.trailing,
    this.padding,
  });

  final Widget child;
  final String? title;
  final String? subtitle;
  final Widget? trailing;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.appColors;
    final layout = context.appLayout;

    return Container(
      decoration: BoxDecoration(
        color: tokens.cardBackground,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(layout.radiusSheet),
        ),
        border: Border(
          top: BorderSide(color: tokens.outlineSoft),
          left: BorderSide(color: tokens.outlineSoft),
          right: BorderSide(color: tokens.outlineSoft),
        ),
        boxShadow: [
          BoxShadow(
            color: tokens.shadowSoft,
            blurRadius: layout.shadowBlur + 4,
            offset: Offset(0, layout.shadowOffsetY),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding:
              padding ??
              EdgeInsets.fromLTRB(
                layout.sheetPadding,
                layout.space4,
                layout.sheetPadding,
                layout.sheetPadding,
              ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (title != null || subtitle != null || trailing != null) ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (title != null)
                            Text(
                              title!,
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          if (subtitle?.isNotEmpty ?? false) ...[
                            SizedBox(height: layout.space2),
                            Text(
                              subtitle!,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (trailing != null) ...[
                      SizedBox(width: layout.blockGap),
                      trailing!,
                    ],
                  ],
                ),
                SizedBox(height: layout.sectionGap),
              ],
              child,
            ],
          ),
        ),
      ),
    );
  }
}

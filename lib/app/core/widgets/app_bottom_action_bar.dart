import 'package:flutter/material.dart';

import '../../theme/app_design_tokens.dart';

class AppBottomActionBar extends StatelessWidget {
  const AppBottomActionBar({
    super.key,
    required this.child,
    this.minimum,
    this.padding,
  });

  final Widget child;
  final EdgeInsets? minimum;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final tokens = context.appColors;
    final layout = context.appLayout;

    return SafeArea(
      minimum:
          minimum ??
          EdgeInsets.fromLTRB(
            layout.pagePadding,
            layout.space4,
            layout.pagePadding,
            layout.pagePadding,
          ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: tokens.cardBackground,
          borderRadius: BorderRadius.circular(layout.radiusXl + 2),
          border: Border.all(color: tokens.outlineSoft),
          boxShadow: [
            BoxShadow(
              color: tokens.shadowSoft,
              blurRadius: layout.shadowBlur,
              offset: Offset(0, layout.shadowOffsetY),
            ),
          ],
        ),
        child: Padding(
          padding:
              padding ??
              EdgeInsets.fromLTRB(
                layout.bottomBarPadding + 2,
                layout.bottomBarPadding,
                layout.bottomBarPadding + 2,
                layout.bottomBarPadding + 2,
              ),
          child: child,
        ),
      ),
    );
  }
}

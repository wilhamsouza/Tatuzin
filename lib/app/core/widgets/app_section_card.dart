import 'package:flutter/material.dart';

import '../../theme/app_design_tokens.dart';
import 'app_card.dart';
import 'app_section_title.dart';

class AppSectionCard extends StatelessWidget {
  const AppSectionCard({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    required this.child,
    this.padding,
    this.tone = AppCardTone.standard,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final AppCardTone tone;

  @override
  Widget build(BuildContext context) {
    final layout = context.appLayout;

    return AppCard(
      tone: tone,
      padding: padding ?? EdgeInsets.all(layout.cardPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppSectionTitle(title: title, subtitle: subtitle, trailing: trailing),
          SizedBox(height: layout.sectionGap),
          child,
        ],
      ),
    );
  }
}

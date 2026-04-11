import 'package:flutter/material.dart';

import 'app_card.dart';
import 'app_section_title.dart';

class AppSectionCard extends StatelessWidget {
  const AppSectionCard({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppSectionTitle(title: title, subtitle: subtitle, trailing: trailing),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';

import 'app_section_title.dart';

class AppSectionHeader extends StatelessWidget {
  const AppSectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return AppSectionTitle(
      title: title,
      subtitle: subtitle,
      trailing: trailing,
    );
  }
}

import 'package:flutter/material.dart';

import '../theme/app_design_tokens.dart';

class AppLeadingAvatar extends StatelessWidget {
  const AppLeadingAvatar({
    super.key,
    required this.label,
    this.icon,
    this.size = 44,
    this.tone = AppLeadingAvatarTone.brand,
  });

  final String label;
  final IconData? icon;
  final double size;
  final AppLeadingAvatarTone tone;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final palette = switch (tone) {
      AppLeadingAvatarTone.brand => colors.brand,
      AppLeadingAvatarTone.info => colors.info,
      AppLeadingAvatarTone.success => colors.success,
      AppLeadingAvatarTone.warning => colors.warning,
      AppLeadingAvatarTone.danger => colors.danger,
    };
    final initials = label
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .take(2)
        .map((part) => part.substring(0, 1).toUpperCase())
        .join();

    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(context.appLayout.radiusMd),
        border: Border.all(color: palette.border),
      ),
      child: icon == null
          ? Text(
              initials.isEmpty ? '?' : initials,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: palette.onSurface,
                fontWeight: FontWeight.w800,
              ),
            )
          : Icon(icon, size: size * 0.48, color: palette.base),
    );
  }
}

enum AppLeadingAvatarTone { brand, info, success, warning, danger }

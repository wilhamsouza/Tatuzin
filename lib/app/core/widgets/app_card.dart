import 'package:flutter/material.dart';

import '../../theme/app_design_tokens.dart';

enum AppCardTone {
  standard,
  muted,
  raised,
  brand,
  info,
  success,
  warning,
  danger,
}

class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding,
    this.onTap,
    this.gradient,
    this.color,
    this.borderColor,
    this.borderWidth = 1,
    this.borderRadius,
    this.tone = AppCardTone.standard,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;
  final Gradient? gradient;
  final Color? color;
  final Color? borderColor;
  final double borderWidth;
  final double? borderRadius;
  final AppCardTone tone;

  @override
  Widget build(BuildContext context) {
    final tokens = context.appColors;
    final layout = context.appLayout;
    final resolvedPadding = padding ?? EdgeInsets.all(layout.cardPadding);
    final resolvedRadius = borderRadius ?? layout.radiusXl;
    final toneColors = _resolveColors(tokens);
    final radius = BorderRadius.circular(resolvedRadius);
    final content = Padding(padding: resolvedPadding, child: child);

    return Card(
      clipBehavior: Clip.antiAlias,
      color: Colors.transparent,
      child: Ink(
        decoration: BoxDecoration(
          borderRadius: radius,
          gradient: gradient,
          color: gradient == null ? (color ?? toneColors.$1) : null,
          border: Border.all(
            color: borderColor ?? toneColors.$2,
            width: borderWidth,
          ),
        ),
        child: onTap == null
            ? content
            : InkWell(onTap: onTap, borderRadius: radius, child: content),
      ),
    );
  }

  (Color, Color) _resolveColors(AppColorTokens tokens) {
    switch (tone) {
      case AppCardTone.muted:
        return (tokens.sectionBackground, tokens.outlineSoft);
      case AppCardTone.raised:
        return (tokens.raisedBackground, tokens.outlineSoft);
      case AppCardTone.brand:
        return (tokens.brand.surface, tokens.brand.border);
      case AppCardTone.info:
        return (tokens.info.surface, tokens.info.border);
      case AppCardTone.success:
        return (tokens.success.surface, tokens.success.border);
      case AppCardTone.warning:
        return (tokens.warning.surface, tokens.warning.border);
      case AppCardTone.danger:
        return (tokens.danger.surface, tokens.danger.border);
      case AppCardTone.standard:
        return (tokens.cardBackground, tokens.outlineSoft);
    }
  }
}

import 'package:flutter/material.dart';

import '../../../../app/core/theme/app_design_tokens.dart';
import '../../../../app/core/widgets/app_card.dart';

class ReportShortcutCard extends StatelessWidget {
  const ReportShortcutCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
    this.palette,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;
  final AppTonePalette? palette;

  @override
  Widget build(BuildContext context) {
    final tokens = context.appColors;
    final layout = context.appLayout;
    final resolvedPalette = palette ?? tokens.brand;

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 240;
        return AppCard(
          onTap: onTap,
          borderRadius: layout.radiusLg,
          padding: EdgeInsets.all(compact ? 10 : layout.compactCardPadding),
          color: resolvedPalette.surface,
          borderColor: resolvedPalette.border,
          child: compact
              ? _CompactShortcutContent(
                  title: title,
                  subtitle: subtitle,
                  icon: icon,
                  palette: resolvedPalette,
                )
              : _WideShortcutContent(
                  title: title,
                  subtitle: subtitle,
                  icon: icon,
                  palette: resolvedPalette,
                ),
        );
      },
    );
  }
}

class _CompactShortcutContent extends StatelessWidget {
  const _CompactShortcutContent({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.palette,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final AppTonePalette palette;

  @override
  Widget build(BuildContext context) {
    final layout = context.appLayout;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _ShortcutIcon(icon: icon, palette: palette, size: 34),
            const Spacer(),
            Icon(
              Icons.chevron_right_rounded,
              size: layout.iconMd,
              color: palette.onSurface.withValues(alpha: 0.82),
            ),
          ],
        ),
        SizedBox(height: layout.space4),
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(
            context,
          ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
        ),
        SizedBox(height: layout.space2),
        Text(
          subtitle,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: palette.onSurface.withValues(alpha: 0.82),
          ),
        ),
      ],
    );
  }
}

class _WideShortcutContent extends StatelessWidget {
  const _WideShortcutContent({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.palette,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final AppTonePalette palette;

  @override
  Widget build(BuildContext context) {
    final layout = context.appLayout;

    return Row(
      children: [
        _ShortcutIcon(icon: icon, palette: palette, size: 40),
        SizedBox(width: layout.space5),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
              ),
              SizedBox(height: layout.space2),
              Text(
                subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: palette.onSurface.withValues(alpha: 0.82),
                ),
              ),
            ],
          ),
        ),
        SizedBox(width: layout.space3),
        Icon(
          Icons.chevron_right_rounded,
          size: layout.iconMd,
          color: palette.onSurface.withValues(alpha: 0.82),
        ),
      ],
    );
  }
}

class _ShortcutIcon extends StatelessWidget {
  const _ShortcutIcon({
    required this.icon,
    required this.palette,
    required this.size,
  });

  final IconData icon;
  final AppTonePalette palette;
  final double size;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(context.appLayout.radiusMd),
      ),
      child: SizedBox.square(
        dimension: size,
        child: Icon(icon, size: size * 0.52, color: palette.base),
      ),
    );
  }
}

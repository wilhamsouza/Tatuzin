import 'package:flutter/material.dart';

import '../constants/app_constants.dart';

class TatuzinBrandLockup extends StatelessWidget {
  const TatuzinBrandLockup({
    super.key,
    this.showTagline = true,
    this.compact = false,
    this.alignment = CrossAxisAlignment.start,
    this.caption,
    this.showCaption = false,
  });

  final bool showTagline;
  final bool compact;
  final CrossAxisAlignment alignment;
  final String? caption;
  final bool showCaption;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        TatuzinMascotBadge(size: compact ? 56 : 72),
        SizedBox(width: compact ? 12 : 14),
        Expanded(
          child: Column(
            crossAxisAlignment: alignment,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                AppConstants.appName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style:
                    (compact
                            ? theme.textTheme.headlineSmall
                            : theme.textTheme.headlineMedium)
                        ?.copyWith(
                          color: colorScheme.onSurface,
                          fontWeight: FontWeight.w900,
                          letterSpacing: compact ? -0.7 : -1.0,
                        ),
              ),
              if (showCaption) ...[
                SizedBox(height: compact ? 2 : 4),
                Text(
                  caption ?? AppConstants.brandLine,
                  maxLines: compact ? 2 : 3,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                    height: 1.25,
                  ),
                ),
              ],
              if (showTagline) ...[
                SizedBox(height: compact ? 6 : 8),
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: compact ? 10 : 12,
                    vertical: compact ? 5 : 6,
                  ),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer.withValues(alpha: 0.75),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    AppConstants.appSlogan,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: colorScheme.onPrimaryContainer,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class TatuzinMascotBadge extends StatelessWidget {
  const TatuzinMascotBadge({
    super.key,
    this.size = 64,
    this.showSurface = true,
  });

  final double size;
  final bool showSurface;

  static const _assetPath = 'assets/branding/logo-transparent.png';

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    final child = Padding(
      padding: EdgeInsets.all(size * 0.04),
      child: Image.asset(
        _assetPath,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
      ),
    );

    if (!showSurface) {
      return SizedBox(width: size, height: size, child: child);
    }

    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(size * 0.08),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(size * 0.28),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: child,
    );
  }
}

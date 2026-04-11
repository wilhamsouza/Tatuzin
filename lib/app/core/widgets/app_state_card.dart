import 'package:flutter/material.dart';

enum AppStateTone { neutral, loading, success, warning, error }

class AppStateCard extends StatelessWidget {
  const AppStateCard({
    super.key,
    required this.title,
    required this.message,
    this.icon,
    this.tone = AppStateTone.neutral,
    this.actionLabel,
    this.onAction,
    this.compact = false,
  });

  final String title;
  final String message;
  final IconData? icon;
  final AppStateTone tone;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final colors = _colors(colorScheme);
    final resolvedIcon = icon ?? _defaultIcon();

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      width: double.infinity,
      padding: EdgeInsets.all(compact ? 16 : 20),
      decoration: BoxDecoration(
        color: colors.$1,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.$3),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            child: tone == AppStateTone.loading
                ? SizedBox(
                    key: const ValueKey('loading'),
                    width: compact ? 28 : 32,
                    height: compact ? 28 : 32,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      valueColor: AlwaysStoppedAnimation<Color>(colors.$2),
                    ),
                  )
                : Container(
                    key: ValueKey(resolvedIcon),
                    width: compact ? 40 : 44,
                    height: compact ? 40 : 44,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.84),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      resolvedIcon,
                      size: compact ? 18 : 20,
                      color: colors.$2,
                    ),
                  ),
          ),
          SizedBox(height: compact ? 12 : 14),
          Text(
            title,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            message,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          if (actionLabel != null && onAction != null) ...[
            SizedBox(height: compact ? 12 : 14),
            FilledButton.tonal(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ],
      ),
    );
  }

  IconData _defaultIcon() {
    switch (tone) {
      case AppStateTone.loading:
        return Icons.hourglass_bottom_rounded;
      case AppStateTone.success:
        return Icons.check_circle_outline_rounded;
      case AppStateTone.warning:
        return Icons.info_outline_rounded;
      case AppStateTone.error:
        return Icons.error_outline_rounded;
      case AppStateTone.neutral:
        return Icons.inbox_outlined;
    }
  }

  (Color, Color, Color) _colors(ColorScheme scheme) {
    switch (tone) {
      case AppStateTone.loading:
        return (
          scheme.surfaceContainerLow,
          scheme.primary,
          scheme.outlineVariant,
        );
      case AppStateTone.success:
        return (
          scheme.tertiaryContainer.withValues(alpha: 0.62),
          scheme.onTertiaryContainer,
          scheme.tertiary.withValues(alpha: 0.22),
        );
      case AppStateTone.warning:
        return (
          scheme.secondaryContainer.withValues(alpha: 0.6),
          scheme.onSecondaryContainer,
          scheme.secondary.withValues(alpha: 0.22),
        );
      case AppStateTone.error:
        return (
          scheme.errorContainer.withValues(alpha: 0.72),
          scheme.onErrorContainer,
          scheme.error.withValues(alpha: 0.2),
        );
      case AppStateTone.neutral:
        return (scheme.surface, scheme.primary, scheme.outlineVariant);
    }
  }
}

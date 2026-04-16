import 'package:flutter/material.dart';

import '../../theme/app_design_tokens.dart';
import 'app_card.dart';

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
    final layout = context.appLayout;
    final colors = _colors(context.appColors);
    final resolvedIcon = icon ?? _defaultIcon();

    return AppCard(
      tone: _cardTone(),
      padding: EdgeInsets.all(compact ? layout.cardPadding : layout.space10),
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
                      valueColor: AlwaysStoppedAnimation<Color>(colors.base),
                    ),
                  )
                : DecoratedBox(
                    key: ValueKey(resolvedIcon),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.86),
                      borderRadius: BorderRadius.circular(layout.radiusMd),
                    ),
                    child: Padding(
                      padding: EdgeInsets.all(
                        compact ? layout.space4 : layout.space5,
                      ),
                      child: Icon(
                        resolvedIcon,
                        size: compact ? 18 : 20,
                        color: colors.onSurface,
                      ),
                    ),
                  ),
          ),
          SizedBox(height: compact ? layout.blockGap : layout.sectionGap),
          Text(
            title,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          SizedBox(height: layout.space2),
          Text(
            message,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurface),
          ),
          if (actionLabel != null && onAction != null) ...[
            SizedBox(height: compact ? layout.blockGap : layout.sectionGap),
            FilledButton.tonal(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ],
      ),
    );
  }

  AppTonePalette _colors(AppColorTokens tokens) {
    switch (tone) {
      case AppStateTone.loading:
        return tokens.info;
      case AppStateTone.success:
        return tokens.success;
      case AppStateTone.warning:
        return tokens.warning;
      case AppStateTone.error:
        return tokens.danger;
      case AppStateTone.neutral:
        return tokens.interactive;
    }
  }

  AppCardTone _cardTone() {
    switch (tone) {
      case AppStateTone.loading:
        return AppCardTone.info;
      case AppStateTone.success:
        return AppCardTone.success;
      case AppStateTone.warning:
        return AppCardTone.warning;
      case AppStateTone.error:
        return AppCardTone.danger;
      case AppStateTone.neutral:
        return AppCardTone.standard;
    }
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
}

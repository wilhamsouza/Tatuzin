import 'package:flutter/material.dart';

import '../../theme/app_design_tokens.dart';

class AppSectionTitle extends StatelessWidget {
  const AppSectionTitle({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onDarkBackground = false,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final bool onDarkBackground;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final layout = context.appLayout;
    final titleColor = onDarkBackground ? Colors.white : colorScheme.onSurface;
    final subtitleColor = onDarkBackground
        ? Colors.white.withValues(alpha: 0.78)
        : colorScheme.onSurfaceVariant;

    final header = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleMedium?.copyWith(
            color: titleColor,
            fontWeight: FontWeight.w700,
          ),
        ),
        if (subtitle?.isNotEmpty ?? false) ...[
          SizedBox(height: layout.space2),
          Text(
            subtitle!,
            style: theme.textTheme.bodySmall?.copyWith(color: subtitleColor),
          ),
        ],
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (trailing != null && constraints.maxWidth < 520) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              header,
              SizedBox(height: layout.blockGap),
              Align(alignment: Alignment.centerLeft, child: trailing!),
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: header),
            if (trailing != null) ...[
              SizedBox(width: layout.blockGap),
              Flexible(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: trailing!,
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

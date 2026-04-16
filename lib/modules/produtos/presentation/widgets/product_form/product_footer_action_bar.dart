import 'package:flutter/material.dart';

import '../../../../../app/core/widgets/app_bottom_action_bar.dart';

class ProductFooterActionBar extends StatelessWidget {
  const ProductFooterActionBar({
    super.key,
    required this.contextLabel,
    required this.primaryLabel,
    required this.isSaving,
    required this.onPressed,
  });

  final String contextLabel;
  final String primaryLabel;
  final bool isSaving;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return AppBottomActionBar(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            contextLabel,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: isSaving ? null : onPressed,
              icon: isSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_rounded),
              label: Text(primaryLabel),
            ),
          ),
        ],
      ),
    );
  }
}

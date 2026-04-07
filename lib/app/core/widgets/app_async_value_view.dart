import 'package:flutter/material.dart';

import '../constants/app_constants.dart';
import 'app_page_header.dart';

class AppAsyncValueView extends StatelessWidget {
  const AppAsyncValueView({
    required this.title,
    required this.message,
    this.icon = Icons.info_outline,
    this.actionLabel,
    this.onAction,
    this.isLoading = false,
    super.key,
  });

  const AppAsyncValueView.loading({
    required this.title,
    required this.message,
    super.key,
  }) : icon = Icons.hourglass_bottom_rounded,
       actionLabel = null,
       onAction = null,
       isLoading = true;

  const AppAsyncValueView.error({
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
    super.key,
  }) : icon = Icons.error_outline_rounded,
       isLoading = false;

  final String title;
  final String message;
  final IconData icon;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const AppPageHeader(
                  title: AppConstants.appName,
                  subtitle: AppConstants.appSlogan,
                  badgeLabel: 'Tatuzin local-first',
                  badgeIcon: Icons.auto_awesome_rounded,
                  emphasized: true,
                ),
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (isLoading)
                          const SizedBox(
                            height: 44,
                            width: 44,
                            child: CircularProgressIndicator(strokeWidth: 3),
                          )
                        else
                          Icon(icon, size: 44, color: colorScheme.primary),
                        const SizedBox(height: 20),
                        Text(
                          title,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.titleLarge,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          message,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                        if (actionLabel != null && onAction != null) ...[
                          const SizedBox(height: 20),
                          FilledButton(
                            onPressed: onAction,
                            child: Text(actionLabel!),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

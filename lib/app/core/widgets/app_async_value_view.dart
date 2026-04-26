import 'package:flutter/material.dart';

import 'app_page_header.dart';
import 'app_state_card.dart';
import 'tatuzin_brand.dart';

class AppAsyncValueView extends StatelessWidget {
  const AppAsyncValueView({
    required this.title,
    required this.message,
    this.icon = Icons.info_outline,
    this.actionLabel,
    this.onAction,
    this.secondaryActionLabel,
    this.onSecondaryAction,
    this.detailsMessage,
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
       secondaryActionLabel = null,
       onSecondaryAction = null,
       detailsMessage = null,
       isLoading = true;

  const AppAsyncValueView.error({
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.secondaryActionLabel,
    this.onSecondaryAction,
    this.detailsMessage,
    super.key,
  }) : icon = Icons.error_outline_rounded,
       isLoading = false;

  final String title;
  final String message;
  final IconData icon;
  final String? actionLabel;
  final VoidCallback? onAction;
  final String? secondaryActionLabel;
  final VoidCallback? onSecondaryAction;
  final String? detailsMessage;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight - 48,
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const TatuzinBrandLockup(),
                        const SizedBox(height: 16),
                        AppPageHeader(
                          title: title,
                          subtitle: message,
                          badgeLabel: isLoading ? 'Carregando' : 'Atencao',
                          badgeIcon: isLoading
                              ? Icons.hourglass_bottom_rounded
                              : Icons.info_outline_rounded,
                          emphasized: true,
                        ),
                        const SizedBox(height: 12),
                        AppStateCard(
                          title: isLoading
                              ? 'Preparando o Tatuzin'
                              : 'Precisamos de atencao',
                          message: isLoading
                              ? 'Organizando o ambiente para voce continuar trabalhando.'
                              : message,
                          icon: icon,
                          tone: isLoading
                              ? AppStateTone.loading
                              : AppStateTone.error,
                          actionLabel: actionLabel,
                          onAction: onAction,
                        ),
                        if (!isLoading &&
                            secondaryActionLabel != null &&
                            onSecondaryAction != null) ...[
                          const SizedBox(height: 12),
                          OutlinedButton(
                            onPressed: onSecondaryAction,
                            child: Text(secondaryActionLabel!),
                          ),
                        ],
                        if (!isLoading &&
                            detailsMessage != null &&
                            detailsMessage!.trim().isNotEmpty) ...[
                          const SizedBox(height: 12),
                          SelectableText(
                            detailsMessage!,
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/core/entitlements/plan_entitlements.dart';
import '../../../../app/core/formatters/app_formatters.dart';
import '../../../../app/core/session/session_provider.dart';
import '../../../../app/core/widgets/app_button.dart';
import '../../../../app/core/widgets/app_main_drawer.dart';
import '../../../../app/core/widgets/app_page_header.dart';
import '../../../../app/core/widgets/app_section_card.dart';
import '../../../../app/core/widgets/app_status_badge.dart';
import '../../domain/billing_models.dart';
import '../providers/billing_providers.dart';
import '../providers/checkout_launcher.dart';

class SubscriptionPage extends ConsumerWidget {
  const SubscriptionPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plansAsync = ref.watch(billingPlansProvider);
    final statusAsync = ref.watch(billingStatusProvider);
    final invoicesAsync = ref.watch(billingInvoicesProvider);
    final paymentMethodAsync = ref.watch(billingPaymentMethodProvider);
    final company = ref.watch(currentCompanyContextProvider);
    final controller = ref.watch(billingControllerProvider);
    final fallbackStatus = BillingStatus(
      companyId: company.remoteId ?? '',
      plan: company.plan,
      status: company.licenseStatus ?? 'active',
      currentPeriodStart: company.licenseStartsAt,
      currentPeriodEnd: null,
      expiresAt: company.licenseExpiresAt,
      provider: null,
      hasProviderSubscription: false,
      maskedProviderSubscriptionId: null,
      canManageBilling: false,
      nextPaymentDate: null,
      entitlements: company.entitlements,
    );
    final status = statusAsync.valueOrNull ?? fallbackStatus;

    return Scaffold(
      appBar: AppBar(title: const Text('Assinatura')),
      drawer: const AppMainDrawer(),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        children: [
          AppPageHeader(
            title: 'Assinatura',
            subtitle: 'Planos Tatuzin para liberar recursos no app.',
            badgeLabel: _planLabel(status.plan),
            badgeIcon: Icons.workspace_premium_outlined,
            emphasized: true,
          ),
          const SizedBox(height: 18),
          _BillingStatusCard(
            status: status,
            isLoading: statusAsync.isLoading || controller.isLoading,
            hasError: statusAsync.hasError,
            onRefresh: () => _refreshStatus(context, ref),
          ),
          if (_hasStateNotice(status)) ...[
            const SizedBox(height: 18),
            _BillingStateNotice(status: status),
          ],
          const SizedBox(height: 18),
          paymentMethodAsync.when(
            data: (paymentMethod) => _PaymentMethodCard(
              paymentMethod: paymentMethod,
              onRefresh: () => _refreshStatus(context, ref),
            ),
            loading: () => const AppSectionCard(
              title: 'Metodo de pagamento',
              child: LinearProgressIndicator(),
            ),
            error: (error, _) => AppSectionCard(
              title: 'Metodo de pagamento',
              subtitle: 'Nao foi possivel carregar o metodo agora.',
              child: AppButton.secondary(
                label: 'Tentar novamente',
                icon: Icons.refresh_rounded,
                onPressed: () => ref.invalidate(billingPaymentMethodProvider),
              ),
            ),
          ),
          const SizedBox(height: 18),
          invoicesAsync.when(
            data: (page) => _InvoicesCard(
              invoices: page.items,
              onRefresh: () => ref.invalidate(billingInvoicesProvider),
              onOpenInvoice: (invoice) =>
                  _openInvoice(context, ref, invoice.invoiceUrl),
            ),
            loading: () => const AppSectionCard(
              title: 'Cobrancas',
              child: LinearProgressIndicator(),
            ),
            error: (error, _) => AppSectionCard(
              title: 'Cobrancas',
              subtitle: 'Nao foi possivel carregar as cobrancas.',
              child: AppButton.secondary(
                label: 'Tentar novamente',
                icon: Icons.refresh_rounded,
                onPressed: () => ref.invalidate(billingInvoicesProvider),
              ),
            ),
          ),
          if (status.plan != PlanKey.free || status.cancelAtPeriodEnd) ...[
            const SizedBox(height: 18),
            _SubscriptionActionsCard(
              status: status,
              isBusy: controller.isLoading,
              onCancel: () => _cancelSubscription(context, ref),
              onResume: () => _resumeSubscription(context, ref),
            ),
          ],
          const SizedBox(height: 18),
          plansAsync.when(
            data: (plans) => _PlanCards(
              plans: plans,
              status: status,
              isBusy: controller.isLoading,
              onChangePlan: (plan) => _changePlan(context, ref, plan, status),
            ),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => AppSectionCard(
              title: 'Planos',
              subtitle: 'Nao foi possivel carregar os planos agora.',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('$error'),
                  const SizedBox(height: 12),
                  AppButton.secondary(
                    label: 'Tentar novamente',
                    icon: Icons.refresh_rounded,
                    onPressed: () => ref.invalidate(billingPlansProvider),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _changePlan(
    BuildContext context,
    WidgetRef ref,
    BillingPlan plan,
    BillingStatus status,
  ) async {
    if (status.plan == PlanKey.pro && plan.key == PlanKey.basic) {
      final confirmed = await _confirmAction(
        context,
        title: 'Mudar para Basico',
        message:
            'O downgrade sera agendado. Seu plano Pro permanece ativo ate o fim do periodo atual.',
        confirmLabel: 'Agendar downgrade',
      );
      if (!confirmed) {
        return;
      }
    }

    try {
      final result = await ref
          .read(billingControllerProvider.notifier)
          .changePlan(plan.key);
      if (!context.mounted) {
        return;
      }
      await _handleActionResult(context, ref, result);
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Nao foi possivel trocar o plano: $error')),
      );
    }
  }

  Future<void> _cancelSubscription(BuildContext context, WidgetRef ref) async {
    final confirmed = await _confirmAction(
      context,
      title: 'Cancelar assinatura',
      message:
          'Voce continuara com acesso ate o fim do periodo ja pago quando houver periodo vigente.',
      confirmLabel: 'Cancelar assinatura',
    );
    if (!confirmed) {
      return;
    }

    try {
      final result = await ref
          .read(billingControllerProvider.notifier)
          .cancelSubscription();
      if (!context.mounted) {
        return;
      }
      await _handleActionResult(context, ref, result);
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Nao foi possivel cancelar: $error')),
      );
    }
  }

  Future<void> _resumeSubscription(BuildContext context, WidgetRef ref) async {
    try {
      final result = await ref
          .read(billingControllerProvider.notifier)
          .resumeSubscription();
      if (!context.mounted) {
        return;
      }
      await _handleActionResult(context, ref, result);
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Nao foi possivel retomar: $error')),
      );
    }
  }

  Future<void> _handleActionResult(
    BuildContext context,
    WidgetRef ref,
    BillingActionResult result,
  ) async {
    final checkoutUrl = result.checkoutUrl;
    if (checkoutUrl != null && checkoutUrl.trim().isNotEmpty) {
      final launcher = ref.read(checkoutLauncherProvider);
      final opened = await launcher.openExternal(checkoutUrl);
      if (!context.mounted) {
        return;
      }
      if (!opened) {
        await _showCopyCheckoutDialog(context, launcher, checkoutUrl);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Apos o pagamento, seu plano sera atualizado automaticamente.',
            ),
          ),
        );
      }
    }

    if (!context.mounted) {
      return;
    }
    try {
      await _refreshStatus(context, ref, showSuccess: false);
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(result.message)));
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Acao enviada, mas nao foi possivel atualizar o status: $error',
          ),
        ),
      );
    }
  }

  Future<void> _openInvoice(
    BuildContext context,
    WidgetRef ref,
    String? invoiceUrl,
  ) async {
    if (invoiceUrl == null || invoiceUrl.trim().isEmpty) {
      return;
    }
    final launcher = ref.read(checkoutLauncherProvider);
    final opened = await launcher.openExternal(invoiceUrl);
    if (!context.mounted) {
      return;
    }
    if (!opened) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Nao foi possivel abrir a cobranca agora.'),
        ),
      );
    }
  }

  Future<void> _refreshStatus(
    BuildContext context,
    WidgetRef ref, {
    bool showSuccess = true,
  }) async {
    try {
      await ref.read(billingControllerProvider.notifier).refreshStatus();
      if (!context.mounted) {
        return;
      }
      if (showSuccess) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Status da assinatura atualizado.')),
        );
      }
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Nao foi possivel atualizar o status: $error')),
      );
    }
  }
}

class _BillingStatusCard extends StatelessWidget {
  const _BillingStatusCard({
    required this.status,
    required this.isLoading,
    required this.hasError,
    required this.onRefresh,
  });

  final BillingStatus status;
  final bool isLoading;
  final bool hasError;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return AppSectionCard(
      title: 'Plano atual',
      subtitle: hasError
          ? 'Mostrando os dados salvos da sessao. Tente atualizar novamente.'
          : 'Status lido do backend Tatuzin.',
      trailing: AppButton.secondary(
        label: isLoading ? 'Atualizando...' : 'Atualizar status',
        icon: Icons.refresh_rounded,
        compact: true,
        onPressed: isLoading ? null : onRefresh,
      ),
      child: Column(
        children: [
          _InfoRow(label: 'Plano', value: _planLabel(status.plan)),
          _InfoRow(label: 'Status', value: _statusLabel(status.status)),
          _InfoRow(
            label: 'Dispositivos',
            value: '${status.entitlements.limits.maxDevices}',
          ),
          _InfoRow(
            label: 'Funcionarios',
            value: '${status.entitlements.limits.maxEmployees}',
          ),
          if (status.nextPaymentDate != null)
            _InfoRow(
              label: 'Proximo pagamento',
              value: AppFormatters.shortDate(status.nextPaymentDate!),
            ),
          if (status.hasProviderSubscription)
            _InfoRow(
              label: 'Assinatura Mercado Pago',
              value: status.maskedProviderSubscriptionId == null
                  ? 'Vinculada'
                  : 'Vinculada (${status.maskedProviderSubscriptionId})',
            ),
        ],
      ),
    );
  }
}

class _BillingStateNotice extends StatelessWidget {
  const _BillingStateNotice({required this.status});

  final BillingStatus status;

  @override
  Widget build(BuildContext context) {
    final messages = <String>[];
    final pendingPlan = status.pendingPlan;
    if (pendingPlan == PlanKey.pro) {
      messages.add(
        'Upgrade para Pro solicitado. Ele sera ativado apos confirmacao do pagamento.',
      );
    } else if (pendingPlan == PlanKey.basic && status.plan == PlanKey.pro) {
      messages.add(
        'Downgrade para Basico agendado. Seu plano Pro continua ativo ate o fim do periodo atual.',
      );
    } else if (pendingPlan != null) {
      messages.add('Troca para ${_planLabel(pendingPlan)} em andamento.');
    }

    if (status.cancelAtPeriodEnd) {
      final end = status.currentPeriodEnd;
      messages.add(
        end == null
            ? 'Cancelamento agendado. Seu acesso permanece ativo enquanto houver periodo vigente.'
            : 'Cancelamento agendado. Seu acesso permanece ativo ate ${AppFormatters.shortDate(end)}.',
      );
    }

    final subscriptionStatus = status.billingSubscriptionStatus;
    if (subscriptionStatus != null &&
        subscriptionStatus.trim().isNotEmpty &&
        subscriptionStatus.toLowerCase() != status.status.toLowerCase()) {
      messages.add(
        'Status da assinatura: ${_statusLabel(subscriptionStatus)}.',
      );
    }

    if (messages.isEmpty) {
      return const SizedBox.shrink();
    }

    return AppSectionCard(
      title: 'Avisos da assinatura',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final message in messages) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.info_outline_rounded, size: 18),
                const SizedBox(width: 8),
                Expanded(child: Text(message)),
              ],
            ),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}

class _PaymentMethodCard extends StatelessWidget {
  const _PaymentMethodCard({
    required this.paymentMethod,
    required this.onRefresh,
  });

  final BillingPaymentMethod paymentMethod;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return AppSectionCard(
      title: 'Metodo de pagamento',
      subtitle: paymentMethod.unavailable
          ? paymentMethod.message ?? 'Metodo indisponivel no momento.'
          : 'Resumo seguro da assinatura vinculada.',
      trailing: paymentMethod.unavailable
          ? AppButton.secondary(
              label: 'Atualizar status',
              icon: Icons.refresh_rounded,
              compact: true,
              onPressed: onRefresh,
            )
          : null,
      child: Column(
        children: [
          _InfoRow(
            label: 'Provider',
            value: paymentMethod.provider ?? 'Nao vinculado',
          ),
          _InfoRow(
            label: 'Metodo',
            value: paymentMethod.hasPaymentMethod
                ? _paymentMethodLabel(paymentMethod)
                : 'Nao informado',
          ),
          if (paymentMethod.status != null)
            _InfoRow(
              label: 'Status',
              value: _statusLabel(paymentMethod.status!),
            ),
          if (paymentMethod.nextPaymentDate != null)
            _InfoRow(
              label: 'Proximo pagamento',
              value: AppFormatters.shortDate(paymentMethod.nextPaymentDate!),
            ),
          if (paymentMethod.maskedProviderSubscriptionId != null)
            _InfoRow(
              label: 'Assinatura',
              value: paymentMethod.maskedProviderSubscriptionId!,
            ),
        ],
      ),
    );
  }
}

class _InvoicesCard extends StatelessWidget {
  const _InvoicesCard({
    required this.invoices,
    required this.onRefresh,
    required this.onOpenInvoice,
  });

  final List<BillingInvoice> invoices;
  final VoidCallback onRefresh;
  final ValueChanged<BillingInvoice> onOpenInvoice;

  @override
  Widget build(BuildContext context) {
    if (invoices.isEmpty) {
      return AppSectionCard(
        title: 'Cobrancas',
        trailing: AppButton.secondary(
          label: 'Atualizar',
          icon: Icons.refresh_rounded,
          compact: true,
          onPressed: onRefresh,
        ),
        child: const Text('Nenhuma cobranca encontrada ainda.'),
      );
    }

    return AppSectionCard(
      title: 'Historico de cobrancas',
      trailing: AppButton.secondary(
        label: 'Atualizar',
        icon: Icons.refresh_rounded,
        compact: true,
        onPressed: onRefresh,
      ),
      child: Column(
        children: [
          for (final invoice in invoices) ...[
            _InvoiceTile(
              invoice: invoice,
              onOpen: () => onOpenInvoice(invoice),
            ),
            if (invoice != invoices.last) const Divider(height: 20),
          ],
        ],
      ),
    );
  }
}

class _InvoiceTile extends StatelessWidget {
  const _InvoiceTile({required this.invoice, required this.onOpen});

  final BillingInvoice invoice;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                AppFormatters.currencyFromCents(invoice.amountCents),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            AppStatusBadge(
              label: _invoiceStatusLabel(invoice.status),
              tone: _invoiceStatusTone(invoice.status),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (invoice.periodStart != null || invoice.periodEnd != null)
          Text(
            'Periodo: ${_periodLabel(invoice.periodStart, invoice.periodEnd)}',
          ),
        if (invoice.dueAt != null)
          Text('Vencimento: ${AppFormatters.shortDate(invoice.dueAt!)}'),
        if (invoice.paidAt != null)
          Text('Pagamento: ${AppFormatters.shortDate(invoice.paidAt!)}'),
        if (invoice.failedAt != null)
          Text('Falha: ${AppFormatters.shortDate(invoice.failedAt!)}'),
        if (invoice.invoiceUrl != null) ...[
          const SizedBox(height: 8),
          AppButton.secondary(
            label: 'Ver cobranca',
            icon: Icons.open_in_new_rounded,
            compact: true,
            onPressed: onOpen,
          ),
        ],
      ],
    );
  }
}

class _SubscriptionActionsCard extends StatelessWidget {
  const _SubscriptionActionsCard({
    required this.status,
    required this.isBusy,
    required this.onCancel,
    required this.onResume,
  });

  final BillingStatus status;
  final bool isBusy;
  final VoidCallback onCancel;
  final VoidCallback onResume;

  @override
  Widget build(BuildContext context) {
    return AppSectionCard(
      title: 'Acoes da assinatura',
      subtitle:
          'O plano so muda depois que o backend confirmar o status com seguranca.',
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          if (status.cancelAtPeriodEnd)
            AppButton.primary(
              label: isBusy ? 'Aguarde...' : 'Retomar assinatura',
              icon: Icons.replay_rounded,
              onPressed: isBusy ? null : onResume,
            ),
          if (status.plan != PlanKey.free)
            AppButton.secondary(
              label: isBusy ? 'Aguarde...' : 'Cancelar assinatura',
              icon: Icons.cancel_outlined,
              onPressed: isBusy ? null : onCancel,
            ),
        ],
      ),
    );
  }
}

class _PlanCards extends StatelessWidget {
  const _PlanCards({
    required this.plans,
    required this.status,
    required this.isBusy,
    required this.onChangePlan,
  });

  final List<BillingPlan> plans;
  final BillingStatus status;
  final bool isBusy;
  final ValueChanged<BillingPlan> onChangePlan;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cardWidth = constraints.maxWidth < 360
            ? constraints.maxWidth
            : 340.0;
        return Wrap(
          spacing: 14,
          runSpacing: 14,
          children: [
            for (final plan in plans)
              SizedBox(
                width: cardWidth,
                child: _PlanCard(
                  plan: plan,
                  currentPlan: status.plan,
                  pendingPlan: status.pendingPlan,
                  canManageBilling: status.canManageBilling,
                  isBusy: isBusy,
                  onChangePlan: () => onChangePlan(plan),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.plan,
    required this.currentPlan,
    required this.pendingPlan,
    required this.canManageBilling,
    required this.isBusy,
    required this.onChangePlan,
  });

  final BillingPlan plan;
  final PlanKey currentPlan;
  final PlanKey? pendingPlan;
  final bool canManageBilling;
  final bool isBusy;
  final VoidCallback onChangePlan;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isCurrent = plan.key == currentPlan;
    final isPending = pendingPlan == plan.key;
    final isUpgrade =
        plan.key != PlanKey.free &&
        _planRank(plan.key) > _planRank(currentPlan);
    final isProDowngrade =
        currentPlan == PlanKey.pro && plan.key == PlanKey.basic;
    final isActionable = (isUpgrade || isProDowngrade) && !isPending;
    final buttonLabel = isCurrent
        ? 'Plano atual'
        : isPending
        ? 'Aguardando'
        : !canManageBilling
        ? 'Somente owner'
        : isUpgrade
        ? 'Assinar ${plan.name}'
        : isProDowngrade
        ? 'Mudar para ${plan.name}'
        : 'Incluso';

    return AppSectionCard(
      title: plan.name,
      trailing: isCurrent
          ? const AppStatusBadge(
              label: 'Atual',
              tone: AppStatusTone.success,
              icon: Icons.check_circle_outline_rounded,
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            plan.priceCents == 0
                ? 'Gratis'
                : '${AppFormatters.currencyFromCents(plan.priceCents)}/mes',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(plan.description),
          const SizedBox(height: 14),
          for (final feature in plan.featuresSummary) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.check_rounded, size: 18),
                const SizedBox(width: 8),
                Expanded(child: Text(feature)),
              ],
            ),
            const SizedBox(height: 8),
          ],
          const SizedBox(height: 12),
          AppButton.primary(
            label: isBusy ? 'Aguarde...' : buttonLabel,
            icon: isCurrent ? Icons.check_rounded : Icons.open_in_new_rounded,
            onPressed: isBusy || isCurrent || !canManageBilling || !isActionable
                ? null
                : onChangePlan,
            expand: true,
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> _showCopyCheckoutDialog(
  BuildContext context,
  CheckoutLauncher launcher,
  String checkoutUrl,
) {
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Nao foi possivel abrir o checkout'),
      content: SelectableText(checkoutUrl),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Fechar'),
        ),
        FilledButton(
          onPressed: () async {
            await launcher.copyLink(checkoutUrl);
            if (context.mounted) {
              Navigator.of(context).pop();
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('Link copiado.')));
            }
          },
          child: const Text('Copiar link'),
        ),
      ],
    ),
  );
}

Future<bool> _confirmAction(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Voltar'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}

bool _hasStateNotice(BillingStatus status) {
  return status.pendingPlan != null ||
      status.cancelAtPeriodEnd ||
      (status.billingSubscriptionStatus?.trim().isNotEmpty ?? false);
}

String _paymentMethodLabel(BillingPaymentMethod paymentMethod) {
  final type = paymentMethod.paymentMethodType ?? 'Metodo';
  final lastFour = paymentMethod.lastFour;
  if (lastFour == null || lastFour.trim().isEmpty) {
    return type;
  }
  return '$type final $lastFour';
}

String _periodLabel(DateTime? start, DateTime? end) {
  if (start != null && end != null) {
    return '${AppFormatters.shortDate(start)} a ${AppFormatters.shortDate(end)}';
  }
  if (start != null) {
    return 'desde ${AppFormatters.shortDate(start)}';
  }
  if (end != null) {
    return 'ate ${AppFormatters.shortDate(end)}';
  }
  return 'Nao informado';
}

String _invoiceStatusLabel(String status) {
  switch (status.trim().toLowerCase()) {
    case 'paid':
      return 'Paga';
    case 'pending':
      return 'Pendente';
    case 'in_process':
      return 'Processando';
    case 'rejected':
    case 'failed':
      return 'Falhou';
    case 'cancelled':
    case 'canceled':
      return 'Cancelada';
    case 'refunded':
      return 'Estornada';
    default:
      return status.trim().isEmpty ? 'Desconhecida' : status;
  }
}

AppStatusTone _invoiceStatusTone(String status) {
  switch (status.trim().toLowerCase()) {
    case 'paid':
      return AppStatusTone.success;
    case 'pending':
    case 'in_process':
      return AppStatusTone.warning;
    case 'rejected':
    case 'failed':
      return AppStatusTone.danger;
    case 'cancelled':
    case 'canceled':
    case 'refunded':
      return AppStatusTone.neutral;
    default:
      return AppStatusTone.info;
  }
}

String _planLabel(PlanKey plan) {
  switch (plan) {
    case PlanKey.free:
      return 'Free';
    case PlanKey.basic:
      return 'Basico';
    case PlanKey.pro:
      return 'Pro';
  }
}

String _statusLabel(String status) {
  switch (status.trim().toLowerCase()) {
    case 'active':
      return 'Ativa';
    case 'trial':
      return 'Trial';
    case 'suspended':
      return 'Suspensa';
    case 'expired':
      return 'Expirada';
    default:
      return status;
  }
}

int _planRank(PlanKey plan) {
  switch (plan) {
    case PlanKey.free:
      return 0;
    case PlanKey.basic:
      return 1;
    case PlanKey.pro:
      return 2;
  }
}

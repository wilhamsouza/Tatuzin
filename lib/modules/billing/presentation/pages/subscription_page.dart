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
import '../providers/billing_checkout_return.dart';
import '../providers/billing_providers.dart';
import '../providers/checkout_launcher.dart';

class SubscriptionPage extends ConsumerWidget {
  const SubscriptionPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plansAsync = ref.watch(billingPlansProvider);
    final statusAsync = ref.watch(billingStatusProvider);
    final company = ref.watch(currentCompanyContextProvider);
    final session = ref.watch(appSessionProvider);
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
      canManageBilling: session.isCompanyOwner,
      nextPaymentDate: null,
      pendingPlan: null,
      pendingPlanRequestedAt: null,
      entitlements: company.entitlements,
    );
    final status = statusAsync.valueOrNull ?? fallbackStatus;
    final canManageSubscription =
        status.canManageBilling || session.isCompanyOwner;

    return Scaffold(
      appBar: AppBar(title: const Text('Assinatura e planos')),
      drawer: const AppMainDrawer(),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        children: [
          AppPageHeader(
            title: 'Assinatura e planos',
            subtitle:
                'Veja o plano atual e escolha o melhor acesso para sua empresa.',
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
          if (!canManageSubscription) ...[
            const SizedBox(height: 18),
            const AppSectionCard(
              title: 'Modo leitura',
              subtitle: 'Apenas o dono da empresa pode gerenciar a assinatura.',
              child: Text(
                'Você pode consultar o plano atual. Para contratar ou trocar de plano, peça ao dono da empresa para fazer a alteração.',
              ),
            ),
          ],
          const SizedBox(height: 18),
          plansAsync.when(
            data: (plans) => _PlanCards(
              plans: plans,
              status: status,
              canManageSubscription: canManageSubscription,
              isBusy: controller.isLoading,
              onSubscribe: (plan) => _subscribe(context, ref, plan),
            ),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => AppSectionCard(
              title: 'Planos',
              subtitle: 'Não foi possível carregar os planos agora.',
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

  Future<void> _subscribe(
    BuildContext context,
    WidgetRef ref,
    BillingPlan plan,
  ) async {
    try {
      final result = await ref
          .read(billingControllerProvider.notifier)
          .subscribe(plan.key);
      if (!context.mounted) {
        return;
      }
      final checkoutUrl = result.checkoutUrl;
      if (checkoutUrl == null || checkoutUrl.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Este já é o seu plano atual.')),
        );
        return;
      }

      final launcher = ref.read(checkoutLauncherProvider);
      final opened = await launcher.openExternal(checkoutUrl);
      if (!context.mounted) {
        return;
      }
      if (!opened) {
        await _showCopyCheckoutDialog(context, launcher, checkoutUrl);
        return;
      }

      await BillingCheckoutReturnStorage().markPending();
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Ao voltar do Mercado Pago, vamos tentar atualizar sua assinatura automaticamente.',
          ),
        ),
      );
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Nao foi possivel iniciar a assinatura agora. Tente novamente em alguns minutos.',
          ),
        ),
      );
    }
  }

  Future<void> _refreshStatus(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(billingControllerProvider.notifier).refreshStatus();
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Status da assinatura atualizado.')),
      );
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Nao foi possivel atualizar o status agora. Tente novamente em alguns instantes.',
          ),
        ),
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
          ? 'Mostrando os dados salvos da sessão. Tente atualizar novamente.'
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
            label: 'Funcionários',
            value: '${status.entitlements.limits.maxEmployees}',
          ),
          if (status.nextPaymentDate != null)
            _InfoRow(
              label: 'Próximo pagamento',
              value: AppFormatters.shortDate(status.nextPaymentDate!),
            ),
          if (status.pendingPlan == PlanKey.pro)
            const _InfoRow(
              label: 'Mercado Pago',
              value: 'Aguardando confirmacao do Mercado Pago',
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

class _PlanCards extends StatelessWidget {
  const _PlanCards({
    required this.plans,
    required this.status,
    required this.canManageSubscription,
    required this.isBusy,
    required this.onSubscribe,
  });

  final List<BillingPlan> plans;
  final BillingStatus status;
  final bool canManageSubscription;
  final bool isBusy;
  final ValueChanged<BillingPlan> onSubscribe;

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
                  canManageBilling: canManageSubscription,
                  isBusy: isBusy,
                  onSubscribe: () => onSubscribe(plan),
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
    required this.onSubscribe,
  });

  final BillingPlan plan;
  final PlanKey currentPlan;
  final PlanKey? pendingPlan;
  final bool canManageBilling;
  final bool isBusy;
  final VoidCallback onSubscribe;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isCurrent = plan.key == currentPlan;
    final isPending = pendingPlan == plan.key;
    final isActionablePlan = plan.key != PlanKey.free && !isCurrent;
    final buttonLabel = isPending
        ? 'Aguardando confirmacao'
        : isCurrent
        ? 'Plano atual'
        : !canManageBilling
        ? 'Apenas o dono da empresa pode alterar'
        : plan.key == PlanKey.free
        ? 'Plano gratuito'
        : currentPlan == PlanKey.free
        ? 'Assinar plano ${_planLabel(plan.key)}'
        : 'Trocar para ${_planLabel(plan.key)}';

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
                ? 'Grátis'
                : '${AppFormatters.currencyFromCents(plan.priceCents)}/mês',
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
            onPressed:
                isBusy ||
                    isCurrent ||
                    isPending ||
                    !canManageBilling ||
                    !isActionablePlan
                ? null
                : onSubscribe,
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
      title: const Text('Não foi possível abrir o checkout'),
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

String _planLabel(PlanKey plan) {
  switch (plan) {
    case PlanKey.free:
      return 'Free';
    case PlanKey.basic:
      return 'Básico';
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

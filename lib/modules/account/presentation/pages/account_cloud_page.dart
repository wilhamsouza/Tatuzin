import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/core/entitlements/plan_entitlements.dart';
import '../../../../app/core/formatters/app_formatters.dart';
import '../../../../app/core/session/app_session.dart';
import '../../../../app/core/session/auth_provider.dart';
import '../../../../app/core/session/session_feedback.dart';
import '../../../../app/core/session/session_provider.dart';
import '../../../../app/core/sync/sync_providers.dart';
import '../../../../app/core/widgets/app_button.dart';
import '../../../../app/core/widgets/app_main_drawer.dart';
import '../../../../app/core/widgets/app_page_header.dart';
import '../../../../app/core/widgets/app_section_card.dart';
import '../../../../app/core/widgets/app_status_badge.dart';
import '../../../../app/routes/route_names.dart';
import '../../../billing/domain/billing_models.dart';
import '../../../billing/presentation/providers/billing_providers.dart';
import '../../../system/presentation/providers/system_providers.dart';
import '../providers/account_cloud_providers.dart';
import '../support/cloud_sync_feedback.dart';

class AccountCloudPage extends ConsumerStatefulWidget {
  const AccountCloudPage({super.key});

  @override
  ConsumerState<AccountCloudPage> createState() => _AccountCloudPageState();
}

class _AccountCloudPageState extends ConsumerState<AccountCloudPage> {
  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider);
    final authStatus = ref.watch(authStatusProvider);
    final session = ref.watch(appSessionProvider);
    final company = ref.watch(currentCompanyContextProvider);
    final accountCloud = ref.watch(accountCloudStatusProvider);
    final syncActionState = ref.watch(catalogSyncControllerProvider);
    final billingStatusAsync = authStatus.isRemoteAuthenticated
        ? ref.watch(billingStatusProvider)
        : null;
    final billingStatus =
        billingStatusAsync?.valueOrNull ?? _fallbackBillingStatus(session);
    final canManageSubscription =
        billingStatus.canManageBilling || session.isCompanyOwner;

    return Scaffold(
      appBar: AppBar(titleSpacing: 0, title: const _AccountAppBarTitle()),
      drawer: const AppMainDrawer(),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        children: [
          AppPageHeader(
            title: 'Conta',
            subtitle: 'Acesso, assinatura e nuvem',
            badgeLabel: accountCloud.commercialStatusLabel,
            badgeIcon: accountCloud.commercialStatusIcon,
            emphasized: true,
          ),
          const SizedBox(height: 18),
          _SessionCard(
            authState: authState,
            authStatus: authStatus,
            session: session,
            accountCloud: accountCloud,
            onRestoreSession: () => _restoreSession(context, ref),
            onSignOut: () => _signOutToLocalMode(context, ref),
          ),
          const SizedBox(height: 18),
          _SubscriptionSummaryCard(
            status: billingStatus,
            isLoading: billingStatusAsync?.isLoading ?? false,
            hasError: billingStatusAsync?.hasError ?? false,
            canManageSubscription: canManageSubscription,
          ),
          const SizedBox(height: 18),
          _CloudSummaryCard(
            accountCloud: accountCloud,
            isRemoteAuthenticated: authStatus.isRemoteAuthenticated,
            cloudEnabled: company.allowsCloudSync,
            isSyncing: syncActionState.isLoading,
            onSync: syncActionState.isLoading
                ? null
                : () => _syncNow(context, ref),
            onDetails: () => context.goNamed(AppRouteNames.backup),
          ),
        ],
      ),
    );
  }

  Future<void> _restoreSession(BuildContext context, WidgetRef ref) async {
    try {
      final session = await ref
          .read(authControllerProvider.notifier)
          .restoreRemoteSession();
      if (!context.mounted) {
        return;
      }
      final messenger = ScaffoldMessenger.of(context);
      if (session == null) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Não encontramos uma sessão salva neste aparelho.'),
          ),
        );
        return;
      }
      messenger.showSnackBar(
        const SnackBar(content: Text('Sessão restaurada com sucesso.')),
      );
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            friendlySessionFeedbackMessage(
              error,
              fallback: 'Não foi possível restaurar sua sessão agora.',
            ),
          ),
        ),
      );
    }
  }

  Future<void> _signOutToLocalMode(BuildContext context, WidgetRef ref) async {
    try {
      final pendingCount = ref.read(accountCloudStatusProvider).pendingCount;
      if (pendingCount > 0) {
        final decision = await _confirmSignOutWithPendingSync(
          context,
          pendingCount,
        );
        if (decision == _SignOutDecision.cancel || !context.mounted) {
          return;
        }
        if (decision == _SignOutDecision.syncFirst) {
          await ref
              .read(autoSyncCoordinatorProvider)
              .runNowIfEligible(reason: 'manual-before-sign-out');
          return;
        }
      }

      await ref.read(authControllerProvider.notifier).signOutCurrentSession();
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Você saiu da conta. Entre novamente para acessar a empresa.',
          ),
        ),
      );
      context.goNamed(AppRouteNames.login);
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            friendlySessionFeedbackMessage(
              error,
              fallback: 'Não foi possível sair da conta agora.',
            ),
          ),
        ),
      );
    }
  }

  Future<void> _syncNow(BuildContext context, WidgetRef ref) async {
    try {
      final result = await ref
          .read(catalogSyncControllerProvider.notifier)
          .syncAll();
      ref.invalidate(accountCloudAttentionItemsProvider);
      if (!context.mounted) {
        return;
      }
      final currentCloudStatus = ref.read(accountCloudStatusProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(cloudSyncResultMessage(result, currentCloudStatus)),
        ),
      );
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível sincronizar agora: $error')),
      );
    }
  }

  Future<_SignOutDecision> _confirmSignOutWithPendingSync(
    BuildContext context,
    int pendingCount,
  ) async {
    return await showDialog<_SignOutDecision>(
          context: context,
          builder: (context) {
            return AlertDialog(
              title: const Text('Dados aguardando envio'),
              content: Text(
                'Existem $pendingCount itens aguardando envio. '
                'Eles continuarao salvos neste dispositivo.',
              ),
              actions: [
                TextButton(
                  onPressed: () =>
                      Navigator.of(context).pop(_SignOutDecision.cancel),
                  child: const Text('Cancelar'),
                ),
                TextButton(
                  onPressed: () =>
                      Navigator.of(context).pop(_SignOutDecision.syncFirst),
                  child: const Text('Sincronizar antes'),
                ),
                FilledButton(
                  onPressed: () =>
                      Navigator.of(context).pop(_SignOutDecision.signOut),
                  child: const Text('Encerrar sessão'),
                ),
              ],
            );
          },
        ) ??
        _SignOutDecision.cancel;
  }
}

class _AccountAppBarTitle extends StatelessWidget {
  const _AccountAppBarTitle();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('Conta'),
        Text(
          'Acesso, assinatura e nuvem',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _SessionCard extends StatelessWidget {
  const _SessionCard({
    required this.authState,
    required this.authStatus,
    required this.session,
    required this.accountCloud,
    required this.onRestoreSession,
    required this.onSignOut,
  });

  final AsyncValue<void> authState;
  final AuthStatusSnapshot authStatus;
  final AppSession session;
  final AccountCloudStatusSnapshot accountCloud;
  final VoidCallback onRestoreSession;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AppSectionCard(
      title: 'Sessão atual',
      subtitle: authStatus.isAuthenticated
          ? 'Acesso liberado neste aparelho.'
          : 'Entre para vincular este aparelho a sua empresa.',
      trailing: AppStatusBadge(
        label: accountCloud.accountModeLabel,
        tone: authStatus.isRemoteAuthenticated
            ? AppStatusTone.success
            : AppStatusTone.neutral,
        icon: authStatus.isRemoteAuthenticated
            ? Icons.verified_user_rounded
            : Icons.person_outline_rounded,
      ),
      child: Column(
        children: [
          _InfoRow(label: 'Usuário', value: authStatus.userLabel),
          if (authStatus.email?.trim().isNotEmpty ?? false)
            _InfoRow(label: 'E-mail', value: authStatus.email!.trim()),
          _InfoRow(label: 'Perfil', value: _profileLabel(session)),
          _InfoRow(label: 'Dispositivo', value: _deviceLabel(session)),
          _InfoRow(
            label: 'Sessão iniciada',
            value: AppFormatters.shortDateTime(session.startedAt),
          ),
          const SizedBox(height: 10),
          if (authStatus.isRemoteAuthenticated)
            AppButton.secondary(
              label: authState.isLoading ? 'Encerrando...' : 'Encerrar sessão',
              icon: Icons.logout_rounded,
              onPressed: authState.isLoading ? null : onSignOut,
              expand: true,
            )
          else if (authStatus.canAttemptRemoteLogin) ...[
            AppButton.primary(
              label: authState.isLoading ? 'Abrindo...' : 'Entrar com conta',
              icon: Icons.login_rounded,
              onPressed: authState.isLoading
                  ? null
                  : () => context.goNamed(AppRouteNames.login),
              expand: true,
            ),
            const SizedBox(height: 10),
            AppButton.secondary(
              label: 'Restaurar sessão',
              icon: Icons.refresh_rounded,
              onPressed: authState.isLoading ? null : onRestoreSession,
              expand: true,
            ),
          ] else
            Text(
              'Conecte este dispositivo a internet para entrar pela primeira vez.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }
}

class _SubscriptionSummaryCard extends StatelessWidget {
  const _SubscriptionSummaryCard({
    required this.status,
    required this.isLoading,
    required this.hasError,
    required this.canManageSubscription,
  });

  final BillingStatus status;
  final bool isLoading;
  final bool hasError;
  final bool canManageSubscription;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AppSectionCard(
      title: 'Assinatura',
      subtitle: hasError
          ? 'Mostrando os dados salvos da sessão.'
          : 'Plano e acesso comercial da empresa.',
      trailing: AppStatusBadge(
        label: _statusLabel(status.status),
        tone: _subscriptionTone(status.status),
        icon: Icons.workspace_premium_outlined,
      ),
      child: Column(
        children: [
          _InfoRow(label: 'Plano', value: _planLabel(status.plan)),
          _InfoRow(label: 'Status', value: _statusLabel(status.status)),
          if (status.nextPaymentDate != null)
            _InfoRow(
              label: 'Próxima cobrança',
              value: AppFormatters.shortDate(status.nextPaymentDate!),
            )
          else if (status.expiresAt != null)
            _InfoRow(
              label: 'Validade',
              value: AppFormatters.shortDate(status.expiresAt!),
            ),
          if (isLoading)
            const _InfoRow(
              label: 'Atualização',
              value: 'Consultando assinatura...',
            ),
          const SizedBox(height: 10),
          if (canManageSubscription)
            AppButton.secondary(
              label: 'Ver planos e fatura',
              icon: Icons.receipt_long_rounded,
              onPressed: () => context.goNamed(AppRouteNames.subscription),
              expand: true,
            )
          else
            Text(
              'Apenas o dono da empresa pode gerenciar planos e cobranças.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }
}

class _CloudSummaryCard extends StatelessWidget {
  const _CloudSummaryCard({
    required this.accountCloud,
    required this.isRemoteAuthenticated,
    required this.cloudEnabled,
    required this.isSyncing,
    required this.onSync,
    required this.onDetails,
  });

  final AccountCloudStatusSnapshot accountCloud;
  final bool isRemoteAuthenticated;
  final bool cloudEnabled;
  final bool isSyncing;
  final VoidCallback? onSync;
  final VoidCallback onDetails;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AppSectionCard(
      title: 'Nuvem',
      subtitle: 'Dados protegidos na nuvem.',
      trailing: AppStatusBadge(
        label: accountCloud.commercialStatusLabel,
        tone: accountCloud.commercialTone,
        icon: accountCloud.commercialStatusIcon,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            accountCloud.commercialStatusMessage,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 14),
          _InfoRow(
            label: 'Ultima sincronizacao',
            value: accountCloud.lastSyncedAt == null
                ? 'Ainda não concluída'
                : AppFormatters.shortDateTime(accountCloud.lastSyncedAt!),
          ),
          if (accountCloud.pendingCount > 0)
            _InfoRow(
              label: 'Aguardando envio',
              value: '${accountCloud.pendingCount}',
            ),
          if (!cloudEnabled && isRemoteAuthenticated)
            const _InfoRow(label: 'Disponibilidade', value: 'Uso local ativo'),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              if (isRemoteAuthenticated)
                AppButton.primary(
                  label: isSyncing ? 'Sincronizando...' : 'Sincronizar',
                  icon: Icons.sync_rounded,
                  compact: true,
                  onPressed: onSync,
                ),
              AppButton.secondary(
                label: 'Ver detalhes',
                icon: Icons.cloud_outlined,
                compact: true,
                onPressed: onDetails,
              ),
            ],
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
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 136,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

enum _SignOutDecision { cancel, syncFirst, signOut }

BillingStatus _fallbackBillingStatus(AppSession session) {
  final company = session.company;
  return BillingStatus(
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
}

String _profileLabel(AppSession session) {
  final employeeRole = session.employee?.role.trim();
  if (employeeRole != null && employeeRole.isNotEmpty) {
    return _roleLabel(employeeRole);
  }
  final membershipRole = session.membership?.role.trim();
  if (membershipRole != null && membershipRole.isNotEmpty) {
    return _roleLabel(membershipRole);
  }
  return session.user.roleLabel;
}

String _roleLabel(String role) {
  switch (role.trim().toUpperCase()) {
    case 'OWNER':
      return 'Dono da empresa';
    case 'ADMIN':
      return 'Administrador';
    case 'OPERATOR':
      return 'Operador';
    default:
      return role;
  }
}

String _deviceLabel(AppSession session) {
  if (session.isOfflineFallback) {
    return 'Este aparelho offline';
  }
  if (session.hasClientInstanceId) {
    return 'Este aparelho vinculado';
  }
  return 'Este aparelho';
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
      return status.trim().isEmpty ? 'Não informado' : status;
  }
}

AppStatusTone _subscriptionTone(String status) {
  switch (status.trim().toLowerCase()) {
    case 'active':
    case 'trial':
      return AppStatusTone.success;
    case 'suspended':
    case 'expired':
      return AppStatusTone.warning;
    default:
      return AppStatusTone.neutral;
  }
}

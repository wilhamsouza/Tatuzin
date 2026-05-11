import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/core/formatters/app_formatters.dart';
import '../../../../app/core/session/auth_provider.dart';
import '../../../../app/core/session/session_feedback.dart';
import '../../../../app/core/session/session_provider.dart';
import '../../../../app/core/sync/sync_display_state.dart';
import '../../../../app/core/sync/sync_batch_result.dart';
import '../../../../app/core/sync/sync_providers.dart';
import '../../../../app/core/sync/sync_queue_feature_summary.dart';
import '../../../../app/core/widgets/app_button.dart';
import '../../../../app/core/widgets/app_main_drawer.dart';
import '../../../../app/core/widgets/app_page_header.dart';
import '../../../../app/core/widgets/app_section_card.dart';
import '../../../../app/core/widgets/app_status_badge.dart';
import '../../../../app/routes/route_names.dart';
import '../../../system/presentation/providers/system_providers.dart';
import '../providers/account_cloud_providers.dart';

class AccountCloudPage extends ConsumerWidget {
  const AccountCloudPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final authState = ref.watch(authControllerProvider);
    final authStatus = ref.watch(authStatusProvider);
    final company = ref.watch(currentCompanyContextProvider);
    final accountCloud = ref.watch(accountCloudStatusProvider);
    final autoSyncSnapshot = ref.watch(autoSyncSnapshotProvider);
    final syncActionState = ref.watch(catalogSyncControllerProvider);
    final syncSummariesAsync = authStatus.isRemoteAuthenticated
        ? ref.watch(syncQueueFeatureSummariesProvider)
        : null;
    final hasSyncAttention =
        authStatus.isRemoteAuthenticated &&
        (accountCloud.errorCount > 0 ||
            accountCloud.blockedCount > 0 ||
            accountCloud.conflictCount > 0);
    final syncIssuesAsync = hasSyncAttention
        ? ref.watch(accountCloudAttentionItemsProvider)
        : null;
    final internalAccess = ref.watch(internalMobileSurfaceAccessProvider);

    return Scaffold(
      appBar: AppBar(titleSpacing: 0, title: const _AccountCloudAppBarTitle()),
      drawer: const AppMainDrawer(),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        children: [
          AppPageHeader(
            title: 'Conta e nuvem',
            subtitle:
                'Veja sua conta, sua empresa e como a nuvem está ajudando o seu negócio sem entrar em detalhes técnicos.',
            badgeLabel: accountCloud.statusLabel,
            badgeIcon: accountCloud.icon,
            emphasized: true,
          ),
          if (hasSyncAttention) ...[
            const SizedBox(height: 18),
            AppSectionCard(
              title: 'Itens com revisão',
              subtitle:
                  'Detalhes reais da fila local para entender o que precisa de nova tentativa ou ajuste.',
              child: syncIssuesAsync!.when(
                data: (issues) {
                  if (issues.isEmpty) {
                    return Text(
                      'A fila informou atenção, mas nenhum item detalhado foi encontrado nesta leitura.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    );
                  }
                  return Column(
                    children: [
                      for (final issue in issues) ...[
                        _SyncIssueTile(issue: issue),
                        const SizedBox(height: 10),
                      ],
                    ],
                  );
                },
                loading: () => Text(
                  'Carregando detalhes da fila...',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                error: (error, _) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Não foi possível carregar os detalhes da fila: $error',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colorScheme.error,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 12),
                    AppButton.secondary(
                      label: 'Tentar novamente',
                      icon: Icons.refresh_rounded,
                      compact: true,
                      onPressed: () =>
                          ref.invalidate(accountCloudAttentionItemsProvider),
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 18),
          if (authStatus.isRemoteAuthenticated) ...[
            AppSectionCard(
              title: 'Fila de sincronização',
              subtitle:
                  'Resumo por módulo para saber o que ainda precisa sair deste aparelho.',
              child: syncSummariesAsync!.when(
                data: (summaries) {
                  final activeSummaries = summaries
                      .where(
                        (summary) =>
                            summary.pendingForDisplay > 0 ||
                            summary.activeProcessingCount > 0 ||
                            summary.errorCount > 0 ||
                            summary.blockedCount > 0 ||
                            summary.conflictCount > 0,
                      )
                      .toList(growable: false);
                  if (activeSummaries.isEmpty) {
                    return Text(
                      'Nenhuma pendência local aguardando envio.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    );
                  }
                  return Column(
                    children: [
                      for (final summary in activeSummaries) ...[
                        _SyncFeatureSummaryTile(summary: summary),
                        const SizedBox(height: 10),
                      ],
                    ],
                  );
                },
                loading: () => Text(
                  'Carregando resumo da fila...',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                error: (error, _) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Não foi possível carregar o resumo da fila: $error',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colorScheme.error,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 12),
                    AppButton.secondary(
                      label: 'Tentar novamente',
                      icon: Icons.refresh_rounded,
                      compact: true,
                      onPressed: () =>
                          ref.invalidate(syncQueueFeatureSummariesProvider),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),
          ],
          AppSectionCard(
            title: 'Sua conta',
            subtitle:
                'Informacoes simples sobre quem esta usando o app neste aparelho.',
            child: Column(
              children: [
                _InfoRow(label: 'Usuario', value: authStatus.userLabel),
                if (authStatus.email?.trim().isNotEmpty ?? false)
                  _InfoRow(label: 'E-mail', value: authStatus.email!.trim()),
                _InfoRow(label: 'Sessão', value: accountCloud.accountModeLabel),
                const _InfoRow(
                  label: 'Acesso local',
                  value: 'Sempre disponível neste aparelho',
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          AppSectionCard(
            title: 'Sua empresa',
            subtitle:
                'Resumo comercial da empresa conectada a esta instalação do Tatuzin.',
            child: Column(
              children: [
                _InfoRow(label: 'Empresa', value: authStatus.companyLabel),
                _InfoRow(label: 'Plano', value: authStatus.licensePlanLabel),
                _InfoRow(
                  label: 'Licença',
                  value: authStatus.licenseStatusLabel,
                ),
                _InfoRow(
                  label: 'Validade',
                  value: authStatus.licenseExpiresAt == null
                      ? 'Não informada'
                      : AppFormatters.shortDate(authStatus.licenseExpiresAt!),
                ),
                _InfoRow(
                  label: 'Uso na nuvem',
                  value: company.allowsCloudSync
                      ? 'Disponível'
                      : 'Uso local disponível',
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          AppSectionCard(
            title: 'Assinatura e planos',
            subtitle:
                'Veja planos, status e opções para liberar novos recursos.',
            child: AppButton.secondary(
              label: 'Ver planos',
              icon: Icons.workspace_premium_outlined,
              onPressed: () => context.goNamed(AppRouteNames.subscription),
              expand: true,
            ),
          ),
          const SizedBox(height: 18),
          AppSectionCard(
            title: 'Nuvem',
            subtitle:
                'Um status claro para você saber se a conta está conectada e se a nuvem está acompanhando sua empresa.',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    AppStatusBadge(
                      label: accountCloud.statusLabel,
                      tone: accountCloud.tone,
                      icon: accountCloud.icon,
                    ),
                    AppStatusBadge(
                      label: accountCloud.accountModeLabel,
                      tone: authStatus.isRemoteAuthenticated
                          ? AppStatusTone.info
                          : AppStatusTone.neutral,
                      icon: authStatus.isRemoteAuthenticated
                          ? Icons.verified_user_rounded
                          : Icons.offline_bolt_rounded,
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  accountCloud.statusMessage,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),
                _InfoRow(
                  label: 'Status da nuvem',
                  value: accountCloud.cloudAvailabilityLabel,
                ),
                if (authStatus.isRemoteAuthenticated) ...[
                  _InfoRow(
                    label: 'Em envio agora',
                    value: '${accountCloud.syncingNowCount}',
                  ),
                  _InfoRow(
                    label: 'Pendencias',
                    value: '${accountCloud.pendingCount}',
                  ),
                  _InfoRow(
                    label: 'Com erro',
                    value: '${accountCloud.errorCount}',
                  ),
                  _InfoRow(
                    label: 'Bloqueados',
                    value: '${accountCloud.blockedCount}',
                  ),
                  if (accountCloud.conflictCount > 0)
                    _InfoRow(
                      label: 'Conflitos',
                      value: '${accountCloud.conflictCount}',
                    ),
                  _InfoRow(
                    label: 'Última sincronização',
                    value: accountCloud.lastSyncedAt == null
                        ? 'Ainda não concluída'
                        : AppFormatters.shortDateTime(
                            accountCloud.lastSyncedAt!,
                          ),
                  ),
                  _InfoRow(
                    label: 'Última tentativa',
                    value: autoSyncSnapshot.lastStartedAt == null
                        ? 'Ainda não iniciada'
                        : AppFormatters.shortDateTime(
                            autoSyncSnapshot.lastStartedAt!,
                          ),
                  ),
                  _InfoRow(
                    label: 'Última conclusão',
                    value: autoSyncSnapshot.lastFinishedAt == null
                        ? 'Ainda não concluída'
                        : AppFormatters.shortDateTime(
                            autoSyncSnapshot.lastFinishedAt!,
                          ),
                  ),
                  if (accountCloud.nextRetryAt != null)
                    _InfoRow(
                      label: 'Próxima tentativa',
                      value: AppFormatters.shortDateTime(
                        accountCloud.nextRetryAt!,
                      ),
                    ),
                  const SizedBox(height: 12),
                  AppButton.secondary(
                    label: syncActionState.isLoading
                        ? 'Sincronizando...'
                        : 'Sincronizar agora',
                    icon: Icons.sync_rounded,
                    compact: true,
                    onPressed: syncActionState.isLoading
                        ? null
                        : () => _syncNow(context, ref),
                  ),
                ] else if (accountCloud.supportingValue != null)
                  _InfoRow(
                    label: accountCloud.supportingLabel ?? 'Atualização',
                    value: accountCloud.supportingValue!,
                  ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          AppSectionCard(
            title: 'Sessão',
            subtitle:
                'Entre, saia ou recupere sua conta para manter a empresa local vinculada ao seu login.',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!authStatus.isRemoteAuthenticated &&
                    authStatus.canAttemptRemoteLogin) ...[
                  AppButton.primary(
                    label: authState.isLoading
                        ? 'Abrindo sua conta...'
                        : 'Entrar com conta',
                    icon: Icons.login_rounded,
                    onPressed: authState.isLoading
                        ? null
                        : () => context.goNamed(AppRouteNames.login),
                    expand: true,
                  ),
                  const SizedBox(height: 12),
                  AppButton.secondary(
                    label: 'Restaurar sessão',
                    icon: Icons.refresh_rounded,
                    onPressed: authState.isLoading
                        ? null
                        : () => _restoreSession(context, ref),
                    expand: true,
                  ),
                ] else if (authStatus.isRemoteAuthenticated) ...[
                  AppButton.primary(
                    label: authState.isLoading
                        ? 'Saindo da conta...'
                        : 'Sair da conta',
                    icon: Icons.logout_rounded,
                    onPressed: authState.isLoading
                        ? null
                        : () => _signOutToLocalMode(context, ref),
                    expand: true,
                  ),
                ],
                const SizedBox(height: 12),
                Text(
                  authStatus.canAttemptRemoteLogin
                      ? authStatus.isRemoteAuthenticated
                            ? 'Ao sair da conta, o Tatuzin volta para a tela de entrada neste dispositivo.'
                            : 'Entre uma vez com internet para liberar a base local da sua empresa neste dispositivo.'
                      : 'Conecte-se a internet para entrar no Tatuzin pela primeira vez neste dispositivo.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          AppSectionCard(
            title: 'Ajuda e suporte',
            subtitle:
                'Quando a internet oscila, a operação local continua disponível apenas para sessões já validadas.',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Se você precisar renovar o acesso, entre novamente na sua conta. Em caso de internet instável, o Tatuzin usa a empresa local já vinculada a esta conta.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                if (authStatus.isPlatformAdmin &&
                    internalAccess.canOpenTechnicalSystem) ...[
                  const SizedBox(height: 16),
                  Text(
                    'Acesso interno',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'O admin web e a superficie administrativa principal. Os atalhos abaixo permanecem apenas como apoio interno dentro do app.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      AppButton.secondary(
                        label: 'Ferramentas internas',
                        icon: Icons.build_circle_outlined,
                        compact: true,
                        onPressed: () =>
                            context.goNamed(AppRouteNames.technicalSystem),
                      ),
                      if (internalAccess.canOpenAdminCloud)
                        AppButton.secondary(
                          label: 'Admin interno de apoio',
                          icon: Icons.admin_panel_settings_outlined,
                          compact: true,
                          onPressed: () => context.goNamed(AppRouteNames.admin),
                        ),
                    ],
                  ),
                ],
              ],
            ),
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
            'Voce saiu da conta. Entre novamente para acessar a empresa.',
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_syncResultMessage(result))));
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
              title: const Text('Pendencias aguardando envio'),
              content: Text(
                'Existem $pendingCount pendências aguardando envio. '
                'Elas continuarao salvas neste dispositivo.',
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
                  child: const Text('Tentar sincronizar antes'),
                ),
                FilledButton(
                  onPressed: () =>
                      Navigator.of(context).pop(_SignOutDecision.signOut),
                  child: const Text('Sair mesmo assim'),
                ),
              ],
            );
          },
        ) ??
        _SignOutDecision.cancel;
  }
}

String _syncResultMessage(SyncBatchResult result) {
  final hasAttention =
      result.failedCount > 0 ||
      result.blockedCount > 0 ||
      result.conflictCount > 0;
  if (!hasAttention) {
    return '${result.message} Enviados: ${result.syncedCount}. Falhas: ${result.failedCount}.';
  }

  final reviewHint = result.conflictCount > 0
      ? ' A revisão de conflitos será disponibilizada em uma próxima atualização.'
      : '';
  return '${result.message}$reviewHint';
}

class _AccountCloudAppBarTitle extends StatelessWidget {
  const _AccountCloudAppBarTitle();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('Conta e nuvem'),
        Text(
          'Licença, empresa e sincronização',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

enum _SignOutDecision { cancel, syncFirst, signOut }

class _SyncFeatureSummaryTile extends StatelessWidget {
  const _SyncFeatureSummaryTile({required this.summary});

  final SyncQueueFeatureSummary summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final nextRetryAt = summary.nextRetryAt;

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    summary.displayName,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                AppStatusBadge(
                  label: summary.displayState.label,
                  tone: summary.hasAttention
                      ? AppStatusTone.warning
                      : summary.hasActiveProcessing
                      ? AppStatusTone.info
                      : AppStatusTone.neutral,
                  icon: summary.hasAttention
                      ? Icons.error_outline_rounded
                      : summary.hasActiveProcessing
                      ? Icons.sync_rounded
                      : Icons.schedule_send_rounded,
                ),
              ],
            ),
            const SizedBox(height: 8),
            _IssueLine(
              label: 'Pendentes',
              value: '${summary.pendingForDisplay}',
            ),
            _IssueLine(
              label: 'Em envio',
              value: '${summary.activeProcessingCount}',
            ),
            _IssueLine(label: 'Com erro', value: '${summary.errorCount}'),
            _IssueLine(label: 'Bloqueados', value: '${summary.blockedCount}'),
            if (summary.conflictCount > 0)
              _IssueLine(label: 'Conflitos', value: '${summary.conflictCount}'),
            if (summary.lastProcessedAt != null)
              _IssueLine(
                label: 'Ultimo processamento',
                value: AppFormatters.shortDateTime(summary.lastProcessedAt!),
              ),
            if (nextRetryAt != null)
              _IssueLine(
                label: 'Próxima tentativa',
                value: AppFormatters.shortDateTime(nextRetryAt),
              ),
            if (summary.lastError?.trim().isNotEmpty == true)
              _IssueLine(label: 'Ultimo erro', value: summary.lastError!),
          ],
        ),
      ),
    );
  }
}

class _SyncIssueTile extends ConsumerWidget {
  const _SyncIssueTile({required this.issue});

  final AccountCloudSyncIssue issue;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final nextRetryAt = issue.nextRetryAt;

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    '${issue.entityLabel} - ${issue.operationLabel}',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                AppStatusBadge(
                  label: issue.statusLabel,
                  tone: AppStatusTone.warning,
                  icon: Icons.error_outline_rounded,
                ),
              ],
            ),
            const SizedBox(height: 8),
            _IssueLine(label: 'ID local', value: '${issue.localId}'),
            if (issue.localUuid != null)
              _IssueLine(label: 'UUID local', value: issue.localUuid!),
            _IssueLine(
              label: 'ID remoto',
              value: issue.remoteId?.trim().isNotEmpty == true
                  ? issue.remoteId!
                  : 'Ainda não criado',
            ),
            _IssueLine(label: 'Endpoint', value: issue.endpoint),
            if (issue.httpStatusCode != null)
              _IssueLine(label: 'HTTP', value: '${issue.httpStatusCode}'),
            _IssueLine(label: 'Mensagem', value: issue.message),
            _IssueLine(
              label: 'Atualizado',
              value: AppFormatters.shortDateTime(issue.updatedAt),
            ),
            _IssueLine(
              label: 'Próxima tentativa',
              value: nextRetryAt == null
                  ? 'Sem retry automatico'
                  : AppFormatters.shortDateTime(nextRetryAt),
            ),
            const SizedBox(height: 10),
            AppButton.secondary(
              label: 'Tentar novamente',
              icon: Icons.refresh_rounded,
              compact: true,
              onPressed: () async {
                await ref
                    .read(catalogSyncControllerProvider.notifier)
                    .retryFeatures([issue.featureKey]);
                ref.invalidate(accountCloudAttentionItemsProvider);
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _IssueLine extends StatelessWidget {
  const _IssueLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '$label: ',
              style: TextStyle(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
            TextSpan(text: value),
          ],
        ),
        style: theme.textTheme.bodySmall,
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
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 136,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/core/app_context/data_access_policy.dart';
import '../../../../app/core/config/app_data_mode.dart';
import '../../../../app/core/config/app_environment.dart';
import '../../../../app/core/formatters/app_formatters.dart';
import '../../../../app/core/network/endpoint_config.dart';
import '../../../../app/core/network/remote_feature_diagnostic.dart';
import '../../../../app/core/session/auth_provider.dart';
import '../../../../app/core/session/session_provider.dart';
import '../../../../app/core/sync/sync_feature_summary.dart';
import '../../../../app/core/sync/sync_queue_feature_summary.dart';
import '../../../../app/core/sync/sync_reconciliation_result.dart';
import '../../../../app/core/sync/sync_repair_action.dart';
import '../../../../app/core/sync/sync_repair_action_type.dart';
import '../../../../app/core/sync/sync_repair_decision.dart';
import '../../../../app/core/widgets/app_main_drawer.dart';
import '../../../../app/core/widgets/app_page_header.dart';
import '../../../../app/core/widgets/app_section_card.dart';
import '../../../../app/core/widgets/app_status_badge.dart';
import '../../../../app/routes/route_names.dart';
import '../providers/system_providers.dart';
import '../widgets/sync_audit_card.dart';
import '../widgets/sync_feature_card.dart';
import '../widgets/sync_repair_action_sheet.dart';
import '../widgets/sync_repair_card.dart';
import '../widgets/sync_reconciliation_card.dart';

class SystemPage extends ConsumerStatefulWidget {
  const SystemPage({super.key});

  @override
  ConsumerState<SystemPage> createState() => _SystemPageState();
}

class _SystemPageState extends ConsumerState<SystemPage> {
  late final TextEditingController _endpointController;
  late final FocusNode _endpointFocusNode;
  late final TextEditingController _emailController;
  late final TextEditingController _passwordController;

  @override
  void initState() {
    super.initState();
    final environment = ref.read(appEnvironmentProvider);
    _endpointController = TextEditingController(
      text: environment.endpointConfig.baseUrl ?? '',
    );
    _endpointFocusNode = FocusNode();
    _emailController = TextEditingController(text: 'admin@simples.local');
    _passwordController = TextEditingController(text: '123456');
  }

  @override
  void dispose() {
    _endpointController.dispose();
    _endpointFocusNode.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final environment = ref.watch(appEnvironmentProvider);
    final session = ref.watch(appSessionProvider);
    final accessPolicy = ref.watch(appDataAccessPolicyProvider);
    final guard = ref.watch(sessionGuardProvider);
    final authState = ref.watch(authControllerProvider);
    final authStatus = ref.watch(authStatusProvider);
    final backendStatusAsync = ref.watch(backendConnectionStatusProvider);
    final remoteDiagnosticsAsync = ref.watch(remoteDiagnosticsProvider);
    final syncSummariesAsync = ref.watch(syncReadinessSummaryProvider);
    final queueSummariesAsync = ref.watch(syncQueueFeatureSummariesProvider);
    final syncHealth = ref.watch(syncHealthOverviewProvider);
    final batchSyncState = ref.watch(catalogSyncControllerProvider);
    final reconciliationState = ref.watch(syncReconciliationControllerProvider);
    final repairState = ref.watch(syncRepairControllerProvider);
    final repairDecisionsByFeature = ref.watch(
      syncRepairDecisionsByFeatureProvider,
    );
    final repairSummary = ref.watch(syncRepairSummaryProvider);
    final auditLogsAsync = ref.watch(syncAuditLogsProvider);
    final theme = Theme.of(context);
    final queueSummaries =
        queueSummariesAsync.valueOrNull ?? const <SyncQueueFeatureSummary>[];
    final reconciliationResults =
        reconciliationState.valueOrNull ?? const <SyncReconciliationResult>[];
    final supplierSummary = _findQueueSummary(queueSummaries, 'suppliers');
    final categorySummary = _findQueueSummary(queueSummaries, 'categories');
    final productSummary = _findQueueSummary(queueSummaries, 'products');
    final customerSummary = _findQueueSummary(queueSummaries, 'customers');
    final purchaseSummary = _findQueueSummary(queueSummaries, 'purchases');
    final salesSummary = _findQueueSummary(queueSummaries, 'sales');
    final financialEventSummary = _findQueueSummary(
      queueSummaries,
      'financial_events',
    );
    final cashEventSummary = _findQueueSummary(queueSummaries, 'cash_events');
    final supplierReconciliation = _findReconciliationResult(
      reconciliationResults,
      'suppliers',
    );
    final categoryReconciliation = _findReconciliationResult(
      reconciliationResults,
      'categories',
    );
    final productReconciliation = _findReconciliationResult(
      reconciliationResults,
      'products',
    );
    final customerReconciliation = _findReconciliationResult(
      reconciliationResults,
      'customers',
    );
    final purchaseReconciliation = _findReconciliationResult(
      reconciliationResults,
      'purchases',
    );
    final salesReconciliation = _findReconciliationResult(
      reconciliationResults,
      'sales',
    );
    final financialReconciliation = _findReconciliationResult(
      reconciliationResults,
      'financial_events',
    );
    final reconciliationOverview = _buildReconciliationOverview(
      reconciliationResults,
    );
    final supplierRepairs =
        repairDecisionsByFeature['suppliers'] ?? const <SyncRepairDecision>[];
    final categoryRepairs =
        repairDecisionsByFeature['categories'] ?? const <SyncRepairDecision>[];
    final productRepairs =
        repairDecisionsByFeature['products'] ?? const <SyncRepairDecision>[];
    final customerRepairs =
        repairDecisionsByFeature['customers'] ?? const <SyncRepairDecision>[];
    final purchaseRepairs =
        repairDecisionsByFeature['purchases'] ?? const <SyncRepairDecision>[];
    final salesRepairs =
        repairDecisionsByFeature['sales'] ?? const <SyncRepairDecision>[];
    final financialRepairs =
        repairDecisionsByFeature['financial_events'] ??
        const <SyncRepairDecision>[];
    final canRunManualSync =
        environment.dataMode == AppDataMode.futureHybridReady &&
        authStatus.isRemoteAuthenticated &&
        authStatus.cloudSyncEnabled;
    final currentEndpointText = environment.endpointConfig.baseUrl ?? '';

    if (!_endpointFocusNode.hasFocus &&
        _endpointController.text.trim() != currentEndpointText) {
      _setEndpointControllerText(currentEndpointText);
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Sistema')),
      drawer: const AppMainDrawer(),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        children: [
          const AppPageHeader(
            title: 'Sistema',
            subtitle:
                'Cockpit tecnico do Tatuzin para sessao, ambiente, sincronizacao, reconciliacao e repair mode.',
            badgeLabel: 'Painel de conex\u00e3o e sess\u00e3o',
            badgeIcon: Icons.settings_ethernet_rounded,
            emphasized: true,
          ),
          const SizedBox(height: 18),
          AppSectionCard(
            title: 'Sessao e tenant ativos',
            subtitle:
                'Contexto operacional centralizado para conviver com sessao local, mock e remota real.',
            trailing: AppStatusBadge(
              label: authStatus.sessionLabel,
              tone: authStatus.isRemoteAuthenticated
                  ? AppStatusTone.success
                  : authStatus.isMockAuthenticated
                  ? AppStatusTone.info
                  : AppStatusTone.warning,
              icon: authStatus.isRemoteAuthenticated
                  ? Icons.verified_user_outlined
                  : authStatus.isMockAuthenticated
                  ? Icons.science_outlined
                  : Icons.offline_bolt_rounded,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _InfoRow(label: 'Usuario', value: authStatus.userLabel),
                _InfoRow(label: 'Perfil', value: session.user.roleLabel),
                _InfoRow(
                  label: 'E-mail ativo',
                  value: authStatus.email ?? 'Nao autenticado',
                ),
                _InfoRow(
                  label: 'Empresa ativa',
                  value: authStatus.companyLabel,
                ),
                _InfoRow(
                  label: 'Plano cloud',
                  value: authStatus.licensePlanLabel,
                ),
                _InfoRow(
                  label: 'Status da licenca',
                  value: authStatus.licenseStatusLabel,
                ),
                _InfoRow(label: 'Cloud/sync', value: authStatus.cloudSyncLabel),
                _InfoRow(
                  label: 'Validade',
                  value: authStatus.licenseExpiresAt == null
                      ? 'Sem vencimento'
                      : AppFormatters.shortDate(authStatus.licenseExpiresAt!),
                ),
                _InfoRow(
                  label: 'Tenant remoto',
                  value: session.company.hasRemoteIdentity
                      ? session.company.remoteId!
                      : 'Nao vinculado',
                ),
                _InfoRow(
                  label: 'Inicio da sessao',
                  value: AppFormatters.shortDateTime(session.startedAt),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          AppSectionCard(
            title: 'Modo de dados e endpoint',
            subtitle:
                'Controle central do ambiente sem levar backend para as telas operacionais.',
            trailing: AppStatusBadge(
              label: accessPolicy.strategyLabel,
              tone: AppStatusTone.success,
              icon: Icons.storage_rounded,
            ),
            child: _buildDataModeSection(context, environment, guard, theme),
          ),
          const SizedBox(height: 18),
          AppSectionCard(
            title: 'API real de desenvolvimento',
            subtitle:
                'Saude do backend local e validacao do tenant remoto sem acoplar vendas, caixa ou relatorios a HTTP.',
            child: backendStatusAsync.when(
              data: (status) => _buildBackendStatusSection(status),
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (error, _) => Text(
                error.toString(),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ),
          ),
          const SizedBox(height: 18),
          AppSectionCard(
            title: 'Autenticacao remota real',
            subtitle:
                'Login incremental para desenvolvimento local. O app continua operando offline mesmo sem sessao remota.',
            trailing: AppStatusBadge(
              label: authStatus.isRemoteAuthenticated
                  ? 'Sessao remota ativa'
                  : 'Sem sessao remota',
              tone: authStatus.isRemoteAuthenticated
                  ? AppStatusTone.success
                  : AppStatusTone.neutral,
              icon: authStatus.isRemoteAuthenticated
                  ? Icons.lock_open_rounded
                  : Icons.lock_outline_rounded,
            ),
            child: _buildRemoteAuthSection(context, authState, authStatus),
          ),
          const SizedBox(height: 18),
          AppSectionCard(
            title: 'Autenticacao mock',
            subtitle:
                'Ferramenta de diagnostico preservada para testar contexto remoto sem depender do backend real.',
            child: _buildMockAuthSection(context, authState, authStatus),
          ),
          const SizedBox(height: 18),
          AppSectionCard(
            title: 'Diagnostico remoto por feature',
            subtitle:
                'Fornecedores, categorias, produtos, clientes, compras, vendas, eventos financeiros e espelho de caixa ja validam endpoint real. O financeiro remoto continua como espelho seguro, nunca como fonte de verdade nesta fase.',
            child: remoteDiagnosticsAsync.when(
              data: (diagnostics) => Column(
                children: diagnostics
                    .map(
                      (diagnostic) =>
                          _RemoteDiagnosticTile(diagnostic: diagnostic),
                    )
                    .toList(),
              ),
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (error, _) => Text(
                error.toString(),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ),
          ),
          const SizedBox(height: 18),
          AppSectionCard(
            title: 'Saude da sincronizacao',
            subtitle:
                'Visao consolidada da fila persistida, retries, bloqueios por dependencia e conflitos iniciais dos cadastros sincronizaveis.',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _ModeChip(
                      label: '${syncHealth.totalPending} pendente(s)',
                      icon: Icons.pending_actions_rounded,
                    ),
                    _ModeChip(
                      label: '${syncHealth.totalProcessing} processando',
                      icon: Icons.sync_rounded,
                    ),
                    _ModeChip(
                      label: '${syncHealth.totalSynced} sincronizado(s)',
                      icon: Icons.cloud_done_outlined,
                    ),
                    _ModeChip(
                      label: '${syncHealth.totalErrors} erro(s)',
                      icon: Icons.error_outline_rounded,
                    ),
                    _ModeChip(
                      label: '${syncHealth.totalBlocked} bloqueado(s)',
                      icon: Icons.link_off_rounded,
                    ),
                    _ModeChip(
                      label: '${syncHealth.totalConflicts} conflito(s)',
                      icon: Icons.warning_amber_rounded,
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  syncHealth.lastProcessedAt == null
                      ? 'Ainda sem processamento concluido nesta base local.'
                      : 'Ultimo processamento de fila em ${AppFormatters.shortDateTime(syncHealth.lastProcessedAt!)}.',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  'Tentativas acumuladas na fila: ${syncHealth.totalAttempts}.',
                  style: theme.textTheme.bodyMedium,
                ),
                if (syncHealth.nextRetryAt != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Proximo retry automatico elegivel em ${AppFormatters.shortDateTime(syncHealth.nextRetryAt!)}.',
                    style: theme.textTheme.bodyMedium,
                  ),
                ],
                if (syncHealth.lastErrorAt != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Ultima falha registrada em ${AppFormatters.shortDateTime(syncHealth.lastErrorAt!)}.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    FilledButton.icon(
                      onPressed: batchSyncState.isLoading || !canRunManualSync
                          ? null
                          : () => _handleSyncAll(context),
                      icon: const Icon(Icons.cloud_sync_outlined),
                      label: Text(
                        batchSyncState.isLoading
                            ? 'Sincronizando...'
                            : 'Sincronizar tudo',
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: batchSyncState.isLoading || !canRunManualSync
                          ? null
                          : () => _handleRetryPending(context),
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Reprocessar pendentes'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          AppSectionCard(
            title: 'Fila de sincronizacao por feature',
            subtitle:
                'Processamento ordenado de fornecedores, categorias, produtos, clientes, compras e vendas, sempre preservando o SQLite como base operacional local e o backend como espelho progressivo.',
            child: Column(
              children: [
                SyncFeatureCard(
                  title: 'Fornecedores',
                  summary: supplierSummary,
                  description: canRunManualSync
                      ? 'Primeira etapa das compras remotas. Garante vinculo consistente antes do envio das compras.'
                      : 'Entre com login remoto e ative o modo hibrido pronto para sincronizar os fornecedores.',
                  buttonLabel: 'Sincronizar fornecedores',
                  isEnabled: canRunManualSync,
                  isLoading: batchSyncState.isLoading,
                  onPressed: () => _handleSupplierSync(context),
                ),
                const SizedBox(height: 12),
                SyncFeatureCard(
                  title: 'Categorias',
                  summary: categorySummary,
                  description: canRunManualSync
                      ? 'Primeira etapa da fila. Consolida dependencias de catalogo antes do push de produtos.'
                      : 'Entre com login remoto e ative o modo hibrido pronto para sincronizar as categorias.',
                  buttonLabel: 'Sincronizar categorias',
                  isEnabled: canRunManualSync,
                  isLoading: batchSyncState.isLoading,
                  onPressed: () => _handleCategorySync(context),
                ),
                const SizedBox(height: 12),
                SyncFeatureCard(
                  title: 'Produtos',
                  summary: productSummary,
                  description: canRunManualSync
                      ? 'Respeita dependencia de categoria remota, aplica retry controlado e detecta conflito basico por updatedAt.'
                      : 'Entre com login remoto e ative o modo hibrido pronto para sincronizar os produtos.',
                  buttonLabel: 'Sincronizar produtos',
                  isEnabled: canRunManualSync,
                  isLoading: batchSyncState.isLoading,
                  onPressed: () => _handleProductSync(context),
                ),
                const SizedBox(height: 12),
                SyncFeatureCard(
                  title: 'Clientes',
                  summary: customerSummary,
                  description: canRunManualSync
                      ? 'Mantem o cadastro local offline, reprocessa falhas elegiveis e aplica soft delete remoto com seguranca.'
                      : 'Entre com login remoto e ative o modo hibrido pronto para sincronizar os clientes.',
                  buttonLabel: 'Sincronizar clientes',
                  isEnabled: canRunManualSync,
                  isLoading: batchSyncState.isLoading,
                  onPressed: () => _handleClientSync(context),
                ),
                const SizedBox(height: 12),
                SyncFeatureCard(
                  title: 'Compras',
                  summary: purchaseSummary,
                  description: canRunManualSync
                      ? 'Espelha compras locais com itens e pagamentos, sem reaplicar estoque ou caixa no retorno remoto.'
                      : 'Entre com login remoto e ative o modo hibrido pronto para sincronizar as compras.',
                  buttonLabel: 'Sincronizar compras',
                  isEnabled: canRunManualSync,
                  isLoading: batchSyncState.isLoading,
                  onPressed: () => _handlePurchaseSync(context),
                ),
                const SizedBox(height: 12),
                SyncFeatureCard(
                  title: 'Vendas',
                  summary: salesSummary,
                  description: canRunManualSync
                      ? 'Espelha vendas locais ativas no backend com idempotencia por localUuid. Caixa, fiado, lucro e relatorios continuam 100% locais nesta fase.'
                      : 'Entre com login remoto e ative o modo hibrido pronto para espelhar as vendas locais.',
                  buttonLabel: 'Sincronizar vendas',
                  isEnabled: canRunManualSync,
                  isLoading: batchSyncState.isLoading,
                  onPressed: () => _handleSalesSync(context),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          AppSectionCard(
            title: 'Eventos financeiros remotos',
            subtitle:
                'Cancelamentos de venda e pagamentos de fiado entram em uma trilha unica de eventos financeiros. O backend apenas espelha os eventos; caixa, fiado, lucro e relatorios continuam locais.',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    FilledButton.icon(
                      onPressed: batchSyncState.isLoading || !canRunManualSync
                          ? null
                          : () => _handleFinancialSyncAll(context),
                      icon: const Icon(Icons.account_balance_wallet_outlined),
                      label: const Text('Sincronizar eventos'),
                    ),
                    OutlinedButton.icon(
                      onPressed: batchSyncState.isLoading || !canRunManualSync
                          ? null
                          : () => _handleFinancialRetry(context),
                      icon: const Icon(Icons.restart_alt_rounded),
                      label: const Text('Reprocessar eventos'),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                SyncFeatureCard(
                  title: 'Eventos financeiros',
                  summary: financialEventSummary,
                  description: canRunManualSync
                      ? 'Inclui cancelamentos de venda e pagamentos de fiado com idempotencia por localUuid, sem recalcular saldo, lucro ou relatorios no backend.'
                      : 'Entre com login remoto e ative o modo hibrido pronto para espelhar os eventos financeiros.',
                  buttonLabel: 'Sincronizar eventos',
                  isEnabled: canRunManualSync,
                  isLoading: batchSyncState.isLoading,
                  onPressed: () => _handleFinancialSyncAll(context),
                ),
                const SizedBox(height: 12),
                SyncFeatureCard(
                  title: 'Espelho de caixa preservado',
                  summary: cashEventSummary,
                  description: canRunManualSync
                      ? 'O espelhamento de caixa ja existente foi preservado e continua isolado da contabilidade local.'
                      : 'Entre com login remoto e ative o modo hibrido pronto para espelhar os eventos de caixa.',
                  buttonLabel: 'Sincronizar caixa',
                  isEnabled: canRunManualSync,
                  isLoading: batchSyncState.isLoading,
                  onPressed: () => _handleCashEventSync(context),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          AppSectionCard(
            title: 'Reconciliação local vs remoto',
            subtitle:
                'Compara SQLite e espelho remoto sem alterar automaticamente os dados operacionais. Divergencias continuam visiveis para diagnostico e reparo controlado.',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _ModeChip(
                      label: '${reconciliationOverview.$1} consistente(s)',
                      icon: Icons.cloud_done_outlined,
                    ),
                    _ModeChip(
                      label: '${reconciliationOverview.$2} pendente(s)',
                      icon: Icons.pending_actions_rounded,
                    ),
                    _ModeChip(
                      label: '${reconciliationOverview.$3} divergencia(s)',
                      icon: Icons.compare_arrows_rounded,
                    ),
                    _ModeChip(
                      label: '${reconciliationOverview.$4} conflito(s)',
                      icon: Icons.warning_amber_rounded,
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    FilledButton.icon(
                      onPressed:
                          reconciliationState.isLoading || !canRunManualSync
                          ? null
                          : () => _handleRunReconciliation(context),
                      icon: const Icon(Icons.rule_folder_outlined),
                      label: Text(
                        reconciliationState.isLoading
                            ? 'Reconciliando...'
                            : 'Executar reconciliacao',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (reconciliationState.hasError)
                  Text(
                    reconciliationState.error.toString(),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  )
                else if (reconciliationResults.isEmpty)
                  Text(
                    'Execute a reconciliacao manual para comparar o estado local com o espelho remoto por feature.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  )
                else
                  Column(
                    children: [
                      if (supplierReconciliation != null)
                        SyncReconciliationCard(
                          result: supplierReconciliation,
                          canRunReconciliation: canRunManualSync,
                          isLoading: reconciliationState.isLoading,
                          onRepair: () => _handleRepairFeature(
                            context,
                            supplierReconciliation.featureKey,
                          ),
                        ),
                      if (supplierReconciliation != null)
                        const SizedBox(height: 12),
                      if (categoryReconciliation != null)
                        SyncReconciliationCard(
                          result: categoryReconciliation,
                          canRunReconciliation: canRunManualSync,
                          isLoading: reconciliationState.isLoading,
                          onRepair: () => _handleRepairFeature(
                            context,
                            categoryReconciliation.featureKey,
                          ),
                        ),
                      if (categoryReconciliation != null)
                        const SizedBox(height: 12),
                      if (productReconciliation != null)
                        SyncReconciliationCard(
                          result: productReconciliation,
                          canRunReconciliation: canRunManualSync,
                          isLoading: reconciliationState.isLoading,
                          onRepair: () => _handleRepairFeature(
                            context,
                            productReconciliation.featureKey,
                          ),
                        ),
                      if (productReconciliation != null)
                        const SizedBox(height: 12),
                      if (customerReconciliation != null)
                        SyncReconciliationCard(
                          result: customerReconciliation,
                          canRunReconciliation: canRunManualSync,
                          isLoading: reconciliationState.isLoading,
                          onRepair: () => _handleRepairFeature(
                            context,
                            customerReconciliation.featureKey,
                          ),
                        ),
                      if (customerReconciliation != null)
                        const SizedBox(height: 12),
                      if (purchaseReconciliation != null)
                        SyncReconciliationCard(
                          result: purchaseReconciliation,
                          canRunReconciliation: canRunManualSync,
                          isLoading: reconciliationState.isLoading,
                          onRepair: () => _handleRepairFeature(
                            context,
                            purchaseReconciliation.featureKey,
                          ),
                        ),
                      if (purchaseReconciliation != null)
                        const SizedBox(height: 12),
                      if (salesReconciliation != null)
                        SyncReconciliationCard(
                          result: salesReconciliation,
                          canRunReconciliation: canRunManualSync,
                          isLoading: reconciliationState.isLoading,
                          onRepair: () => _handleRepairFeature(
                            context,
                            salesReconciliation.featureKey,
                          ),
                        ),
                      if (salesReconciliation != null)
                        const SizedBox(height: 12),
                      if (financialReconciliation != null)
                        SyncReconciliationCard(
                          result: financialReconciliation,
                          canRunReconciliation: canRunManualSync,
                          isLoading: reconciliationState.isLoading,
                          onRepair: () => _handleRepairFeature(
                            context,
                            financialReconciliation.featureKey,
                          ),
                        ),
                    ],
                  ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          AppSectionCard(
            title: 'Repair mode avancado',
            subtitle:
                'Correcao assistida e auditavel de vinculos, bloqueios e reenvios seguros, sem tocar nas regras operacionais locais.',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _ModeChip(
                      label: '${repairSummary.totalIssues} issue(s)',
                      icon: Icons.build_circle_outlined,
                    ),
                    _ModeChip(
                      label: '${repairSummary.autoSafeCount} seguro(s)',
                      icon: Icons.auto_fix_high_rounded,
                    ),
                    _ModeChip(
                      label: '${repairSummary.assistedSafeCount} assistido(s)',
                      icon: Icons.handyman_outlined,
                    ),
                    _ModeChip(
                      label:
                          '${repairSummary.manualReviewCount} revisao manual',
                      icon: Icons.manage_search_rounded,
                    ),
                    if (repairSummary.batchSafeCount > 0)
                      _ModeChip(
                        label: '${repairSummary.batchSafeCount} em lote',
                        icon: Icons.playlist_add_check_circle_outlined,
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    FilledButton.icon(
                      onPressed: repairState.isLoading || !canRunManualSync
                          ? null
                          : () => _handleRunSafeRepairs(context),
                      icon: const Icon(Icons.auto_fix_high_rounded),
                      label: Text(
                        repairState.isLoading
                            ? 'Aplicando reparos...'
                            : 'Executar reparos seguros',
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed:
                          reconciliationState.isLoading || !canRunManualSync
                          ? null
                          : () => _handleRunReconciliation(context),
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Atualizar diagnostico'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (repairState.hasError)
                  Text(
                    repairState.error.toString(),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  )
                else if (repairSummary.totalIssues == 0)
                  Text(
                    'Nenhuma issue reparavel foi identificada no ultimo diagnostico. Execute a reconciliacao para atualizar esta leitura.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  )
                else
                  Column(
                    children: [
                      SyncRepairCard(
                        title: 'Fornecedores',
                        decisions: supplierRepairs,
                        canRunRepair: canRunManualSync,
                        isLoading: repairState.isLoading,
                        onRunSafeRepairs: supplierRepairs.isEmpty
                            ? null
                            : () => _handleRunSafeRepairsForFeature(
                                context,
                                'suppliers',
                              ),
                        onOpenDecision: (decision) =>
                            _handleOpenRepairDecision(context, decision),
                      ),
                      const SizedBox(height: 12),
                      SyncRepairCard(
                        title: 'Categorias',
                        decisions: categoryRepairs,
                        canRunRepair: canRunManualSync,
                        isLoading: repairState.isLoading,
                        onRunSafeRepairs: categoryRepairs.isEmpty
                            ? null
                            : () => _handleRunSafeRepairsForFeature(
                                context,
                                'categories',
                              ),
                        onOpenDecision: (decision) =>
                            _handleOpenRepairDecision(context, decision),
                      ),
                      const SizedBox(height: 12),
                      SyncRepairCard(
                        title: 'Produtos',
                        decisions: productRepairs,
                        canRunRepair: canRunManualSync,
                        isLoading: repairState.isLoading,
                        onRunSafeRepairs: productRepairs.isEmpty
                            ? null
                            : () => _handleRunSafeRepairsForFeature(
                                context,
                                'products',
                              ),
                        onOpenDecision: (decision) =>
                            _handleOpenRepairDecision(context, decision),
                      ),
                      const SizedBox(height: 12),
                      SyncRepairCard(
                        title: 'Clientes',
                        decisions: customerRepairs,
                        canRunRepair: canRunManualSync,
                        isLoading: repairState.isLoading,
                        onRunSafeRepairs: customerRepairs.isEmpty
                            ? null
                            : () => _handleRunSafeRepairsForFeature(
                                context,
                                'customers',
                              ),
                        onOpenDecision: (decision) =>
                            _handleOpenRepairDecision(context, decision),
                      ),
                      const SizedBox(height: 12),
                      SyncRepairCard(
                        title: 'Compras',
                        decisions: purchaseRepairs,
                        canRunRepair: canRunManualSync,
                        isLoading: repairState.isLoading,
                        onRunSafeRepairs: purchaseRepairs.isEmpty
                            ? null
                            : () => _handleRunSafeRepairsForFeature(
                                context,
                                'purchases',
                              ),
                        onOpenDecision: (decision) =>
                            _handleOpenRepairDecision(context, decision),
                      ),
                      const SizedBox(height: 12),
                      SyncRepairCard(
                        title: 'Vendas',
                        decisions: salesRepairs,
                        canRunRepair: canRunManualSync,
                        isLoading: repairState.isLoading,
                        onRunSafeRepairs: salesRepairs.isEmpty
                            ? null
                            : () => _handleRunSafeRepairsForFeature(
                                context,
                                'sales',
                              ),
                        onOpenDecision: (decision) =>
                            _handleOpenRepairDecision(context, decision),
                      ),
                      const SizedBox(height: 12),
                      SyncRepairCard(
                        title: 'Eventos financeiros',
                        decisions: financialRepairs,
                        canRunRepair: canRunManualSync,
                        isLoading: repairState.isLoading,
                        onRunSafeRepairs: financialRepairs.isEmpty
                            ? null
                            : () => _handleRunSafeRepairsForFeature(
                                context,
                                'financial_events',
                              ),
                        onOpenDecision: (decision) =>
                            _handleOpenRepairDecision(context, decision),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          AppSectionCard(
            title: 'Auditoria de sync',
            subtitle:
                'Trilha local das acoes da fila, bloqueios, falhas, conflitos, reparos e reconciliacoes para suporte tecnico e diagnostico.',
            child: auditLogsAsync.when(
              data: (logs) => SyncAuditCard(logs: logs),
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (error, _) => Text(
                error.toString(),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ),
          ),
          const SizedBox(height: 18),
          AppSectionCard(
            title: 'Prontidao de sincronizacao',
            subtitle:
                'Leitura da base local real para preparar remoteId, syncStatus e conciliacao futura sem migration arriscada agora.',
            child: syncSummariesAsync.when(
              data: (summaries) => Column(
                children: summaries
                    .map((summary) => _SyncSummaryTile(summary: summary))
                    .toList(),
              ),
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (error, _) => Text(
                error.toString(),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ),
          ),
          const SizedBox(height: 18),
          AppSectionCard(
            title: 'Ferramentas do sistema',
            subtitle:
                'Utilitarios fora do fluxo operacional principal para manter vendas, caixa e relatorios limpos.',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FilledButton.icon(
                  onPressed: () => context.pushNamed(AppRouteNames.backup),
                  icon: const Icon(Icons.shield_outlined),
                  label: const Text('Backup e restore'),
                ),
                const SizedBox(height: 12),
                Text(
                  'Nada aqui altera a logica contabil ou tira o app do modo offline-first. Esta area so organiza conexao, sessao e utilitarios de sistema.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDataModeSection(
    BuildContext context,
    AppEnvironment environment,
    SessionGuardSnapshot guard,
    ThemeData theme,
  ) {
    final defaultEndpointBaseUrl =
        const EndpointConfig.localDevelopment().baseUrl!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SegmentedButton<AppDataMode>(
          segments: AppDataMode.values
              .map(
                (mode) => ButtonSegment<AppDataMode>(
                  value: mode,
                  label: Text(mode.label),
                ),
              )
              .toList(),
          selected: <AppDataMode>{environment.dataMode},
          showSelectedIcon: false,
          onSelectionChanged: (selection) async {
            await ref
                .read(appEnvironmentProvider.notifier)
                .setDataMode(selection.first);
            final updatedEnvironment = ref.read(appEnvironmentProvider);
            _setEndpointControllerText(
              updatedEnvironment.endpointConfig.baseUrl ??
                  (selection.first == AppDataMode.localOnly
                      ? ''
                      : defaultEndpointBaseUrl),
            );
          },
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _endpointController,
          focusNode: _endpointFocusNode,
          decoration: InputDecoration(
            labelText: 'Base URL do backend',
            hintText: defaultEndpointBaseUrl,
            prefixIcon: const Icon(Icons.link_rounded),
          ),
          keyboardType: TextInputType.url,
          textInputAction: TextInputAction.done,
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            FilledButton.icon(
              onPressed: _saveEndpoint,
              icon: const Icon(Icons.save_outlined),
              label: const Text('Salvar endpoint'),
            ),
            OutlinedButton.icon(
              onPressed: () async {
                _setEndpointControllerText(defaultEndpointBaseUrl);
                await _saveEndpoint();
              },
              icon: const Icon(Icons.restart_alt_rounded),
              label: const Text('Usar endpoint padrao'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            const _ModeChip(
              label: 'SQLite local ativo',
              icon: Icons.dns_rounded,
            ),
            _ModeChip(
              label: environment.endpointConfig.summaryLabel,
              icon: Icons.cloud_queue_rounded,
            ),
            _ModeChip(
              label: guard.allowRemoteRoutes
                  ? 'Remoto liberado'
                  : 'Remoto em espera',
              icon: Icons.sync_alt_rounded,
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          environment.dataMode.description,
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 14),
        _InfoRow(label: 'Ambiente', value: environment.name),
        _InfoRow(
          label: 'Auth remota',
          value: environment.authEnabled
              ? 'Real habilitada para desenvolvimento'
              : 'Desativada no modo local',
        ),
        _InfoRow(
          label: 'Sync remota',
          value: environment.remoteSyncEnabled
              ? 'Preparado para fase futura'
              : 'Ainda isolado do operacional',
        ),
      ],
    );
  }

  Widget _buildBackendStatusSection(BackendConnectionStatus status) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _StateTile(
          icon: status.isReachable
              ? Icons.cloud_done_outlined
              : Icons.cloud_off_outlined,
          title: status.isReachable
              ? 'Backend local alcancavel'
              : status.isConfigured
              ? 'Backend configurado, mas indisponivel'
              : 'Backend remoto ainda nao configurado',
          subtitle: status.message,
        ),
        const SizedBox(height: 14),
        _InfoRow(label: 'Endpoint', value: status.endpointLabel),
        _InfoRow(
          label: 'Ultima verificacao',
          value: AppFormatters.shortDateTime(status.checkedAt),
        ),
        _InfoRow(
          label: 'Tenant remoto',
          value: status.remoteCompanyName ?? 'Nao validado',
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () => ref.invalidate(backendConnectionStatusProvider),
          icon: const Icon(Icons.wifi_tethering_rounded),
          label: const Text('Testar conexao'),
        ),
      ],
    );
  }

  Widget _buildRemoteAuthSection(
    BuildContext context,
    AsyncValue<void> authState,
    AuthStatusSnapshot authStatus,
  ) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _StateTile(
          icon: authStatus.isRemoteAuthenticated
              ? Icons.hub_rounded
              : Icons.login_rounded,
          title: authStatus.isRemoteAuthenticated
              ? 'Login remoto validado'
              : 'Use o backend local para autenticar',
          subtitle: authStatus.isRemoteAuthenticated
              ? 'Sessao remota ativa e tenant resolvido pelo backend. Os modulos operacionais continuam locais nesta fase.'
              : 'Ative um modo com backend, confirme o endpoint e entre com o usuario seeded para validar a arquitetura real.',
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _emailController,
          enabled: !authState.isLoading,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(
            labelText: 'E-mail',
            prefixIcon: Icon(Icons.alternate_email_rounded),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _passwordController,
          enabled: !authState.isLoading,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'Senha',
            prefixIcon: Icon(Icons.password_rounded),
          ),
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            FilledButton.icon(
              onPressed:
                  authState.isLoading || !authStatus.canAttemptRemoteLogin
                  ? null
                  : () => _handleRemoteSignIn(context),
              icon: const Icon(Icons.login_rounded),
              label: Text(
                authState.isLoading && !authStatus.isRemoteAuthenticated
                    ? 'Entrando...'
                    : 'Entrar com backend',
              ),
            ),
            OutlinedButton.icon(
              onPressed:
                  authState.isLoading || !authStatus.canAttemptRemoteLogin
                  ? null
                  : () => _handleRestoreRemoteSession(context),
              icon: const Icon(Icons.history_toggle_off_rounded),
              label: const Text('Restaurar sessao'),
            ),
            OutlinedButton.icon(
              onPressed: authState.isLoading || !authStatus.isAuthenticated
                  ? null
                  : () => _handleSignOut(context),
              icon: const Icon(Icons.logout_rounded),
              label: const Text('Sair da sessao atual'),
            ),
          ],
        ),
        if (authState.hasError) ...[
          const SizedBox(height: 12),
          Text(
            authState.error.toString(),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildMockAuthSection(
    BuildContext context,
    AsyncValue<void> authState,
    AuthStatusSnapshot authStatus,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _StateTile(
          icon: authStatus.isMockAuthenticated
              ? Icons.badge_outlined
              : Icons.science_outlined,
          title: authStatus.isMockAuthenticated
              ? 'Sessao mock ativa'
              : 'Sessao mock disponivel',
          subtitle: authStatus.isMockAuthenticated
              ? 'A identidade mock continua util para testar a arquitetura hibrida quando voce nao quiser subir a API real.'
              : 'O fluxo mock continua coexistindo com o login real para validar a arquitetura sem bloquear a operacao local.',
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            FilledButton.icon(
              onPressed: authState.isLoading || authStatus.isAuthenticated
                  ? null
                  : () => _handleMockSignIn(context),
              icon: const Icon(Icons.science_outlined),
              label: const Text('Entrar com mock'),
            ),
            OutlinedButton.icon(
              onPressed: authState.isLoading || !authStatus.isMockAuthenticated
                  ? null
                  : () => _handleSignOut(context),
              icon: const Icon(Icons.logout_rounded),
              label: const Text('Encerrar mock'),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _saveEndpoint() async {
    final messenger = ScaffoldMessenger.of(context);
    await ref
        .read(appEnvironmentProvider.notifier)
        .setEndpointBaseUrl(_endpointController.text);
    _setEndpointControllerText(
      ref.read(appEnvironmentProvider).endpointConfig.baseUrl ?? '',
    );
    ref.invalidate(backendConnectionStatusProvider);
    ref.invalidate(remoteDiagnosticsProvider);
    ref.invalidate(syncReconciliationControllerProvider);

    if (!mounted) {
      return;
    }
    messenger.showSnackBar(
      const SnackBar(
        content: Text('Endpoint remoto atualizado para este ambiente.'),
      ),
    );
  }

  void _setEndpointControllerText(String value) {
    _endpointController.value = _endpointController.value.copyWith(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
      composing: TextRange.empty,
    );
  }

  Future<void> _handleMockSignIn(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final session = await ref
          .read(authControllerProvider.notifier)
          .signInMock();
      if (!mounted) {
        return;
      }
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Sessao mock iniciada para ${session.user.displayName}.',
          ),
        ),
      );
    } catch (_) {
      if (!mounted) {
        return;
      }
    }
  }

  Future<void> _handleRemoteSignIn(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final session = await ref
          .read(authControllerProvider.notifier)
          .signInRemote(
            email: _emailController.text,
            password: _passwordController.text,
          );
      ref.invalidate(backendConnectionStatusProvider);
      ref.invalidate(syncReconciliationControllerProvider);
      if (!mounted) {
        return;
      }
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Sessao remota iniciada para ${session.user.displayName}.',
          ),
        ),
      );
    } catch (_) {
      if (!mounted) {
        return;
      }
    }
  }

  Future<void> _handleRestoreRemoteSession(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final session = await ref
          .read(authControllerProvider.notifier)
          .restoreRemoteSession();
      ref.invalidate(backendConnectionStatusProvider);
      ref.invalidate(syncReconciliationControllerProvider);
      if (!mounted) {
        return;
      }

      final message = session == null
          ? 'Nao existe sessao remota salva neste dispositivo.'
          : 'Sessao remota restaurada para ${session.user.displayName}.';
      messenger.showSnackBar(SnackBar(content: Text(message)));
    } catch (_) {
      if (!mounted) {
        return;
      }
    }
  }

  Future<void> _handleSignOut(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(authControllerProvider.notifier).signOutCurrentSession();
      ref.invalidate(backendConnectionStatusProvider);
      ref.invalidate(syncReconciliationControllerProvider);
      if (!mounted) {
        return;
      }
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Sessao encerrada. O app voltou ao contexto local.'),
        ),
      );
    } catch (_) {
      if (!mounted) {
        return;
      }
    }
  }

  Future<void> _handleProductSync(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final result = await ref
          .read(catalogSyncControllerProvider.notifier)
          .syncFeature('products');
      if (!mounted) {
        return;
      }
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Produtos processados: ${result.processedCount}, sincronizados: ${result.syncedCount}, bloqueados: ${result.blockedCount}, conflitos: ${result.conflictCount}, falhas: ${result.failedCount}.',
          ),
        ),
      );
    } catch (_) {
      if (!mounted) {
        return;
      }
    }
  }

  Future<void> _handleSupplierSync(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final result = await ref
          .read(catalogSyncControllerProvider.notifier)
          .syncFeature('suppliers');
      if (!mounted) {
        return;
      }
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Fornecedores processados: ${result.processedCount}, sincronizados: ${result.syncedCount}, bloqueados: ${result.blockedCount}, conflitos: ${result.conflictCount}, falhas: ${result.failedCount}.',
          ),
        ),
      );
    } catch (_) {
      if (!mounted) {
        return;
      }
    }
  }

  Future<void> _handleCategorySync(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final result = await ref
          .read(catalogSyncControllerProvider.notifier)
          .syncFeature('categories');
      if (!mounted) {
        return;
      }
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Categorias processadas: ${result.processedCount}, sincronizadas: ${result.syncedCount}, bloqueadas: ${result.blockedCount}, conflitos: ${result.conflictCount}, falhas: ${result.failedCount}.',
          ),
        ),
      );
    } catch (_) {
      if (!mounted) {
        return;
      }
    }
  }

  Future<void> _handleClientSync(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final result = await ref
          .read(catalogSyncControllerProvider.notifier)
          .syncFeature('customers');
      if (!mounted) {
        return;
      }
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Clientes processados: ${result.processedCount}, sincronizados: ${result.syncedCount}, bloqueados: ${result.blockedCount}, conflitos: ${result.conflictCount}, falhas: ${result.failedCount}.',
          ),
        ),
      );
    } catch (_) {
      if (!mounted) {
        return;
      }
    }
  }

  Future<void> _handlePurchaseSync(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final result = await ref
          .read(catalogSyncControllerProvider.notifier)
          .syncFeature('purchases');
      if (!mounted) {
        return;
      }
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Compras processadas: ${result.processedCount}, sincronizadas: ${result.syncedCount}, bloqueadas: ${result.blockedCount}, conflitos: ${result.conflictCount}, falhas: ${result.failedCount}.',
          ),
        ),
      );
    } catch (_) {
      if (!mounted) {
        return;
      }
    }
  }

  Future<void> _handleSalesSync(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final result = await ref
          .read(catalogSyncControllerProvider.notifier)
          .syncFeature('sales');
      if (!mounted) {
        return;
      }
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Vendas processadas: ${result.processedCount}, sincronizadas: ${result.syncedCount}, bloqueadas: ${result.blockedCount}, conflitos: ${result.conflictCount}, falhas: ${result.failedCount}.',
          ),
        ),
      );
    } catch (_) {
      if (!mounted) {
        return;
      }
    }
  }

  Future<void> _handleCashEventSync(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final result = await ref
          .read(catalogSyncControllerProvider.notifier)
          .syncFeature('cash_events');
      if (!mounted) {
        return;
      }
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Eventos de caixa processados: ${result.processedCount}, sincronizados: ${result.syncedCount}, bloqueados: ${result.blockedCount}, conflitos: ${result.conflictCount}, falhas: ${result.failedCount}.',
          ),
        ),
      );
    } catch (_) {
      if (!mounted) {
        return;
      }
    }
  }

  Future<void> _handleFinancialSyncAll(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final result = await ref
          .read(catalogSyncControllerProvider.notifier)
          .syncFeature('financial_events');
      if (!mounted) {
        return;
      }
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Eventos financeiros processados. Processados: ${result.processedCount}, sync: ${result.syncedCount}, bloqueados: ${result.blockedCount}, conflitos: ${result.conflictCount}, falhas: ${result.failedCount}.',
          ),
        ),
      );
    } catch (_) {
      if (!mounted) {
        return;
      }
    }
  }

  Future<void> _handleFinancialRetry(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final result = await ref
          .read(catalogSyncControllerProvider.notifier)
          .retryFeatures(const <String>['financial_events']);
      if (!mounted) {
        return;
      }
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Reprocessamento de eventos financeiros concluido. Processados: ${result.processedCount}, sync: ${result.syncedCount}, bloqueados: ${result.blockedCount}, conflitos: ${result.conflictCount}, falhas: ${result.failedCount}.',
          ),
        ),
      );
    } catch (_) {
      if (!mounted) {
        return;
      }
    }
  }

  Future<void> _handleSyncAll(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final result = await ref
          .read(catalogSyncControllerProvider.notifier)
          .syncAll();
      if (!mounted) {
        return;
      }
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            '${result.message} Processados: ${result.processedCount}, sync: ${result.syncedCount}, bloqueados: ${result.blockedCount}, conflitos: ${result.conflictCount}, falhas: ${result.failedCount}.',
          ),
        ),
      );
    } catch (_) {
      if (!mounted) {
        return;
      }
    }
  }

  Future<void> _handleRetryPending(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final result = await ref
          .read(catalogSyncControllerProvider.notifier)
          .retryPending();
      if (!mounted) {
        return;
      }
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            '${result.message} Processados: ${result.processedCount}, sync: ${result.syncedCount}, bloqueados: ${result.blockedCount}, conflitos: ${result.conflictCount}, falhas: ${result.failedCount}.',
          ),
        ),
      );
    } catch (_) {
      if (!mounted) {
        return;
      }
    }
  }

  Future<void> _handleRunReconciliation(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final results = await ref
          .read(syncReconciliationControllerProvider.notifier)
          .run();
      if (!mounted) {
        return;
      }
      final overview = _buildReconciliationOverview(results);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Reconciliacao concluida. Consistentes: ${overview.$1}, pendentes: ${overview.$2}, divergentes: ${overview.$3}, conflitos: ${overview.$4}.',
          ),
        ),
      );
    } catch (_) {
      if (!mounted) {
        return;
      }
    }
  }

  Future<void> _handleRunSafeRepairs(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final result = await ref
          .read(syncRepairControllerProvider.notifier)
          .applySafeRepairs();
      if (!mounted) {
        return;
      }
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            '${result.message} Solicitados: ${result.requestedCount}, aplicados: ${result.appliedCount}, ignorados: ${result.skippedCount}, falhas: ${result.failedCount}.',
          ),
        ),
      );
    } catch (_) {
      if (!mounted) {
        return;
      }
    }
  }

  Future<void> _handleRunSafeRepairsForFeature(
    BuildContext context,
    String featureKey,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final result = await ref
          .read(syncRepairControllerProvider.notifier)
          .applySafeRepairs(featureKeys: <String>[featureKey]);
      if (!mounted) {
        return;
      }
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            '${_displayNameForFeature(featureKey)}: ${result.message} Aplicados: ${result.appliedCount}, ignorados: ${result.skippedCount}, falhas: ${result.failedCount}.',
          ),
        ),
      );
    } catch (_) {
      if (!mounted) {
        return;
      }
    }
  }

  Future<void> _handleOpenRepairDecision(
    BuildContext context,
    SyncRepairDecision decision,
  ) async {
    final action = await showModalBottomSheet<SyncRepairAction>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => SyncRepairActionSheet(decision: decision),
    );
    if (!context.mounted || action == null) {
      return;
    }

    if (decision.requiresConfirmation ||
        action.type == SyncRepairActionType.relinkRemoteId) {
      final confirmed = await _confirmRepairAction(context, action, decision);
      if (!context.mounted || !confirmed) {
        return;
      }
    }

    try {
      final result = await ref
          .read(syncRepairControllerProvider.notifier)
          .applyAction(action);
      if (!context.mounted) {
        return;
      }
      final messenger = ScaffoldMessenger.of(context);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            '${action.type.label}: ${result.message} Aplicados: ${result.appliedCount}, ignorados: ${result.skippedCount}, falhas: ${result.failedCount}.',
          ),
        ),
      );
    } catch (_) {
      if (!mounted) {
        return;
      }
    }
  }

  Future<bool> _confirmRepairAction(
    BuildContext context,
    SyncRepairAction action,
    SyncRepairDecision decision,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(action.type.label),
          content: Text(
            'Voce esta prestes a aplicar um repair em ${decision.target.entityLabel}.\n\n${decision.reason}\n\nConfianca: ${(decision.confidence * 100).round()}%',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Confirmar repair'),
            ),
          ],
        );
      },
    );

    return confirmed ?? false;
  }

  Future<void> _handleRepairFeature(
    BuildContext context,
    String featureKey,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final repairedCount = await ref
          .read(syncReconciliationControllerProvider.notifier)
          .repairFeature(featureKey);
      if (!mounted) {
        return;
      }
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            repairedCount == 0
                ? 'Nenhum item elegivel para reenvio em ${_displayNameForFeature(featureKey).toLowerCase()}.'
                : '$repairedCount item(ns) de ${_displayNameForFeature(featureKey).toLowerCase()} foram marcados para reenvio.',
          ),
        ),
      );
    } catch (_) {
      if (!mounted) {
        return;
      }
    }
  }

  SyncQueueFeatureSummary? _findQueueSummary(
    List<SyncQueueFeatureSummary> summaries,
    String featureKey,
  ) {
    for (final summary in summaries) {
      if (summary.featureKey == featureKey) {
        return summary;
      }
    }

    return null;
  }

  SyncReconciliationResult? _findReconciliationResult(
    List<SyncReconciliationResult> results,
    String featureKey,
  ) {
    for (final result in results) {
      if (result.featureKey == featureKey) {
        return result;
      }
    }

    return null;
  }

  (int, int, int, int) _buildReconciliationOverview(
    List<SyncReconciliationResult> results,
  ) {
    var consistent = 0;
    var pending = 0;
    var divergent = 0;
    var conflicts = 0;

    for (final result in results) {
      consistent += result.consistentCount;
      pending += result.pendingSyncCount;
      divergent +=
          result.outOfSyncCount +
          result.missingRemoteCount +
          result.invalidLinkCount +
          result.remoteOnlyCount +
          result.orphanRemoteCount;
      conflicts += result.conflictCount;
    }

    return (consistent, pending, divergent, conflicts);
  }

  String _displayNameForFeature(String featureKey) {
    switch (featureKey) {
      case 'suppliers':
        return 'Fornecedores';
      case 'categories':
        return 'Categorias';
      case 'products':
        return 'Produtos';
      case 'customers':
        return 'Clientes';
      case 'purchases':
        return 'Compras';
      case 'sales':
        return 'Vendas';
      case 'financial_events':
        return 'Eventos financeiros';
      default:
        return featureKey;
    }
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
            width: 132,
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
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ModeChip extends StatelessWidget {
  const _ModeChip({required this.label, required this.icon});

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [Icon(icon, size: 18), const SizedBox(width: 8), Text(label)],
      ),
    );
  }
}

class _StateTile extends StatelessWidget {
  const _StateTile({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: colorScheme.primaryContainer,
            child: Icon(icon, color: colorScheme.onPrimaryContainer),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RemoteDiagnosticTile extends StatelessWidget {
  const _RemoteDiagnosticTile({required this.diagnostic});

  final RemoteFeatureDiagnostic diagnostic;

  @override
  Widget build(BuildContext context) {
    final tone = diagnostic.reachable
        ? (diagnostic.requiresAuthentication && !diagnostic.isAuthenticated
              ? AppStatusTone.warning
              : AppStatusTone.success)
        : AppStatusTone.neutral;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    diagnostic.displayName,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                AppStatusBadge(
                  label: diagnostic.reachable ? 'Pronto' : 'Em espera',
                  tone: tone,
                  icon: diagnostic.reachable
                      ? Icons.cloud_done_outlined
                      : Icons.cloud_off_outlined,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(diagnostic.summary),
            const SizedBox(height: 10),
            Text('Endpoint: ${diagnostic.endpointLabel}'),
            Text(
              'Ultima verificacao: ${AppFormatters.shortDateTime(diagnostic.lastCheckedAt)}',
            ),
            if (diagnostic.capabilities.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: diagnostic.capabilities
                    .map(
                      (capability) => _ModeChip(
                        label: capability,
                        icon: Icons.memory_rounded,
                      ),
                    )
                    .toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SyncSummaryTile extends StatelessWidget {
  const _SyncSummaryTile({required this.summary});

  final SyncFeatureSummary summary;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              summary.displayName,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _ModeChip(
                  label: '${summary.totalRecords} registro(s)',
                  icon: Icons.inventory_2_outlined,
                ),
                _ModeChip(
                  label: '${summary.localOnlyCount} local',
                  icon: Icons.offline_pin_rounded,
                ),
                if (summary.pendingUploadCount > 0)
                  _ModeChip(
                    label: '${summary.pendingUploadCount} upload',
                    icon: Icons.upload_rounded,
                  ),
                if (summary.pendingUpdateCount > 0)
                  _ModeChip(
                    label: '${summary.pendingUpdateCount} update',
                    icon: Icons.system_update_alt_rounded,
                  ),
                if (summary.conflictCount > 0)
                  _ModeChip(
                    label: '${summary.conflictCount} conflito',
                    icon: Icons.warning_amber_rounded,
                  ),
                if (summary.errorCount > 0)
                  _ModeChip(
                    label: '${summary.errorCount} erro',
                    icon: Icons.error_outline_rounded,
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              summary.lastLocalChangeAt == null
                  ? 'Sem alteracoes locais detectadas.'
                  : 'Ultima mudanca local: ${AppFormatters.shortDateTime(summary.lastLocalChangeAt!)}',
            ),
            if (summary.lastErrorMessage != null) ...[
              const SizedBox(height: 10),
              Text(
                'Ultimo erro: ${summary.lastErrorMessage!}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

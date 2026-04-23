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
import '../../../../app/core/sync/sync_providers.dart';
import '../../../../app/core/sync/sync_queue_feature_summary.dart';
import '../../../../app/core/sync/sync_reconciliation_result.dart';
import '../../../../app/core/sync/sync_repair_action.dart';
import '../../../../app/core/sync/sync_repair_action_type.dart';
import '../../../../app/core/sync/sync_repair_decision.dart';
import '../../../../app/core/sync/sync_batch_result.dart';
import '../../../../app/core/widgets/app_main_drawer.dart';
import '../../../../app/core/widgets/app_page_header.dart';
import '../../../../app/core/widgets/app_section_card.dart';
import '../../../../app/core/widgets/app_status_badge.dart';
import '../../../../app/routes/route_names.dart';
import '../helpers/system_feedback_helpers.dart';
import '../helpers/system_page_helpers.dart';
import '../providers/system_providers.dart';
import '../widgets/system_backend_status_section.dart';
import '../widgets/system_financial_events_section.dart';
import '../widgets/system_hybrid_governance_section.dart';
import '../widgets/system_mock_auth_section.dart';
import '../widgets/system_reconciliation_section.dart';
import '../widgets/system_repair_section.dart';
import '../widgets/system_remote_auth_section.dart';
import '../widgets/system_session_section.dart';
import '../widgets/system_support_widgets.dart';
import '../widgets/system_sync_health_section.dart';
import '../widgets/system_sync_queue_section.dart';
import '../widgets/sync_audit_card.dart';
import '../widgets/sync_repair_action_sheet.dart';

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
    final hybridOperationalTruth = ref.watch(
      hybridOperationalTruthSnapshotProvider,
    );
    final remoteDiagnosticsAsync = ref.watch(remoteDiagnosticsProvider);
    final syncSummariesAsync = ref.watch(syncReadinessSummaryProvider);
    final queueSummariesAsync = ref.watch(syncQueueFeatureSummariesProvider);
    final syncHealth = ref.watch(syncHealthOverviewProvider);
    final autoSyncSnapshot = ref.watch(autoSyncSnapshotProvider);
    final batchSyncState = ref.watch(catalogSyncControllerProvider);
    final isSyncBatchRunning = ref.watch(syncBatchActivityProvider);
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
    final supplierSummary = findQueueSummary(queueSummaries, 'suppliers');
    final categorySummary = findQueueSummary(queueSummaries, 'categories');
    final productSummary = findQueueSummary(queueSummaries, 'products');
    final customerSummary = findQueueSummary(queueSummaries, 'customers');
    final purchaseSummary = findQueueSummary(queueSummaries, 'purchases');
    final salesSummary = findQueueSummary(queueSummaries, 'sales');
    final financialEventSummary = findQueueSummary(
      queueSummaries,
      'financial_events',
    );
    final cashEventSummary = findQueueSummary(queueSummaries, 'cash_events');
    final supplierReconciliation = findReconciliationResult(
      reconciliationResults,
      'suppliers',
    );
    final categoryReconciliation = findReconciliationResult(
      reconciliationResults,
      'categories',
    );
    final productReconciliation = findReconciliationResult(
      reconciliationResults,
      'products',
    );
    final customerReconciliation = findReconciliationResult(
      reconciliationResults,
      'customers',
    );
    final purchaseReconciliation = findReconciliationResult(
      reconciliationResults,
      'purchases',
    );
    final salesReconciliation = findReconciliationResult(
      reconciliationResults,
      'sales',
    );
    final financialReconciliation = findReconciliationResult(
      reconciliationResults,
      'financial_events',
    );
    final reconciliationOverview = buildReconciliationOverview(
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
          SystemSessionSection(session: session, authStatus: authStatus),
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
          SystemHybridGovernanceSection(snapshot: hybridOperationalTruth),
          const SizedBox(height: 18),
          backendStatusAsync.when(
            data: (status) => SystemBackendStatusSection(
              status: status,
              onTestConnection: () =>
                  ref.invalidate(backendConnectionStatusProvider),
            ),
            loading: () => const AppSectionCard(
              title: 'API real de desenvolvimento',
              subtitle:
                  'Saude do backend local e validacao do tenant remoto sem acoplar vendas, caixa ou relatorios a HTTP.',
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
            error: (error, _) => AppSectionCard(
              title: 'API real de desenvolvimento',
              subtitle:
                  'Saude do backend local e validacao do tenant remoto sem acoplar vendas, caixa ou relatorios a HTTP.',
              child: Text(
                error.toString(),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ),
          ),
          const SizedBox(height: 18),
          SystemRemoteAuthSection(
            authState: authState,
            authStatus: authStatus,
            emailController: _emailController,
            passwordController: _passwordController,
            onRemoteSignIn: () => _handleRemoteSignIn(context),
            onRestoreRemoteSession: () => _handleRestoreRemoteSession(context),
            onSignOut: () => _handleSignOut(context),
          ),
          const SizedBox(height: 18),
          SystemMockAuthSection(
            authState: authState,
            authStatus: authStatus,
            onMockSignIn: () => _handleMockSignIn(context),
            onSignOut: () => _handleSignOut(context),
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
          SystemSyncHealthSection(
            syncHealth: syncHealth,
            autoSyncSnapshot: autoSyncSnapshot,
            isLoading: batchSyncState.isLoading || isSyncBatchRunning,
            canRunManualSync: canRunManualSync,
            onSyncAll: () => _handleSyncAll(context),
            onRetryPending: () => _handleRetryPending(context),
          ),
          const SizedBox(height: 18),
          SystemSyncQueueSection(
            canRunManualSync: canRunManualSync,
            isLoading: batchSyncState.isLoading || isSyncBatchRunning,
            supplierSummary: supplierSummary,
            categorySummary: categorySummary,
            productSummary: productSummary,
            customerSummary: customerSummary,
            purchaseSummary: purchaseSummary,
            salesSummary: salesSummary,
            onSupplierSync: () => _handleSupplierSync(context),
            onCategorySync: () => _handleCategorySync(context),
            onProductSync: () => _handleProductSync(context),
            onClientSync: () => _handleClientSync(context),
            onPurchaseSync: () => _handlePurchaseSync(context),
            onSalesSync: () => _handleSalesSync(context),
          ),
          const SizedBox(height: 18),
          SystemFinancialEventsSection(
            canRunManualSync: canRunManualSync,
            isLoading: batchSyncState.isLoading,
            financialEventSummary: financialEventSummary,
            cashEventSummary: cashEventSummary,
            onFinancialSync: () => _handleFinancialSyncAll(context),
            onFinancialRetry: () => _handleFinancialRetry(context),
            onCashEventSync: () => _handleCashEventSync(context),
          ),
          const SizedBox(height: 18),
          SystemReconciliationSection(
            overview: reconciliationOverview,
            canRunManualSync: canRunManualSync,
            isLoading: reconciliationState.isLoading,
            errorMessage: reconciliationState.hasError
                ? reconciliationState.error.toString()
                : null,
            supplierReconciliation: supplierReconciliation,
            categoryReconciliation: categoryReconciliation,
            productReconciliation: productReconciliation,
            customerReconciliation: customerReconciliation,
            purchaseReconciliation: purchaseReconciliation,
            salesReconciliation: salesReconciliation,
            financialReconciliation: financialReconciliation,
            onRunReconciliation: () => _handleRunReconciliation(context),
            onRepairFeature: (featureKey) =>
                _handleRepairFeature(context, featureKey),
          ),
          const SizedBox(height: 18),
          SystemRepairSection(
            summary: repairSummary,
            canRunManualSync: canRunManualSync,
            isRepairLoading: repairState.isLoading,
            isReconciliationLoading: reconciliationState.isLoading,
            errorMessage: repairState.hasError
                ? repairState.error.toString()
                : null,
            supplierRepairs: supplierRepairs,
            categoryRepairs: categoryRepairs,
            productRepairs: productRepairs,
            customerRepairs: customerRepairs,
            purchaseRepairs: purchaseRepairs,
            salesRepairs: salesRepairs,
            financialRepairs: financialRepairs,
            onRunSafeRepairs: () => _handleRunSafeRepairs(context),
            onRefreshDiagnostics: () => _handleRunReconciliation(context),
            onRunSafeRepairsForFeature: (featureKey) =>
                _handleRunSafeRepairsForFeature(context, featureKey),
            onOpenDecision: (decision) =>
                _handleOpenRepairDecision(context, decision),
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
    final defaultEndpointBaseUrl = EndpointConfig.remoteDefault().baseUrl!;

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
            const SystemModeChip(
              label: 'SQLite local ativo',
              icon: Icons.dns_rounded,
            ),
            SystemModeChip(
              label: environment.endpointConfig.summaryLabel,
              icon: Icons.cloud_queue_rounded,
            ),
            SystemModeChip(
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
        SystemInfoRow(label: 'Ambiente', value: environment.name),
        SystemInfoRow(
          label: 'Auth remota',
          value: environment.authEnabled
              ? 'Real habilitada para desenvolvimento'
              : 'Desativada no modo local',
        ),
        SystemInfoRow(
          label: 'Sync remota',
          value: environment.remoteSyncEnabled
              ? 'Preparado para fase futura'
              : 'Ainda isolado do operacional',
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
      if (!context.mounted) {
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
      if (!context.mounted) {
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
      if (!context.mounted) {
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
      if (!context.mounted) {
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
      if (!context.mounted) {
        return;
      }

      final message = session == null
          ? 'Nao existe sessao remota salva neste dispositivo.'
          : 'Sessao remota restaurada para ${session.user.displayName}.';
      messenger.showSnackBar(SnackBar(content: Text(message)));
    } catch (_) {
      if (!context.mounted) {
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
      if (!context.mounted) {
        return;
      }
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Sessao encerrada. O app voltou ao contexto local.'),
        ),
      );
    } catch (_) {
      if (!context.mounted) {
        return;
      }
    }
  }

  Future<void> _handleProductSync(BuildContext context) async {
    await _runFeatureSync(
      context,
      featureKey: 'products',
      featureLabel: 'Produtos',
      syncedLabel: 'sincronizados',
      blockedLabel: 'bloqueados',
    );
  }

  Future<void> _handleSupplierSync(BuildContext context) async {
    await _runFeatureSync(
      context,
      featureKey: 'suppliers',
      featureLabel: 'Fornecedores',
      syncedLabel: 'sincronizados',
      blockedLabel: 'bloqueados',
    );
  }

  Future<void> _handleCategorySync(BuildContext context) async {
    await _runFeatureSync(
      context,
      featureKey: 'categories',
      featureLabel: 'Categorias',
      syncedLabel: 'sincronizadas',
      blockedLabel: 'bloqueadas',
    );
  }

  Future<void> _handleClientSync(BuildContext context) async {
    await _runFeatureSync(
      context,
      featureKey: 'customers',
      featureLabel: 'Clientes',
      syncedLabel: 'sincronizados',
      blockedLabel: 'bloqueados',
    );
  }

  Future<void> _handlePurchaseSync(BuildContext context) async {
    await _runFeatureSync(
      context,
      featureKey: 'purchases',
      featureLabel: 'Compras',
      syncedLabel: 'sincronizadas',
      blockedLabel: 'bloqueadas',
    );
  }

  Future<void> _handleSalesSync(BuildContext context) async {
    await _runFeatureSync(
      context,
      featureKey: 'sales',
      featureLabel: 'Vendas',
      syncedLabel: 'sincronizadas',
      blockedLabel: 'bloqueadas',
    );
  }

  Future<void> _handleCashEventSync(BuildContext context) async {
    await _runFeatureSync(
      context,
      featureKey: 'cash_events',
      featureLabel: 'Eventos de caixa',
      syncedLabel: 'sincronizados',
      blockedLabel: 'bloqueados',
    );
  }

  Future<void> _handleFinancialSyncAll(BuildContext context) async {
    await _runBatchSyncAction(
      context,
      action: (controller) => controller.syncFeature('financial_events'),
      messageBuilder: buildFinancialSyncMessage,
    );
  }

  Future<void> _handleFinancialRetry(BuildContext context) async {
    await _runBatchSyncAction(
      context,
      action: (controller) =>
          controller.retryFeatures(const <String>['financial_events']),
      messageBuilder: buildRetryMessage,
    );
  }

  Future<void> _handleSyncAll(BuildContext context) async {
    await _runBatchSyncAction(
      context,
      action: (controller) => controller.syncAll(),
      messageBuilder: buildRetryMessage,
    );
  }

  Future<void> _handleRetryPending(BuildContext context) async {
    await _runBatchSyncAction(
      context,
      action: (controller) => controller.retryPending(),
      messageBuilder: buildRetryMessage,
    );
  }

  Future<void> _runFeatureSync(
    BuildContext context, {
    required String featureKey,
    required String featureLabel,
    required String syncedLabel,
    required String blockedLabel,
  }) async {
    await _runBatchSyncAction(
      context,
      action: (controller) => controller.syncFeature(featureKey),
      messageBuilder: (result) => buildFeatureSyncMessage(
        featureLabel: featureLabel,
        syncedLabel: syncedLabel,
        blockedLabel: blockedLabel,
        result: result,
      ),
    );
  }

  Future<void> _runBatchSyncAction(
    BuildContext context, {
    required Future<SyncBatchResult> Function(CatalogSyncController controller)
    action,
    required String Function(SyncBatchResult result) messageBuilder,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final controller = ref.read(catalogSyncControllerProvider.notifier);
      final result = await action(controller);
      if (!context.mounted) {
        return;
      }
      showSystemSnackbar(messenger, messageBuilder(result));
    } catch (_) {
      if (!context.mounted) {
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
      final overview = buildReconciliationOverview(results);
      showSystemSnackbar(messenger, buildReconciliationMessage(overview));
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
      showSystemSnackbar(messenger, buildRepairMessage(result));
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
      showSystemSnackbar(
        messenger,
        buildFeatureRepairMessage(featureKey: featureKey, result: result),
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
      showSystemSnackbar(
        messenger,
        buildRepairActionMessage(
          actionLabel: action.type.label,
          result: result,
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
      showSystemSnackbar(
        messenger,
        buildRepairFeatureQueueMessage(
          featureKey: featureKey,
          repairedCount: repairedCount,
        ),
      );
    } catch (_) {
      if (!mounted) {
        return;
      }
    }
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
                      (capability) => SystemModeChip(
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
                SystemModeChip(
                  label: '${summary.totalRecords} registro(s)',
                  icon: Icons.inventory_2_outlined,
                ),
                SystemModeChip(
                  label: '${summary.localOnlyCount} local',
                  icon: Icons.offline_pin_rounded,
                ),
                if (summary.pendingUploadCount > 0)
                  SystemModeChip(
                    label: '${summary.pendingUploadCount} upload',
                    icon: Icons.upload_rounded,
                  ),
                if (summary.pendingUpdateCount > 0)
                  SystemModeChip(
                    label: '${summary.pendingUpdateCount} update',
                    icon: Icons.system_update_alt_rounded,
                  ),
                if (summary.conflictCount > 0)
                  SystemModeChip(
                    label: '${summary.conflictCount} conflito',
                    icon: Icons.warning_amber_rounded,
                  ),
                if (summary.errorCount > 0)
                  SystemModeChip(
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

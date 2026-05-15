import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/core/formatters/app_formatters.dart';
import '../../../../app/core/session/auth_provider.dart';
import '../../../../app/core/session/session_provider.dart';
import '../../../../app/core/sync/auto_sync_coordinator.dart';
import '../../../../app/core/sync/sync_display_state.dart';
import '../../../../app/core/sync/sync_providers.dart';
import '../../../../app/core/sync/sync_queue_feature_summary.dart';
import '../../../../app/core/sync/sync_queue_item.dart';
import '../../../../app/core/sync/sync_queue_operation.dart';
import '../../../../app/core/sync/sync_queue_status.dart';
import '../../../../app/core/providers/app_data_refresh_provider.dart';
import '../../../../app/core/providers/provider_guard.dart';
import '../../../../app/core/providers/tenant_bootstrap_gate.dart';
import '../../../../app/core/widgets/app_status_badge.dart';
import '../../../system/presentation/providers/system_providers.dart';

final accountCloudAttentionItemsProvider =
    FutureProvider<List<AccountCloudSyncIssue>>((ref) async {
      await requireTenantBootstrapReady(
        ref,
        'accountCloudAttentionItemsProvider',
      );
      ref.watch(appDataRefreshProvider);
      final items = await runProviderGuarded(
        'accountCloudAttentionItemsProvider',
        () => ref.watch(syncQueueRepositoryProvider).listAttentionItems(),
        timeout: syncProviderTimeout,
      );
      return items
          .map(AccountCloudSyncIssue.fromQueueItem)
          .toList(growable: false);
    });

final accountCloudStatusProvider = Provider<AccountCloudStatusSnapshot>((ref) {
  final authStatus = ref.watch(authStatusProvider);
  final session = ref.watch(appSessionProvider);
  final company = ref.watch(currentCompanyContextProvider);
  final connectionAsync = ref.watch(backendConnectionStatusProvider);
  final syncOverview = ref.watch(syncHealthOverviewProvider);
  final autoSyncSnapshot = ref.watch(autoSyncSnapshotProvider);
  final connection = connectionAsync.valueOrNull;
  final hasRecentSync = syncOverview.lastProcessedAt != null;
  final pendingCount = syncOverview.totalPendingForDisplay;
  final syncingNowCount = syncOverview.totalActiveProcessing;
  List<SyncQueueFeatureSummary> loadAttentionSummaries() {
    return ref.watch(syncQueueFeatureSummariesProvider).valueOrNull ??
        const <SyncQueueFeatureSummary>[];
  }

  if (!authStatus.isRemoteAuthenticated || session.isLocalDefault) {
    return AccountCloudStatusSnapshot(
      statusLabel: 'Login necessario',
      statusMessage:
          'Entre com uma conta vinculada a empresa para liberar a operacao neste aparelho.',
      tone: AppStatusTone.neutral,
      icon: Icons.lock_outline_rounded,
      accountModeLabel: 'Sem sessao',
      cloudAvailabilityLabel: 'Primeiro acesso exige internet',
      supportingLabel: hasRecentSync ? 'Ultima sincronizacao' : null,
      supportingValue: hasRecentSync
          ? AppFormatters.shortDateTime(syncOverview.lastProcessedAt!)
          : null,
      syncingNowCount: 0,
      pendingCount: pendingCount,
      errorCount: syncOverview.totalErrors,
      blockedCount: syncOverview.totalBlocked,
      conflictCount: syncOverview.totalConflicts,
      lastSyncedAt: syncOverview.lastProcessedAt,
      nextRetryAt: syncOverview.nextRetryAt,
    );
  }

  if (!company.hasCloudLicense) {
    return AccountCloudStatusSnapshot(
      statusLabel: 'Precisa de atencao',
      statusMessage:
          'Sua empresa ainda nao tem uma licenca de nuvem pronta para sincronizar. A base local segue vinculada a este tenant.',
      tone: AppStatusTone.warning,
      icon: Icons.info_outline_rounded,
      accountModeLabel: 'Conta conectada',
      cloudAvailabilityLabel: 'Nuvem indisponivel',
      syncingNowCount: syncingNowCount,
      pendingCount: pendingCount,
      errorCount: syncOverview.totalErrors,
      blockedCount: syncOverview.totalBlocked,
      conflictCount: syncOverview.totalConflicts,
      lastSyncedAt: syncOverview.lastProcessedAt,
      nextRetryAt: syncOverview.nextRetryAt,
    );
  }

  if (company.isSuspendedLicense) {
    return AccountCloudStatusSnapshot(
      statusLabel: 'Precisa de atencao',
      statusMessage:
          'Sua licenca de nuvem esta suspensa. A base local permanece vinculada a esta empresa enquanto a conta precisa de atencao.',
      tone: AppStatusTone.warning,
      icon: Icons.pause_circle_outline_rounded,
      accountModeLabel: 'Conta conectada',
      cloudAvailabilityLabel: 'Nuvem indisponivel',
      syncingNowCount: syncingNowCount,
      pendingCount: pendingCount,
      errorCount: syncOverview.totalErrors,
      blockedCount: syncOverview.totalBlocked,
      conflictCount: syncOverview.totalConflicts,
      lastSyncedAt: syncOverview.lastProcessedAt,
      nextRetryAt: syncOverview.nextRetryAt,
    );
  }

  if (company.isExpiredLicense) {
    return AccountCloudStatusSnapshot(
      statusLabel: 'Precisa de atencao',
      statusMessage:
          'Sua licenca de nuvem venceu. A base local permanece vinculada a esta empresa enquanto a conta precisa de atencao.',
      tone: AppStatusTone.warning,
      icon: Icons.event_busy_rounded,
      accountModeLabel: 'Conta conectada',
      cloudAvailabilityLabel: 'Nuvem indisponivel',
      syncingNowCount: syncingNowCount,
      pendingCount: pendingCount,
      errorCount: syncOverview.totalErrors,
      blockedCount: syncOverview.totalBlocked,
      conflictCount: syncOverview.totalConflicts,
      lastSyncedAt: syncOverview.lastProcessedAt,
      nextRetryAt: syncOverview.nextRetryAt,
    );
  }

  if (!company.syncEnabled) {
    return AccountCloudStatusSnapshot(
      statusLabel: 'Precisa de atencao',
      statusMessage:
          'A nuvem desta empresa esta desativada no momento. A base local permanece vinculada a este tenant.',
      tone: AppStatusTone.warning,
      icon: Icons.cloud_off_rounded,
      accountModeLabel: 'Conta conectada',
      cloudAvailabilityLabel: 'Nuvem indisponivel',
      syncingNowCount: syncingNowCount,
      pendingCount: pendingCount,
      errorCount: syncOverview.totalErrors,
      blockedCount: syncOverview.totalBlocked,
      conflictCount: syncOverview.totalConflicts,
      lastSyncedAt: syncOverview.lastProcessedAt,
      nextRetryAt: syncOverview.nextRetryAt,
    );
  }

  if (connectionAsync.isLoading && connection == null) {
    return AccountCloudStatusSnapshot(
      statusLabel: 'Sincronizando',
      statusMessage: 'Estamos verificando sua conexao com a nuvem.',
      tone: AppStatusTone.info,
      icon: Icons.sync_rounded,
      accountModeLabel: 'Conta conectada',
      cloudAvailabilityLabel: 'Verificando a nuvem',
      syncingNowCount: syncingNowCount,
      pendingCount: pendingCount,
      errorCount: syncOverview.totalErrors,
      blockedCount: syncOverview.totalBlocked,
      conflictCount: syncOverview.totalConflicts,
      lastSyncedAt: syncOverview.lastProcessedAt,
      nextRetryAt: syncOverview.nextRetryAt,
    );
  }

  if (connection == null || !connection.isReachable) {
    return AccountCloudStatusSnapshot(
      statusLabel: 'Sem internet',
      statusMessage:
          'Nao conseguimos falar com a nuvem agora. O Tatuzin usa a base local ja vinculada a esta empresa.',
      tone: AppStatusTone.warning,
      icon: Icons.cloud_off_rounded,
      accountModeLabel: 'Conta conectada',
      cloudAvailabilityLabel: 'Sem internet',
      supportingLabel: hasRecentSync
          ? 'Ultima sincronizacao'
          : 'Ultima verificacao',
      supportingValue: hasRecentSync
          ? AppFormatters.shortDateTime(syncOverview.lastProcessedAt!)
          : AppFormatters.shortDateTime(
              connection?.checkedAt ?? DateTime.now(),
            ),
      syncingNowCount: syncingNowCount,
      pendingCount: pendingCount,
      errorCount: syncOverview.totalErrors,
      blockedCount: syncOverview.totalBlocked,
      conflictCount: syncOverview.totalConflicts,
      lastSyncedAt: syncOverview.lastProcessedAt,
      nextRetryAt: syncOverview.nextRetryAt,
    );
  }

  if (autoSyncSnapshot.lastFailureMessage != null &&
      autoSyncSnapshot.lastFailureMessage!.trim().isNotEmpty &&
      !syncOverview.hasAttention) {
    return AccountCloudStatusSnapshot(
      statusLabel: 'Precisa de atencao',
      statusMessage:
          'Sua conta entrou, mas o auto-sync inicial nao conseguiu ser agendado. A base local permanece vinculada enquanto a nuvem precisa de revisao.',
      tone: AppStatusTone.warning,
      icon: Icons.error_outline_rounded,
      accountModeLabel: 'Conta conectada',
      cloudAvailabilityLabel: 'Auto-sync com alerta',
      supportingLabel: 'Ultima falha',
      supportingValue: autoSyncSnapshot.lastFailureMessage,
      syncingNowCount: syncingNowCount,
      pendingCount: pendingCount,
      errorCount: syncOverview.totalErrors,
      blockedCount: syncOverview.totalBlocked,
      conflictCount: syncOverview.totalConflicts,
      lastSyncedAt: syncOverview.lastProcessedAt,
      nextRetryAt: _nextOperatorAttemptAt(
        syncOverview: syncOverview,
        autoSyncSnapshot: autoSyncSnapshot,
      ),
    );
  }

  switch (syncOverview.displayState) {
    case SyncDisplayState.conflict:
      final syncSummaries = loadAttentionSummaries();
      return AccountCloudStatusSnapshot(
        statusLabel: 'Com conflito',
        statusMessage: _buildAttentionMessage(
          syncOverview,
          syncSummaries: syncSummaries,
          autoSyncSnapshot: autoSyncSnapshot,
        ),
        tone: AppStatusTone.warning,
        icon: Icons.warning_amber_rounded,
        accountModeLabel: 'Conta conectada',
        cloudAvailabilityLabel: 'Requer revisao',
        supportingLabel: hasRecentSync
            ? 'Ultima sincronizacao'
            : 'Ultima verificacao',
        supportingValue: hasRecentSync
            ? AppFormatters.shortDateTime(syncOverview.lastProcessedAt!)
            : AppFormatters.shortDateTime(connection.checkedAt),
        syncingNowCount: syncingNowCount,
        pendingCount: pendingCount,
        errorCount: syncOverview.totalErrors,
        blockedCount: syncOverview.totalBlocked,
        conflictCount: syncOverview.totalConflicts,
        lastSyncedAt: syncOverview.lastProcessedAt,
        nextRetryAt: _nextOperatorAttemptAt(
          syncOverview: syncOverview,
          autoSyncSnapshot: autoSyncSnapshot,
        ),
      );
    case SyncDisplayState.error:
      final syncSummaries = loadAttentionSummaries();
      return AccountCloudStatusSnapshot(
        statusLabel: 'Erro de sincronizacao',
        statusMessage: _buildAttentionMessage(
          syncOverview,
          syncSummaries: syncSummaries,
          autoSyncSnapshot: autoSyncSnapshot,
        ),
        tone: AppStatusTone.warning,
        icon: Icons.error_outline_rounded,
        accountModeLabel: 'Conta conectada',
        cloudAvailabilityLabel: 'Requer revisao',
        supportingLabel: hasRecentSync
            ? 'Ultima sincronizacao'
            : 'Ultima verificacao',
        supportingValue: hasRecentSync
            ? AppFormatters.shortDateTime(syncOverview.lastProcessedAt!)
            : AppFormatters.shortDateTime(connection.checkedAt),
        syncingNowCount: syncingNowCount,
        pendingCount: pendingCount,
        errorCount: syncOverview.totalErrors,
        blockedCount: syncOverview.totalBlocked,
        conflictCount: syncOverview.totalConflicts,
        lastSyncedAt: syncOverview.lastProcessedAt,
        nextRetryAt: _nextOperatorAttemptAt(
          syncOverview: syncOverview,
          autoSyncSnapshot: autoSyncSnapshot,
        ),
      );
    case SyncDisplayState.serverDataStale:
      return AccountCloudStatusSnapshot(
        statusLabel: 'Dados do servidor desatualizados',
        statusMessage:
            'Suas operacoes locais foram preservadas, mas nao conseguimos atualizar os dados vindos do servidor agora.',
        tone: AppStatusTone.warning,
        icon: Icons.cloud_off_outlined,
        accountModeLabel: 'Conta conectada',
        cloudAvailabilityLabel: 'Atualizacao pendente',
        supportingLabel: syncOverview.lastSnapshotError != null
            ? 'Falha ao atualizar dados'
            : 'Falha ao puxar dados',
        supportingValue:
            syncOverview.lastSnapshotError ??
            syncOverview.lastPullError ??
            'Tente sincronizar novamente.',
        syncingNowCount: syncingNowCount,
        pendingCount: pendingCount,
        errorCount: syncOverview.totalErrors,
        blockedCount: syncOverview.totalBlocked,
        conflictCount: syncOverview.totalConflicts,
        lastSyncedAt: syncOverview.lastProcessedAt,
        nextRetryAt: _nextOperatorAttemptAt(
          syncOverview: syncOverview,
          autoSyncSnapshot: autoSyncSnapshot,
        ),
      );
    case SyncDisplayState.syncing:
      return AccountCloudStatusSnapshot(
        statusLabel: 'Sincronizando',
        statusMessage: _buildSyncingMessage(
          syncOverview,
          autoSyncSnapshot: autoSyncSnapshot,
        ),
        tone: AppStatusTone.info,
        icon: Icons.sync_rounded,
        accountModeLabel: 'Conta conectada',
        cloudAvailabilityLabel: 'Envio em andamento',
        supportingLabel: hasRecentSync ? 'Ultima sincronizacao' : null,
        supportingValue: hasRecentSync
            ? AppFormatters.shortDateTime(syncOverview.lastProcessedAt!)
            : null,
        syncingNowCount: syncingNowCount,
        pendingCount: pendingCount,
        errorCount: syncOverview.totalErrors,
        blockedCount: syncOverview.totalBlocked,
        conflictCount: syncOverview.totalConflicts,
        lastSyncedAt: syncOverview.lastProcessedAt,
        nextRetryAt: _nextOperatorAttemptAt(
          syncOverview: syncOverview,
          autoSyncSnapshot: autoSyncSnapshot,
        ),
      );
    case SyncDisplayState.pending:
      return AccountCloudStatusSnapshot(
        statusLabel: 'Pendente',
        statusMessage: _buildPendingMessage(
          syncOverview,
          autoSyncSnapshot: autoSyncSnapshot,
        ),
        tone: AppStatusTone.neutral,
        icon: Icons.schedule_send_rounded,
        accountModeLabel: 'Conta conectada',
        cloudAvailabilityLabel: 'Pendencias aguardando envio',
        supportingLabel: hasRecentSync ? 'Ultima sincronizacao' : null,
        supportingValue: hasRecentSync
            ? AppFormatters.shortDateTime(syncOverview.lastProcessedAt!)
            : null,
        syncingNowCount: syncingNowCount,
        pendingCount: pendingCount,
        errorCount: syncOverview.totalErrors,
        blockedCount: syncOverview.totalBlocked,
        conflictCount: syncOverview.totalConflicts,
        lastSyncedAt: syncOverview.lastProcessedAt,
        nextRetryAt: _nextOperatorAttemptAt(
          syncOverview: syncOverview,
          autoSyncSnapshot: autoSyncSnapshot,
        ),
      );
    case SyncDisplayState.synced:
      break;
  }

  return AccountCloudStatusSnapshot(
    statusLabel: 'Sincronizado',
    statusMessage:
        'Sua conta esta conectada e a nuvem esta funcionando normalmente para a sua empresa.',
    tone: AppStatusTone.success,
    icon: Icons.cloud_done_rounded,
    accountModeLabel: 'Conta conectada',
    cloudAvailabilityLabel: 'Nuvem disponivel',
    supportingLabel: hasRecentSync
        ? 'Ultima sincronizacao'
        : connection.remoteCompanyName == null
        ? 'Conta conectada'
        : 'Empresa na nuvem',
    supportingValue: hasRecentSync
        ? AppFormatters.shortDateTime(syncOverview.lastProcessedAt!)
        : connection.remoteCompanyName ?? authStatus.companyLabel,
    syncingNowCount: syncingNowCount,
    pendingCount: pendingCount,
    errorCount: syncOverview.totalErrors,
    blockedCount: syncOverview.totalBlocked,
    conflictCount: syncOverview.totalConflicts,
    lastSyncedAt: syncOverview.lastProcessedAt,
    nextRetryAt: _nextOperatorAttemptAt(
      syncOverview: syncOverview,
      autoSyncSnapshot: autoSyncSnapshot,
    ),
  );
});

String _buildSyncingMessage(
  SyncHealthOverview syncOverview, {
  required AutoSyncCoordinatorSnapshot autoSyncSnapshot,
}) {
  final parts = <String>[
    _countLabel(
      syncOverview.totalActiveProcessing,
      'item esta sendo enviado agora',
      'itens estao sendo enviados agora',
    ),
  ];

  if (syncOverview.totalPendingForDisplay > 0) {
    parts.add(
      _countLabel(
        syncOverview.totalPendingForDisplay,
        'item ainda aguarda na fila local',
        'itens ainda aguardam na fila local',
      ),
    );
  }

  if (autoSyncSnapshot.followUpQueued) {
    parts.add(
      'Novas mudancas entraram na fila e um lote complementar ja foi reservado',
    );
  }

  return '${parts.join('. ')}.';
}

String _buildPendingMessage(
  SyncHealthOverview syncOverview, {
  required AutoSyncCoordinatorSnapshot autoSyncSnapshot,
}) {
  final parts = <String>[
    _countLabel(
      syncOverview.totalPendingForDisplay,
      'pendencia aguarda envio automatico',
      'pendencias aguardam envio automatico',
    ),
  ];

  if (syncOverview.totalStaleProcessing > 0) {
    parts.add(
      _countLabel(
        syncOverview.totalStaleProcessing,
        'item preso em processing antigo voltou para nova tentativa',
        'itens presos em processing antigo voltaram para nova tentativa',
      ),
    );
  }

  final nextAttemptAt = _nextOperatorAttemptAt(
    syncOverview: syncOverview,
    autoSyncSnapshot: autoSyncSnapshot,
  );
  if (nextAttemptAt != null) {
    parts.add(
      'A proxima tentativa automatica esta prevista para ${AppFormatters.shortDateTime(nextAttemptAt)}',
    );
  }

  return '${parts.join('. ')}.';
}

String _buildAttentionMessage(
  SyncHealthOverview syncOverview, {
  required List<SyncQueueFeatureSummary> syncSummaries,
  required AutoSyncCoordinatorSnapshot autoSyncSnapshot,
}) {
  final parts = <String>[];
  final primaryAttentionSummary = _primaryAttentionSummary(syncSummaries);

  if (syncOverview.totalErrors > 0) {
    final singleErrorLabel =
        syncOverview.totalErrors == 1 && primaryAttentionSummary != null
        ? _singleFailureLabel(primaryAttentionSummary.featureKey)
        : null;
    parts.add(
      singleErrorLabel == null
          ? '${_countLabel(syncOverview.totalErrors, 'operacao com falha de sincronizacao', 'operacoes com falha de sincronizacao')}. Os dados locais estao preservados'
          : 'Ha 1 $singleErrorLabel com falha de sincronizacao. Os dados locais estao preservados',
    );
    final lastError = _cleanSyncError(primaryAttentionSummary?.lastError);
    if (lastError != null) {
      parts.add(
        'Ultimo erro em ${primaryAttentionSummary!.displayName}: $lastError',
      );
    }
  }

  if (syncOverview.totalBlocked > 0) {
    parts.add(
      _countLabel(
        syncOverview.totalBlocked,
        'item bloqueado',
        'itens bloqueados',
      ),
    );
  }

  if (syncOverview.totalConflicts > 0) {
    parts.add(
      _countLabel(
        syncOverview.totalConflicts,
        'conflito pendente',
        'conflitos pendentes',
      ),
    );
    parts.add(
      'a revisão de conflitos será disponibilizada em uma próxima atualização',
    );
  }

  final nextAttemptAt = _nextOperatorAttemptAt(
    syncOverview: syncOverview,
    autoSyncSnapshot: autoSyncSnapshot,
  );
  if (nextAttemptAt != null) {
    parts.add(
      'A proxima tentativa automatica elegivel esta prevista para ${AppFormatters.shortDateTime(nextAttemptAt)}',
    );
  }

  if (parts.isEmpty) {
    return 'Sua conta esta conectada, mas a nuvem precisa de atencao para voltar ao ritmo normal.';
  }

  return 'Sua conta esta conectada, mas a nuvem precisa de atencao: ${parts.join(', ')}.';
}

SyncQueueFeatureSummary? _primaryAttentionSummary(
  List<SyncQueueFeatureSummary> summaries,
) {
  SyncQueueFeatureSummary? match;
  for (final summary in summaries) {
    if (!summary.hasAttention) {
      continue;
    }
    if (match == null) {
      match = summary;
      continue;
    }
    final currentAt =
        summary.lastErrorAt ?? DateTime.fromMillisecondsSinceEpoch(0);
    final bestAt = match.lastErrorAt ?? DateTime.fromMillisecondsSinceEpoch(0);
    if (currentAt.isAfter(bestAt)) {
      match = summary;
    }
  }
  return match;
}

String _singleFailureLabel(String featureKey) {
  switch (featureKey) {
    case 'sales':
      return 'venda';
    case 'cash_events':
    case 'cash_movements':
      return 'movimento de caixa';
    case 'cash_sessions':
      return 'sessao de caixa';
    case 'fiado_payments':
      return 'recebimento de fiado';
    case 'financial_events':
      return 'evento financeiro';
    case 'products':
      return 'produto';
    case 'customers':
      return 'cliente';
    default:
      return 'operacao';
  }
}

String? _cleanSyncError(String? message) {
  final trimmed = message?.trim();
  if (trimmed == null || trimmed.isEmpty) {
    return null;
  }
  return trimmed.replaceAll(RegExp(r'\s+'), ' ');
}

String _countLabel(int count, String singular, String plural) {
  return '$count ${count == 1 ? singular : plural}';
}

DateTime? _nextOperatorAttemptAt({
  required SyncHealthOverview syncOverview,
  required AutoSyncCoordinatorSnapshot autoSyncSnapshot,
}) {
  final scheduledAt = autoSyncSnapshot.nextScheduledAt;
  final retryAt = syncOverview.nextRetryAt;
  final lastProcessedAt = syncOverview.lastProcessedAt;
  DateTime? candidate;
  if (scheduledAt == null) {
    candidate = retryAt;
  } else if (retryAt == null) {
    candidate = scheduledAt;
  } else {
    candidate = scheduledAt.isBefore(retryAt) ? scheduledAt : retryAt;
  }
  if (candidate == null || lastProcessedAt == null) {
    return candidate;
  }
  if (!candidate.isBefore(lastProcessedAt)) {
    return candidate;
  }
  return lastProcessedAt.add(const Duration(minutes: 1));
}

final internalMobileSurfaceAccessProvider =
    Provider<InternalMobileSurfaceAccess>((ref) {
      final authStatus = ref.watch(authStatusProvider);
      final canOpenTechnicalSystem =
          kDebugMode ||
          authStatus.isPlatformAdmin ||
          authStatus.isSupportProfile;
      final canOpenAdminCloud =
          authStatus.isRemoteAuthenticated &&
          (kDebugMode ||
              authStatus.isPlatformAdmin ||
              authStatus.isSupportProfile);

      return InternalMobileSurfaceAccess(
        canOpenTechnicalSystem: canOpenTechnicalSystem,
        canOpenAdminCloud: canOpenAdminCloud,
      );
    });

class AccountCloudStatusSnapshot {
  const AccountCloudStatusSnapshot({
    required this.statusLabel,
    required this.statusMessage,
    required this.tone,
    required this.icon,
    required this.accountModeLabel,
    required this.cloudAvailabilityLabel,
    required this.syncingNowCount,
    required this.pendingCount,
    required this.errorCount,
    required this.blockedCount,
    required this.conflictCount,
    required this.lastSyncedAt,
    required this.nextRetryAt,
    this.supportingLabel,
    this.supportingValue,
  });

  final String statusLabel;
  final String statusMessage;
  final AppStatusTone tone;
  final IconData icon;
  final String accountModeLabel;
  final String cloudAvailabilityLabel;
  final int syncingNowCount;
  final int pendingCount;
  final int errorCount;
  final int blockedCount;
  final int conflictCount;
  final DateTime? lastSyncedAt;
  final DateTime? nextRetryAt;
  final String? supportingLabel;
  final String? supportingValue;
}

class InternalMobileSurfaceAccess {
  const InternalMobileSurfaceAccess({
    required this.canOpenTechnicalSystem,
    required this.canOpenAdminCloud,
  });

  final bool canOpenTechnicalSystem;
  final bool canOpenAdminCloud;

  bool get hasAnyAccess => canOpenTechnicalSystem || canOpenAdminCloud;
}

class AccountCloudSyncIssue {
  const AccountCloudSyncIssue({
    required this.queueId,
    required this.featureKey,
    required this.entityLabel,
    required this.operationLabel,
    required this.statusLabel,
    required this.localId,
    required this.localUuid,
    required this.remoteId,
    required this.endpoint,
    required this.message,
    required this.httpStatusCode,
    required this.nextRetryAt,
    required this.updatedAt,
  });

  factory AccountCloudSyncIssue.fromQueueItem(SyncQueueItem item) {
    return AccountCloudSyncIssue(
      queueId: item.id,
      featureKey: item.featureKey,
      entityLabel: item.entityType,
      operationLabel: item.operation.operatorLabel,
      statusLabel: item.status.operatorLabel,
      localId: item.localEntityId,
      localUuid: item.localUuid,
      remoteId: item.remoteId,
      endpoint: _endpointFor(item),
      message:
          item.conflictReason ??
          item.lastError ??
          'A fila marcou este item para revisao, mas nao registrou uma mensagem detalhada.',
      httpStatusCode: _extractHttpStatusCode(item.lastError),
      nextRetryAt: item.nextRetryAt,
      updatedAt: item.updatedAt,
    );
  }

  final int queueId;
  final String featureKey;
  final String entityLabel;
  final String operationLabel;
  final String statusLabel;
  final int localId;
  final String? localUuid;
  final String? remoteId;
  final String endpoint;
  final String message;
  final int? httpStatusCode;
  final DateTime? nextRetryAt;
  final DateTime updatedAt;
}

extension on SyncQueueOperation {
  String get operatorLabel {
    switch (this) {
      case SyncQueueOperation.create:
        return 'Criacao';
      case SyncQueueOperation.update:
        return 'Atualizacao';
      case SyncQueueOperation.delete:
        return 'Exclusao';
      case SyncQueueOperation.cancel:
        return 'Cancelamento';
    }
  }
}

extension on SyncQueueStatus {
  String get operatorLabel {
    switch (this) {
      case SyncQueueStatus.pendingUpload:
        return 'Pendente de envio';
      case SyncQueueStatus.pendingUpdate:
        return 'Pendente de atualizacao';
      case SyncQueueStatus.processing:
        return 'Em processamento';
      case SyncQueueStatus.synced:
        return 'Sincronizado';
      case SyncQueueStatus.syncError:
        return 'Com erro';
      case SyncQueueStatus.blockedDependency:
        return 'Bloqueado por dependencia';
      case SyncQueueStatus.conflict:
        return 'Conflito';
    }
  }
}

String _endpointFor(SyncQueueItem item) {
  final collection = switch (item.featureKey) {
    'categories' => '/categories',
    'supplies' => '/supplies',
    'products' => '/products',
    'product_recipes' => '/product-recipes',
    'customers' => '/customers',
    'suppliers' => '/suppliers',
    'purchases' => '/purchases',
    'sales' => '/sales',
    'sale_cancellations' => '/sales',
    'fiado_payments' => '/financial-events',
    'financial_events' => '/financial-events',
    'cash_events' => '/cash/events',
    _ => '/${item.featureKey}',
  };
  final remoteId = item.remoteId;
  if (remoteId == null || remoteId.trim().isEmpty) {
    return collection;
  }
  return '$collection/$remoteId';
}

int? _extractHttpStatusCode(String? message) {
  if (message == null) {
    return null;
  }
  final match = RegExp(r'HTTP\s+(\d{3})').firstMatch(message);
  if (match == null) {
    return null;
  }
  return int.tryParse(match.group(1)!);
}

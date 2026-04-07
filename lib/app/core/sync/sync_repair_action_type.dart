enum SyncRepairActionType {
  reenqueueForSync,
  relinkRemoteId,
  relinkLocalUuid,
  markMissingRemote,
  markMissingLocal,
  clearStaleBlock,
  retryDependencyChain,
  refreshRemoteSnapshot,
  markConflictReviewed,
  repairRemoteLink,
  repairLocalMetadata,
  rebuildDependencyState,
  reclassifySyncStatus,
  revalidateRemotePresence,
  clearInvalidRemoteId,
}

extension SyncRepairActionTypeX on SyncRepairActionType {
  String get storageValue {
    switch (this) {
      case SyncRepairActionType.reenqueueForSync:
        return 'reenqueue_for_sync';
      case SyncRepairActionType.relinkRemoteId:
        return 'relink_remote_id';
      case SyncRepairActionType.relinkLocalUuid:
        return 'relink_local_uuid';
      case SyncRepairActionType.markMissingRemote:
        return 'mark_missing_remote';
      case SyncRepairActionType.markMissingLocal:
        return 'mark_missing_local';
      case SyncRepairActionType.clearStaleBlock:
        return 'clear_stale_block';
      case SyncRepairActionType.retryDependencyChain:
        return 'retry_dependency_chain';
      case SyncRepairActionType.refreshRemoteSnapshot:
        return 'refresh_remote_snapshot';
      case SyncRepairActionType.markConflictReviewed:
        return 'mark_conflict_reviewed';
      case SyncRepairActionType.repairRemoteLink:
        return 'repair_remote_link';
      case SyncRepairActionType.repairLocalMetadata:
        return 'repair_local_metadata';
      case SyncRepairActionType.rebuildDependencyState:
        return 'rebuild_dependency_state';
      case SyncRepairActionType.reclassifySyncStatus:
        return 'reclassify_sync_status';
      case SyncRepairActionType.revalidateRemotePresence:
        return 'revalidate_remote_presence';
      case SyncRepairActionType.clearInvalidRemoteId:
        return 'clear_invalid_remote_id';
    }
  }

  String get label {
    switch (this) {
      case SyncRepairActionType.reenqueueForSync:
        return 'Marcar para reenvio';
      case SyncRepairActionType.relinkRemoteId:
        return 'Religar remoteId';
      case SyncRepairActionType.relinkLocalUuid:
        return 'Religar localUuid';
      case SyncRepairActionType.markMissingRemote:
        return 'Marcar ausente no remoto';
      case SyncRepairActionType.markMissingLocal:
        return 'Marcar ausente no local';
      case SyncRepairActionType.clearStaleBlock:
        return 'Limpar bloqueio obsoleto';
      case SyncRepairActionType.retryDependencyChain:
        return 'Reprocessar dependencias';
      case SyncRepairActionType.refreshRemoteSnapshot:
        return 'Atualizar snapshot remoto';
      case SyncRepairActionType.markConflictReviewed:
        return 'Marcar conflito como revisado';
      case SyncRepairActionType.repairRemoteLink:
        return 'Corrigir vinculo remoto';
      case SyncRepairActionType.repairLocalMetadata:
        return 'Corrigir metadata local';
      case SyncRepairActionType.rebuildDependencyState:
        return 'Reconstruir estado de dependencia';
      case SyncRepairActionType.reclassifySyncStatus:
        return 'Reclassificar status';
      case SyncRepairActionType.revalidateRemotePresence:
        return 'Revalidar presenca remota';
      case SyncRepairActionType.clearInvalidRemoteId:
        return 'Limpar remoteId invalido';
    }
  }

  String get description {
    switch (this) {
      case SyncRepairActionType.reenqueueForSync:
        return 'Reclassifica o item para uma nova rodada da fila sem alterar a regra operacional local.';
      case SyncRepairActionType.relinkRemoteId:
        return 'Atualiza o vinculo remoto local quando ha evidencia forte de correspondencia segura.';
      case SyncRepairActionType.relinkLocalUuid:
        return 'Reaponta o localUuid apenas quando o espelho remoto ja comprova a mesma identidade.';
      case SyncRepairActionType.markMissingRemote:
        return 'Registra que o espelho remoto nao foi encontrado, sem correcao destrutiva.';
      case SyncRepairActionType.markMissingLocal:
        return 'Registra que o item nao existe mais localmente e exige revisao.';
      case SyncRepairActionType.clearStaleBlock:
        return 'Remove bloqueio antigo da fila e deixa o item pronto para nova validacao.';
      case SyncRepairActionType.retryDependencyChain:
        return 'Reenfileira dependencias e o item alvo em ordem segura.';
      case SyncRepairActionType.refreshRemoteSnapshot:
        return 'Refaz a leitura remota para atualizar o diagnostico atual.';
      case SyncRepairActionType.markConflictReviewed:
        return 'Mantem o conflito visivel, mas registra que ele ja foi avaliado.';
      case SyncRepairActionType.repairRemoteLink:
        return 'Ajusta o vinculo local/remoto sem tocar regras contabeis.';
      case SyncRepairActionType.repairLocalMetadata:
        return 'Corrige metadata de sync e fila com rastreabilidade.';
      case SyncRepairActionType.rebuildDependencyState:
        return 'Recalcula o estado de dependencia antes de nova tentativa.';
      case SyncRepairActionType.reclassifySyncStatus:
        return 'Atualiza a classificacao tecnica de sync de forma controlada.';
      case SyncRepairActionType.revalidateRemotePresence:
        return 'Consulta novamente o backend antes de decidir o proximo passo.';
      case SyncRepairActionType.clearInvalidRemoteId:
        return 'Remove um remoteId quebrado e prepara o item para novo vinculo seguro.';
    }
  }
}

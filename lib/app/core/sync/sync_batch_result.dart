class SyncBatchResult {
  const SyncBatchResult({
    required this.processedCount,
    required this.syncedCount,
    required this.failedCount,
    required this.blockedCount,
    required this.conflictCount,
    required this.reprocessedOnly,
    required this.startedAt,
    required this.finishedAt,
    this.pullFailed = false,
    this.snapshotFailed = false,
    this.lastPullError,
    this.lastSnapshotError,
  });

  final int processedCount;
  final int syncedCount;
  final int failedCount;
  final int blockedCount;
  final int conflictCount;
  final bool reprocessedOnly;
  final DateTime startedAt;
  final DateTime finishedAt;
  final bool pullFailed;
  final bool snapshotFailed;
  final String? lastPullError;
  final String? lastSnapshotError;

  Duration get duration => finishedAt.difference(startedAt);

  bool get hasServerDataStale => pullFailed || snapshotFailed;

  bool get hasAttention =>
      failedCount > 0 || blockedCount > 0 || conflictCount > 0;

  bool get isClean => !hasAttention && !hasServerDataStale;

  String get message {
    final scope = reprocessedOnly ? 'pendências' : 'fila';
    if (hasServerDataStale) {
      return 'Sincronização concluída, mas os dados do servidor ficaram desatualizados.';
    }
    if (isClean) {
      return 'Processamento de $scope concluído com sucesso.';
    }

    final parts = <String>[];
    if (conflictCount > 0) {
      parts.add('Conflitos: $conflictCount');
    }
    if (failedCount > 0) {
      parts.add('Erros: $failedCount');
    }
    if (blockedCount > 0) {
      parts.add('Bloqueados: $blockedCount');
    }
    final suffix = parts.isEmpty ? '' : ' ${parts.join(' · ')}.';
    return 'Sincronização concluída, mas ainda há itens que precisam de revisão.$suffix';
  }
}

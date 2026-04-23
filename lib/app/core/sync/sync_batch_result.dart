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
  });

  final int processedCount;
  final int syncedCount;
  final int failedCount;
  final int blockedCount;
  final int conflictCount;
  final bool reprocessedOnly;
  final DateTime startedAt;
  final DateTime finishedAt;

  Duration get duration => finishedAt.difference(startedAt);

  bool get hasAttention =>
      failedCount > 0 || blockedCount > 0 || conflictCount > 0;

  bool get isClean => !hasAttention;

  String get message {
    final scope = reprocessedOnly ? 'pendencias' : 'fila';
    if (isClean) {
      return 'Processamento de $scope concluido com sucesso.';
    }

    return 'Processamento de $scope concluido com pendencias ou falhas.';
  }
}

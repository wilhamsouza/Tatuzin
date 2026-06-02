import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tatuzin/app/core/sync/sync_batch_result.dart';
import 'package:tatuzin/app/core/widgets/app_status_badge.dart';
import 'package:tatuzin/modules/account/presentation/providers/account_cloud_providers.dart';
import 'package:tatuzin/modules/account/presentation/support/cloud_sync_feedback.dart';

void main() {
  test('mensagem de sync nao diz nuvem atualizada quando pull falha', () {
    final message = cloudSyncResultMessage(
      _result(pullFailed: true),
      _cloudStatus(),
    );

    expect(
      message,
      'A nuvem precisa de atenção. Seus dados continuam salvos neste aparelho.',
    );
    expect(message, isNot(contains('Nuvem atualizada')));
    expect(message, isNot(contains('Enviados: 0')));
  });

  test('mensagem de sync limpa informa nuvem atualizada', () {
    final message = cloudSyncResultMessage(_result(), _cloudStatus());

    expect(message, 'Nuvem atualizada. Enviados: 0.');
  });
}

SyncBatchResult _result({
  bool pullFailed = false,
  bool snapshotFailed = false,
}) {
  final startedAt = DateTime(2026, 6, 2, 10);
  return SyncBatchResult(
    processedCount: 0,
    syncedCount: 0,
    failedCount: 0,
    blockedCount: 0,
    conflictCount: 0,
    reprocessedOnly: false,
    startedAt: startedAt,
    finishedAt: startedAt.add(const Duration(milliseconds: 1)),
    pullFailed: pullFailed,
    snapshotFailed: snapshotFailed,
  );
}

AccountCloudStatusSnapshot _cloudStatus() {
  return const AccountCloudStatusSnapshot(
    statusLabel: 'Sincronizado',
    statusMessage: 'Dados atualizados.',
    tone: AppStatusTone.success,
    icon: Icons.cloud_done_outlined,
    accountModeLabel: 'Conta online',
    cloudAvailabilityLabel: 'Online',
    syncingNowCount: 0,
    pendingCount: 0,
    errorCount: 0,
    blockedCount: 0,
    conflictCount: 0,
    lastSyncedAt: null,
    nextRetryAt: null,
  );
}

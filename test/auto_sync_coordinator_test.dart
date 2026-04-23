import 'dart:async';

import 'package:erp_pdv_app/app/core/sync/auto_sync_coordinator.dart';
import 'package:erp_pdv_app/app/core/sync/sync_batch_result.dart';
import 'package:erp_pdv_app/app/core/sync/sync_queue_feature_summary.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AutoSyncCoordinator', () {
    test(
      'agenda follow-up sem concorrencia quando mutacao chega no meio do lote',
      () async {
        final snapshots = <AutoSyncCoordinatorSnapshot>[];
        final firstRunCompleter = Completer<SyncBatchResult>();
        var runCount = 0;
        var running = false;

        late final AutoSyncCoordinator coordinator;
        coordinator = AutoSyncCoordinator(
          isEligible: () => true,
          isRunning: () => running,
          runSync: () {
            runCount++;
            if (runCount == 1) {
              running = true;
              return firstRunCompleter.future.whenComplete(() {
                running = false;
              });
            }
            return Future.value(_result());
          },
          loadQueueSummaries: () async => const <SyncQueueFeatureSummary>[],
          onSnapshot: snapshots.add,
          followUpDebounce: const Duration(milliseconds: 10),
        );
        addTearDown(coordinator.dispose);

        unawaited(
          coordinator.runNowIfEligible(reason: 'remote-session-available'),
        );
        await Future<void>.delayed(const Duration(milliseconds: 5));

        coordinator.scheduleSync(
          delay: const Duration(milliseconds: 5),
          reason: 'mutation:products',
        );
        await Future<void>.delayed(const Duration(milliseconds: 10));

        expect(runCount, 1);
        expect(coordinator.snapshot.isRunning, isTrue);
        expect(coordinator.snapshot.followUpQueued, isTrue);

        firstRunCompleter.complete(_result());
        await Future<void>.delayed(const Duration(milliseconds: 40));

        expect(runCount, 2);
        expect(coordinator.snapshot.phase, AutoSyncCoordinatorPhase.idle);
        expect(coordinator.snapshot.followUpQueued, isFalse);
        expect(snapshots.any((snapshot) => snapshot.followUpQueued), isTrue);
      },
    );

    test(
      'escuta mutacoes enfileiradas e agenda auto-sync com debounce',
      () async {
        var runCount = 0;

        final coordinator = AutoSyncCoordinator(
          isEligible: () => true,
          isRunning: () => false,
          runSync: () async {
            runCount++;
            return _result();
          },
          loadQueueSummaries: () async => const <SyncQueueFeatureSummary>[],
          mutationDebounce: const Duration(milliseconds: 15),
        );
        addTearDown(coordinator.dispose);

        SyncMutationSignalBus.instance.notifyEnqueued(featureKey: 'sales');

        await Future<void>.delayed(const Duration(milliseconds: 5));
        expect(coordinator.snapshot.phase, AutoSyncCoordinatorPhase.scheduled);
        expect(coordinator.snapshot.currentReason, 'mutation:sales');

        await Future<void>.delayed(const Duration(milliseconds: 30));
        expect(runCount, 1);
        expect(coordinator.snapshot.phase, AutoSyncCoordinatorPhase.idle);
        expect(coordinator.snapshot.lastResult?.isClean, isTrue);
      },
    );
  });
}

SyncBatchResult _result() {
  final now = DateTime.now();
  return SyncBatchResult(
    processedCount: 1,
    syncedCount: 1,
    failedCount: 0,
    blockedCount: 0,
    conflictCount: 0,
    reprocessedOnly: false,
    startedAt: now,
    finishedAt: now,
  );
}

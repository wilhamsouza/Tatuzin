import '../utils/app_logger.dart';
import 'app_snapshot_remote_datasource.dart';
import 'operational_sync_queue_item.dart';
import 'operational_sync_queue_repository.dart';
import 'operational_sync_remote_datasource.dart';
import 'sync_batch_result.dart';

class OperationalSyncRunner {
  const OperationalSyncRunner({
    required OperationalSyncQueueRepository queueRepository,
    required OperationalSyncRemoteDataSource remoteDataSource,
    required AppSnapshotRemoteDataSource snapshotRemoteDataSource,
    required bool Function() shouldContinue,
    required void Function() onCacheSnapshotChanged,
  }) : _queueRepository = queueRepository,
       _remoteDataSource = remoteDataSource,
       _snapshotRemoteDataSource = snapshotRemoteDataSource,
       _shouldContinue = shouldContinue,
       _onCacheSnapshotChanged = onCacheSnapshotChanged;

  static const int maxEventsPerBatch = 100;
  static const _serverFirstSnapshotFeatures = <String>[
    'products',
    'categories',
    'suppliers',
    'customers',
    'fiado',
    'costs',
    'settings',
    'plan',
  ];

  final OperationalSyncQueueRepository _queueRepository;
  final OperationalSyncRemoteDataSource _remoteDataSource;
  final AppSnapshotRemoteDataSource _snapshotRemoteDataSource;
  final bool Function() _shouldContinue;
  final void Function() _onCacheSnapshotChanged;

  Future<SyncBatchResult> run({
    required bool retryOnly,
    bool ignoreRetryBackoff = false,
  }) async {
    final startedAt = DateTime.now();
    var processedCount = 0;
    var syncedCount = 0;
    var failedCount = 0;
    var conflictCount = 0;

    if (!_shouldContinue()) {
      return _result(
        retryOnly: retryOnly,
        startedAt: startedAt,
        processedCount: processedCount,
        syncedCount: syncedCount,
        failedCount: failedCount,
        conflictCount: conflictCount,
      );
    }

    final pending = await _queueRepository.listPending(
      limit: maxEventsPerBatch,
      retryOnly: retryOnly,
      ignoreRetryBackoff: ignoreRetryBackoff,
    );

    if (pending.isNotEmpty) {
      await _queueRepository.markPushing(pending, startedAt: DateTime.now());
      processedCount += pending.length;
      try {
        final checkpoint = await _queueRepository.readCheckpoint();
        final response = await _remoteDataSource.pushEvents(
          pending.map((item) => item.event).toList(growable: false),
          lastKnownServerVersion: checkpoint,
        );
        if (!_shouldContinue()) {
          return _cancelled(retryOnly: retryOnly, startedAt: startedAt);
        }

        final conflictIdsByEventId = response.conflicts.isEmpty
            ? const <String, String>{}
            : await _loadConflictIdsByEventId();

        for (final item in response.accepted) {
          await _queueRepository.markAccepted(
            eventId: item.eventId,
            serverVersion: item.serverVersion,
            processedAt: DateTime.now(),
          );
          syncedCount++;
        }
        for (final item in response.duplicates) {
          await _queueRepository.markDuplicate(
            eventId: item.eventId,
            serverVersion: item.serverVersion,
            processedAt: DateTime.now(),
          );
          syncedCount++;
        }
        for (final item in response.rejected) {
          await _queueRepository.markRejected(
            eventId: item.eventId,
            code: item.code ?? 'SYNC_REJECTED',
            message: item.message ?? 'Evento recusado pelo servidor.',
            processedAt: DateTime.now(),
          );
          failedCount++;
        }
        for (final item in response.conflicts) {
          await _queueRepository.markConflict(
            eventId: item.eventId,
            serverVersion: item.serverVersion,
            code: item.code ?? 'SYNC_CONFLICT',
            message: item.message ?? 'Conflito de sincronizacao.',
            conflictId: conflictIdsByEventId[item.eventId],
            processedAt: DateTime.now(),
          );
          conflictCount++;
        }
      } catch (error, stackTrace) {
        failedCount += pending.length;
        await _queueRepository.markFailed(
          pending,
          message: error.toString(),
          failedAt: DateTime.now(),
          nextRetryAt: _nextRetryAt(pending),
        );
        AppLogger.error(
          '[OperationalSync] push_failed',
          error: error,
          stackTrace: stackTrace,
        );
      }
    }

    if (_shouldContinue()) {
      await _pullAndRefreshSnapshot();
    }

    return _result(
      retryOnly: retryOnly,
      startedAt: startedAt,
      processedCount: processedCount,
      syncedCount: syncedCount,
      failedCount: failedCount,
      conflictCount: conflictCount,
    );
  }

  Future<void> _pullAndRefreshSnapshot() async {
    try {
      final checkpoint = await _queueRepository.readCheckpoint();
      final pull = await _remoteDataSource.pullChanges(
        sinceVersion: checkpoint,
        features: const <String>['pdv'],
        limit: 100,
      );
      await _queueRepository.saveCheckpoint(pull.nextSinceVersion);

      final status = await _remoteDataSource.getStatus();
      if (status.currentServerVersion.trim().isNotEmpty) {
        await _queueRepository.saveCheckpoint(status.currentServerVersion);
      }

      final previousSnapshotVersion = await _queueRepository
          .readSnapshotVersion();
      final snapshot = await _snapshotRemoteDataSource.fetchSnapshot(
        features: _serverFirstSnapshotFeatures,
      );
      if (snapshot.serverFirstSnapshotVersion != previousSnapshotVersion) {
        await _queueRepository.saveSnapshotVersion(
          snapshot.serverFirstSnapshotVersion,
        );
        _onCacheSnapshotChanged();
        AppLogger.info(
          '[OperationalSync] server_first_snapshot_changed '
          'version=${snapshot.serverFirstSnapshotVersion}',
        );
      }
    } catch (error, stackTrace) {
      AppLogger.error(
        '[OperationalSync] pull_or_snapshot_failed',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<Map<String, String>> _loadConflictIdsByEventId() async {
    try {
      final conflicts = await _remoteDataSource.getConflicts();
      return <String, String>{
        for (final conflict in conflicts)
          if (conflict.eventId != null) conflict.eventId!: conflict.id,
      };
    } catch (error, stackTrace) {
      AppLogger.error(
        '[OperationalSync] conflict_lookup_failed',
        error: error,
        stackTrace: stackTrace,
      );
      return const <String, String>{};
    }
  }

  DateTime _nextRetryAt(List<OperationalSyncQueueItem> items) {
    final maxAttempt = items.fold<int>(
      1,
      (max, item) => item.attemptCount >= max ? item.attemptCount + 1 : max,
    );
    final seconds = (5 * (1 << (maxAttempt - 1))).clamp(5, 300).toInt();
    return DateTime.now().add(Duration(seconds: seconds));
  }

  SyncBatchResult _cancelled({
    required bool retryOnly,
    required DateTime startedAt,
  }) {
    return _result(retryOnly: retryOnly, startedAt: startedAt);
  }

  SyncBatchResult _result({
    required bool retryOnly,
    required DateTime startedAt,
    int processedCount = 0,
    int syncedCount = 0,
    int failedCount = 0,
    int conflictCount = 0,
  }) {
    return SyncBatchResult(
      processedCount: processedCount,
      syncedCount: syncedCount,
      failedCount: failedCount,
      blockedCount: 0,
      conflictCount: conflictCount,
      reprocessedOnly: retryOnly,
      startedAt: startedAt,
      finishedAt: DateTime.now(),
    );
  }
}

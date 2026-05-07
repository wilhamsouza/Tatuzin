import '../utils/app_logger.dart';
import 'app_snapshot_remote_datasource.dart';
import 'operational_sync_policy.dart';
import 'operational_sync_projection_applier.dart';
import 'operational_sync_queue_item.dart';
import 'operational_sync_queue_repository.dart';
import 'operational_sync_remote_datasource.dart';
import 'sync_batch_result.dart';

class OperationalSyncRunner {
  const OperationalSyncRunner({
    required OperationalSyncQueueRepository queueRepository,
    required OperationalSyncRemoteDataSource remoteDataSource,
    OperationalSyncProjectionApplier projectionApplier =
        const NoopOperationalSyncProjectionApplier(),
    required AppSnapshotRemoteDataSource snapshotRemoteDataSource,
    required bool Function() shouldContinue,
    required void Function() onCacheSnapshotChanged,
  }) : _queueRepository = queueRepository,
       _remoteDataSource = remoteDataSource,
       _projectionApplier = projectionApplier,
       _snapshotRemoteDataSource = snapshotRemoteDataSource,
       _shouldContinue = shouldContinue,
       _onCacheSnapshotChanged = onCacheSnapshotChanged;

  static const int maxEventsPerBatch = 100;
  static const int pullLimitPerPage = 100;
  static const int maxPullPagesPerRun = 10;
  static const int maxPullChangesPerRun = 1000;
  static const stalePushingAfter = Duration(minutes: 2);
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
  final OperationalSyncProjectionApplier _projectionApplier;
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

    await _queueRepository.recoverStalePushing(staleAfter: stalePushingAfter);

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

    final refreshOutcome = _shouldContinue()
        ? await _pullAndRefreshSnapshot()
        : const _RefreshOutcome();

    return _result(
      retryOnly: retryOnly,
      startedAt: startedAt,
      processedCount: processedCount,
      syncedCount: syncedCount,
      failedCount: failedCount,
      conflictCount: conflictCount,
      pullFailed: refreshOutcome.pullFailed,
      snapshotFailed: refreshOutcome.snapshotFailed,
      lastPullError: refreshOutcome.lastPullError,
      lastSnapshotError: refreshOutcome.lastSnapshotError,
    );
  }

  Future<_RefreshOutcome> _pullAndRefreshSnapshot() async {
    var pullFailed = false;
    var snapshotFailed = false;
    String? lastPullError;
    String? lastSnapshotError;

    try {
      final checkpoint = await _queueRepository.readCheckpoint();
      final pullOutcome = await _pullOperationalPages(checkpoint);
      final status = await _remoteDataSource.getStatus();
      if (pullOutcome.canFastForwardWithStatus &&
          _isVersionAhead(
            status.currentServerVersion,
            pullOutcome.appliedCheckpoint,
          )) {
        await _queueRepository.saveCheckpoint(status.currentServerVersion);
      }
      await _queueRepository.recordPullSucceeded(completedAt: DateTime.now());
    } catch (error, stackTrace) {
      pullFailed = true;
      lastPullError = error.toString();
      await _queueRepository.recordPullFailed(
        message: lastPullError,
        failedAt: DateTime.now(),
      );
      AppLogger.error(
        '[OperationalSync] pull_failed_after_push',
        error: error,
        stackTrace: stackTrace,
      );
      return _RefreshOutcome(
        pullFailed: pullFailed,
        snapshotFailed: snapshotFailed,
        lastPullError: lastPullError,
        lastSnapshotError: lastSnapshotError,
      );
    }

    try {
      final previousSnapshotVersion = await _queueRepository
          .readSnapshotVersion();
      final snapshot = await _snapshotRemoteDataSource.fetchSnapshot(
        features: _serverFirstSnapshotFeatures,
      );
      await _queueRepository.recordSnapshotSucceeded(
        serverFirstSnapshotVersion: snapshot.serverFirstSnapshotVersion,
        completedAt: DateTime.now(),
      );
      if (snapshot.serverFirstSnapshotVersion != previousSnapshotVersion) {
        _onCacheSnapshotChanged();
        AppLogger.info(
          '[OperationalSync] server_first_snapshot_changed '
          'version=${snapshot.serverFirstSnapshotVersion}',
        );
      }
    } catch (error, stackTrace) {
      snapshotFailed = true;
      lastSnapshotError = error.toString();
      await _queueRepository.recordSnapshotFailed(
        message: lastSnapshotError,
        failedAt: DateTime.now(),
      );
      AppLogger.error(
        '[OperationalSync] snapshot_failed_after_push',
        error: error,
        stackTrace: stackTrace,
      );
    }

    return _RefreshOutcome(
      pullFailed: pullFailed,
      snapshotFailed: snapshotFailed,
      lastPullError: lastPullError,
      lastSnapshotError: lastSnapshotError,
    );
  }

  Future<_PullPagesOutcome> _pullOperationalPages(String checkpoint) async {
    var sinceVersion = checkpoint;
    var safeCheckpoint = checkpoint;
    var pageCount = 0;
    var processedChanges = 0;
    var pulledAnyChange = false;

    while (_shouldContinue()) {
      if (pageCount >= maxPullPagesPerRun) {
        AppLogger.warn(
          '[OperationalSync] pull_page_limit_reached '
          'pages=$pageCount checkpoint=$safeCheckpoint',
        );
        return _PullPagesOutcome(
          appliedCheckpoint: safeCheckpoint,
          reachedSafetyLimit: true,
        );
      }
      if (processedChanges >= maxPullChangesPerRun) {
        AppLogger.warn(
          '[OperationalSync] pull_change_limit_reached '
          'changes=$processedChanges checkpoint=$safeCheckpoint',
        );
        return _PullPagesOutcome(
          appliedCheckpoint: safeCheckpoint,
          reachedSafetyLimit: true,
        );
      }

      final pageStartingCheckpoint = safeCheckpoint;
      final pull = await _remoteDataSource.pullChanges(
        sinceVersion: sinceVersion,
        features: const <String>['pdv'],
        limit: pullLimitPerPage,
      );
      pageCount++;

      if (pull.changes.isEmpty) {
        if (pull.hasMore) {
          AppLogger.warn(
            '[OperationalSync] pull_page_empty_with_has_more '
            'page=$pageCount checkpoint=$safeCheckpoint',
          );
        }
        return _PullPagesOutcome(
          appliedCheckpoint: safeCheckpoint,
          canFastForwardWithStatus: !pulledAnyChange && !pull.hasMore,
        );
      }

      pulledAnyChange = true;
      final remainingChanges = maxPullChangesPerRun - processedChanges;
      final applyOutcome = await _applyPulledChanges(
        pull,
        startingCheckpoint: safeCheckpoint,
        maxChanges: remainingChanges,
      );
      safeCheckpoint = applyOutcome.safeCheckpoint;
      processedChanges += applyOutcome.processedChanges;

      if (applyOutcome.reachedChangeLimit) {
        AppLogger.warn(
          '[OperationalSync] pull_change_limit_reached '
          'changes=$processedChanges checkpoint=$safeCheckpoint',
        );
        return _PullPagesOutcome(
          appliedCheckpoint: safeCheckpoint,
          reachedSafetyLimit: true,
        );
      }

      if (!pull.hasMore) {
        return _PullPagesOutcome(appliedCheckpoint: safeCheckpoint);
      }

      if (!_isVersionAhead(safeCheckpoint, pageStartingCheckpoint)) {
        AppLogger.warn(
          '[OperationalSync] pull_page_non_advancing '
          'page=$pageCount checkpoint=$safeCheckpoint',
        );
        return _PullPagesOutcome(
          appliedCheckpoint: safeCheckpoint,
          reachedSafetyLimit: true,
        );
      }

      sinceVersion = safeCheckpoint;
    }

    return _PullPagesOutcome(
      appliedCheckpoint: safeCheckpoint,
      reachedSafetyLimit: true,
    );
  }

  Future<_ApplyPulledChangesOutcome> _applyPulledChanges(
    OperationalSyncPullResponse pull, {
    required String startingCheckpoint,
    required int maxChanges,
  }) async {
    var safeCheckpoint = startingCheckpoint;
    if (pull.changes.isEmpty) {
      return _ApplyPulledChangesOutcome(safeCheckpoint: safeCheckpoint);
    }

    final orderedChanges = pull.changes.toList(growable: false)
      ..sort(_comparePulledChanges);
    var processedChanges = 0;
    for (final change in orderedChanges) {
      if (processedChanges >= maxChanges) {
        return _ApplyPulledChangesOutcome(
          safeCheckpoint: safeCheckpoint,
          processedChanges: processedChanges,
          reachedChangeLimit: true,
        );
      }

      final changeVersion = change.serverVersion;
      if (changeVersion == null || changeVersion.trim().isEmpty) {
        continue;
      }
      if (!_isVersionAhead(changeVersion, safeCheckpoint)) {
        AppLogger.warn(
          '[OperationalSync] pull_change_non_advancing '
          'eventId=${change.eventId} entity=${change.entity} '
          'serverVersion=$changeVersion checkpoint=$safeCheckpoint',
        );
        continue;
      }
      processedChanges++;

      if (!OperationalSyncPolicy.isLocalFirstEntity(change.entity)) {
        AppLogger.warn(
          '[OperationalSync] pull_change_ignored entity=${change.entity} '
          'eventId=${change.eventId} reason=not_local_first',
        );
        safeCheckpoint = changeVersion;
        await _queueRepository.saveCheckpoint(safeCheckpoint);
        continue;
      }

      if (change.projection == null) {
        if (pull.usesProjectionContract && change.projectionWarning != null) {
          const message =
              '$operationalSyncPartialDataMessage. Tente sincronizar novamente.';
          AppLogger.warn(
            '[OperationalSync] pull_projection_warning eventId=${change.eventId} '
            'entity=${change.entity} warning=${change.projectionWarning}',
          );
          throw const _OperationalSyncPullProjectionWarning(message);
        }

        safeCheckpoint = changeVersion;
        await _queueRepository.saveCheckpoint(safeCheckpoint);
        continue;
      }

      await _projectionApplier.apply(change);
      safeCheckpoint = changeVersion;
      await _queueRepository.saveCheckpoint(safeCheckpoint);
    }

    return _ApplyPulledChangesOutcome(
      safeCheckpoint: safeCheckpoint,
      processedChanges: processedChanges,
    );
  }

  int _comparePulledChanges(
    OperationalSyncPulledEvent left,
    OperationalSyncPulledEvent right,
  ) {
    final leftVersion = left.serverVersion?.trim();
    final rightVersion = right.serverVersion?.trim();
    if (leftVersion == null || leftVersion.isEmpty) {
      return rightVersion == null || rightVersion.isEmpty ? 0 : 1;
    }
    if (rightVersion == null || rightVersion.isEmpty) {
      return -1;
    }
    final leftNumber = int.tryParse(leftVersion);
    final rightNumber = int.tryParse(rightVersion);
    if (leftNumber != null && rightNumber != null) {
      return leftNumber.compareTo(rightNumber);
    }
    return leftVersion.compareTo(rightVersion);
  }

  bool _isVersionAhead(String candidate, String current) {
    final candidateValue = int.tryParse(candidate.trim());
    final currentValue = int.tryParse(current.trim());
    if (candidateValue != null && currentValue != null) {
      return candidateValue > currentValue;
    }
    return candidate.trim().isNotEmpty && candidate != current;
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
    bool pullFailed = false,
    bool snapshotFailed = false,
    String? lastPullError,
    String? lastSnapshotError,
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
      pullFailed: pullFailed,
      snapshotFailed: snapshotFailed,
      lastPullError: lastPullError,
      lastSnapshotError: lastSnapshotError,
    );
  }
}

class _RefreshOutcome {
  const _RefreshOutcome({
    this.pullFailed = false,
    this.snapshotFailed = false,
    this.lastPullError,
    this.lastSnapshotError,
  });

  final bool pullFailed;
  final bool snapshotFailed;
  final String? lastPullError;
  final String? lastSnapshotError;
}

class _PullPagesOutcome {
  const _PullPagesOutcome({
    required this.appliedCheckpoint,
    this.canFastForwardWithStatus = false,
    this.reachedSafetyLimit = false,
  });

  final String appliedCheckpoint;
  final bool canFastForwardWithStatus;
  final bool reachedSafetyLimit;
}

class _ApplyPulledChangesOutcome {
  const _ApplyPulledChangesOutcome({
    required this.safeCheckpoint,
    this.processedChanges = 0,
    this.reachedChangeLimit = false,
  });

  final String safeCheckpoint;
  final int processedChanges;
  final bool reachedChangeLimit;
}

class _OperationalSyncPullProjectionWarning implements Exception {
  const _OperationalSyncPullProjectionWarning(this.message);

  final String message;

  @override
  String toString() => message;
}

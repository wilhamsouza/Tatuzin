import 'sync_batch_result.dart';
import 'sync_dependency_resolver.dart';
import 'sync_error_info.dart';
import 'sync_feature_keys.dart';
import 'sync_feature_processor.dart';
import 'sync_queue_feature_summary.dart';
import 'sync_queue_operation.dart';
import 'sync_queue_repository.dart';
import 'sync_retry_policy.dart';
import '../utils/app_logger.dart';

class SyncQueueEngine {
  const SyncQueueEngine({
    required SyncQueueRepository queueRepository,
    required List<SyncFeatureProcessor> processors,
    required SyncRetryPolicy retryPolicy,
    required SyncDependencyResolver dependencyResolver,
    required bool Function() shouldContinue,
  }) : _queueRepository = queueRepository,
       _processors = processors,
       _retryPolicy = retryPolicy,
       _dependencyResolver = dependencyResolver,
       _shouldContinue = shouldContinue;

  final SyncQueueRepository _queueRepository;
  final List<SyncFeatureProcessor> _processors;
  final SyncRetryPolicy _retryPolicy;
  final SyncDependencyResolver _dependencyResolver;
  final bool Function() _shouldContinue;

  Future<SyncBatchResult> process({
    Iterable<String>? featureKeys,
    required bool retryOnly,
    bool ignoreRetryBackoff = false,
  }) async {
    final startedAt = DateTime.now();
    var processedCount = 0;
    var syncedCount = 0;
    var failedCount = 0;
    var blockedCount = 0;
    var conflictCount = 0;
    var skippedCount = 0;

    final initialSummaries = await _queueRepository.listFeatureSummaries();
    AppLogger.info(
      '[Sync] batch_started '
      'pending=${_sumPending(initialSummaries)} '
      'error=${_sumErrors(initialSummaries)} '
      'blocked=${_sumBlocked(initialSummaries)} '
      'retryOnly=$retryOnly ignoreBackoff=$ignoreRetryBackoff',
    );

    for (final processor in _orderedProcessors(featureKeys)) {
      if (!_shouldContinue()) {
        break;
      }

      final eligibleItems = await _queueRepository.listEligibleItems(
        featureKeys: [processor.featureKey],
        retryOnly: retryOnly,
        ignoreRetryBackoff: ignoreRetryBackoff,
        now: DateTime.now(),
      );
      if (eligibleItems.isEmpty) {
        skippedCount++;
        continue;
      }

      try {
        await processor.ensureSyncAllowed();
      } catch (error) {
        final syncError = resolveSyncError(error);
        AppLogger.info(
          '[Sync] auto_sync_skipped reason=processor_not_allowed '
          'feature=${processor.featureKey} error=${syncError.message}',
        );
        for (final item in eligibleItems) {
          failedCount++;
          final now = DateTime.now();
          final nextRetryAt = _retryPolicy.nextRetryAt(
            attemptCount: item.attemptCount,
            errorType: syncError.type,
            now: now,
          );
          await _queueRepository.markFailure(
            item.id,
            message: syncError.message,
            errorType: syncError.type,
            processedAt: now,
            nextRetryAt: nextRetryAt,
          );
        }
        continue;
      }

      for (final candidate in eligibleItems) {
        if (!_shouldContinue()) {
          break;
        }

        final locked = await _queueRepository.lockItem(candidate.id);
        if (locked == null) {
          continue;
        }

        processedCount++;
        var activeItem = locked;
        AppLogger.info(
          '[Sync] item_started id=${activeItem.id} '
          'entity=${activeItem.entityType} '
          'operation=${activeItem.operation.storageValue} '
          'attempt=${activeItem.attemptCount}',
        );

        final dependency = await _dependencyResolver.check(locked);
        if (dependency.isBlocked) {
          blockedCount++;
          await _queueRepository.markBlocked(
            locked.id,
            reason: dependency.reason ?? 'Dependencia pendente.',
            blockedAt: DateTime.now(),
          );
          continue;
        }

        try {
          var result = await processor.processQueueItem(activeItem);
          if (!_shouldContinue()) {
            break;
          }

          if (result.outcome == SyncFeatureProcessOutcome.requeued) {
            final retried = await _queueRepository.lockItem(activeItem.id);
            if (retried != null) {
              activeItem = retried;
              result = await processor.processQueueItem(activeItem);
              if (!_shouldContinue()) {
                break;
              }
            }
          }

          switch (result.outcome) {
            case SyncFeatureProcessOutcome.synced:
              syncedCount++;
              await _queueRepository.markSynced(
                activeItem.id,
                remoteId: result.remoteId ?? activeItem.remoteId,
                processedAt: DateTime.now(),
              );
              AppLogger.info(
                '[Sync] item_succeeded id=${activeItem.id} '
                'entity=${activeItem.entityType} '
                'operation=${activeItem.operation.storageValue}',
              );
              break;
            case SyncFeatureProcessOutcome.blocked:
              blockedCount++;
              await _queueRepository.markBlocked(
                activeItem.id,
                reason: result.message ?? 'Dependencia pendente.',
                blockedAt: DateTime.now(),
              );
              break;
            case SyncFeatureProcessOutcome.conflict:
              conflictCount++;
              await _queueRepository.markConflict(
                activeItem.id,
                conflict: result.conflict!,
                processedAt: DateTime.now(),
              );
              break;
            case SyncFeatureProcessOutcome.requeued:
              break;
          }
        } catch (error) {
          if (!_shouldContinue()) {
            break;
          }

          failedCount++;
          final syncError = resolveSyncError(error);
          final nextRetryAt = _retryPolicy.nextRetryAt(
            attemptCount: activeItem.attemptCount,
            errorType: syncError.type,
            now: DateTime.now(),
          );
          await _queueRepository.markFailure(
            activeItem.id,
            message: syncError.message,
            errorType: syncError.type,
            processedAt: DateTime.now(),
            nextRetryAt: nextRetryAt,
          );
          AppLogger.info(
            '[Sync] item_failed id=${activeItem.id} '
            'entity=${activeItem.entityType} '
            'operation=${activeItem.operation.storageValue} '
            'error=${syncError.message} '
            'nextRetryAt=${nextRetryAt?.toIso8601String() ?? 'none'}',
          );
        }
      }

      if (!_shouldContinue()) {
        break;
      }

      await processor.pullRemoteSnapshot();
    }

    final finishedAt = DateTime.now();
    AppLogger.info(
      '[Sync] batch_finished '
      'sent=$syncedCount failed=$failedCount skipped=$skippedCount '
      'blocked=$blockedCount conflicts=$conflictCount '
      'duration_ms=${finishedAt.difference(startedAt).inMilliseconds}',
    );
    AppLogger.info(
      '[Sync] last_sync_completed_updated at=${finishedAt.toIso8601String()}',
    );

    return SyncBatchResult(
      processedCount: processedCount,
      syncedCount: syncedCount,
      failedCount: failedCount,
      blockedCount: blockedCount,
      conflictCount: conflictCount,
      reprocessedOnly: retryOnly,
      startedAt: startedAt,
      finishedAt: finishedAt,
    );
  }

  int _sumPending(List<SyncQueueFeatureSummary> summaries) =>
      summaries.fold<int>(
        0,
        (total, summary) =>
            total + summary.pendingCount + summary.staleProcessingCount,
      );

  int _sumErrors(List<SyncQueueFeatureSummary> summaries) =>
      summaries.fold<int>(0, (total, summary) => total + summary.errorCount);

  int _sumBlocked(List<SyncQueueFeatureSummary> summaries) =>
      summaries.fold<int>(0, (total, summary) => total + summary.blockedCount);

  List<SyncFeatureProcessor> _orderedProcessors(Iterable<String>? featureKeys) {
    final filtered = featureKeys == null
        ? _processors
        : _processors
              .where((processor) => featureKeys.contains(processor.featureKey))
              .toList();

    filtered.sort(
      (left, right) =>
          _priorityOf(left.featureKey).compareTo(_priorityOf(right.featureKey)),
    );
    return filtered;
  }

  int _priorityOf(String featureKey) {
    switch (featureKey) {
      case SyncFeatureKeys.categories:
        return 0;
      case SyncFeatureKeys.suppliers:
        return 1;
      case SyncFeatureKeys.supplies:
        return 2;
      case SyncFeatureKeys.products:
        return 3;
      case SyncFeatureKeys.productRecipes:
        return 4;
      case SyncFeatureKeys.customers:
        return 5;
      case SyncFeatureKeys.purchases:
        return 6;
      case SyncFeatureKeys.sales:
        return 7;
      case SyncFeatureKeys.financialEvents:
        return 8;
      case SyncFeatureKeys.saleCancellations:
        return 9;
      case SyncFeatureKeys.fiadoPayments:
        return 10;
      case SyncFeatureKeys.cashEvents:
        return 11;
      default:
        return 99;
    }
  }
}

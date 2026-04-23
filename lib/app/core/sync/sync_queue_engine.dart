import 'sync_batch_result.dart';
import 'sync_dependency_resolver.dart';
import 'sync_error_info.dart';
import 'sync_feature_keys.dart';
import 'sync_feature_processor.dart';
import 'sync_queue_repository.dart';
import 'sync_retry_policy.dart';

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
  }) async {
    final startedAt = DateTime.now();
    var processedCount = 0;
    var syncedCount = 0;
    var failedCount = 0;
    var blockedCount = 0;
    var conflictCount = 0;

    for (final processor in _orderedProcessors(featureKeys)) {
      if (!_shouldContinue()) {
        break;
      }

      await processor.ensureSyncAllowed();

      final eligibleItems = await _queueRepository.listEligibleItems(
        featureKeys: [processor.featureKey],
        retryOnly: retryOnly,
        now: DateTime.now(),
      );

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
        }
      }

      if (!_shouldContinue()) {
        break;
      }

      await processor.pullRemoteSnapshot();
    }

    return SyncBatchResult(
      processedCount: processedCount,
      syncedCount: syncedCount,
      failedCount: failedCount,
      blockedCount: blockedCount,
      conflictCount: conflictCount,
      reprocessedOnly: retryOnly,
      startedAt: startedAt,
      finishedAt: DateTime.now(),
    );
  }

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

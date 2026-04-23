import 'dart:async';

import '../utils/app_logger.dart';
import 'sync_batch_result.dart';
import 'sync_queue_feature_summary.dart';

class SyncMutationSignal {
  const SyncMutationSignal({
    required this.featureKey,
    required this.enqueuedAt,
  });

  final String featureKey;
  final DateTime enqueuedAt;
}

class SyncMutationSignalBus {
  SyncMutationSignalBus._();

  static final SyncMutationSignalBus instance = SyncMutationSignalBus._();

  final StreamController<SyncMutationSignal> _controller =
      StreamController<SyncMutationSignal>.broadcast();

  Stream<SyncMutationSignal> get stream => _controller.stream;

  void notifyEnqueued({required String featureKey, DateTime? enqueuedAt}) {
    if (_controller.isClosed) {
      return;
    }

    _controller.add(
      SyncMutationSignal(
        featureKey: featureKey,
        enqueuedAt: enqueuedAt ?? DateTime.now(),
      ),
    );
  }
}

enum AutoSyncCoordinatorPhase { idle, scheduled, running }

extension AutoSyncCoordinatorPhaseX on AutoSyncCoordinatorPhase {
  String get label {
    switch (this) {
      case AutoSyncCoordinatorPhase.idle:
        return 'Ocioso';
      case AutoSyncCoordinatorPhase.scheduled:
        return 'Programado';
      case AutoSyncCoordinatorPhase.running:
        return 'Em execucao';
    }
  }
}

class AutoSyncCoordinatorSnapshot {
  const AutoSyncCoordinatorSnapshot({
    required this.phase,
    required this.currentReason,
    required this.nextScheduledAt,
    required this.followUpQueued,
    required this.lastRequestedAt,
    required this.lastStartedAt,
    required this.lastFinishedAt,
    required this.lastSuccessfulAt,
    required this.lastSkippedReason,
    required this.lastFailureMessage,
    required this.lastResult,
  });

  const AutoSyncCoordinatorSnapshot.idle()
    : phase = AutoSyncCoordinatorPhase.idle,
      currentReason = null,
      nextScheduledAt = null,
      followUpQueued = false,
      lastRequestedAt = null,
      lastStartedAt = null,
      lastFinishedAt = null,
      lastSuccessfulAt = null,
      lastSkippedReason = null,
      lastFailureMessage = null,
      lastResult = null;

  final AutoSyncCoordinatorPhase phase;
  final String? currentReason;
  final DateTime? nextScheduledAt;
  final bool followUpQueued;
  final DateTime? lastRequestedAt;
  final DateTime? lastStartedAt;
  final DateTime? lastFinishedAt;
  final DateTime? lastSuccessfulAt;
  final String? lastSkippedReason;
  final String? lastFailureMessage;
  final SyncBatchResult? lastResult;

  bool get isScheduled => phase == AutoSyncCoordinatorPhase.scheduled;

  bool get isRunning => phase == AutoSyncCoordinatorPhase.running;

  AutoSyncCoordinatorSnapshot copyWith({
    AutoSyncCoordinatorPhase? phase,
    String? currentReason,
    bool clearCurrentReason = false,
    DateTime? nextScheduledAt,
    bool clearNextScheduledAt = false,
    bool? followUpQueued,
    DateTime? lastRequestedAt,
    bool clearLastRequestedAt = false,
    DateTime? lastStartedAt,
    bool clearLastStartedAt = false,
    DateTime? lastFinishedAt,
    bool clearLastFinishedAt = false,
    DateTime? lastSuccessfulAt,
    bool clearLastSuccessfulAt = false,
    String? lastSkippedReason,
    bool clearLastSkippedReason = false,
    String? lastFailureMessage,
    bool clearLastFailureMessage = false,
    SyncBatchResult? lastResult,
    bool clearLastResult = false,
  }) {
    return AutoSyncCoordinatorSnapshot(
      phase: phase ?? this.phase,
      currentReason: clearCurrentReason
          ? null
          : currentReason ?? this.currentReason,
      nextScheduledAt: clearNextScheduledAt
          ? null
          : nextScheduledAt ?? this.nextScheduledAt,
      followUpQueued: followUpQueued ?? this.followUpQueued,
      lastRequestedAt: clearLastRequestedAt
          ? null
          : lastRequestedAt ?? this.lastRequestedAt,
      lastStartedAt: clearLastStartedAt
          ? null
          : lastStartedAt ?? this.lastStartedAt,
      lastFinishedAt: clearLastFinishedAt
          ? null
          : lastFinishedAt ?? this.lastFinishedAt,
      lastSuccessfulAt: clearLastSuccessfulAt
          ? null
          : lastSuccessfulAt ?? this.lastSuccessfulAt,
      lastSkippedReason: clearLastSkippedReason
          ? null
          : lastSkippedReason ?? this.lastSkippedReason,
      lastFailureMessage: clearLastFailureMessage
          ? null
          : lastFailureMessage ?? this.lastFailureMessage,
      lastResult: clearLastResult ? null : lastResult ?? this.lastResult,
    );
  }
}

class AutoSyncCoordinator {
  AutoSyncCoordinator({
    required bool Function() isEligible,
    required bool Function() isRunning,
    required Future<SyncBatchResult> Function() runSync,
    required Future<List<SyncQueueFeatureSummary>> Function()
    loadQueueSummaries,
    void Function(AutoSyncCoordinatorSnapshot snapshot)? onSnapshot,
    DateTime Function()? now,
    Duration lifecycleDebounce = const Duration(seconds: 1),
    Duration mutationDebounce = const Duration(seconds: 2),
    Duration followUpDebounce = const Duration(seconds: 2),
  }) : _isEligible = isEligible,
       _isRunning = isRunning,
       _runSync = runSync,
       _loadQueueSummaries = loadQueueSummaries,
       _onSnapshot = onSnapshot,
       _now = now ?? DateTime.now,
       _lifecycleDebounce = lifecycleDebounce,
       _mutationDebounce = mutationDebounce,
       _followUpDebounce = followUpDebounce {
    _mutationSubscription = SyncMutationSignalBus.instance.stream.listen((
      signal,
    ) {
      scheduleSync(
        delay: _mutationDebounce,
        reason: 'mutation:${signal.featureKey}',
      );
    });
  }

  final bool Function() _isEligible;
  final bool Function() _isRunning;
  final Future<SyncBatchResult> Function() _runSync;
  final Future<List<SyncQueueFeatureSummary>> Function() _loadQueueSummaries;
  final void Function(AutoSyncCoordinatorSnapshot snapshot)? _onSnapshot;
  final DateTime Function() _now;
  final Duration _lifecycleDebounce;
  final Duration _mutationDebounce;
  final Duration _followUpDebounce;

  Timer? _timer;
  StreamSubscription<SyncMutationSignal>? _mutationSubscription;
  bool _disposed = false;
  bool _runAgainAfterCurrentBatch = false;
  AutoSyncCoordinatorSnapshot _snapshot =
      const AutoSyncCoordinatorSnapshot.idle();

  AutoSyncCoordinatorSnapshot get snapshot => _snapshot;

  void scheduleSync({Duration? delay, String reason = 'scheduled'}) {
    if (_disposed) {
      return;
    }

    if (!_isEligible()) {
      cancelPending(
        skippedReason: 'nao_elegivel:$reason',
        clearLastRequestedAt: false,
      );
      return;
    }

    final effectiveDelay = delay ?? _mutationDebounce;
    final requestedAt = _now();
    final scheduledAt = requestedAt.add(effectiveDelay);

    if (_isRunning()) {
      _runAgainAfterCurrentBatch = true;
      _publishSnapshot(
        _snapshot.copyWith(
          phase: AutoSyncCoordinatorPhase.running,
          currentReason: reason,
          clearNextScheduledAt: true,
          followUpQueued: true,
          lastRequestedAt: requestedAt,
          clearLastSkippedReason: true,
        ),
      );
      return;
    }

    _timer?.cancel();
    _timer = Timer(effectiveDelay, () {
      unawaited(runNowIfEligible(reason: reason));
    });

    _publishSnapshot(
      _snapshot.copyWith(
        phase: AutoSyncCoordinatorPhase.scheduled,
        currentReason: reason,
        nextScheduledAt: scheduledAt,
        followUpQueued: _runAgainAfterCurrentBatch,
        lastRequestedAt: requestedAt,
        clearLastSkippedReason: true,
      ),
    );
  }

  Future<void> runNowIfEligible({String reason = 'manual'}) async {
    if (_disposed) {
      return;
    }

    final requestedAt = _now();
    if (!_isEligible()) {
      cancelPending(
        skippedReason: 'nao_elegivel:$reason',
        clearLastRequestedAt: false,
      );
      _publishSnapshot(
        _snapshot.copyWith(
          lastRequestedAt: requestedAt,
          lastSkippedReason: 'nao_elegivel:$reason',
        ),
      );
      return;
    }

    if (_isRunning()) {
      _runAgainAfterCurrentBatch = true;
      AppLogger.info(
        'Auto sync adiado porque ja existe um lote em andamento | reason=$reason',
      );
      _publishSnapshot(
        _snapshot.copyWith(
          phase: AutoSyncCoordinatorPhase.running,
          currentReason: reason,
          followUpQueued: true,
          lastRequestedAt: requestedAt,
          lastSkippedReason: 'ja_existe_lote_em_andamento:$reason',
        ),
      );
      return;
    }

    cancelPending(clearLastRequestedAt: false);

    final startedAt = _now();
    _publishSnapshot(
      _snapshot.copyWith(
        phase: AutoSyncCoordinatorPhase.running,
        currentReason: reason,
        clearNextScheduledAt: true,
        followUpQueued: false,
        lastRequestedAt: requestedAt,
        lastStartedAt: startedAt,
        clearLastSkippedReason: true,
        clearLastFailureMessage: true,
      ),
    );

    try {
      AppLogger.info('Auto sync iniciado | reason=$reason');
      final result = await _runSync();
      final finishedAt = _now();
      _publishSnapshot(
        _snapshot.copyWith(
          phase: AutoSyncCoordinatorPhase.running,
          currentReason: reason,
          lastFinishedAt: finishedAt,
          lastSuccessfulAt: result.isClean
              ? finishedAt
              : _snapshot.lastSuccessfulAt,
          lastResult: result,
          clearLastFailureMessage: true,
        ),
      );
    } catch (error, stackTrace) {
      final finishedAt = _now();
      AppLogger.error('Auto sync falhou', error: error, stackTrace: stackTrace);
      _publishSnapshot(
        _snapshot.copyWith(
          phase: AutoSyncCoordinatorPhase.running,
          currentReason: reason,
          lastFinishedAt: finishedAt,
          lastFailureMessage: error.toString(),
        ),
      );
    } finally {
      if (!_disposed) {
        final shouldRunAgain = _runAgainAfterCurrentBatch;
        _runAgainAfterCurrentBatch = false;

        if (shouldRunAgain) {
          scheduleSync(
            delay: _followUpDebounce,
            reason: 'follow-up-after-running-batch',
          );
        } else {
          final scheduledRetry = await _scheduleRetryWakeupIfNeeded();
          if (!scheduledRetry) {
            _publishSnapshot(
              _snapshot.copyWith(
                phase: AutoSyncCoordinatorPhase.idle,
                clearCurrentReason: true,
                clearNextScheduledAt: true,
                followUpQueued: false,
              ),
            );
          }
        }
      }
    }
  }

  void onRemoteSessionAvailable() {
    scheduleSync(delay: _lifecycleDebounce, reason: 'remote-session-available');
  }

  void onAppResumed() {
    scheduleSync(delay: _lifecycleDebounce, reason: 'app-resumed');
  }

  void cancelPending({
    String? skippedReason,
    bool clearLastRequestedAt = true,
  }) {
    _timer?.cancel();
    _timer = null;

    if (_disposed) {
      return;
    }

    final shouldResetToIdle = !_snapshot.isRunning;
    _publishSnapshot(
      _snapshot.copyWith(
        phase: shouldResetToIdle
            ? AutoSyncCoordinatorPhase.idle
            : _snapshot.phase,
        clearCurrentReason: shouldResetToIdle,
        clearNextScheduledAt: true,
        followUpQueued: _runAgainAfterCurrentBatch,
        lastSkippedReason: skippedReason,
        clearLastRequestedAt: clearLastRequestedAt,
      ),
    );
  }

  Future<void> dispose() async {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
    await _mutationSubscription?.cancel();
  }

  Future<bool> _scheduleRetryWakeupIfNeeded() async {
    final summaries = await _loadQueueSummaries();
    DateTime? nextRetryAt;

    for (final summary in summaries) {
      if (summary.nextRetryAt == null) {
        continue;
      }

      if (nextRetryAt == null || summary.nextRetryAt!.isBefore(nextRetryAt)) {
        nextRetryAt = summary.nextRetryAt;
      }
    }

    if (nextRetryAt == null) {
      return false;
    }

    final now = _now();
    if (!nextRetryAt.isAfter(now)) {
      scheduleSync(
        delay: const Duration(milliseconds: 250),
        reason: 'eligible-retry-ready',
      );
      return true;
    }

    scheduleSync(
      delay: nextRetryAt.difference(now),
      reason: 'waiting-next-retry',
    );
    return true;
  }

  void _publishSnapshot(AutoSyncCoordinatorSnapshot snapshot) {
    _snapshot = snapshot;
    _onSnapshot?.call(snapshot);
  }
}

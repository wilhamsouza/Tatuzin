import 'dart:async';

import 'package:erp_pdv_app/app/core/providers/provider_guard.dart';
import 'package:erp_pdv_app/app/core/sync/sync_queue_feature_summary.dart';
import 'package:erp_pdv_app/modules/system/presentation/providers/system_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('runProviderGuarded surfaces timeout instead of waiting forever', () {
    expect(
      runProviderGuarded(
        'testHangingProvider',
        () => Completer<void>().future,
        timeout: const Duration(milliseconds: 10),
      ),
      throwsA(isA<TimeoutException>()),
    );
  });

  test(
    'sync health does not expose next retry before last processed sync',
    () async {
      final lastProcessedAt = DateTime(2026, 4, 26, 7, 43);
      final staleRetryAt = DateTime(2026, 4, 24, 13, 44);
      final expectedRetryAt = lastProcessedAt.add(const Duration(minutes: 1));

      final container = ProviderContainer(
        overrides: [
          syncQueueFeatureSummariesProvider.overrideWith(
            (ref) async => [
              SyncQueueFeatureSummary(
                featureKey: 'customers',
                displayName: 'Clientes',
                totalTracked: 1,
                pendingCount: 0,
                processingCount: 0,
                activeProcessingCount: 0,
                staleProcessingCount: 0,
                syncedCount: 1,
                errorCount: 1,
                blockedCount: 0,
                conflictCount: 0,
                totalAttemptCount: 3,
                lastProcessedAt: lastProcessedAt,
                nextRetryAt: staleRetryAt,
                lastError: 'Falha de teste',
                lastErrorType: null,
                lastErrorAt: lastProcessedAt,
              ),
            ],
          ),
        ],
      );
      addTearDown(container.dispose);

      await container.read(syncQueueFeatureSummariesProvider.future);

      final overview = container.read(syncHealthOverviewProvider);

      expect(overview.lastProcessedAt, lastProcessedAt);
      expect(overview.nextRetryAt, expectedRetryAt);
    },
  );
}

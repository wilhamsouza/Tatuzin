import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/core/providers/app_data_refresh_provider.dart';
import '../../../app/core/providers/tenant_bootstrap_gate.dart';
import '../../historico_vendas/presentation/providers/sale_history_providers.dart';
import '../../vendas/domain/entities/sale_record.dart';

final dailySaleActivityProvider = FutureProvider<List<SaleRecord>>((ref) async {
  ref.watch(appDataRefreshProvider);
  await requireTenantBootstrapReady(ref, 'dailySaleActivityProvider');
  final now = DateTime.now();
  final start = DateTime(now.year, now.month, now.day);
  final end = DateTime(now.year, now.month, now.day + 1);
  final timer = Timer(end.difference(now), ref.invalidateSelf);
  ref.onDispose(timer.cancel);
  // Remote records are UTC, while existing device records may be local ISO strings.
  // Read a bounded margin, then compare actual instants in the device's calendar.
  final candidates = await ref
      .watch(saleHistoryRepositoryProvider)
      .search(
        from: DateTime(now.year, now.month, now.day - 2),
        to: DateTime(now.year, now.month, now.day + 3),
      );
  final sales = candidates.where((sale) {
    final local = sale.soldAt.toLocal();
    return !local.isBefore(start) && local.isBefore(end);
  }).toList()..sort((a, b) => b.soldAt.compareTo(a.soldAt));
  return sales;
});

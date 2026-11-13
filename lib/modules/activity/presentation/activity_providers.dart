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
  return ref
      .watch(saleHistoryRepositoryProvider)
      .search(from: start, to: end.subtract(const Duration(microseconds: 1)));
});

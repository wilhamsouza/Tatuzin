import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/core/errors/app_exceptions.dart';
import '../../../../app/core/providers/app_data_refresh_provider.dart';
import '../../data/services/default_order_ticket_builder.dart';
import '../../data/services/escpos_kitchen_print_service.dart';
import '../../data/shared_preferences_kitchen_printer_settings_repository.dart';
import '../../domain/entities/kitchen_printer_config.dart';
import '../../domain/entities/order_ticket_document.dart';
import '../../domain/entities/operational_order.dart';
import '../../domain/repositories/kitchen_printer_settings_repository.dart';
import '../../domain/services/kitchen_print_service.dart';
import '../../domain/services/order_ticket_builder.dart';
import 'order_providers.dart';

final kitchenPrinterSettingsRepositoryProvider =
    Provider<KitchenPrinterSettingsRepository>((ref) {
      return SharedPreferencesKitchenPrinterSettingsRepository();
    });

final orderTicketBuilderProvider = Provider<OrderTicketBuilder>((ref) {
  return const DefaultOrderTicketBuilder();
});

final kitchenPrintServiceProvider = Provider<KitchenPrintService>((ref) {
  return const EscPosKitchenPrintService();
});

final kitchenPrinterConfigProvider = FutureProvider<KitchenPrinterConfig?>((
  ref,
) {
  return ref.read(kitchenPrinterSettingsRepositoryProvider).loadDefault();
});

final orderTicketDocumentProvider =
    FutureProvider.family<
      OrderTicketDocument,
      ({int orderId, OrderTicketProfile profile})
    >((ref, args) async {
      final detail = await ref.watch(
        operationalOrderDetailProvider(args.orderId).future,
      );
      if (detail == null) {
        throw StateError('Pedido #${args.orderId} nao encontrado.');
      }

      return ref
          .read(orderTicketBuilderProvider)
          .build(detail: detail, profile: args.profile);
    });

final kitchenPrinterConfigControllerProvider =
    AsyncNotifierProvider<KitchenPrinterConfigController, void>(
      KitchenPrinterConfigController.new,
    );

final kitchenPrinterTestControllerProvider =
    AsyncNotifierProvider<KitchenPrinterTestController, void>(
      KitchenPrinterTestController.new,
    );

final orderKitchenDispatchControllerProvider =
    AsyncNotifierProvider<OrderKitchenDispatchController, void>(
      OrderKitchenDispatchController.new,
    );

final orderTicketReprintControllerProvider =
    AsyncNotifierProvider<OrderTicketReprintController, void>(
      OrderTicketReprintController.new,
    );

class OrderTicketDispatchResult {
  const OrderTicketDispatchResult({
    required this.printed,
    required this.failureMessage,
  });

  final bool printed;
  final String? failureMessage;

  bool get hasFailure => !printed;
}

class KitchenPrinterConfigController extends AsyncNotifier<void> {
  @override
  FutureOr<void> build() {}

  Future<void> save(KitchenPrinterConfig config) async {
    state = const AsyncLoading();
    try {
      await ref
          .read(kitchenPrinterSettingsRepositoryProvider)
          .saveDefault(config);
      ref.invalidate(kitchenPrinterConfigProvider);
      state = const AsyncData(null);
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
      rethrow;
    }
  }

  Future<void> clear() async {
    state = const AsyncLoading();
    try {
      await ref.read(kitchenPrinterSettingsRepositoryProvider).clearDefault();
      ref.invalidate(kitchenPrinterConfigProvider);
      state = const AsyncData(null);
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
      rethrow;
    }
  }
}

class KitchenPrinterTestController extends AsyncNotifier<void> {
  @override
  FutureOr<void> build() {}

  Future<void> printTest(KitchenPrinterConfig config) async {
    state = const AsyncLoading();
    try {
      await ref.read(kitchenPrintServiceProvider).printTest(printer: config);
      state = const AsyncData(null);
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
      rethrow;
    }
  }
}

class OrderKitchenDispatchController extends AsyncNotifier<void> {
  @override
  FutureOr<void> build() {}

  Future<OrderTicketDispatchResult> sendToKitchen(int orderId) async {
    state = const AsyncLoading();
    try {
      await ref.read(operationalOrderRepositoryProvider).sendToKitchen(orderId);
      final result = await _dispatchTicket(ref, orderId);
      _invalidateOrder(ref, orderId);
      state = const AsyncData(null);
      return result;
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
      rethrow;
    }
  }
}

class OrderTicketReprintController extends AsyncNotifier<void> {
  @override
  FutureOr<void> build() {}

  Future<OrderTicketDispatchResult> reprint(int orderId) async {
    state = const AsyncLoading();
    try {
      final result = await _dispatchTicket(ref, orderId);
      _invalidateOrder(ref, orderId);
      state = const AsyncData(null);
      return result;
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
      rethrow;
    }
  }
}

Future<OrderTicketDispatchResult> _dispatchTicket(Ref ref, int orderId) async {
  final repository = ref.read(operationalOrderRepositoryProvider);
  try {
    final printer = await ref.read(kitchenPrinterConfigProvider.future);
    if (printer == null) {
      throw const ValidationException(
        'Nenhuma impressora configurada para separacao.',
      );
    }

    final ticket = await ref.read(
      orderTicketDocumentProvider((
        orderId: orderId,
        profile: OrderTicketProfile.kitchen,
      )).future,
    );
    await ref
        .read(kitchenPrintServiceProvider)
        .print(printer: printer, ticket: ticket);
    await repository.updateTicketDispatchState(
      orderId: orderId,
      status: OrderTicketDispatchStatus.sent,
    );
    return const OrderTicketDispatchResult(printed: true, failureMessage: null);
  } catch (error) {
    await repository.updateTicketDispatchState(
      orderId: orderId,
      status: OrderTicketDispatchStatus.failed,
      failureMessage: error.toString(),
    );
    return OrderTicketDispatchResult(
      printed: false,
      failureMessage: error.toString(),
    );
  }
}

void _invalidateOrder(Ref ref, int orderId) {
  ref.read(appDataRefreshProvider.notifier).state++;
  ref.invalidate(kitchenPrinterConfigProvider);
  ref.invalidate(operationalOrderBoardProvider);
  ref.invalidate(operationalOrderDetailProvider(orderId));
}

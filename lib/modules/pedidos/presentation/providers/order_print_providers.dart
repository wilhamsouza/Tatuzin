import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/core/errors/app_exceptions.dart';
import '../../data/services/default_order_ticket_builder.dart';
import '../../data/services/escpos_kitchen_print_service.dart';
import '../../data/shared_preferences_kitchen_printer_settings_repository.dart';
import '../../domain/entities/kitchen_printer_config.dart';
import '../../domain/entities/order_ticket_document.dart';
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

final orderKitchenPrintControllerProvider =
    AsyncNotifierProvider<OrderKitchenPrintController, void>(
      OrderKitchenPrintController.new,
    );

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

class OrderKitchenPrintController extends AsyncNotifier<void> {
  @override
  FutureOr<void> build() {}

  Future<void> printOrder(int orderId) async {
    state = const AsyncLoading();
    try {
      final printer = await ref.read(kitchenPrinterConfigProvider.future);
      if (printer == null) {
        throw const ValidationException(
          'Nenhuma impressora de cozinha configurada.',
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
      state = const AsyncData(null);
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
      rethrow;
    }
  }
}

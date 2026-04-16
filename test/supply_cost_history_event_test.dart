import 'package:erp_pdv_app/modules/insumos/domain/entities/supply_cost_history_entry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SupplyCostHistoryEventType', () {
    test('resolve fallback legivel para registros antigos manuais', () {
      final type = supplyCostHistoryEventTypeFromStorage(
        null,
        fallbackSource: SupplyCostHistorySource.manual,
      );

      expect(type, SupplyCostHistoryEventType.manualEdit);
      expect(type.label, 'Edicao manual');
    });

    test('resolve fallback legivel para registros antigos de compra', () {
      final type = supplyCostHistoryEventTypeFromStorage(
        null,
        fallbackSource: SupplyCostHistorySource.purchase,
      );

      expect(type, SupplyCostHistoryEventType.purchaseUpdated);
      expect(type.label, 'Compra atualizada');
    });

    test('mantem origem explicita para cancelamento', () {
      final type = supplyCostHistoryEventTypeFromStorage('purchase_canceled');

      expect(type, SupplyCostHistoryEventType.purchaseCanceled);
      expect(type.label, 'Compra cancelada');
    });
  });
}

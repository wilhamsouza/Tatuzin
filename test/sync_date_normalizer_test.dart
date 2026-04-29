import 'package:erp_pdv_app/app/core/sync/sync_date_normalizer.dart';
import 'package:erp_pdv_app/app/core/sync/sync_status.dart';
import 'package:erp_pdv_app/modules/caixa/data/models/cash_event_sync_payload.dart';
import 'package:erp_pdv_app/modules/caixa/data/models/remote_cash_event_record.dart';
import 'package:erp_pdv_app/modules/caixa/domain/entities/cash_enums.dart';
import 'package:erp_pdv_app/modules/vendas/data/models/remote_sale_record.dart';
import 'package:erp_pdv_app/modules/vendas/data/models/sale_sync_payload.dart';
import 'package:erp_pdv_app/modules/vendas/domain/entities/sale_enums.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('normalizeSyncDate', () {
    test('mantem ISO UTC valido', () {
      final result = normalizeSyncDate(
        '2026-04-28T21:30:45.123Z',
        entity: 'sale',
        field: 'soldAt',
        fallbacks: const [],
      );

      expect(result.fallbackUsed, isFalse);
      expect(result.source, 'iso_utc');
      expect(result.value.isUtc, isTrue);
      expect(result.toIsoUtc(), '2026-04-28T21:30:45.123Z');
    });

    test('normaliza epoch milliseconds para ISO UTC valido', () {
      final result = normalizeSyncDate(
        1777421445123,
        entity: 'sale',
        field: 'soldAt',
        fallbacks: const [],
      );

      expect(result.fallbackUsed, isFalse);
      expect(result.source, 'epoch_milliseconds');
      expect(result.value.isUtc, isTrue);
      expect(result.toIsoUtc(), endsWith('Z'));
    });

    test('normaliza epoch seconds em string numerica', () {
      final result = normalizeSyncDate(
        '1777421445',
        entity: 'cash_event',
        field: 'createdAt',
        fallbacks: const [],
      );

      expect(result.fallbackUsed, isFalse);
      expect(result.source, 'epoch_seconds');
      expect(result.value.isUtc, isTrue);
      expect(result.toIsoUtc(), endsWith('Z'));
    });

    test('aceita data local brasileira', () {
      final result = normalizeSyncDate(
        '28/04/2026 21:30:45',
        entity: 'sale',
        field: 'soldAt',
        fallbacks: const [],
      );

      expect(result.fallbackUsed, isFalse);
      expect(result.source, 'brazilian_local');
      expect(result.value.isUtc, isTrue);
      expect(result.toIsoUtc(), endsWith('Z'));
    });

    test('usa fallback para string vazia', () {
      final fallback = DateTime.utc(2026, 4, 28, 21, 31, 45);
      final result = normalizeSyncDate(
        '',
        entity: 'sale',
        field: 'soldAt',
        fallbacks: [
          SyncDateFallback(label: 'queue.createdAt', value: fallback),
        ],
      );

      expect(result.fallbackUsed, isTrue);
      expect(result.source, 'queue.createdAt');
      expect(result.rawType, 'empty_string');
      expect(result.toIsoUtc(), '2026-04-28T21:31:45.000Z');
    });

    test('usa fallback para null', () {
      final fallback = DateTime.utc(2026, 4, 28, 21, 31, 45);
      final result = normalizeSyncDate(
        null,
        entity: 'cash_event',
        field: 'createdAt',
        fallbacks: [
          SyncDateFallback(label: 'queue.createdAt', value: fallback),
        ],
      );

      expect(result.fallbackUsed, isTrue);
      expect(result.rawType, 'null');
      expect(result.toIsoUtc(), '2026-04-28T21:31:45.000Z');
    });

    test('usa now como ultimo recurso sem gerar Invalid Date', () {
      final now = DateTime.utc(2026, 4, 28, 21, 31, 45);
      final result = normalizeSyncDate(
        'data invalida',
        entity: 'sale',
        field: 'soldAt',
        fallbacks: const [],
        now: now,
      );

      expect(result.fallbackUsed, isTrue);
      expect(result.source, 'now');
      expect(result.toIsoUtc(), '2026-04-28T21:31:45.000Z');
      expect(result.toIsoUtc(), isNot(contains('Invalid')));
    });
  });

  group('payloads de sync', () {
    test('sale create serializa soldAt como ISO UTC com Z', () {
      final payload = _salePayload(soldAt: DateTime(2026, 4, 28, 21, 30, 45));

      final body = RemoteSaleRecord.fromSyncPayload(payload).toCreateBody();
      final soldAt = body['soldAt'] as String;

      expect(soldAt, endsWith('Z'));
      expect(DateTime.tryParse(soldAt), isNotNull);
      expect(soldAt, isNot(contains('Invalid')));
    });

    test(
      'sale create usa data normalizada por fallback quando soldAt falha',
      () {
        final fallback = DateTime.utc(2026, 4, 28, 21, 31, 45);
        final normalized = normalizeSyncDate(
          '',
          entity: 'sale',
          field: 'soldAt',
          fallbacks: [
            SyncDateFallback(label: 'queue.createdAt', value: fallback),
          ],
        );
        final payload = _salePayload(soldAt: DateTime(2026, 4, 28, 21, 30));

        final body = RemoteSaleRecord.fromSyncPayload(
          payload,
          soldAt: normalized.value,
          createdAt: normalized.value,
        ).toCreateBody();

        expect(body['soldAt'], '2026-04-28T21:31:45.000Z');
      },
    );

    test('cash_event create serializa createdAt como ISO UTC com Z', () {
      final payload = _cashEventPayload(
        createdAt: DateTime(2026, 4, 28, 21, 30, 45),
      );

      final body = RemoteCashEventRecord.fromSyncPayload(
        payload,
      ).toCreateBody();
      final createdAt = body['createdAt'] as String;

      expect(createdAt, endsWith('Z'));
      expect(DateTime.tryParse(createdAt), isNotNull);
      expect(createdAt, isNot(contains('Invalid')));
    });

    test('cash_event create usa fallback quando createdAt falha', () {
      final fallback = DateTime.utc(2026, 4, 28, 21, 31, 45);
      final normalized = normalizeSyncDate(
        'data invalida',
        entity: 'cash_event',
        field: 'createdAt',
        fallbacks: [
          SyncDateFallback(label: 'queue.createdAt', value: fallback),
        ],
      );
      final payload = _cashEventPayload(
        createdAt: DateTime(2026, 4, 28, 21, 30),
      );

      final body = RemoteCashEventRecord.fromSyncPayload(
        payload,
        createdAt: normalized.value,
      ).toCreateBody();

      expect(body['createdAt'], '2026-04-28T21:31:45.000Z');
    });
  });
}

SaleSyncPayload _salePayload({required DateTime soldAt}) {
  return SaleSyncPayload(
    saleId: 1,
    saleUuid: 'sale-local-1',
    receiptNumber: '000001',
    saleType: SaleType.cash,
    paymentMethod: PaymentMethod.cash,
    status: SaleStatus.active,
    totalAmountCents: 1500,
    totalCostCents: 1000,
    soldAt: soldAt,
    updatedAt: soldAt,
    clientLocalId: null,
    clientRemoteId: null,
    notes: null,
    remoteId: null,
    syncStatus: SyncStatus.pendingUpload,
    lastSyncedAt: null,
    items: const [
      SaleSyncItemPayload(
        itemId: 1,
        productLocalId: 1,
        productRemoteId: 'prod-remote-1',
        productNameSnapshot: 'Produto',
        quantityMil: 1000,
        unitPriceCents: 1500,
        totalPriceCents: 1500,
        unitCostCents: 1000,
        totalCostCents: 1000,
        unitMeasure: 'un',
        productType: 'simple',
      ),
    ],
  );
}

CashEventSyncPayload _cashEventPayload({required DateTime createdAt}) {
  return CashEventSyncPayload(
    movementId: 1,
    movementUuid: 'cash-event-local-1',
    type: CashMovementType.sale,
    amountCents: 1500,
    paymentMethod: PaymentMethod.cash,
    referenceType: 'venda',
    referenceLocalId: 1,
    referenceRemoteId: 'sale-remote-1',
    description: 'Venda',
    createdAt: createdAt,
    updatedAt: createdAt,
    remoteId: null,
    syncStatus: SyncStatus.pendingUpload,
    lastSyncedAt: null,
  );
}

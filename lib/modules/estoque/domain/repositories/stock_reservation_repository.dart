import '../entities/stock_reservation.dart';

abstract interface class StockReservationRepository {
  Future<int> createReservation(StockReservationInput input);

  Future<List<StockReservation>> findActiveByOrderId(int orderId);

  Future<StockReservation?> findActiveByOrderItemId(int orderItemId);

  Future<int> getReservedQuantityMil({
    required int productId,
    required int? productVariantId,
  });

  Future<Map<StockReservationProductKey, int>> getReservedQuantityByProductKeys(
    Iterable<StockReservationProductKey> keys,
  );

  Future<void> releaseReservation(int reservationId);

  Future<void> releaseActiveByOrderId(int orderId);

  Future<void> markConverted(int reservationId, int saleId);

  Future<void> markActiveByOrderIdConverted(int orderId, int saleId);
}

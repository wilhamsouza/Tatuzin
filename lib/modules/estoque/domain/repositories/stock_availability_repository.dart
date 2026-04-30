import '../entities/stock_availability.dart';
import '../entities/stock_reservation.dart';

abstract interface class StockAvailabilityRepository {
  Future<StockAvailability> getAvailability({
    required int productId,
    required int? productVariantId,
  });

  Future<Map<StockReservationProductKey, StockAvailability>>
  getAvailabilityByProductKeys(Iterable<StockReservationProductKey> keys);
}

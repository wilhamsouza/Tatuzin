import '../../../vendas/domain/entities/sale_detail.dart';
import '../../../vendas/domain/entities/sale_enums.dart';
import '../../../vendas/domain/entities/sale_record.dart';

abstract interface class SaleHistoryRepository {
  Future<List<SaleRecord>> search({
    String query = '',
    SaleStatus? status,
    SaleType? type,
    DateTime? from,
    DateTime? to,
  });

  Future<SaleDetail> fetchDetail(int saleId);
}

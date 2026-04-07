import 'sale_item_detail.dart';
import 'sale_record.dart';

class SaleDetail {
  const SaleDetail({required this.sale, required this.items});

  final SaleRecord sale;
  final List<SaleItemDetail> items;
}

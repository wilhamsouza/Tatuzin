import '../entities/supplier.dart';

abstract interface class SupplierRepository {
  Future<List<Supplier>> search({String query = ''});
  Future<Supplier?> findById(int id);
  Future<int> create(SupplierInput input);
  Future<void> update(int id, SupplierInput input);
  Future<void> delete(int id);
}

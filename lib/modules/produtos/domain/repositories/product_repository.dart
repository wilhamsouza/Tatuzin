import '../entities/product.dart';

abstract interface class ProductRepository {
  Future<List<Product>> search({String query = ''});
  Future<List<Product>> searchAvailable({String query = ''});
  Future<int> create(ProductInput input);
  Future<void> update(int id, ProductInput input);
  Future<void> delete(int id);
}

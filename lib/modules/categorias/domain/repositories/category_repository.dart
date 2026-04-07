import '../entities/category.dart';

abstract interface class CategoryRepository {
  Future<List<Category>> search({String query = ''});
  Future<int> create(CategoryInput input);
  Future<void> update(int id, CategoryInput input);
  Future<void> delete(int id);
}

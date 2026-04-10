import '../entities/base_product.dart';
import '../entities/modifier_group.dart';
import '../entities/modifier_option.dart';
import '../entities/variant_attribute.dart';

abstract interface class LocalCatalogRepository {
  Future<List<BaseProduct>> listBaseProducts({String query = ''});

  Future<BaseProduct?> findBaseProductById(int id);

  Future<List<int>> listVariantProductIdsForBase(int baseProductId);

  Future<List<VariantAttribute>> listVariantAttributes(int productId);

  Future<List<ModifierGroup>> listModifierGroups(int baseProductId);

  Future<List<ModifierOption>> listModifierOptions(int groupId);

  Future<int> upsertModifierGroup({int? id, required ModifierGroupInput input});

  Future<int> upsertModifierOption({
    int? id,
    required ModifierOptionInput input,
  });
}

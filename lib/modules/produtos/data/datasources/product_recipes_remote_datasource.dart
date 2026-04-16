import '../../../../app/core/network/contracts/remote_datasource_contract.dart';
import '../../../../app/core/network/remote_feature_diagnostic.dart';
import '../models/remote_product_recipe_record.dart';

abstract interface class ProductRecipesRemoteDatasource
    implements RemoteDatasourceContract {
  Future<List<RemoteProductRecipeRecord>> listAll();

  Future<RemoteProductRecipeRecord> fetchByProductId(String productRemoteId);

  Future<RemoteProductRecipeRecord> upsert(
    String productRemoteId,
    RemoteProductRecipeRecord record,
  );

  Future<void> delete(String productRemoteId);

  Future<RemoteFeatureDiagnostic> fetchDiagnostic();
}

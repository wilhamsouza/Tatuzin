import '../../../modules/categorias/data/models/remote_category_record.dart';
import '../../../modules/categorias/data/sqlite_category_repository.dart';
import '../../../modules/caixa/data/models/remote_cash_movement_record.dart';
import '../../../modules/caixa/data/models/remote_cash_session_record.dart';
import '../../../modules/caixa/data/sqlite_cash_repository.dart';
import '../../../modules/clientes/data/models/remote_customer_record.dart';
import '../../../modules/clientes/data/sqlite_client_repository.dart';
import '../../../modules/fornecedores/data/models/remote_supplier_record.dart';
import '../../../modules/fornecedores/data/sqlite_supplier_repository.dart';
import '../../../modules/produtos/data/models/remote_product_record.dart';
import '../../../modules/produtos/data/sqlite_product_repository.dart';
import 'app_snapshot_remote_datasource.dart';
import 'sync_feature_keys.dart';

abstract interface class AppSnapshotHydrator {
  Future<AppSnapshotHydrationResult> hydrate(AppSnapshotResponse snapshot);
}

class NoopAppSnapshotHydrator implements AppSnapshotHydrator {
  const NoopAppSnapshotHydrator();

  @override
  Future<AppSnapshotHydrationResult> hydrate(
    AppSnapshotResponse snapshot,
  ) async {
    return const AppSnapshotHydrationResult(appliedRecords: 0);
  }
}

class SqliteAppSnapshotHydrator implements AppSnapshotHydrator {
  const SqliteAppSnapshotHydrator({
    required SqliteCategoryRepository categoryRepository,
    required SqliteSupplierRepository supplierRepository,
    required SqliteClientRepository clientRepository,
    required SqliteProductRepository productRepository,
    required SqliteCashRepository cashRepository,
  }) : _categoryRepository = categoryRepository,
       _supplierRepository = supplierRepository,
       _clientRepository = clientRepository,
       _productRepository = productRepository,
       _cashRepository = cashRepository;

  final SqliteCategoryRepository _categoryRepository;
  final SqliteSupplierRepository _supplierRepository;
  final SqliteClientRepository _clientRepository;
  final SqliteProductRepository _productRepository;
  final SqliteCashRepository _cashRepository;

  @override
  Future<AppSnapshotHydrationResult> hydrate(
    AppSnapshotResponse snapshot,
  ) async {
    var appliedRecords = 0;

    for (final item in _items(snapshot, SyncFeatureKeys.categories)) {
      await _categoryRepository.upsertFromRemote(
        RemoteCategoryRecord.fromJson(item),
      );
      appliedRecords++;
    }

    for (final item in _items(snapshot, SyncFeatureKeys.suppliers)) {
      await _supplierRepository.upsertFromRemote(
        RemoteSupplierRecord.fromJson(item),
      );
      appliedRecords++;
    }

    for (final item in _items(snapshot, SyncFeatureKeys.customers)) {
      await _clientRepository.upsertFromRemote(
        RemoteCustomerRecord.fromJson(item),
      );
      appliedRecords++;
    }

    for (final item in _items(snapshot, SyncFeatureKeys.products)) {
      await _productRepository.upsertFromRemote(
        RemoteProductRecord.fromJson(item),
      );
      appliedRecords++;
    }

    for (final item in _items(snapshot, SyncFeatureKeys.cashSessions)) {
      await _cashRepository.upsertSessionFromRemote(
        RemoteCashSessionRecord.fromJson(item),
      );
      appliedRecords++;
    }

    for (final item in _items(snapshot, SyncFeatureKeys.cashMovements)) {
      await _cashRepository.upsertMovementFromRemote(
        RemoteCashMovementRecord.fromJson(item),
      );
      appliedRecords++;
    }

    return AppSnapshotHydrationResult(appliedRecords: appliedRecords);
  }

  List<Map<String, dynamic>> _items(
    AppSnapshotResponse snapshot,
    String featureKey,
  ) {
    return snapshot.features[featureKey]?.items ??
        const <Map<String, dynamic>>[];
  }
}

class AppSnapshotHydrationResult {
  const AppSnapshotHydrationResult({required this.appliedRecords});

  final int appliedRecords;
}

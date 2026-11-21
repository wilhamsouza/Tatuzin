import '../../../app/core/database/app_database.dart';
import '../../../app/core/database/table_names.dart';
import '../../../app/core/errors/app_exceptions.dart';
import '../../../app/core/sync/sqlite_sync_metadata_repository.dart';
import '../../../app/core/sync/sync_feature_keys.dart';
import 'support/central_stock_refresh_support.dart';

/// Mirrors absolute, confirmed quantities. It never replays an adjustment delta
/// and never writes through locally pending operational effects.
class ConfirmedInventoryMirror {
  ConfirmedInventoryMirror(this.database)
    : metadata = SqliteSyncMetadataRepository(database);

  final AppDatabase database;
  final SqliteSyncMetadataRepository metadata;
  String _key(Map<String, dynamic> row) =>
      '${row['productId']}:${row['productVariantId'] ?? ''}';

  Future<List<Map<String, dynamic>>> pending() async =>
      CentralStockRefreshSupport.read(await database.database);

  Future<void> stage(
    Iterable<Map<String, dynamic>> rows, {
    void Function()? ensureCurrent,
  }) async {
    final db = await database.database;
    await db.transaction((tx) async {
      ensureCurrent?.call();
      final merged = {
        for (final row in await CentralStockRefreshSupport.read(tx))
          _key(row): row,
      };
      for (final row in rows) {
        if (row['productId'] is String && row['currentStockMil'] is num) {
          merged[_key(row)] = {
            'productId': row['productId'],
            'productVariantId': row['productVariantId'],
            'currentStockMil': (row['currentStockMil'] as num).toInt(),
          };
        }
      }
      ensureCurrent?.call();
      await CentralStockRefreshSupport.store(tx, merged.values.toList());
    });
  }

  Future<void> stageIntent(
    Iterable<Map<String, dynamic>> rows,
    String requestId, {
    required void Function() ensureCurrent,
  }) async {
    final db = await database.database;
    await db.transaction((tx) async {
      ensureCurrent();
      final merged = {
        for (final row in await CentralStockRefreshSupport.read(tx))
          _key(row): row,
      };
      for (final row in rows) {
        final existing = merged[_key(row)];
        if (existing?['uncertainRequestId'] != null &&
            existing!['uncertainRequestId'] != requestId) {
          throw const ValidationException(
            'Confira a movimentação anterior em Estoque antes de iniciar outra.',
          );
        }
        merged[_key(row)] = {
          'productId': row['productId'],
          'productVariantId': row['productVariantId'],
          'currentStockMil': row['currentStockMil'] ?? 0,
          'uncertainRequestId': requestId,
        };
      }
      ensureCurrent();
      await CentralStockRefreshSupport.store(tx, merged.values.toList());
    });
  }

  Future<void> resolveIntent(
    String requestId, {
    required void Function() ensureCurrent,
  }) async {
    final db = await database.database;
    await db.transaction((tx) async {
      ensureCurrent();
      final rows = await CentralStockRefreshSupport.read(tx);
      for (final row in rows) {
        if (row['uncertainRequestId'] == requestId) {
          row.remove('uncertainRequestId');
        }
      }
      await CentralStockRefreshSupport.store(tx, rows);
    });
  }

  Future<bool> refreshPending({
    required Future<void> Function() prepare,
    required Future<Map<String, dynamic>> Function(Map<String, dynamic> target)
    fetchCurrent,
    required void Function() ensureCurrent,
  }) async {
    ensureCurrent();
    if ((await pending()).any((row) => row['uncertainRequestId'] != null)) {
      return false;
    }
    await prepare();
    ensureCurrent();
    final fresh = <Map<String, dynamic>>[];
    for (final target in await pending()) {
      ensureCurrent();
      final value = await fetchCurrent(target);
      ensureCurrent();
      if (value['productId'] != target['productId'] ||
          value['productVariantId'] != target['productVariantId'] ||
          value['currentStockMil'] is! num) {
        throw const ValidationException(
          'Não foi possível conferir o saldo atual deste item. Tente atualizar novamente.',
        );
      }
      fresh.add(value);
    }
    await stage(fresh, ensureCurrent: ensureCurrent);
    return applyPending(ensureCurrent: ensureCurrent);
  }

  Future<bool> applyPending({required void Function() ensureCurrent}) async {
    final db = await database.database;
    return db.transaction((tx) async {
      ensureCurrent();
      final rows = await CentralStockRefreshSupport.read(tx);
      if (rows.isEmpty) return true;
      if (rows.any((row) => row['uncertainRequestId'] != null)) return false;
      final pending = await tx.rawQuery(
        "SELECT 1 FROM ${TableNames.operationalSyncEvents} WHERE status IN ('pending','pushing','failed','rejected','conflict') LIMIT 1",
      );
      if (pending.isNotEmpty) return false;
      final updates = <({int productId, int? variantId, int quantity})>[];
      for (final row in rows) {
        final remoteId = row['productId'] as String;
        final mapping = await metadata.findByRemoteId(
          tx,
          featureKey: SyncFeatureKeys.products,
          remoteId: remoteId,
        );
        var localId = mapping?.identity.localId;
        if (localId == null) {
          final products = await tx.query(
            TableNames.produtos,
            columns: ['id'],
            where: 'uuid = ?',
            whereArgs: [remoteId],
            limit: 2,
          );
          if (products.length == 1) localId = products.single['id'] as int;
        }
        if (localId == null) return false;
        int? variantId;
        if (row['productVariantId'] != null) {
          final variants = await tx.query(
            TableNames.produtoVariantes,
            columns: ['id'],
            where: 'produto_id = ? AND (remote_id = ? OR uuid = ?)',
            whereArgs: [
              localId,
              row['productVariantId'],
              row['productVariantId'],
            ],
            limit: 2,
          );
          if (variants.length != 1) return false;
          variantId = variants.single['id'] as int;
        }
        updates.add((
          productId: localId,
          variantId: variantId,
          quantity: (row['currentStockMil'] as num).toInt(),
        ));
      }
      final parents = <int>{};
      for (final update in updates) {
        ensureCurrent();
        await tx.update(
          update.variantId == null
              ? TableNames.produtos
              : TableNames.produtoVariantes,
          {'estoque_mil': update.quantity},
          where: 'id = ?',
          whereArgs: [update.variantId ?? update.productId],
        );
        if (update.variantId != null) parents.add(update.productId);
      }
      for (final id in parents) {
        await tx.rawUpdate(
          '''UPDATE ${TableNames.produtos} SET estoque_mil = COALESCE((
          SELECT SUM(CASE WHEN ativo = 1 THEN estoque_mil ELSE 0 END)
          FROM ${TableNames.produtoVariantes} WHERE produto_id = ?), 0) WHERE id = ?''',
          [id, id],
        );
      }
      ensureCurrent();
      await CentralStockRefreshSupport.store(tx, []);
      return true;
    });
  }
}

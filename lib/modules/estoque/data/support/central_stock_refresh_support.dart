import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../../../../app/core/database/table_names.dart';
import '../../../../app/core/errors/app_exceptions.dart';

/// A company-local recovery marker. Only a confirmed central quantity change
/// creates it; ordinary offline sales keep their existing behavior.
abstract final class CentralStockRefreshSupport {
  static const key = 'inventory.confirmed_stock_pending';

  static Future<List<Map<String, dynamic>>> read(DatabaseExecutor db) async {
    final table = await db.rawQuery(
      "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ? LIMIT 1",
      [TableNames.operationalSyncState],
    );
    if (table.isEmpty) return [];
    final values = await db.query(
      TableNames.operationalSyncState,
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (values.isEmpty) return [];
    final decoded = jsonDecode(values.single['value'] as String);
    return decoded is List
        ? decoded
              .whereType<Map>()
              .map((row) => Map<String, dynamic>.from(row))
              .toList()
        : [];
  }

  static Future<void> store(
    DatabaseExecutor db,
    List<Map<String, dynamic>> rows,
  ) async {
    if (rows.isEmpty) {
      await db.delete(
        TableNames.operationalSyncState,
        where: 'key = ?',
        whereArgs: [key],
      );
      return;
    }
    await db.insert(
      TableNames.operationalSyncState,
      {
        'key': key,
        'value': jsonEncode(rows),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  static Future<void> assertReady(DatabaseExecutor db) async {
    if ((await read(db)).isNotEmpty) {
      throw const ValidationException(
        'Há uma conferência de saldo pendente neste aparelho. Peça ao responsável para conferir a operação em Estoque antes de vender.',
      );
    }
  }
}

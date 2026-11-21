import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import '../../../app/core/database/table_names.dart';

/// Tenant isolation is supplied by the company's local database.
abstract final class CashWorkspaceStore {
  static Future<Map<String, dynamic>> read(
    DatabaseExecutor db,
    String key,
  ) async {
    final rows = await db.query(
      TableNames.configuracoes,
      columns: ['valor_json'],
      where: 'chave = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (rows.isEmpty) return {};
    return Map<String, dynamic>.from(
      jsonDecode(rows.first['valor_json'] as String) as Map,
    );
  }

  static Future<void> write(
    DatabaseExecutor db,
    String key,
    Map<String, dynamic> value,
  ) async {
    await db.insert(TableNames.configuracoes, {
      'chave': key,
      'valor_json': jsonEncode(value),
      'atualizado_em': DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Future<Map<String, dynamic>> openingPolicy(
    DatabaseExecutor db,
    int amount,
  ) async {
    final policy = await read(db, 'cash.policy');
    return {
      'version': 2,
      'countedAmountCents': amount,
      'blindClosureEnabled': policy['cashBlindClosureEnabled'] == true,
      'policyRevision': policy['cashPolicyRevision'] ?? 0,
    };
  }
}

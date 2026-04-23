import '../../../app/core/database/app_database.dart';
import '../../../app/core/database/table_names.dart';
import '../domain/entities/operational_dashboard_snapshot.dart';
import '../domain/repositories/operational_dashboard_repository.dart';

class SqliteOperationalDashboardRepository
    implements OperationalDashboardRepository {
  SqliteOperationalDashboardRepository(this._appDatabase);

  final AppDatabase _appDatabase;

  @override
  Future<OperationalDashboardSnapshot> fetchSnapshot() async {
    final database = await _appDatabase.database;
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day).toIso8601String();
    final tomorrowStart = DateTime(
      now.year,
      now.month,
      now.day + 1,
    ).toIso8601String();

    final salesRows = await database.rawQuery(
      '''
      SELECT COALESCE(SUM(valor_final_centavos), 0) AS total
      FROM ${TableNames.vendas}
      WHERE status = 'ativa'
        AND data_venda >= ?
        AND data_venda < ?
    ''',
      [todayStart, tomorrowStart],
    );

    final cashSessionRows = await database.rawQuery('''
      SELECT id, saldo_final_centavos
      FROM ${TableNames.caixaSessoes}
      WHERE status = 'aberto'
      ORDER BY aberta_em DESC
      LIMIT 1
    ''');
    final currentCashSessionId = cashSessionRows.isEmpty
        ? null
        : cashSessionRows.first['id'] as int?;

    final pendingFiadoRows = await database.rawQuery('''
      SELECT
        COUNT(*) AS quantidade,
        COALESCE(SUM(valor_aberto_centavos), 0) AS total_aberto
      FROM ${TableNames.fiado}
      WHERE status IN ('pendente', 'parcial')
    ''');

    final operationalOrdersRows = await database.rawQuery('''
      SELECT COUNT(*) AS quantidade
      FROM ${TableNames.pedidosOperacionais}
      WHERE status IN ('draft', 'open', 'in_preparation', 'ready')
    ''');

    final recentMovementRows = await database.rawQuery('''
      SELECT
        tipo_movimento,
        valor_centavos,
        descricao,
        criado_em
      FROM ${TableNames.caixaMovimentos}
      ${currentCashSessionId == null ? '' : 'WHERE sessao_id = ?'}
      ORDER BY criado_em DESC, id DESC
      LIMIT 5
    ''', currentCashSessionId == null ? null : [currentCashSessionId]);

    return OperationalDashboardSnapshot(
      soldTodayCents: salesRows.first['total'] as int? ?? 0,
      currentCashCents: cashSessionRows.isEmpty
          ? 0
          : cashSessionRows.first['saldo_final_centavos'] as int? ?? 0,
      pendingFiadoCount: pendingFiadoRows.first['quantidade'] as int? ?? 0,
      pendingFiadoCents: pendingFiadoRows.first['total_aberto'] as int? ?? 0,
      activeOperationalOrdersCount:
          operationalOrdersRows.first['quantidade'] as int? ?? 0,
      recentMovements: recentMovementRows.map(_mapRecentMovement).toList(),
    );
  }

  OperationalDashboardRecentMovement _mapRecentMovement(
    Map<String, Object?> row,
  ) {
    final type = row['tipo_movimento'] as String? ?? '';
    return OperationalDashboardRecentMovement(
      label: _movementLabel(type),
      amountCents: row['valor_centavos'] as int? ?? 0,
      createdAt: DateTime.parse(row['criado_em'] as String),
      direction: _movementDirection(type),
      description: row['descricao'] as String?,
    );
  }

  String _movementLabel(String type) {
    switch (type) {
      case 'venda':
        return 'Venda recebida';
      case 'recebimento_fiado':
        return 'Recebimento de fiado';
      case 'sangria':
        return 'Sangria';
      case 'suprimento':
        return 'Suprimento';
      case 'cancelamento':
        return 'Cancelamento';
      case 'ajuste':
        return 'Ajuste manual';
      default:
        return 'Movimento local';
    }
  }

  OperationalDashboardMovementDirection _movementDirection(String type) {
    switch (type) {
      case 'venda':
      case 'recebimento_fiado':
      case 'suprimento':
        return OperationalDashboardMovementDirection.inflow;
      case 'sangria':
        return OperationalDashboardMovementDirection.outflow;
      case 'cancelamento':
      case 'ajuste':
      default:
        return OperationalDashboardMovementDirection.neutral;
    }
  }
}

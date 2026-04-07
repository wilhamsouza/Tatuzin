import '../../../app/core/database/app_database.dart';
import '../../../app/core/database/table_names.dart';
import '../domain/entities/dashboard_metrics.dart';
import '../domain/repositories/dashboard_repository.dart';

class SqliteDashboardRepository implements DashboardRepository {
  SqliteDashboardRepository(this._appDatabase);

  final AppDatabase _appDatabase;

  @override
  Future<DashboardMetrics> fetchMetrics() async {
    final database = await _appDatabase.database;
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day).toIso8601String();
    final tomorrowStart = DateTime(
      now.year,
      now.month,
      now.day + 1,
    ).toIso8601String();
    const soldAmountExpression = '''
      COALESCE(
        iv.subtotal_centavos,
        CAST(ROUND((iv.quantidade_mil * iv.valor_unitario_centavos) / 1000.0, 0) AS INTEGER)
      )
    ''';
    const costAmountExpression = '''
      COALESCE(
        iv.custo_total_centavos,
        CAST(ROUND((iv.quantidade_mil * iv.custo_unitario_centavos) / 1000.0, 0) AS INTEGER)
      )
    ''';

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

    final cashProfitRows = await database.rawQuery(
      '''
      SELECT COALESCE(SUM($soldAmountExpression - $costAmountExpression), 0) AS lucro
      FROM ${TableNames.itensVenda} iv
      INNER JOIN ${TableNames.vendas} v ON v.id = iv.venda_id
      WHERE v.status = 'ativa'
        AND v.tipo_venda = 'vista'
        AND v.data_venda >= ?
        AND v.data_venda < ?
    ''',
      [todayStart, tomorrowStart],
    );

    final fiadoProfitRows = await database.rawQuery(
      '''
      WITH fiado_margens AS (
        SELECT
          f.id AS fiado_id,
          v.valor_final_centavos AS valor_final_centavos,
          COALESCE(SUM($soldAmountExpression - $costAmountExpression), 0) AS margem_total_centavos
        FROM ${TableNames.fiado} f
        INNER JOIN ${TableNames.vendas} v ON v.id = f.venda_id
        INNER JOIN ${TableNames.itensVenda} iv ON iv.venda_id = v.id
        WHERE v.status = 'ativa'
          AND v.tipo_venda = 'fiado'
        GROUP BY f.id, v.valor_final_centavos
      ),
      pagamentos_periodo AS (
        SELECT
          lanc.fiado_id AS fiado_id,
          COALESCE(SUM(lanc.valor_centavos), 0) AS valor_pago_centavos
        FROM ${TableNames.fiadoLancamentos} lanc
        WHERE lanc.tipo_lancamento = 'pagamento'
          AND lanc.data_lancamento >= ?
          AND lanc.data_lancamento < ?
        GROUP BY lanc.fiado_id
      )
      SELECT
        COALESCE(
          SUM(
            CASE
              WHEN margem.valor_final_centavos <= 0 THEN 0
              ELSE CAST(
                ROUND(
                  (margem.margem_total_centavos * pagamentos.valor_pago_centavos) /
                  CAST(margem.valor_final_centavos AS REAL),
                  0
                ) AS INTEGER
              )
            END
          ),
          0
        ) AS lucro
      FROM fiado_margens margem
      INNER JOIN pagamentos_periodo pagamentos
        ON pagamentos.fiado_id = margem.fiado_id
    ''',
      [todayStart, tomorrowStart],
    );

    final cashRows = await database.rawQuery('''
      SELECT saldo_final_centavos
      FROM ${TableNames.caixaSessoes}
      WHERE status = 'aberto'
      ORDER BY aberta_em DESC
      LIMIT 1
    ''');

    final pendingFiadoRows = await database.rawQuery('''
      SELECT
        COUNT(*) AS quantidade,
        COALESCE(SUM(valor_aberto_centavos), 0) AS total_aberto
      FROM ${TableNames.fiado}
      WHERE status IN ('pendente', 'parcial')
    ''');

    return DashboardMetrics(
      soldTodayCents: salesRows.first['total'] as int? ?? 0,
      currentCashCents: cashRows.isEmpty
          ? 0
          : cashRows.first['saldo_final_centavos'] as int? ?? 0,
      pendingFiadoCount: pendingFiadoRows.first['quantidade'] as int? ?? 0,
      pendingFiadoCents: pendingFiadoRows.first['total_aberto'] as int? ?? 0,
      realizedProfitTodayCents:
          (cashProfitRows.first['lucro'] as int? ?? 0) +
          (fiadoProfitRows.first['lucro'] as int? ?? 0),
    );
  }
}

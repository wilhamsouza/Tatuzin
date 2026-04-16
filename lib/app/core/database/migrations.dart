import 'package:sqflite/sqflite.dart';

import '../utils/app_logger.dart';
import 'table_names.dart';

typedef MigrationRunner = Future<void> Function(DatabaseExecutor db);

class MigrationStep {
  const MigrationStep({required this.version, required this.up});

  final int version;
  final MigrationRunner up;
}

abstract final class AppMigrations {
  static final List<MigrationStep> _steps = <MigrationStep>[
    const MigrationStep(version: 1, up: _createVersion1Schema),
    const MigrationStep(version: 2, up: _createVersion2Schema),
    const MigrationStep(version: 3, up: _createVersion3Schema),
    const MigrationStep(version: 4, up: _createVersion4Schema),
    const MigrationStep(version: 5, up: _createVersion5Schema),
    const MigrationStep(version: 6, up: _createVersion6Schema),
    const MigrationStep(version: 7, up: _createVersion7Schema),
    const MigrationStep(version: 8, up: _createVersion8Schema),
    const MigrationStep(version: 9, up: _createVersion9Schema),
    const MigrationStep(version: 10, up: _createVersion10Schema),
    const MigrationStep(version: 11, up: _createVersion11Schema),
    const MigrationStep(version: 12, up: _createVersion12Schema),
    const MigrationStep(version: 13, up: _createVersion13Schema),
    const MigrationStep(version: 14, up: _createVersion14Schema),
    const MigrationStep(version: 15, up: _createVersion15Schema),
    const MigrationStep(version: 16, up: _createVersion16Schema),
    const MigrationStep(version: 17, up: _createVersion17Schema),
    const MigrationStep(version: 18, up: _createVersion18Schema),
    const MigrationStep(version: 19, up: _createVersion19Schema),
    const MigrationStep(version: 20, up: _createVersion20Schema),
    const MigrationStep(version: 21, up: _createVersion21Schema),
    const MigrationStep(version: 22, up: _createVersion22Schema),
    const MigrationStep(version: 23, up: _createVersion23Schema),
    const MigrationStep(version: 24, up: _createVersion24Schema),
    const MigrationStep(version: 25, up: _createVersion25Schema),
    const MigrationStep(version: 26, up: _createVersion26Schema),
    const MigrationStep(version: 27, up: _createVersion27Schema),
    const MigrationStep(version: 28, up: _createVersion28Schema),
    const MigrationStep(version: 29, up: _createVersion29Schema),
    const MigrationStep(version: 30, up: _createVersion30Schema),
  ];

  static Future<void> runCreate(DatabaseExecutor db, int version) async {
    for (final step in _steps.where((step) => step.version <= version)) {
      AppLogger.info('Applying schema step v${step.version} on create');
      await step.up(db);
    }
  }

  static Future<void> runUpgrade(
    DatabaseExecutor db,
    int oldVersion,
    int newVersion,
  ) async {
    for (final step in _steps) {
      final shouldRun = step.version > oldVersion && step.version <= newVersion;
      if (shouldRun) {
        AppLogger.info('Applying upgrade step v${step.version}');
        await step.up(db);
      }
    }
  }

  static Future<void> _createVersion1Schema(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE ${TableNames.usuarios} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        uuid TEXT NOT NULL UNIQUE,
        nome TEXT NOT NULL,
        pin_hash TEXT,
        ativo INTEGER NOT NULL DEFAULT 1,
        criado_em TEXT NOT NULL,
        atualizado_em TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE ${TableNames.categorias} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        uuid TEXT NOT NULL UNIQUE,
        nome TEXT NOT NULL,
        descricao TEXT,
        ativo INTEGER NOT NULL DEFAULT 1,
        criado_em TEXT NOT NULL,
        atualizado_em TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE ${TableNames.produtos} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        uuid TEXT NOT NULL UNIQUE,
        nome TEXT NOT NULL,
        descricao TEXT,
        categoria_id INTEGER,
        foto_path TEXT,
        codigo_barras TEXT,
        tipo_produto TEXT NOT NULL CHECK (tipo_produto IN ('unidade', 'peso')),
        unidade_medida TEXT NOT NULL,
        custo_centavos INTEGER NOT NULL,
        preco_venda_centavos INTEGER NOT NULL,
        estoque_mil INTEGER NOT NULL DEFAULT 0,
        ativo INTEGER NOT NULL DEFAULT 1,
        criado_em TEXT NOT NULL,
        atualizado_em TEXT NOT NULL,
        deletado_em TEXT,
        FOREIGN KEY (categoria_id) REFERENCES ${TableNames.categorias}(id) ON DELETE SET NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE ${TableNames.clientes} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        uuid TEXT NOT NULL UNIQUE,
        nome TEXT NOT NULL,
        telefone TEXT,
        endereco TEXT,
        observacao TEXT,
        saldo_devedor_centavos INTEGER NOT NULL DEFAULT 0,
        ativo INTEGER NOT NULL DEFAULT 1,
        criado_em TEXT NOT NULL,
        atualizado_em TEXT NOT NULL,
        deletado_em TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE ${TableNames.vendas} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        uuid TEXT NOT NULL UNIQUE,
        cliente_id INTEGER,
        tipo_venda TEXT NOT NULL CHECK (tipo_venda IN ('vista', 'fiado')),
        forma_pagamento TEXT NOT NULL CHECK (forma_pagamento IN ('dinheiro', 'pix', 'cartao', 'fiado')),
        status TEXT NOT NULL CHECK (status IN ('ativa', 'cancelada')),
        desconto_centavos INTEGER NOT NULL DEFAULT 0,
        acrescimo_centavos INTEGER NOT NULL DEFAULT 0,
        valor_total_centavos INTEGER NOT NULL,
        valor_final_centavos INTEGER NOT NULL,
        numero_cupom TEXT NOT NULL UNIQUE,
        data_venda TEXT NOT NULL,
        usuario_id INTEGER,
        observacao TEXT,
        cancelada_em TEXT,
        venda_origem_id INTEGER,
        FOREIGN KEY (cliente_id) REFERENCES ${TableNames.clientes}(id) ON DELETE SET NULL,
        FOREIGN KEY (usuario_id) REFERENCES ${TableNames.usuarios}(id) ON DELETE SET NULL,
        FOREIGN KEY (venda_origem_id) REFERENCES ${TableNames.vendas}(id) ON DELETE SET NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE ${TableNames.itensVenda} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        uuid TEXT NOT NULL UNIQUE,
        venda_id INTEGER NOT NULL,
        produto_id INTEGER NOT NULL,
        nome_produto_snapshot TEXT NOT NULL,
        quantidade_mil INTEGER NOT NULL,
        valor_unitario_centavos INTEGER NOT NULL,
        subtotal_centavos INTEGER NOT NULL,
        custo_unitario_centavos INTEGER NOT NULL,
        custo_total_centavos INTEGER NOT NULL,
        unidade_medida_snapshot TEXT NOT NULL,
        tipo_produto_snapshot TEXT NOT NULL,
        FOREIGN KEY (venda_id) REFERENCES ${TableNames.vendas}(id) ON DELETE CASCADE,
        FOREIGN KEY (produto_id) REFERENCES ${TableNames.produtos}(id) ON DELETE RESTRICT
      )
    ''');

    await db.execute('''
      CREATE TABLE ${TableNames.fiado} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        uuid TEXT NOT NULL UNIQUE,
        venda_id INTEGER NOT NULL UNIQUE,
        cliente_id INTEGER NOT NULL,
        valor_original_centavos INTEGER NOT NULL,
        valor_aberto_centavos INTEGER NOT NULL,
        vencimento TEXT NOT NULL,
        status TEXT NOT NULL CHECK (status IN ('pendente', 'parcial', 'quitado', 'cancelado')),
        criado_em TEXT NOT NULL,
        atualizado_em TEXT NOT NULL,
        quitado_em TEXT,
        FOREIGN KEY (venda_id) REFERENCES ${TableNames.vendas}(id) ON DELETE CASCADE,
        FOREIGN KEY (cliente_id) REFERENCES ${TableNames.clientes}(id) ON DELETE RESTRICT
      )
    ''');

    await db.execute('''
      CREATE TABLE ${TableNames.caixaSessoes} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        uuid TEXT NOT NULL UNIQUE,
        usuario_id INTEGER,
        aberta_em TEXT NOT NULL,
        fechada_em TEXT,
        troco_inicial_centavos INTEGER NOT NULL DEFAULT 0,
        total_suprimentos_centavos INTEGER NOT NULL DEFAULT 0,
        total_sangrias_centavos INTEGER NOT NULL DEFAULT 0,
        total_vendas_centavos INTEGER NOT NULL DEFAULT 0,
        total_recebimentos_fiado_centavos INTEGER NOT NULL DEFAULT 0,
        saldo_final_centavos INTEGER NOT NULL DEFAULT 0,
        status TEXT NOT NULL CHECK (status IN ('aberto', 'fechado')),
        observacao TEXT,
        FOREIGN KEY (usuario_id) REFERENCES ${TableNames.usuarios}(id) ON DELETE SET NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE ${TableNames.caixaMovimentos} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        uuid TEXT NOT NULL UNIQUE,
        sessao_id INTEGER NOT NULL,
        tipo_movimento TEXT NOT NULL CHECK (
          tipo_movimento IN ('venda', 'recebimento_fiado', 'sangria', 'suprimento', 'ajuste', 'cancelamento')
        ),
        referencia_tipo TEXT,
        referencia_id INTEGER,
        valor_centavos INTEGER NOT NULL,
        descricao TEXT,
        criado_em TEXT NOT NULL,
        FOREIGN KEY (sessao_id) REFERENCES ${TableNames.caixaSessoes}(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE ${TableNames.fiadoLancamentos} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        uuid TEXT NOT NULL UNIQUE,
        fiado_id INTEGER NOT NULL,
        cliente_id INTEGER NOT NULL,
        tipo_lancamento TEXT NOT NULL CHECK (tipo_lancamento IN ('abertura', 'pagamento', 'ajuste', 'cancelamento')),
        valor_centavos INTEGER NOT NULL,
        data_lancamento TEXT NOT NULL,
        observacao TEXT,
        caixa_movimento_id INTEGER,
        FOREIGN KEY (fiado_id) REFERENCES ${TableNames.fiado}(id) ON DELETE CASCADE,
        FOREIGN KEY (cliente_id) REFERENCES ${TableNames.clientes}(id) ON DELETE RESTRICT,
        FOREIGN KEY (caixa_movimento_id) REFERENCES ${TableNames.caixaMovimentos}(id) ON DELETE SET NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE ${TableNames.configuracoes} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        chave TEXT NOT NULL UNIQUE,
        valor_json TEXT NOT NULL,
        atualizado_em TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE ${TableNames.backupLogs} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        uuid TEXT NOT NULL UNIQUE,
        tipo_backup TEXT NOT NULL,
        destino TEXT NOT NULL,
        status TEXT NOT NULL,
        detalhes TEXT,
        criado_em TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE INDEX idx_produtos_nome
      ON ${TableNames.produtos}(nome)
    ''');
    await db.execute('''
      CREATE INDEX idx_produtos_codigo_barras
      ON ${TableNames.produtos}(codigo_barras)
    ''');
    await db.execute('''
      CREATE INDEX idx_clientes_nome
      ON ${TableNames.clientes}(nome)
    ''');
    await db.execute('''
      CREATE INDEX idx_vendas_data_venda
      ON ${TableNames.vendas}(data_venda)
    ''');
    await db.execute('''
      CREATE INDEX idx_vendas_cliente_status
      ON ${TableNames.vendas}(cliente_id, status)
    ''');
    await db.execute('''
      CREATE INDEX idx_fiado_status_vencimento
      ON ${TableNames.fiado}(status, vencimento)
    ''');
    await db.execute('''
      CREATE INDEX idx_caixa_movimentos_sessao_data
      ON ${TableNames.caixaMovimentos}(sessao_id, criado_em)
    ''');
    await db.execute('''
      CREATE INDEX idx_itens_venda_venda
      ON ${TableNames.itensVenda}(venda_id)
    ''');
  }

  static Future<void> _createVersion2Schema(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE ${TableNames.syncRegistros} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        feature_key TEXT NOT NULL,
        local_id INTEGER,
        local_uuid TEXT,
        remote_id TEXT,
        sync_status TEXT NOT NULL CHECK (
          sync_status IN (
            'local_only',
            'pending_upload',
            'synced',
            'pending_update',
            'sync_error',
            'conflict'
          )
        ),
        origin TEXT NOT NULL CHECK (origin IN ('local', 'remote', 'merged')),
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        last_synced_at TEXT,
        last_error TEXT,
        last_error_type TEXT,
        last_error_at TEXT
      )
    ''');

    await db.execute('''
      CREATE UNIQUE INDEX idx_sync_feature_local_id
      ON ${TableNames.syncRegistros}(feature_key, local_id)
    ''');
    await db.execute('''
      CREATE UNIQUE INDEX idx_sync_feature_local_uuid
      ON ${TableNames.syncRegistros}(feature_key, local_uuid)
    ''');
    await db.execute('''
      CREATE UNIQUE INDEX idx_sync_feature_remote_id
      ON ${TableNames.syncRegistros}(feature_key, remote_id)
    ''');
    await db.execute('''
      CREATE INDEX idx_sync_feature_status
      ON ${TableNames.syncRegistros}(feature_key, sync_status)
    ''');

    await db.execute('''
      INSERT OR IGNORE INTO ${TableNames.syncRegistros} (
        feature_key,
        local_id,
        local_uuid,
        remote_id,
        sync_status,
        origin,
        created_at,
        updated_at,
        last_synced_at,
        last_error,
        last_error_type,
        last_error_at
      )
      SELECT
        'products',
        id,
        uuid,
        NULL,
        'pending_upload',
        'local',
        criado_em,
        atualizado_em,
        NULL,
        NULL,
        NULL,
        NULL
      FROM ${TableNames.produtos}
      WHERE deletado_em IS NULL
    ''');

    await db.execute('''
      INSERT OR IGNORE INTO ${TableNames.syncRegistros} (
        feature_key,
        local_id,
        local_uuid,
        remote_id,
        sync_status,
        origin,
        created_at,
        updated_at,
        last_synced_at,
        last_error,
        last_error_type,
        last_error_at
      )
      SELECT
        'customers',
        id,
        uuid,
        NULL,
        'pending_upload',
        'local',
        criado_em,
        atualizado_em,
        NULL,
        NULL,
        NULL,
        NULL
      FROM ${TableNames.clientes}
      WHERE deletado_em IS NULL
    ''');
  }

  static Future<void> _createVersion3Schema(DatabaseExecutor db) async {
    await _ensureColumnExists(
      db,
      tableName: TableNames.categorias,
      columnName: 'deletado_em',
      columnDefinition: 'TEXT',
    );
    await _ensureColumnExists(
      db,
      tableName: TableNames.syncRegistros,
      columnName: 'last_error_type',
      columnDefinition: 'TEXT',
    );
    await _ensureColumnExists(
      db,
      tableName: TableNames.syncRegistros,
      columnName: 'last_error_at',
      columnDefinition: 'TEXT',
    );

    await db.execute('''
      INSERT OR IGNORE INTO ${TableNames.syncRegistros} (
        feature_key,
        local_id,
        local_uuid,
        remote_id,
        sync_status,
        origin,
        created_at,
        updated_at,
        last_synced_at,
        last_error,
        last_error_type,
        last_error_at
      )
      SELECT
        'categories',
        id,
        uuid,
        NULL,
        'pending_upload',
        'local',
        criado_em,
        atualizado_em,
        NULL,
        NULL,
        NULL,
        NULL
      FROM ${TableNames.categorias}
      WHERE deletado_em IS NULL
    ''');
  }

  static Future<void> _createVersion4Schema(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE ${TableNames.syncQueue} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        feature_key TEXT NOT NULL,
        entity_type TEXT NOT NULL,
        local_entity_id INTEGER NOT NULL,
        local_uuid TEXT,
        remote_id TEXT,
        operation_type TEXT NOT NULL CHECK (
          operation_type IN ('create', 'update', 'delete')
        ),
        status TEXT NOT NULL CHECK (
          status IN (
            'pending_upload',
            'pending_update',
            'processing',
            'synced',
            'sync_error',
            'blocked_dependency',
            'conflict'
          )
        ),
        attempt_count INTEGER NOT NULL DEFAULT 0,
        next_retry_at TEXT,
        last_error TEXT,
        last_error_type TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        locked_at TEXT,
        last_processed_at TEXT,
        correlation_key TEXT NOT NULL,
        local_updated_at TEXT,
        remote_updated_at TEXT,
        conflict_reason TEXT
      )
    ''');

    await db.execute('''
      CREATE UNIQUE INDEX idx_sync_queue_correlation
      ON ${TableNames.syncQueue}(correlation_key)
    ''');
    await db.execute('''
      CREATE INDEX idx_sync_queue_status_retry
      ON ${TableNames.syncQueue}(status, next_retry_at, updated_at)
    ''');
    await db.execute('''
      CREATE INDEX idx_sync_queue_feature_entity
      ON ${TableNames.syncQueue}(feature_key, local_entity_id)
    ''');

    await _backfillQueueForFeature(
      db,
      featureKey: 'categories',
      entityType: 'category',
      sourceTable: TableNames.categorias,
      deletedColumn: 'deletado_em',
    );
    await _backfillQueueForFeature(
      db,
      featureKey: 'products',
      entityType: 'product',
      sourceTable: TableNames.produtos,
      deletedColumn: 'deletado_em',
    );
    await _backfillQueueForFeature(
      db,
      featureKey: 'customers',
      entityType: 'customer',
      sourceTable: TableNames.clientes,
      deletedColumn: 'deletado_em',
    );
  }

  static Future<void> _createVersion5Schema(DatabaseExecutor db) async {
    await db.execute('''
      INSERT OR IGNORE INTO ${TableNames.syncRegistros} (
        feature_key,
        local_id,
        local_uuid,
        remote_id,
        sync_status,
        origin,
        created_at,
        updated_at,
        last_synced_at,
        last_error,
        last_error_type,
        last_error_at
      )
      SELECT
        'sales',
        id,
        uuid,
        NULL,
        'pending_upload',
        'local',
        data_venda,
        data_venda,
        NULL,
        NULL,
        NULL,
        NULL
      FROM ${TableNames.vendas}
      WHERE status = 'ativa'
    ''');

    await db.execute('''
      INSERT OR IGNORE INTO ${TableNames.syncQueue} (
        feature_key,
        entity_type,
        local_entity_id,
        local_uuid,
        remote_id,
        operation_type,
        status,
        attempt_count,
        next_retry_at,
        last_error,
        last_error_type,
        created_at,
        updated_at,
        locked_at,
        last_processed_at,
        correlation_key,
        local_updated_at,
        remote_updated_at,
        conflict_reason
      )
      SELECT
        sync.feature_key,
        'sale',
        venda.id,
        venda.uuid,
        sync.remote_id,
        CASE
          WHEN sync.remote_id IS NULL THEN 'create'
          ELSE 'update'
        END,
        CASE sync.sync_status
          WHEN 'pending_upload' THEN 'pending_upload'
          WHEN 'pending_update' THEN 'pending_update'
          WHEN 'sync_error' THEN 'sync_error'
          WHEN 'conflict' THEN 'conflict'
          ELSE 'pending_upload'
        END,
        0,
        NULL,
        sync.last_error,
        sync.last_error_type,
        sync.created_at,
        sync.updated_at,
        NULL,
        sync.last_synced_at,
        sync.feature_key || ':' || venda.id,
        venda.data_venda,
        sync.last_synced_at,
        NULL
      FROM ${TableNames.vendas} venda
      INNER JOIN ${TableNames.syncRegistros} sync
        ON sync.feature_key = 'sales'
        AND sync.local_id = venda.id
      WHERE venda.status = 'ativa'
        AND sync.sync_status IN (
          'pending_upload',
          'pending_update',
          'sync_error',
          'conflict'
        )
    ''');
  }

  static Future<void> _createVersion6Schema(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE sync_queue_v6 (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        feature_key TEXT NOT NULL,
        entity_type TEXT NOT NULL,
        local_entity_id INTEGER NOT NULL,
        local_uuid TEXT,
        remote_id TEXT,
        operation_type TEXT NOT NULL CHECK (
          operation_type IN ('create', 'update', 'delete', 'cancel')
        ),
        status TEXT NOT NULL CHECK (
          status IN (
            'pending_upload',
            'pending_update',
            'processing',
            'synced',
            'sync_error',
            'blocked_dependency',
            'conflict'
          )
        ),
        attempt_count INTEGER NOT NULL DEFAULT 0,
        next_retry_at TEXT,
        last_error TEXT,
        last_error_type TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        locked_at TEXT,
        last_processed_at TEXT,
        correlation_key TEXT NOT NULL,
        local_updated_at TEXT,
        remote_updated_at TEXT,
        conflict_reason TEXT
      )
    ''');

    await db.execute('''
      INSERT INTO sync_queue_v6 (
        id,
        feature_key,
        entity_type,
        local_entity_id,
        local_uuid,
        remote_id,
        operation_type,
        status,
        attempt_count,
        next_retry_at,
        last_error,
        last_error_type,
        created_at,
        updated_at,
        locked_at,
        last_processed_at,
        correlation_key,
        local_updated_at,
        remote_updated_at,
        conflict_reason
      )
      SELECT
        id,
        feature_key,
        entity_type,
        local_entity_id,
        local_uuid,
        remote_id,
        operation_type,
        status,
        attempt_count,
        next_retry_at,
        last_error,
        last_error_type,
        created_at,
        updated_at,
        locked_at,
        last_processed_at,
        correlation_key,
        local_updated_at,
        remote_updated_at,
        conflict_reason
      FROM ${TableNames.syncQueue}
    ''');

    await db.execute('DROP TABLE ${TableNames.syncQueue}');
    await db.execute(
      'ALTER TABLE sync_queue_v6 RENAME TO ${TableNames.syncQueue}',
    );
    await db.execute('''
      CREATE UNIQUE INDEX idx_sync_queue_correlation
      ON ${TableNames.syncQueue}(correlation_key)
    ''');
    await db.execute('''
      CREATE INDEX idx_sync_queue_status_retry
      ON ${TableNames.syncQueue}(status, next_retry_at, updated_at)
    ''');
    await db.execute('''
      CREATE INDEX idx_sync_queue_feature_entity
      ON ${TableNames.syncQueue}(feature_key, local_entity_id)
    ''');

    await _backfillSaleCancellationSync(db);
    await _backfillFiadoPaymentSync(db);
    await _backfillCashEventSync(db);
  }

  static Future<void> _createVersion7Schema(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE sync_queue_v7 (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        feature_key TEXT NOT NULL,
        entity_type TEXT NOT NULL,
        local_entity_id INTEGER NOT NULL,
        local_uuid TEXT,
        remote_id TEXT,
        operation_type TEXT NOT NULL CHECK (
          operation_type IN ('create', 'update', 'delete', 'cancel')
        ),
        status TEXT NOT NULL CHECK (
          status IN (
            'pending_upload',
            'pending_update',
            'processing',
            'synced',
            'sync_error',
            'blocked_dependency',
            'conflict'
          )
        ),
        attempt_count INTEGER NOT NULL DEFAULT 0,
        next_retry_at TEXT,
        last_error TEXT,
        last_error_type TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        locked_at TEXT,
        last_processed_at TEXT,
        correlation_key TEXT NOT NULL,
        local_updated_at TEXT,
        remote_updated_at TEXT,
        conflict_reason TEXT
      )
    ''');

    await db.execute('''
      INSERT INTO sync_queue_v7 (
        id,
        feature_key,
        entity_type,
        local_entity_id,
        local_uuid,
        remote_id,
        operation_type,
        status,
        attempt_count,
        next_retry_at,
        last_error,
        last_error_type,
        created_at,
        updated_at,
        locked_at,
        last_processed_at,
        correlation_key,
        local_updated_at,
        remote_updated_at,
        conflict_reason
      )
      SELECT
        id,
        feature_key,
        entity_type,
        local_entity_id,
        local_uuid,
        remote_id,
        operation_type,
        status,
        attempt_count,
        next_retry_at,
        last_error,
        last_error_type,
        created_at,
        updated_at,
        locked_at,
        last_processed_at,
        feature_key || ':' || entity_type || ':' || local_entity_id,
        local_updated_at,
        remote_updated_at,
        conflict_reason
      FROM ${TableNames.syncQueue}
      WHERE feature_key NOT IN ('sale_cancellations', 'fiado_payments')
    ''');

    await db.execute('DROP TABLE ${TableNames.syncQueue}');
    await db.execute(
      'ALTER TABLE sync_queue_v7 RENAME TO ${TableNames.syncQueue}',
    );
    await db.execute('''
      CREATE UNIQUE INDEX idx_sync_queue_correlation
      ON ${TableNames.syncQueue}(correlation_key)
    ''');
    await db.execute('''
      CREATE INDEX idx_sync_queue_status_retry
      ON ${TableNames.syncQueue}(status, next_retry_at, updated_at)
    ''');
    await db.execute('''
      CREATE INDEX idx_sync_queue_feature_entity
      ON ${TableNames.syncQueue}(feature_key, local_entity_id)
    ''');

    await db.update(
      TableNames.syncRegistros,
      {
        'remote_id': null,
        'sync_status': 'pending_upload',
        'origin': 'local',
        'last_synced_at': null,
        'last_error': null,
        'last_error_type': null,
        'last_error_at': null,
      },
      where: 'feature_key IN (?, ?)',
      whereArgs: ['sale_cancellations', 'fiado_payments'],
    );

    await _backfillFinancialEventQueue(db);
  }

  static Future<void> _ensureColumnExists(
    DatabaseExecutor db, {
    required String tableName,
    required String columnName,
    required String columnDefinition,
  }) async {
    final columns = await db.rawQuery('PRAGMA table_info($tableName)');
    final hasColumn = columns.any(
      (row) =>
          row['name']?.toString().toLowerCase() == columnName.toLowerCase(),
    );

    if (hasColumn) {
      AppLogger.info(
        'Skipping column $columnName on $tableName because it already exists',
      );
      return;
    }

    await db.execute(
      'ALTER TABLE $tableName ADD COLUMN $columnName $columnDefinition',
    );
  }

  static Future<bool> _tableExists(
    DatabaseExecutor db,
    String tableName,
  ) async {
    final rows = await db.rawQuery(
      '''
      SELECT name
      FROM sqlite_master
      WHERE type = 'table' AND name = ?
      LIMIT 1
      ''',
      [tableName],
    );
    return rows.isNotEmpty;
  }

  static Future<void> _backfillQueueForFeature(
    DatabaseExecutor db, {
    required String featureKey,
    required String entityType,
    required String sourceTable,
    required String deletedColumn,
  }) async {
    await db.execute('''
      INSERT OR IGNORE INTO ${TableNames.syncQueue} (
        feature_key,
        entity_type,
        local_entity_id,
        local_uuid,
        remote_id,
        operation_type,
        status,
        attempt_count,
        next_retry_at,
        last_error,
        last_error_type,
        created_at,
        updated_at,
        locked_at,
        last_processed_at,
        correlation_key,
        local_updated_at,
        remote_updated_at,
        conflict_reason
      )
      SELECT
        sync.feature_key,
        '$entityType',
        source.id,
        source.uuid,
        sync.remote_id,
        CASE
          WHEN source.$deletedColumn IS NOT NULL THEN 'delete'
          WHEN sync.remote_id IS NULL THEN 'create'
          ELSE 'update'
        END,
        CASE sync.sync_status
          WHEN 'pending_upload' THEN 'pending_upload'
          WHEN 'pending_update' THEN 'pending_update'
          WHEN 'sync_error' THEN 'sync_error'
          WHEN 'conflict' THEN 'conflict'
          ELSE 'pending_update'
        END,
        0,
        NULL,
        sync.last_error,
        sync.last_error_type,
        sync.created_at,
        sync.updated_at,
        NULL,
        sync.last_synced_at,
        sync.feature_key || ':$entityType:' || source.id,
        source.atualizado_em,
        sync.last_synced_at,
        NULL
      FROM $sourceTable source
      INNER JOIN ${TableNames.syncRegistros} sync
        ON sync.feature_key = '$featureKey'
        AND sync.local_id = source.id
      WHERE sync.sync_status IN ('pending_upload', 'pending_update', 'sync_error', 'conflict')
    ''');
  }

  static Future<void> _backfillSaleCancellationSync(DatabaseExecutor db) async {
    await db.execute('''
      INSERT OR IGNORE INTO ${TableNames.syncRegistros} (
        feature_key,
        local_id,
        local_uuid,
        remote_id,
        sync_status,
        origin,
        created_at,
        updated_at,
        last_synced_at,
        last_error,
        last_error_type,
        last_error_at
      )
      SELECT
        'sale_cancellations',
        venda.id,
        venda.uuid,
        sale_sync.remote_id,
        'pending_update',
        'merged',
        venda.cancelada_em,
        venda.cancelada_em,
        NULL,
        NULL,
        NULL,
        NULL
      FROM ${TableNames.vendas} venda
      INNER JOIN ${TableNames.syncRegistros} sale_sync
        ON sale_sync.feature_key = 'sales'
        AND sale_sync.local_id = venda.id
        AND sale_sync.remote_id IS NOT NULL
      WHERE venda.status = 'cancelada'
        AND venda.cancelada_em IS NOT NULL
    ''');

    await db.execute('''
      INSERT OR IGNORE INTO ${TableNames.syncQueue} (
        feature_key,
        entity_type,
        local_entity_id,
        local_uuid,
        remote_id,
        operation_type,
        status,
        attempt_count,
        next_retry_at,
        last_error,
        last_error_type,
        created_at,
        updated_at,
        locked_at,
        last_processed_at,
        correlation_key,
        local_updated_at,
        remote_updated_at,
        conflict_reason
      )
      SELECT
        sync.feature_key,
        'sale',
        venda.id,
        venda.uuid,
        sync.remote_id,
        'cancel',
        CASE sync.sync_status
          WHEN 'sync_error' THEN 'sync_error'
          WHEN 'conflict' THEN 'conflict'
          ELSE 'pending_update'
        END,
        0,
        NULL,
        sync.last_error,
        sync.last_error_type,
        sync.created_at,
        sync.updated_at,
        NULL,
        sync.last_synced_at,
        sync.feature_key || ':' || venda.id,
        venda.cancelada_em,
        sync.last_synced_at,
        NULL
      FROM ${TableNames.vendas} venda
      INNER JOIN ${TableNames.syncRegistros} sync
        ON sync.feature_key = 'sale_cancellations'
        AND sync.local_id = venda.id
      WHERE venda.status = 'cancelada'
        AND venda.cancelada_em IS NOT NULL
        AND sync.sync_status IN ('pending_update', 'sync_error', 'conflict')
    ''');
  }

  static Future<void> _backfillFiadoPaymentSync(DatabaseExecutor db) async {
    await db.execute('''
      INSERT OR IGNORE INTO ${TableNames.syncRegistros} (
        feature_key,
        local_id,
        local_uuid,
        remote_id,
        sync_status,
        origin,
        created_at,
        updated_at,
        last_synced_at,
        last_error,
        last_error_type,
        last_error_at
      )
      SELECT
        'fiado_payments',
        lanc.id,
        lanc.uuid,
        NULL,
        'pending_upload',
        'local',
        lanc.data_lancamento,
        lanc.data_lancamento,
        NULL,
        NULL,
        NULL,
        NULL
      FROM ${TableNames.fiadoLancamentos} lanc
      WHERE lanc.tipo_lancamento = 'pagamento'
    ''');

    await db.execute('''
      INSERT OR IGNORE INTO ${TableNames.syncQueue} (
        feature_key,
        entity_type,
        local_entity_id,
        local_uuid,
        remote_id,
        operation_type,
        status,
        attempt_count,
        next_retry_at,
        last_error,
        last_error_type,
        created_at,
        updated_at,
        locked_at,
        last_processed_at,
        correlation_key,
        local_updated_at,
        remote_updated_at,
        conflict_reason
      )
      SELECT
        sync.feature_key,
        'fiado_payment',
        lanc.id,
        lanc.uuid,
        sync.remote_id,
        'create',
        CASE sync.sync_status
          WHEN 'sync_error' THEN 'sync_error'
          WHEN 'conflict' THEN 'conflict'
          ELSE 'pending_upload'
        END,
        0,
        NULL,
        sync.last_error,
        sync.last_error_type,
        sync.created_at,
        sync.updated_at,
        NULL,
        sync.last_synced_at,
        sync.feature_key || ':' || lanc.id,
        lanc.data_lancamento,
        sync.last_synced_at,
        NULL
      FROM ${TableNames.fiadoLancamentos} lanc
      INNER JOIN ${TableNames.syncRegistros} sync
        ON sync.feature_key = 'fiado_payments'
        AND sync.local_id = lanc.id
      WHERE lanc.tipo_lancamento = 'pagamento'
        AND sync.sync_status IN ('pending_upload', 'sync_error', 'conflict')
    ''');
  }

  static Future<void> _backfillCashEventSync(DatabaseExecutor db) async {
    await db.execute('''
      INSERT OR IGNORE INTO ${TableNames.syncRegistros} (
        feature_key,
        local_id,
        local_uuid,
        remote_id,
        sync_status,
        origin,
        created_at,
        updated_at,
        last_synced_at,
        last_error,
        last_error_type,
        last_error_at
      )
      SELECT
        'cash_events',
        mov.id,
        mov.uuid,
        NULL,
        'pending_upload',
        'local',
        mov.criado_em,
        mov.criado_em,
        NULL,
        NULL,
        NULL,
        NULL
      FROM ${TableNames.caixaMovimentos} mov
    ''');

    await db.execute('''
      INSERT OR IGNORE INTO ${TableNames.syncQueue} (
        feature_key,
        entity_type,
        local_entity_id,
        local_uuid,
        remote_id,
        operation_type,
        status,
        attempt_count,
        next_retry_at,
        last_error,
        last_error_type,
        created_at,
        updated_at,
        locked_at,
        last_processed_at,
        correlation_key,
        local_updated_at,
        remote_updated_at,
        conflict_reason
      )
      SELECT
        sync.feature_key,
        'cash_event',
        mov.id,
        mov.uuid,
        sync.remote_id,
        'create',
        CASE sync.sync_status
          WHEN 'sync_error' THEN 'sync_error'
          WHEN 'conflict' THEN 'conflict'
          ELSE 'pending_upload'
        END,
        0,
        NULL,
        sync.last_error,
        sync.last_error_type,
        sync.created_at,
        sync.updated_at,
        NULL,
        sync.last_synced_at,
        sync.feature_key || ':' || mov.id,
        mov.criado_em,
        sync.last_synced_at,
        NULL
      FROM ${TableNames.caixaMovimentos} mov
      INNER JOIN ${TableNames.syncRegistros} sync
        ON sync.feature_key = 'cash_events'
        AND sync.local_id = mov.id
      WHERE sync.sync_status IN ('pending_upload', 'sync_error', 'conflict')
    ''');
  }

  static Future<void> _backfillFinancialEventQueue(DatabaseExecutor db) async {
    await db.execute('''
      INSERT OR IGNORE INTO ${TableNames.syncQueue} (
        feature_key,
        entity_type,
        local_entity_id,
        local_uuid,
        remote_id,
        operation_type,
        status,
        attempt_count,
        next_retry_at,
        last_error,
        last_error_type,
        created_at,
        updated_at,
        locked_at,
        last_processed_at,
        correlation_key,
        local_updated_at,
        remote_updated_at,
        conflict_reason
      )
      SELECT
        'financial_events',
        'sale_canceled_event',
        venda.id,
        venda.uuid,
        NULL,
        'create',
        CASE sync.sync_status
          WHEN 'sync_error' THEN 'sync_error'
          WHEN 'conflict' THEN 'conflict'
          ELSE 'pending_upload'
        END,
        0,
        NULL,
        sync.last_error,
        sync.last_error_type,
        sync.created_at,
        sync.updated_at,
        NULL,
        sync.last_synced_at,
        'financial_events:sale_canceled_event:' || venda.id,
        venda.cancelada_em,
        NULL,
        NULL
      FROM ${TableNames.vendas} venda
      INNER JOIN ${TableNames.syncRegistros} sync
        ON sync.feature_key = 'sale_cancellations'
        AND sync.local_id = venda.id
      WHERE venda.status = 'cancelada'
        AND venda.cancelada_em IS NOT NULL
    ''');

    await db.execute('''
      INSERT OR IGNORE INTO ${TableNames.syncQueue} (
        feature_key,
        entity_type,
        local_entity_id,
        local_uuid,
        remote_id,
        operation_type,
        status,
        attempt_count,
        next_retry_at,
        last_error,
        last_error_type,
        created_at,
        updated_at,
        locked_at,
        last_processed_at,
        correlation_key,
        local_updated_at,
        remote_updated_at,
        conflict_reason
      )
      SELECT
        'financial_events',
        'fiado_payment_event',
        lanc.id,
        lanc.uuid,
        NULL,
        'create',
        CASE sync.sync_status
          WHEN 'sync_error' THEN 'sync_error'
          WHEN 'conflict' THEN 'conflict'
          ELSE 'pending_upload'
        END,
        0,
        NULL,
        sync.last_error,
        sync.last_error_type,
        sync.created_at,
        sync.updated_at,
        NULL,
        sync.last_synced_at,
        'financial_events:fiado_payment_event:' || lanc.id,
        lanc.data_lancamento,
        NULL,
        NULL
      FROM ${TableNames.fiadoLancamentos} lanc
      INNER JOIN ${TableNames.syncRegistros} sync
        ON sync.feature_key = 'fiado_payments'
        AND sync.local_id = lanc.id
      WHERE lanc.tipo_lancamento = 'pagamento'
    ''');
  }

  static Future<void> _createVersion8Schema(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE ${TableNames.syncAuditLogs} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        feature_key TEXT NOT NULL,
        entity_type TEXT,
        local_entity_id INTEGER,
        local_uuid TEXT,
        remote_id TEXT,
        event_type TEXT NOT NULL,
        message TEXT NOT NULL,
        details_json TEXT,
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE INDEX idx_sync_audit_feature_created
      ON ${TableNames.syncAuditLogs}(feature_key, created_at DESC)
    ''');
    await db.execute('''
      CREATE INDEX idx_sync_audit_entity_created
      ON ${TableNames.syncAuditLogs}(feature_key, local_entity_id, created_at DESC)
    ''');
  }

  static Future<void> _createVersion9Schema(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE ${TableNames.fornecedores} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        uuid TEXT NOT NULL UNIQUE,
        nome TEXT NOT NULL,
        nome_fantasia TEXT,
        telefone TEXT,
        email TEXT,
        endereco TEXT,
        documento TEXT,
        contato_responsavel TEXT,
        observacao TEXT,
        ativo INTEGER NOT NULL DEFAULT 1,
        criado_em TEXT NOT NULL,
        atualizado_em TEXT NOT NULL,
        deletado_em TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE ${TableNames.compras} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        uuid TEXT NOT NULL UNIQUE,
        fornecedor_id INTEGER NOT NULL,
        numero_documento TEXT,
        observacao TEXT,
        data_compra TEXT NOT NULL,
        data_vencimento TEXT,
        forma_pagamento TEXT,
        status TEXT NOT NULL CHECK (
          status IN (
            'rascunho',
            'aberta',
            'recebida',
            'parcialmente_paga',
            'paga',
            'cancelada'
          )
        ),
        subtotal_centavos INTEGER NOT NULL,
        desconto_centavos INTEGER NOT NULL DEFAULT 0,
        acrescimo_centavos INTEGER NOT NULL DEFAULT 0,
        frete_centavos INTEGER NOT NULL DEFAULT 0,
        valor_final_centavos INTEGER NOT NULL,
        valor_pago_centavos INTEGER NOT NULL DEFAULT 0,
        valor_pendente_centavos INTEGER NOT NULL,
        cancelada_em TEXT,
        criado_em TEXT NOT NULL,
        atualizado_em TEXT NOT NULL,
        FOREIGN KEY (fornecedor_id) REFERENCES ${TableNames.fornecedores}(id) ON DELETE RESTRICT
      )
    ''');

    await db.execute('''
      CREATE TABLE ${TableNames.itensCompra} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        uuid TEXT NOT NULL UNIQUE,
        compra_id INTEGER NOT NULL,
        produto_id INTEGER NOT NULL,
        nome_produto_snapshot TEXT NOT NULL,
        unidade_medida_snapshot TEXT NOT NULL,
        quantidade_mil INTEGER NOT NULL,
        custo_unitario_centavos INTEGER NOT NULL,
        subtotal_centavos INTEGER NOT NULL,
        FOREIGN KEY (compra_id) REFERENCES ${TableNames.compras}(id) ON DELETE CASCADE,
        FOREIGN KEY (produto_id) REFERENCES ${TableNames.produtos}(id) ON DELETE RESTRICT
      )
    ''');

    await db.execute('''
      CREATE TABLE ${TableNames.compraPagamentos} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        uuid TEXT NOT NULL UNIQUE,
        compra_id INTEGER NOT NULL,
        valor_centavos INTEGER NOT NULL,
        forma_pagamento TEXT NOT NULL,
        data_hora TEXT NOT NULL,
        observacao TEXT,
        caixa_movimento_id INTEGER,
        FOREIGN KEY (compra_id) REFERENCES ${TableNames.compras}(id) ON DELETE CASCADE,
        FOREIGN KEY (caixa_movimento_id) REFERENCES ${TableNames.caixaMovimentos}(id) ON DELETE SET NULL
      )
    ''');

    await db.execute('''
      CREATE INDEX idx_fornecedores_nome
      ON ${TableNames.fornecedores}(nome)
    ''');
    await db.execute('''
      CREATE INDEX idx_fornecedores_documento
      ON ${TableNames.fornecedores}(documento)
    ''');
    await db.execute('''
      CREATE INDEX idx_compras_fornecedor_data
      ON ${TableNames.compras}(fornecedor_id, data_compra DESC)
    ''');
    await db.execute('''
      CREATE INDEX idx_compras_status
      ON ${TableNames.compras}(status, data_compra DESC)
    ''');
    await db.execute('''
      CREATE INDEX idx_itens_compra_compra
      ON ${TableNames.itensCompra}(compra_id)
    ''');
    await db.execute('''
      CREATE INDEX idx_compra_pagamentos_compra_data
      ON ${TableNames.compraPagamentos}(compra_id, data_hora DESC)
    ''');
  }

  static Future<void> _createVersion10Schema(DatabaseExecutor db) async {
    await db.execute('''
      INSERT OR IGNORE INTO ${TableNames.syncRegistros} (
        feature_key,
        local_id,
        local_uuid,
        remote_id,
        sync_status,
        origin,
        created_at,
        updated_at,
        last_synced_at,
        last_error,
        last_error_type,
        last_error_at
      )
      SELECT
        'suppliers',
        id,
        uuid,
        NULL,
        'pending_upload',
        'local',
        criado_em,
        atualizado_em,
        NULL,
        NULL,
        NULL,
        NULL
      FROM ${TableNames.fornecedores}
      WHERE deletado_em IS NULL
    ''');

    await _backfillQueueForFeature(
      db,
      featureKey: 'suppliers',
      entityType: 'supplier',
      sourceTable: TableNames.fornecedores,
      deletedColumn: 'deletado_em',
    );

    await db.execute('''
      INSERT OR IGNORE INTO ${TableNames.syncRegistros} (
        feature_key,
        local_id,
        local_uuid,
        remote_id,
        sync_status,
        origin,
        created_at,
        updated_at,
        last_synced_at,
        last_error,
        last_error_type,
        last_error_at
      )
      SELECT
        'purchases',
        id,
        uuid,
        NULL,
        'pending_upload',
        'local',
        criado_em,
        atualizado_em,
        NULL,
        NULL,
        NULL,
        NULL
      FROM ${TableNames.compras}
    ''');

    await db.execute('''
      INSERT OR IGNORE INTO ${TableNames.syncQueue} (
        feature_key,
        entity_type,
        local_entity_id,
        local_uuid,
        remote_id,
        operation_type,
        status,
        attempt_count,
        next_retry_at,
        last_error,
        last_error_type,
        created_at,
        updated_at,
        locked_at,
        last_processed_at,
        correlation_key,
        local_updated_at,
        remote_updated_at,
        conflict_reason
      )
      SELECT
        sync.feature_key,
        'purchase',
        compra.id,
        compra.uuid,
        sync.remote_id,
        CASE
          WHEN sync.remote_id IS NULL THEN 'create'
          ELSE 'update'
        END,
        CASE sync.sync_status
          WHEN 'pending_upload' THEN 'pending_upload'
          WHEN 'pending_update' THEN 'pending_update'
          WHEN 'sync_error' THEN 'sync_error'
          WHEN 'conflict' THEN 'conflict'
          ELSE 'pending_upload'
        END,
        0,
        NULL,
        sync.last_error,
        sync.last_error_type,
        sync.created_at,
        sync.updated_at,
        NULL,
        sync.last_synced_at,
        sync.feature_key || ':purchase:' || compra.id,
        compra.atualizado_em,
        sync.last_synced_at,
        NULL
      FROM ${TableNames.compras} compra
      INNER JOIN ${TableNames.syncRegistros} sync
        ON sync.feature_key = 'purchases'
        AND sync.local_id = compra.id
      WHERE sync.sync_status IN (
        'pending_upload',
        'pending_update',
        'sync_error',
        'conflict'
      )
    ''');
  }

  static Future<void> _createVersion11Schema(DatabaseExecutor db) async {
    await _ensureColumnExists(
      db,
      tableName: TableNames.produtos,
      columnName: 'catalog_type',
      columnDefinition: "TEXT NOT NULL DEFAULT 'simple'",
    );
    await _ensureColumnExists(
      db,
      tableName: TableNames.produtos,
      columnName: 'model_name',
      columnDefinition: 'TEXT',
    );
    await _ensureColumnExists(
      db,
      tableName: TableNames.produtos,
      columnName: 'variant_label',
      columnDefinition: 'TEXT',
    );

    await db.execute('''
      UPDATE ${TableNames.produtos}
      SET catalog_type = 'simple'
      WHERE catalog_type IS NULL OR TRIM(catalog_type) = ''
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_produtos_model_name
      ON ${TableNames.produtos}(model_name)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_produtos_variant_label
      ON ${TableNames.produtos}(variant_label)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_produtos_catalog_type
      ON ${TableNames.produtos}(catalog_type)
    ''');
  }

  static Future<void> _createVersion12Schema(DatabaseExecutor db) async {
    final nowIso = DateTime.now().toIso8601String();

    await db.execute('''
      CREATE TABLE ${TableNames.contasReceber} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        uuid TEXT NOT NULL UNIQUE,
        remote_id TEXT,
        descricao TEXT NOT NULL,
        cliente_id INTEGER,
        tipo_origem TEXT,
        origem_id INTEGER,
        chave_origem TEXT UNIQUE,
        valor_centavos INTEGER NOT NULL,
        valor_recebido_centavos INTEGER NOT NULL DEFAULT 0,
        vencimento TEXT NOT NULL,
        recebido_em TEXT,
        forma_recebimento TEXT,
        status TEXT NOT NULL CHECK (
          status IN ('pending', 'partial', 'paid', 'overdue', 'canceled')
        ),
        criado_em TEXT NOT NULL,
        atualizado_em TEXT NOT NULL,
        cancelado_em TEXT,
        FOREIGN KEY (cliente_id) REFERENCES ${TableNames.clientes}(id) ON DELETE SET NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE ${TableNames.recebimentosContasReceber} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        uuid TEXT NOT NULL UNIQUE,
        conta_receber_id INTEGER NOT NULL,
        tipo_origem TEXT,
        origem_id INTEGER,
        chave_origem TEXT UNIQUE,
        valor_centavos INTEGER NOT NULL,
        data_hora TEXT NOT NULL,
        forma_pagamento TEXT,
        observacao TEXT,
        caixa_movimento_id INTEGER,
        FOREIGN KEY (conta_receber_id) REFERENCES ${TableNames.contasReceber}(id) ON DELETE CASCADE,
        FOREIGN KEY (caixa_movimento_id) REFERENCES ${TableNames.caixaMovimentos}(id) ON DELETE SET NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE ${TableNames.contasPagar} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        uuid TEXT NOT NULL UNIQUE,
        remote_id TEXT,
        descricao TEXT NOT NULL,
        fornecedor_id INTEGER,
        categoria_despesa TEXT,
        tipo_origem TEXT,
        origem_id INTEGER,
        chave_origem TEXT UNIQUE,
        valor_centavos INTEGER NOT NULL,
        valor_pago_centavos INTEGER NOT NULL DEFAULT 0,
        vencimento TEXT NOT NULL,
        pago_em TEXT,
        forma_pagamento TEXT,
        status TEXT NOT NULL CHECK (
          status IN ('pending', 'partial', 'paid', 'overdue', 'canceled')
        ),
        criado_em TEXT NOT NULL,
        atualizado_em TEXT NOT NULL,
        cancelado_em TEXT,
        FOREIGN KEY (fornecedor_id) REFERENCES ${TableNames.fornecedores}(id) ON DELETE SET NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE ${TableNames.pagamentosContasPagar} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        uuid TEXT NOT NULL UNIQUE,
        conta_pagar_id INTEGER NOT NULL,
        tipo_origem TEXT,
        origem_id INTEGER,
        chave_origem TEXT UNIQUE,
        valor_centavos INTEGER NOT NULL,
        data_hora TEXT NOT NULL,
        forma_pagamento TEXT,
        observacao TEXT,
        caixa_movimento_id INTEGER,
        FOREIGN KEY (conta_pagar_id) REFERENCES ${TableNames.contasPagar}(id) ON DELETE CASCADE,
        FOREIGN KEY (caixa_movimento_id) REFERENCES ${TableNames.caixaMovimentos}(id) ON DELETE SET NULL
      )
    ''');

    await db.execute('''
      CREATE INDEX idx_contas_receber_status_vencimento
      ON ${TableNames.contasReceber}(status, vencimento)
    ''');
    await db.execute('''
      CREATE INDEX idx_contas_receber_cliente
      ON ${TableNames.contasReceber}(cliente_id, vencimento)
    ''');
    await db.execute('''
      CREATE INDEX idx_recebimentos_contas_receber_conta
      ON ${TableNames.recebimentosContasReceber}(conta_receber_id, data_hora DESC)
    ''');
    await db.execute('''
      CREATE INDEX idx_contas_pagar_status_vencimento
      ON ${TableNames.contasPagar}(status, vencimento)
    ''');
    await db.execute('''
      CREATE INDEX idx_contas_pagar_fornecedor
      ON ${TableNames.contasPagar}(fornecedor_id, vencimento)
    ''');
    await db.execute('''
      CREATE INDEX idx_pagamentos_contas_pagar_conta
      ON ${TableNames.pagamentosContasPagar}(conta_pagar_id, data_hora DESC)
    ''');

    await db.execute('''
      INSERT OR IGNORE INTO ${TableNames.contasReceber} (
        uuid,
        remote_id,
        descricao,
        cliente_id,
        tipo_origem,
        origem_id,
        chave_origem,
        valor_centavos,
        valor_recebido_centavos,
        vencimento,
        recebido_em,
        forma_recebimento,
        status,
        criado_em,
        atualizado_em,
        cancelado_em
      )
      SELECT
        'receber-' || f.uuid,
        NULL,
        'Fiado ' || v.numero_cupom || ' - ' || c.nome,
        f.cliente_id,
        'fiado',
        f.id,
        'fiado:' || f.id,
        f.valor_original_centavos,
        (f.valor_original_centavos - f.valor_aberto_centavos),
        f.vencimento,
        f.quitado_em,
        NULL,
        CASE
          WHEN f.status = 'cancelado' THEN 'canceled'
          WHEN f.status = 'quitado' THEN 'paid'
          WHEN f.vencimento < '$nowIso' THEN 'overdue'
          WHEN f.status = 'parcial' THEN 'partial'
          ELSE 'pending'
        END,
        f.criado_em,
        f.atualizado_em,
        CASE WHEN f.status = 'cancelado' THEN f.atualizado_em ELSE NULL END
      FROM ${TableNames.fiado} f
      INNER JOIN ${TableNames.clientes} c ON c.id = f.cliente_id
      INNER JOIN ${TableNames.vendas} v ON v.id = f.venda_id
    ''');

    await db.execute('''
      INSERT OR IGNORE INTO ${TableNames.recebimentosContasReceber} (
        uuid,
        conta_receber_id,
        tipo_origem,
        origem_id,
        chave_origem,
        valor_centavos,
        data_hora,
        forma_pagamento,
        observacao,
        caixa_movimento_id
      )
      SELECT
        'recebimento-' || lanc.uuid,
        conta.id,
        'fiado_lancamento',
        lanc.id,
        'fiado_lancamento:' || lanc.id,
        lanc.valor_centavos,
        lanc.data_lancamento,
        NULL,
        lanc.observacao,
        lanc.caixa_movimento_id
      FROM ${TableNames.fiadoLancamentos} lanc
      INNER JOIN ${TableNames.contasReceber} conta
        ON conta.tipo_origem = 'fiado'
        AND conta.origem_id = lanc.fiado_id
      WHERE lanc.tipo_lancamento IN ('pagamento', 'cancelamento')
    ''');

    await db.execute('''
      INSERT OR IGNORE INTO ${TableNames.contasPagar} (
        uuid,
        remote_id,
        descricao,
        fornecedor_id,
        categoria_despesa,
        tipo_origem,
        origem_id,
        chave_origem,
        valor_centavos,
        valor_pago_centavos,
        vencimento,
        pago_em,
        forma_pagamento,
        status,
        criado_em,
        atualizado_em,
        cancelado_em
      )
      SELECT
        'pagar-' || c.uuid,
        NULL,
        'Compra ' || COALESCE(c.numero_documento, '#' || c.id) || ' - ' || f.nome,
        c.fornecedor_id,
        'Compra',
        'purchase',
        c.id,
        'purchase:' || c.id,
        c.valor_final_centavos,
        c.valor_pago_centavos,
        COALESCE(c.data_vencimento, c.data_compra),
        (
          SELECT MAX(p.data_hora)
          FROM ${TableNames.compraPagamentos} p
          WHERE p.compra_id = c.id
        ),
        c.forma_pagamento,
        CASE
          WHEN c.status = 'cancelada' THEN 'canceled'
          WHEN c.status = 'paga' THEN 'paid'
          WHEN COALESCE(c.data_vencimento, c.data_compra) < '$nowIso'
            AND c.valor_pendente_centavos > 0 THEN 'overdue'
          WHEN c.valor_pago_centavos > 0 THEN 'partial'
          ELSE 'pending'
        END,
        c.criado_em,
        c.atualizado_em,
        c.cancelada_em
      FROM ${TableNames.compras} c
      INNER JOIN ${TableNames.fornecedores} f ON f.id = c.fornecedor_id
    ''');

    await db.execute('''
      INSERT OR IGNORE INTO ${TableNames.pagamentosContasPagar} (
        uuid,
        conta_pagar_id,
        tipo_origem,
        origem_id,
        chave_origem,
        valor_centavos,
        data_hora,
        forma_pagamento,
        observacao,
        caixa_movimento_id
      )
      SELECT
        'pagamento-' || pag.uuid,
        conta.id,
        'purchase_payment',
        pag.id,
        'purchase_payment:' || pag.id,
        pag.valor_centavos,
        pag.data_hora,
        pag.forma_pagamento,
        pag.observacao,
        pag.caixa_movimento_id
      FROM ${TableNames.compraPagamentos} pag
      INNER JOIN ${TableNames.contasPagar} conta
        ON conta.tipo_origem = 'purchase'
        AND conta.origem_id = pag.compra_id
    ''');
  }

  static Future<void> _createVersion13Schema(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE ${TableNames.custos} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        uuid TEXT NOT NULL UNIQUE,
        remote_id TEXT,
        descricao TEXT NOT NULL,
        tipo_custo TEXT NOT NULL CHECK (tipo_custo IN ('fixed', 'variable')),
        categoria TEXT,
        valor_centavos INTEGER NOT NULL,
        data_referencia TEXT NOT NULL,
        pago_em TEXT,
        forma_pagamento TEXT,
        observacao TEXT,
        recorrente INTEGER NOT NULL DEFAULT 0,
        status TEXT NOT NULL CHECK (status IN ('pending', 'paid', 'canceled')),
        caixa_movimento_id INTEGER,
        criado_em TEXT NOT NULL,
        atualizado_em TEXT NOT NULL,
        cancelado_em TEXT,
        FOREIGN KEY (caixa_movimento_id) REFERENCES ${TableNames.caixaMovimentos}(id) ON DELETE SET NULL
      )
    ''');

    await db.execute('''
      CREATE INDEX idx_custos_tipo_status_data
      ON ${TableNames.custos}(tipo_custo, status, data_referencia)
    ''');
    await db.execute('''
      CREATE INDEX idx_custos_data_referencia
      ON ${TableNames.custos}(data_referencia DESC)
    ''');
    await db.execute('''
      CREATE INDEX idx_custos_categoria
      ON ${TableNames.custos}(categoria)
    ''');

    await db.execute('''
      INSERT OR IGNORE INTO ${TableNames.custos} (
        uuid,
        remote_id,
        descricao,
        tipo_custo,
        categoria,
        valor_centavos,
        data_referencia,
        pago_em,
        forma_pagamento,
        observacao,
        recorrente,
        status,
        caixa_movimento_id,
        criado_em,
        atualizado_em,
        cancelado_em
      )
      SELECT
        cp.uuid,
        cp.remote_id,
        cp.descricao,
        'variable',
        COALESCE(cp.categoria_despesa, 'Custo migrado'),
        cp.valor_centavos,
        cp.vencimento,
        cp.pago_em,
        cp.forma_pagamento,
        'Migrado do modulo financeiro anterior.',
        0,
        CASE
          WHEN cp.status = 'paid' THEN 'paid'
          WHEN cp.status = 'canceled' THEN 'canceled'
          ELSE 'pending'
        END,
        (
          SELECT pg.caixa_movimento_id
          FROM ${TableNames.pagamentosContasPagar} pg
          WHERE pg.conta_pagar_id = cp.id
            AND pg.caixa_movimento_id IS NOT NULL
          ORDER BY pg.data_hora DESC, pg.id DESC
          LIMIT 1
        ),
        cp.criado_em,
        cp.atualizado_em,
        cp.cancelado_em
      FROM ${TableNames.contasPagar} cp
      WHERE cp.tipo_origem = 'manual'
    ''');
  }

  static Future<void> _createVersion14Schema(DatabaseExecutor db) async {
    final nowIso = DateTime.now().toIso8601String();

    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${TableNames.produtosBase} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        uuid TEXT NOT NULL UNIQUE,
        nome TEXT NOT NULL,
        descricao TEXT,
        categoria_id INTEGER,
        ativo INTEGER NOT NULL DEFAULT 1,
        criado_em TEXT NOT NULL,
        atualizado_em TEXT NOT NULL,
        FOREIGN KEY (categoria_id) REFERENCES ${TableNames.categorias}(id) ON DELETE SET NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${TableNames.produtosBaseVariantes} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        uuid TEXT NOT NULL UNIQUE,
        produto_base_id INTEGER NOT NULL,
        produto_id INTEGER NOT NULL UNIQUE,
        criado_em TEXT NOT NULL,
        atualizado_em TEXT NOT NULL,
        FOREIGN KEY (produto_base_id) REFERENCES ${TableNames.produtosBase}(id) ON DELETE CASCADE,
        FOREIGN KEY (produto_id) REFERENCES ${TableNames.produtos}(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${TableNames.produtoVarianteAtributos} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        uuid TEXT NOT NULL UNIQUE,
        produto_id INTEGER NOT NULL,
        chave TEXT NOT NULL,
        valor TEXT NOT NULL,
        criado_em TEXT NOT NULL,
        atualizado_em TEXT NOT NULL,
        FOREIGN KEY (produto_id) REFERENCES ${TableNames.produtos}(id) ON DELETE CASCADE,
        UNIQUE (produto_id, chave)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${TableNames.gruposModificadores} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        uuid TEXT NOT NULL UNIQUE,
        produto_base_id INTEGER NOT NULL,
        nome TEXT NOT NULL,
        obrigatorio INTEGER NOT NULL DEFAULT 0,
        min_selecoes INTEGER NOT NULL DEFAULT 0,
        max_selecoes INTEGER,
        ativo INTEGER NOT NULL DEFAULT 1,
        criado_em TEXT NOT NULL,
        atualizado_em TEXT NOT NULL,
        FOREIGN KEY (produto_base_id) REFERENCES ${TableNames.produtosBase}(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${TableNames.opcoesModificadores} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        uuid TEXT NOT NULL UNIQUE,
        grupo_modificador_id INTEGER NOT NULL,
        nome TEXT NOT NULL,
        tipo_ajuste TEXT NOT NULL CHECK (tipo_ajuste IN ('add', 'remove')),
        preco_delta_centavos INTEGER NOT NULL DEFAULT 0,
        linked_produto_id INTEGER,
        ativo INTEGER NOT NULL DEFAULT 1,
        ordem INTEGER NOT NULL DEFAULT 0,
        criado_em TEXT NOT NULL,
        atualizado_em TEXT NOT NULL,
        FOREIGN KEY (grupo_modificador_id) REFERENCES ${TableNames.gruposModificadores}(id) ON DELETE CASCADE,
        FOREIGN KEY (linked_produto_id) REFERENCES ${TableNames.produtos}(id) ON DELETE SET NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${TableNames.pedidosOperacionais} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        uuid TEXT NOT NULL UNIQUE,
        status TEXT NOT NULL CHECK (
          status IN ('draft', 'open', 'in_preparation', 'ready', 'delivered', 'canceled')
        ),
        observacao TEXT,
        criado_em TEXT NOT NULL,
        atualizado_em TEXT NOT NULL,
        fechado_em TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${TableNames.pedidosOperacionaisItens} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        uuid TEXT NOT NULL UNIQUE,
        pedido_operacional_id INTEGER NOT NULL,
        produto_id INTEGER NOT NULL,
        nome_produto_snapshot TEXT NOT NULL,
        quantidade_mil INTEGER NOT NULL,
        valor_unitario_centavos INTEGER NOT NULL DEFAULT 0,
        subtotal_centavos INTEGER NOT NULL DEFAULT 0,
        observacao TEXT,
        criado_em TEXT NOT NULL,
        atualizado_em TEXT NOT NULL,
        FOREIGN KEY (pedido_operacional_id) REFERENCES ${TableNames.pedidosOperacionais}(id) ON DELETE CASCADE,
        FOREIGN KEY (produto_id) REFERENCES ${TableNames.produtos}(id) ON DELETE RESTRICT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${TableNames.pedidosOperacionaisItemModificadores} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        uuid TEXT NOT NULL UNIQUE,
        pedido_operacional_item_id INTEGER NOT NULL,
        grupo_modificador_id INTEGER,
        opcao_modificador_id INTEGER,
        nome_grupo_snapshot TEXT,
        nome_opcao_snapshot TEXT NOT NULL,
        tipo_ajuste_snapshot TEXT NOT NULL CHECK (tipo_ajuste_snapshot IN ('add', 'remove')),
        preco_delta_centavos INTEGER NOT NULL DEFAULT 0,
        quantidade INTEGER NOT NULL DEFAULT 1,
        criado_em TEXT NOT NULL,
        atualizado_em TEXT NOT NULL,
        FOREIGN KEY (pedido_operacional_item_id) REFERENCES ${TableNames.pedidosOperacionaisItens}(id) ON DELETE CASCADE,
        FOREIGN KEY (grupo_modificador_id) REFERENCES ${TableNames.gruposModificadores}(id) ON DELETE SET NULL,
        FOREIGN KEY (opcao_modificador_id) REFERENCES ${TableNames.opcoesModificadores}(id) ON DELETE SET NULL
      )
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_produtos_base_nome
      ON ${TableNames.produtosBase}(nome)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_produtos_base_variantes_base
      ON ${TableNames.produtosBaseVariantes}(produto_base_id)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_produto_variante_atributos_produto
      ON ${TableNames.produtoVarianteAtributos}(produto_id)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_grupos_modificadores_base
      ON ${TableNames.gruposModificadores}(produto_base_id)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_opcoes_modificadores_grupo
      ON ${TableNames.opcoesModificadores}(grupo_modificador_id)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_pedidos_operacionais_status
      ON ${TableNames.pedidosOperacionais}(status, atualizado_em DESC)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_pedidos_operacionais_itens_pedido
      ON ${TableNames.pedidosOperacionaisItens}(pedido_operacional_id)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_pedidos_item_modificadores_item
      ON ${TableNames.pedidosOperacionaisItemModificadores}(pedido_operacional_item_id)
    ''');

    await db.execute('''
      INSERT OR IGNORE INTO ${TableNames.produtosBase} (
        uuid,
        nome,
        descricao,
        categoria_id,
        ativo,
        criado_em,
        atualizado_em
      )
      SELECT
        'base:' || p.uuid,
        COALESCE(NULLIF(TRIM(p.model_name), ''), p.nome),
        p.descricao,
        p.categoria_id,
        COALESCE(p.ativo, 1),
        COALESCE(p.criado_em, '$nowIso'),
        COALESCE(p.atualizado_em, '$nowIso')
      FROM ${TableNames.produtos} p
    ''');

    await db.execute('''
      INSERT OR IGNORE INTO ${TableNames.produtosBaseVariantes} (
        uuid,
        produto_base_id,
        produto_id,
        criado_em,
        atualizado_em
      )
      SELECT
        'link:' || p.uuid,
        b.id,
        p.id,
        COALESCE(p.criado_em, '$nowIso'),
        COALESCE(p.atualizado_em, '$nowIso')
      FROM ${TableNames.produtos} p
      INNER JOIN ${TableNames.produtosBase} b
        ON b.uuid = 'base:' || p.uuid
    ''');

    await db.execute('''
      INSERT INTO ${TableNames.produtoVarianteAtributos} (
        uuid,
        produto_id,
        chave,
        valor,
        criado_em,
        atualizado_em
      )
      SELECT
        'attr:legacy_variant_label:' || p.uuid,
        p.id,
        'legacy_variant_label',
        TRIM(p.variant_label),
        COALESCE(p.criado_em, '$nowIso'),
        COALESCE(p.atualizado_em, '$nowIso')
      FROM ${TableNames.produtos} p
      WHERE TRIM(COALESCE(p.variant_label, '')) <> ''
      ON CONFLICT(produto_id, chave) DO UPDATE SET
        valor = excluded.valor,
        atualizado_em = excluded.atualizado_em
    ''');

    await db.execute('''
      DELETE FROM ${TableNames.produtoVarianteAtributos}
      WHERE chave = 'legacy_variant_label'
        AND produto_id IN (
          SELECT id
          FROM ${TableNames.produtos}
          WHERE TRIM(COALESCE(variant_label, '')) = ''
        )
    ''');

    await db.execute(
      'DROP TRIGGER IF EXISTS trg_produtos_local_catalog_after_insert',
    );
    await db.execute('''
      CREATE TRIGGER trg_produtos_local_catalog_after_insert
      AFTER INSERT ON ${TableNames.produtos}
      BEGIN
        INSERT OR IGNORE INTO ${TableNames.produtosBase} (
          uuid,
          nome,
          descricao,
          categoria_id,
          ativo,
          criado_em,
          atualizado_em
        ) VALUES (
          'base:' || NEW.uuid,
          COALESCE(NULLIF(TRIM(NEW.model_name), ''), NEW.nome),
          NEW.descricao,
          NEW.categoria_id,
          COALESCE(NEW.ativo, 1),
          COALESCE(NEW.criado_em, NEW.atualizado_em, '$nowIso'),
          COALESCE(NEW.atualizado_em, NEW.criado_em, '$nowIso')
        );

        INSERT OR IGNORE INTO ${TableNames.produtosBaseVariantes} (
          uuid,
          produto_base_id,
          produto_id,
          criado_em,
          atualizado_em
        )
        SELECT
          'link:' || NEW.uuid,
          b.id,
          NEW.id,
          COALESCE(NEW.criado_em, NEW.atualizado_em, '$nowIso'),
          COALESCE(NEW.atualizado_em, NEW.criado_em, '$nowIso')
        FROM ${TableNames.produtosBase} b
        WHERE b.uuid = 'base:' || NEW.uuid;

        INSERT INTO ${TableNames.produtoVarianteAtributos} (
          uuid,
          produto_id,
          chave,
          valor,
          criado_em,
          atualizado_em
        )
        SELECT
          'attr:legacy_variant_label:' || NEW.uuid,
          NEW.id,
          'legacy_variant_label',
          TRIM(NEW.variant_label),
          COALESCE(NEW.criado_em, NEW.atualizado_em, '$nowIso'),
          COALESCE(NEW.atualizado_em, NEW.criado_em, '$nowIso')
        WHERE TRIM(COALESCE(NEW.variant_label, '')) <> ''
        ON CONFLICT(produto_id, chave) DO UPDATE SET
          valor = excluded.valor,
          atualizado_em = excluded.atualizado_em;

        DELETE FROM ${TableNames.produtoVarianteAtributos}
        WHERE produto_id = NEW.id
          AND chave = 'legacy_variant_label'
          AND TRIM(COALESCE(NEW.variant_label, '')) = '';
      END
    ''');

    await db.execute(
      'DROP TRIGGER IF EXISTS trg_produtos_local_catalog_after_update',
    );
    await db.execute('''
      CREATE TRIGGER trg_produtos_local_catalog_after_update
      AFTER UPDATE ON ${TableNames.produtos}
      BEGIN
        INSERT OR IGNORE INTO ${TableNames.produtosBase} (
          uuid,
          nome,
          descricao,
          categoria_id,
          ativo,
          criado_em,
          atualizado_em
        ) VALUES (
          'base:' || NEW.uuid,
          COALESCE(NULLIF(TRIM(NEW.model_name), ''), NEW.nome),
          NEW.descricao,
          NEW.categoria_id,
          COALESCE(NEW.ativo, 1),
          COALESCE(NEW.criado_em, NEW.atualizado_em, '$nowIso'),
          COALESCE(NEW.atualizado_em, NEW.criado_em, '$nowIso')
        );

        INSERT OR IGNORE INTO ${TableNames.produtosBaseVariantes} (
          uuid,
          produto_base_id,
          produto_id,
          criado_em,
          atualizado_em
        )
        SELECT
          'link:' || NEW.uuid,
          b.id,
          NEW.id,
          COALESCE(NEW.criado_em, NEW.atualizado_em, '$nowIso'),
          COALESCE(NEW.atualizado_em, NEW.criado_em, '$nowIso')
        FROM ${TableNames.produtosBase} b
        WHERE b.uuid = 'base:' || NEW.uuid;

        UPDATE ${TableNames.produtosBase}
        SET
          nome = COALESCE(NULLIF(TRIM(NEW.model_name), ''), NEW.nome),
          descricao = NEW.descricao,
          categoria_id = NEW.categoria_id,
          ativo = COALESCE(NEW.ativo, 1),
          atualizado_em = COALESCE(NEW.atualizado_em, '$nowIso')
        WHERE uuid = 'base:' || NEW.uuid;

        INSERT INTO ${TableNames.produtoVarianteAtributos} (
          uuid,
          produto_id,
          chave,
          valor,
          criado_em,
          atualizado_em
        )
        SELECT
          'attr:legacy_variant_label:' || NEW.uuid,
          NEW.id,
          'legacy_variant_label',
          TRIM(NEW.variant_label),
          COALESCE(NEW.criado_em, NEW.atualizado_em, '$nowIso'),
          COALESCE(NEW.atualizado_em, NEW.criado_em, '$nowIso')
        WHERE TRIM(COALESCE(NEW.variant_label, '')) <> ''
        ON CONFLICT(produto_id, chave) DO UPDATE SET
          valor = excluded.valor,
          atualizado_em = excluded.atualizado_em;

        DELETE FROM ${TableNames.produtoVarianteAtributos}
        WHERE produto_id = NEW.id
          AND chave = 'legacy_variant_label'
          AND TRIM(COALESCE(NEW.variant_label, '')) = '';
      END
    ''');
  }

  static Future<void> _createVersion15Schema(DatabaseExecutor db) async {
    await _ensureColumnExists(
      db,
      tableName: TableNames.itensVenda,
      columnName: 'observacao_item_snapshot',
      columnDefinition: 'TEXT',
    );

    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${TableNames.itensVendaModificadores} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        uuid TEXT NOT NULL UNIQUE,
        item_venda_id INTEGER NOT NULL,
        grupo_modificador_id INTEGER,
        opcao_modificador_id INTEGER,
        nome_grupo_snapshot TEXT,
        nome_opcao_snapshot TEXT NOT NULL,
        tipo_ajuste_snapshot TEXT NOT NULL CHECK (tipo_ajuste_snapshot IN ('add', 'remove')),
        preco_delta_centavos INTEGER NOT NULL DEFAULT 0,
        quantidade INTEGER NOT NULL DEFAULT 1,
        criado_em TEXT NOT NULL,
        atualizado_em TEXT NOT NULL,
        FOREIGN KEY (item_venda_id) REFERENCES ${TableNames.itensVenda}(id) ON DELETE CASCADE,
        FOREIGN KEY (grupo_modificador_id) REFERENCES ${TableNames.gruposModificadores}(id) ON DELETE SET NULL,
        FOREIGN KEY (opcao_modificador_id) REFERENCES ${TableNames.opcoesModificadores}(id) ON DELETE SET NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${TableNames.vendasPedidosOperacionais} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        uuid TEXT NOT NULL UNIQUE,
        venda_id INTEGER NOT NULL UNIQUE,
        pedido_operacional_id INTEGER NOT NULL UNIQUE,
        criado_em TEXT NOT NULL,
        atualizado_em TEXT NOT NULL,
        FOREIGN KEY (venda_id) REFERENCES ${TableNames.vendas}(id) ON DELETE CASCADE,
        FOREIGN KEY (pedido_operacional_id) REFERENCES ${TableNames.pedidosOperacionais}(id) ON DELETE RESTRICT
      )
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_itens_venda_modificadores_item
      ON ${TableNames.itensVendaModificadores}(item_venda_id)
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_vendas_pedidos_operacionais_venda
      ON ${TableNames.vendasPedidosOperacionais}(venda_id)
    ''');
  }

  static Future<void> _createVersion16Schema(DatabaseExecutor db) async {
    await _ensureColumnExists(
      db,
      tableName: TableNames.produtos,
      columnName: 'nicho',
      columnDefinition:
          "TEXT NOT NULL DEFAULT 'alimentacao' CHECK (nicho IN ('alimentacao', 'moda'))",
    );

    await db.execute('''
      UPDATE ${TableNames.produtos}
      SET nicho = 'alimentacao'
      WHERE nicho IS NULL
         OR TRIM(nicho) = ''
         OR nicho NOT IN ('alimentacao', 'moda')
    ''');
  }

  static Future<void> _createVersion17Schema(DatabaseExecutor db) async {
    final nowIso = DateTime.now().toIso8601String();

    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${TableNames.produtoFotos} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        uuid TEXT NOT NULL UNIQUE,
        produto_id INTEGER NOT NULL,
        caminho_local TEXT NOT NULL,
        e_principal INTEGER NOT NULL DEFAULT 0,
        ordem INTEGER NOT NULL DEFAULT 0,
        criado_em TEXT NOT NULL,
        atualizado_em TEXT NOT NULL,
        FOREIGN KEY (produto_id) REFERENCES ${TableNames.produtos}(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_produto_fotos_produto
      ON ${TableNames.produtoFotos}(produto_id, ordem ASC, id ASC)
    ''');

    await db.execute('''
      INSERT OR IGNORE INTO ${TableNames.produtoFotos} (
        uuid,
        produto_id,
        caminho_local,
        e_principal,
        ordem,
        criado_em,
        atualizado_em
      )
      SELECT
        'foto_principal:' || p.uuid,
        p.id,
        p.foto_path,
        1,
        0,
        COALESCE(p.criado_em, '$nowIso'),
        COALESCE(p.atualizado_em, '$nowIso')
      FROM ${TableNames.produtos} p
      WHERE TRIM(COALESCE(p.foto_path, '')) <> ''
    ''');
  }

  static Future<void> _createVersion18Schema(DatabaseExecutor db) async {
    await _ensureColumnExists(
      db,
      tableName: TableNames.caixaSessoes,
      columnName: 'aguardando_confirmacao_troco_inicial',
      columnDefinition: 'INTEGER NOT NULL DEFAULT 0',
    );
    await _ensureColumnExists(
      db,
      tableName: TableNames.caixaSessoes,
      columnName: 'total_entradas_dinheiro_centavos',
      columnDefinition: 'INTEGER NOT NULL DEFAULT 0',
    );
    await _ensureColumnExists(
      db,
      tableName: TableNames.caixaSessoes,
      columnName: 'total_recebimentos_fiado_dinheiro_centavos',
      columnDefinition: 'INTEGER NOT NULL DEFAULT 0',
    );
    await _ensureColumnExists(
      db,
      tableName: TableNames.caixaSessoes,
      columnName: 'total_recebimentos_fiado_pix_centavos',
      columnDefinition: 'INTEGER NOT NULL DEFAULT 0',
    );
    await _ensureColumnExists(
      db,
      tableName: TableNames.caixaSessoes,
      columnName: 'total_recebimentos_fiado_cartao_centavos',
      columnDefinition: 'INTEGER NOT NULL DEFAULT 0',
    );
    await _ensureColumnExists(
      db,
      tableName: TableNames.caixaSessoes,
      columnName: 'saldo_esperado_centavos',
      columnDefinition: 'INTEGER NOT NULL DEFAULT 0',
    );
    await _ensureColumnExists(
      db,
      tableName: TableNames.caixaSessoes,
      columnName: 'saldo_contado_centavos',
      columnDefinition: 'INTEGER',
    );
    await _ensureColumnExists(
      db,
      tableName: TableNames.caixaSessoes,
      columnName: 'diferenca_centavos',
      columnDefinition: 'INTEGER',
    );

    await db.execute('''
      UPDATE ${TableNames.caixaSessoes}
      SET aguardando_confirmacao_troco_inicial = CASE
        WHEN status = 'aberto' AND troco_inicial_centavos = 0 THEN 1
        ELSE COALESCE(aguardando_confirmacao_troco_inicial, 0)
      END
    ''');

    await db.execute('''
      UPDATE ${TableNames.caixaSessoes}
      SET total_entradas_dinheiro_centavos = COALESCE((
        SELECT SUM(
          CASE
            WHEN mov.tipo_movimento = 'venda'
             AND mov.valor_centavos > 0
             AND substr(COALESCE(mov.descricao, ''), 1, 13) = '[pm:dinheiro]'
            THEN mov.valor_centavos
            WHEN mov.tipo_movimento = 'cancelamento'
             AND mov.referencia_tipo = 'venda'
             AND mov.valor_centavos < 0
             AND substr(COALESCE(mov.descricao, ''), 1, 13) = '[pm:dinheiro]'
            THEN mov.valor_centavos
            ELSE 0
          END
        )
        FROM ${TableNames.caixaMovimentos} mov
        WHERE mov.sessao_id = ${TableNames.caixaSessoes}.id
      ), 0),
      total_recebimentos_fiado_dinheiro_centavos = COALESCE((
        SELECT SUM(
          CASE
            WHEN mov.tipo_movimento = 'recebimento_fiado'
             AND mov.valor_centavos > 0
             AND substr(COALESCE(mov.descricao, ''), 1, 13) = '[pm:dinheiro]'
            THEN mov.valor_centavos
            WHEN mov.tipo_movimento = 'cancelamento'
             AND mov.referencia_tipo = 'fiado'
             AND mov.valor_centavos < 0
             AND substr(COALESCE(mov.descricao, ''), 1, 13) = '[pm:dinheiro]'
            THEN mov.valor_centavos
            ELSE 0
          END
        )
        FROM ${TableNames.caixaMovimentos} mov
        WHERE mov.sessao_id = ${TableNames.caixaSessoes}.id
      ), 0),
      total_recebimentos_fiado_pix_centavos = COALESCE((
        SELECT SUM(
          CASE
            WHEN mov.tipo_movimento = 'recebimento_fiado'
             AND mov.valor_centavos > 0
             AND substr(COALESCE(mov.descricao, ''), 1, 8) = '[pm:pix]'
            THEN mov.valor_centavos
            WHEN mov.tipo_movimento = 'cancelamento'
             AND mov.referencia_tipo = 'fiado'
             AND mov.valor_centavos < 0
             AND substr(COALESCE(mov.descricao, ''), 1, 8) = '[pm:pix]'
            THEN mov.valor_centavos
            ELSE 0
          END
        )
        FROM ${TableNames.caixaMovimentos} mov
        WHERE mov.sessao_id = ${TableNames.caixaSessoes}.id
      ), 0),
      total_recebimentos_fiado_cartao_centavos = COALESCE((
        SELECT SUM(
          CASE
            WHEN mov.tipo_movimento = 'recebimento_fiado'
             AND mov.valor_centavos > 0
             AND substr(COALESCE(mov.descricao, ''), 1, 11) = '[pm:cartao]'
            THEN mov.valor_centavos
            WHEN mov.tipo_movimento = 'cancelamento'
             AND mov.referencia_tipo = 'fiado'
             AND mov.valor_centavos < 0
             AND substr(COALESCE(mov.descricao, ''), 1, 11) = '[pm:cartao]'
            THEN mov.valor_centavos
            ELSE 0
          END
        )
        FROM ${TableNames.caixaMovimentos} mov
        WHERE mov.sessao_id = ${TableNames.caixaSessoes}.id
      ), 0)
    ''');

    await db.execute('''
      UPDATE ${TableNames.caixaSessoes}
      SET saldo_esperado_centavos =
            troco_inicial_centavos
          + total_entradas_dinheiro_centavos
          + total_recebimentos_fiado_dinheiro_centavos
          + total_suprimentos_centavos
          - total_sangrias_centavos,
          saldo_final_centavos =
            troco_inicial_centavos
          + total_entradas_dinheiro_centavos
          + total_recebimentos_fiado_dinheiro_centavos
          + total_suprimentos_centavos
          - total_sangrias_centavos,
          diferenca_centavos = CASE
            WHEN saldo_contado_centavos IS NULL THEN NULL
            ELSE saldo_contado_centavos - (
              troco_inicial_centavos
              + total_entradas_dinheiro_centavos
              + total_recebimentos_fiado_dinheiro_centavos
              + total_suprimentos_centavos
              - total_sangrias_centavos
            )
          END
    ''');
  }

  static Future<void> _createVersion19Schema(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${TableNames.produtoVariantes} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        uuid TEXT NOT NULL UNIQUE,
        produto_id INTEGER NOT NULL,
        sku TEXT NOT NULL,
        cor TEXT NOT NULL,
        tamanho TEXT NOT NULL,
        preco_adicional_centavos INTEGER NOT NULL DEFAULT 0,
        estoque_mil INTEGER NOT NULL DEFAULT 0,
        ordem INTEGER NOT NULL DEFAULT 0,
        ativo INTEGER NOT NULL DEFAULT 1,
        criado_em TEXT NOT NULL,
        atualizado_em TEXT NOT NULL,
        FOREIGN KEY (produto_id) REFERENCES ${TableNames.produtos}(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_produto_variantes_produto
      ON ${TableNames.produtoVariantes}(produto_id, ordem ASC, id ASC)
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_produto_variantes_sku
      ON ${TableNames.produtoVariantes}(sku)
    ''');

    await _ensureColumnExists(
      db,
      tableName: TableNames.itensVenda,
      columnName: 'produto_variante_id',
      columnDefinition: 'INTEGER',
    );
    await _ensureColumnExists(
      db,
      tableName: TableNames.itensVenda,
      columnName: 'sku_variante_snapshot',
      columnDefinition: 'TEXT',
    );
    await _ensureColumnExists(
      db,
      tableName: TableNames.itensVenda,
      columnName: 'cor_variante_snapshot',
      columnDefinition: 'TEXT',
    );
    await _ensureColumnExists(
      db,
      tableName: TableNames.itensVenda,
      columnName: 'tamanho_variante_snapshot',
      columnDefinition: 'TEXT',
    );
  }

  static Future<void> _createVersion20Schema(DatabaseExecutor db) async {
    const legacyFashionGradeTableName = 'produto_moda_grade';
    final legacyTableExists = await _tableExists(
      db,
      legacyFashionGradeTableName,
    );
    if (legacyTableExists) {
      final nowIso = DateTime.now().toIso8601String();
      await db.execute('''
        INSERT OR IGNORE INTO ${TableNames.produtoVariantes} (
          uuid,
          produto_id,
          sku,
          cor,
          tamanho,
          preco_adicional_centavos,
          estoque_mil,
          ordem,
          ativo,
          criado_em,
          atualizado_em
        )
        SELECT
          'variant:' || grade.uuid,
          grade.produto_id,
          UPPER(
            REPLACE(
              REPLACE(
                COALESCE(NULLIF(p.model_name, ''), NULLIF(p.nome, ''), 'produto'),
                ' ',
                '-'
              ),
              '/',
              '-'
            )
          ) || '-' || UPPER(REPLACE(grade.tamanho, ' ', '-')) || '-' || UPPER(REPLACE(grade.cor, ' ', '-')),
          grade.cor,
          grade.tamanho,
          0,
          COALESCE(grade.estoque_mil, 0),
          COALESCE(grade.ordem, 0),
          1,
          COALESCE(grade.criado_em, '$nowIso'),
          COALESCE(grade.atualizado_em, '$nowIso')
        FROM $legacyFashionGradeTableName grade
        INNER JOIN ${TableNames.produtos} p
          ON p.id = grade.produto_id
      ''');
    }

    await db.execute('DROP TABLE IF EXISTS produto_moda_grade');
  }

  static Future<void> _createVersion21Schema(DatabaseExecutor db) async {
    await _ensureColumnExists(
      db,
      tableName: TableNames.clientes,
      columnName: 'credit_balance',
      columnDefinition: 'INTEGER NOT NULL DEFAULT 0',
    );

    await _ensureColumnExists(
      db,
      tableName: TableNames.vendas,
      columnName: 'haver_utilizado_centavos',
      columnDefinition: 'INTEGER NOT NULL DEFAULT 0',
    );
    await _ensureColumnExists(
      db,
      tableName: TableNames.vendas,
      columnName: 'haver_gerado_centavos',
      columnDefinition: 'INTEGER NOT NULL DEFAULT 0',
    );
    await _ensureColumnExists(
      db,
      tableName: TableNames.vendas,
      columnName: 'valor_recebido_imediato_centavos',
      columnDefinition: 'INTEGER NOT NULL DEFAULT 0',
    );

    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${TableNames.customerCreditTransactions} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        customer_id INTEGER NOT NULL,
        type TEXT NOT NULL,
        amount INTEGER NOT NULL,
        description TEXT,
        sale_id INTEGER,
        fiado_id INTEGER,
        cash_session_id INTEGER,
        origin_payment_id INTEGER,
        reversed_transaction_id INTEGER,
        is_reversed INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT,
        FOREIGN KEY (customer_id) REFERENCES ${TableNames.clientes}(id) ON DELETE CASCADE,
        FOREIGN KEY (sale_id) REFERENCES ${TableNames.vendas}(id) ON DELETE SET NULL,
        FOREIGN KEY (fiado_id) REFERENCES ${TableNames.fiado}(id) ON DELETE SET NULL,
        FOREIGN KEY (cash_session_id) REFERENCES ${TableNames.caixaSessoes}(id) ON DELETE SET NULL,
        FOREIGN KEY (origin_payment_id) REFERENCES ${TableNames.fiadoLancamentos}(id) ON DELETE SET NULL,
        FOREIGN KEY (reversed_transaction_id) REFERENCES ${TableNames.customerCreditTransactions}(id) ON DELETE SET NULL
      )
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_customer_credit_transactions_customer
      ON ${TableNames.customerCreditTransactions}(customer_id, created_at DESC, id DESC)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_customer_credit_transactions_sale
      ON ${TableNames.customerCreditTransactions}(sale_id)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_customer_credit_transactions_fiado
      ON ${TableNames.customerCreditTransactions}(fiado_id)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_customer_credit_transactions_cash_session
      ON ${TableNames.customerCreditTransactions}(cash_session_id)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_customer_credit_transactions_type
      ON ${TableNames.customerCreditTransactions}(type)
    ''');

    await db.execute('''
      UPDATE ${TableNames.vendas}
      SET valor_recebido_imediato_centavos = CASE
        WHEN tipo_venda = 'fiado' THEN 0
        ELSE COALESCE(valor_final_centavos, 0)
      END
      WHERE COALESCE(valor_recebido_imediato_centavos, 0) = 0
    ''');
  }

  static Future<void> _createVersion22Schema(DatabaseExecutor db) async {
    await _ensureColumnExists(
      db,
      tableName: TableNames.produtoVariantes,
      columnName: 'foto_path',
      columnDefinition: 'TEXT',
    );
  }

  static Future<void> _createVersion23Schema(DatabaseExecutor db) async {
    await _ensureColumnExists(
      db,
      tableName: TableNames.pedidosOperacionais,
      columnName: 'atendimento_tipo',
      columnDefinition: "TEXT NOT NULL DEFAULT 'counter'",
    );
    await _ensureColumnExists(
      db,
      tableName: TableNames.pedidosOperacionais,
      columnName: 'cliente_identificador',
      columnDefinition: 'TEXT',
    );
    await _ensureColumnExists(
      db,
      tableName: TableNames.pedidosOperacionais,
      columnName: 'telefone_cliente',
      columnDefinition: 'TEXT',
    );
    await _ensureColumnExists(
      db,
      tableName: TableNames.pedidosOperacionais,
      columnName: 'ticket_status',
      columnDefinition: "TEXT NOT NULL DEFAULT 'pending'",
    );
    await _ensureColumnExists(
      db,
      tableName: TableNames.pedidosOperacionais,
      columnName: 'ticket_tentativas',
      columnDefinition: 'INTEGER NOT NULL DEFAULT 0',
    );
    await _ensureColumnExists(
      db,
      tableName: TableNames.pedidosOperacionais,
      columnName: 'ticket_ultimo_erro',
      columnDefinition: 'TEXT',
    );
    await _ensureColumnExists(
      db,
      tableName: TableNames.pedidosOperacionais,
      columnName: 'ticket_ultima_tentativa_em',
      columnDefinition: 'TEXT',
    );
    await _ensureColumnExists(
      db,
      tableName: TableNames.pedidosOperacionais,
      columnName: 'ticket_enviado_em',
      columnDefinition: 'TEXT',
    );
    await _ensureColumnExists(
      db,
      tableName: TableNames.pedidosOperacionais,
      columnName: 'enviado_cozinha_em',
      columnDefinition: 'TEXT',
    );
    await _ensureColumnExists(
      db,
      tableName: TableNames.pedidosOperacionais,
      columnName: 'em_preparo_em',
      columnDefinition: 'TEXT',
    );
    await _ensureColumnExists(
      db,
      tableName: TableNames.pedidosOperacionais,
      columnName: 'pronto_em',
      columnDefinition: 'TEXT',
    );
    await _ensureColumnExists(
      db,
      tableName: TableNames.pedidosOperacionais,
      columnName: 'entregue_em',
      columnDefinition: 'TEXT',
    );
    await _ensureColumnExists(
      db,
      tableName: TableNames.pedidosOperacionais,
      columnName: 'cancelado_em',
      columnDefinition: 'TEXT',
    );

    await db.execute('''
      UPDATE ${TableNames.pedidosOperacionais}
      SET atendimento_tipo = COALESCE(NULLIF(TRIM(atendimento_tipo), ''), 'counter')
    ''');

    await db.execute('''
      UPDATE ${TableNames.pedidosOperacionais}
      SET enviado_cozinha_em = CASE
            WHEN enviado_cozinha_em IS NOT NULL THEN enviado_cozinha_em
            WHEN status IN ('open', 'in_preparation', 'ready', 'delivered')
              THEN atualizado_em
            ELSE enviado_cozinha_em
          END,
          em_preparo_em = CASE
            WHEN em_preparo_em IS NOT NULL THEN em_preparo_em
            WHEN status IN ('in_preparation', 'ready', 'delivered')
              THEN atualizado_em
            ELSE em_preparo_em
          END,
          pronto_em = CASE
            WHEN pronto_em IS NOT NULL THEN pronto_em
            WHEN status IN ('ready', 'delivered') THEN atualizado_em
            ELSE pronto_em
          END,
          entregue_em = CASE
            WHEN entregue_em IS NOT NULL THEN entregue_em
            WHEN status = 'delivered' THEN COALESCE(fechado_em, atualizado_em)
            ELSE entregue_em
          END,
          cancelado_em = CASE
            WHEN cancelado_em IS NOT NULL THEN cancelado_em
            WHEN status = 'canceled' THEN COALESCE(fechado_em, atualizado_em)
            ELSE cancelado_em
          END
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_pedidos_operacionais_atendimento_status
      ON ${TableNames.pedidosOperacionais}(atendimento_tipo, status, atualizado_em DESC)
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_pedidos_operacionais_cliente_identificador
      ON ${TableNames.pedidosOperacionais}(cliente_identificador)
    ''');
  }

  static Future<void> _createVersion24Schema(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${TableNames.supplies} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        uuid TEXT NOT NULL UNIQUE,
        name TEXT NOT NULL,
        sku TEXT,
        unit_type TEXT NOT NULL,
        purchase_unit_type TEXT NOT NULL,
        conversion_factor INTEGER NOT NULL,
        last_purchase_price_cents INTEGER NOT NULL DEFAULT 0,
        average_purchase_price_cents INTEGER,
        current_stock_mil INTEGER,
        minimum_stock_mil INTEGER,
        default_supplier_id INTEGER,
        is_active INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (default_supplier_id) REFERENCES ${TableNames.fornecedores}(id) ON DELETE SET NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${TableNames.productRecipeItems} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        uuid TEXT NOT NULL UNIQUE,
        product_id INTEGER NOT NULL,
        supply_id INTEGER NOT NULL,
        quantity_used_mil INTEGER NOT NULL,
        unit_type TEXT NOT NULL,
        waste_basis_points INTEGER NOT NULL DEFAULT 0,
        notes TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (product_id) REFERENCES ${TableNames.produtos}(id) ON DELETE CASCADE,
        FOREIGN KEY (supply_id) REFERENCES ${TableNames.supplies}(id) ON DELETE RESTRICT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${TableNames.productCostSnapshot} (
        product_id INTEGER PRIMARY KEY,
        variable_cost_snapshot_cents INTEGER NOT NULL DEFAULT 0,
        estimated_gross_margin_cents INTEGER NOT NULL DEFAULT 0,
        estimated_gross_margin_percent_basis_points INTEGER NOT NULL DEFAULT 0,
        last_cost_updated_at TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (product_id) REFERENCES ${TableNames.produtos}(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_supplies_name_active
      ON ${TableNames.supplies}(name COLLATE NOCASE, is_active)
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_product_recipe_items_product
      ON ${TableNames.productRecipeItems}(product_id)
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_product_recipe_items_supply
      ON ${TableNames.productRecipeItems}(supply_id)
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_product_cost_snapshot_product
      ON ${TableNames.productCostSnapshot}(product_id)
    ''');
  }

  static Future<void> _createVersion25Schema(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${TableNames.supplyCostHistory} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        uuid TEXT NOT NULL UNIQUE,
        supply_id INTEGER NOT NULL,
        purchase_id INTEGER,
        purchase_item_id INTEGER,
        source TEXT NOT NULL CHECK (source IN ('manual', 'purchase')),
        purchase_unit_type TEXT NOT NULL,
        conversion_factor INTEGER NOT NULL,
        last_purchase_price_cents INTEGER NOT NULL,
        average_purchase_price_cents INTEGER,
        notes TEXT,
        occurred_at TEXT NOT NULL,
        created_at TEXT NOT NULL,
        FOREIGN KEY (supply_id) REFERENCES ${TableNames.supplies}(id) ON DELETE CASCADE,
        FOREIGN KEY (purchase_id) REFERENCES ${TableNames.compras}(id) ON DELETE SET NULL,
        FOREIGN KEY (purchase_item_id) REFERENCES ${TableNames.itensCompra}(id) ON DELETE SET NULL
      )
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_supply_cost_history_supply
      ON ${TableNames.supplyCostHistory}(supply_id, occurred_at DESC, id DESC)
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_supply_cost_history_purchase
      ON ${TableNames.supplyCostHistory}(purchase_id, purchase_item_id)
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${TableNames.itensCompra}_v25 (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        uuid TEXT NOT NULL UNIQUE,
        compra_id INTEGER NOT NULL,
        item_type TEXT NOT NULL DEFAULT 'product' CHECK (item_type IN ('product', 'supply')),
        produto_id INTEGER,
        supply_id INTEGER,
        nome_item_snapshot TEXT NOT NULL,
        unidade_medida_snapshot TEXT NOT NULL,
        quantidade_mil INTEGER NOT NULL,
        custo_unitario_centavos INTEGER NOT NULL,
        subtotal_centavos INTEGER NOT NULL,
        FOREIGN KEY (compra_id) REFERENCES ${TableNames.compras}(id) ON DELETE CASCADE,
        FOREIGN KEY (produto_id) REFERENCES ${TableNames.produtos}(id) ON DELETE RESTRICT,
        FOREIGN KEY (supply_id) REFERENCES ${TableNames.supplies}(id) ON DELETE RESTRICT
      )
    ''');

    final existingRows = await db.query(
      TableNames.itensCompra,
      columns: const ['id'],
      limit: 1,
    );
    if (existingRows.isNotEmpty) {
      await db.execute('''
        INSERT INTO ${TableNames.itensCompra}_v25 (
          id,
          uuid,
          compra_id,
          item_type,
          produto_id,
          supply_id,
          nome_item_snapshot,
          unidade_medida_snapshot,
          quantidade_mil,
          custo_unitario_centavos,
          subtotal_centavos
        )
        SELECT
          id,
          uuid,
          compra_id,
          'product',
          produto_id,
          NULL,
          nome_produto_snapshot,
          unidade_medida_snapshot,
          quantidade_mil,
          custo_unitario_centavos,
          subtotal_centavos
        FROM ${TableNames.itensCompra}
      ''');
    }

    await db.execute('DROP TABLE IF EXISTS ${TableNames.itensCompra}');
    await db.execute(
      'ALTER TABLE ${TableNames.itensCompra}_v25 RENAME TO ${TableNames.itensCompra}',
    );

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_itens_compra_compra
      ON ${TableNames.itensCompra}(compra_id)
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_itens_compra_produto
      ON ${TableNames.itensCompra}(produto_id)
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_itens_compra_supply
      ON ${TableNames.itensCompra}(supply_id)
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_itens_compra_tipo
      ON ${TableNames.itensCompra}(item_type)
    ''');
  }

  static Future<void> _createVersion26Schema(DatabaseExecutor db) async {
    await db.execute('''
      ALTER TABLE ${TableNames.produtos}
      ADD COLUMN manual_cost_centavos INTEGER NOT NULL DEFAULT 0
    ''');

    await db.execute('''
      ALTER TABLE ${TableNames.produtos}
      ADD COLUMN cost_source TEXT NOT NULL DEFAULT 'manual'
    ''');

    await db.execute('''
      UPDATE ${TableNames.produtos}
      SET
        manual_cost_centavos = custo_centavos,
        cost_source = CASE
          WHEN EXISTS (
            SELECT 1
            FROM ${TableNames.productRecipeItems} pri
            WHERE pri.product_id = ${TableNames.produtos}.id
          )
          AND EXISTS (
            SELECT 1
            FROM ${TableNames.productCostSnapshot} pcs
            WHERE pcs.product_id = ${TableNames.produtos}.id
          )
            THEN 'recipe_snapshot'
          ELSE 'manual'
        END
    ''');

    await db.execute('''
      ALTER TABLE ${TableNames.supplyCostHistory}
      ADD COLUMN event_type TEXT NOT NULL DEFAULT 'manual_edit'
    ''');

    await db.execute('''
      ALTER TABLE ${TableNames.supplyCostHistory}
      ADD COLUMN change_summary TEXT
    ''');

    await db.execute('''
      UPDATE ${TableNames.supplyCostHistory}
      SET
        event_type = CASE
          WHEN source = 'purchase' THEN 'purchase_updated'
          ELSE 'manual_edit'
        END,
        change_summary = COALESCE(change_summary, notes)
    ''');
  }

  static Future<void> _createVersion27Schema(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${TableNames.supplyInventoryMovements} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        uuid TEXT NOT NULL UNIQUE,
        remote_id TEXT,
        supply_id INTEGER NOT NULL,
        movement_type TEXT NOT NULL CHECK (
          movement_type IN ('in', 'out', 'reversal', 'adjustment')
        ),
        source_type TEXT NOT NULL CHECK (
          source_type IN (
            'purchase',
            'purchase_cancel',
            'sale',
            'sale_cancel',
            'manual_adjustment',
            'migration_seed'
          )
        ),
        source_local_uuid TEXT,
        source_remote_id TEXT,
        dedupe_key TEXT NOT NULL UNIQUE,
        quantity_delta_mil INTEGER NOT NULL,
        unit_type TEXT NOT NULL,
        balance_after_mil INTEGER,
        notes TEXT,
        occurred_at TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (supply_id) REFERENCES ${TableNames.supplies}(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_supply_inventory_movements_supply
      ON ${TableNames.supplyInventoryMovements}(supply_id, occurred_at DESC, id DESC)
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_supply_inventory_movements_source
      ON ${TableNames.supplyInventoryMovements}(source_type, source_local_uuid, supply_id)
    ''');

    await db.execute('''
      INSERT OR IGNORE INTO ${TableNames.supplyInventoryMovements} (
        uuid,
        remote_id,
        supply_id,
        movement_type,
        source_type,
        source_local_uuid,
        source_remote_id,
        dedupe_key,
        quantity_delta_mil,
        unit_type,
        balance_after_mil,
        notes,
        occurred_at,
        created_at,
        updated_at
      )
      SELECT
        'inventory-seed:' || s.uuid,
        NULL,
        s.id,
        'adjustment',
        'migration_seed',
        s.uuid,
        NULL,
        'migration_seed:' || s.uuid,
        s.current_stock_mil,
        s.unit_type,
        s.current_stock_mil,
        'Baseline operacional criada a partir do current_stock_mil legado na migracao 27.',
        COALESCE(s.updated_at, s.created_at),
        COALESCE(s.updated_at, s.created_at),
        COALESCE(s.updated_at, s.created_at)
      FROM ${TableNames.supplies} s
      WHERE s.current_stock_mil IS NOT NULL
        AND s.current_stock_mil >= 0
        AND TRIM(COALESCE(s.uuid, '')) <> ''
        AND NOT EXISTS (
          SELECT 1
          FROM ${TableNames.supplyInventoryMovements} sim
          WHERE sim.supply_id = s.id
        )
    ''');
  }

  static Future<void> _createVersion28Schema(DatabaseExecutor db) async {
    await db.execute('''
      DELETE FROM ${TableNames.supplyInventoryMovements}
      WHERE source_type = 'migration_seed'
        AND id NOT IN (
          SELECT MIN(id)
          FROM ${TableNames.supplyInventoryMovements}
          WHERE source_type = 'migration_seed'
          GROUP BY supply_id
        )
    ''');

    await db.execute('''
      CREATE UNIQUE INDEX IF NOT EXISTS idx_supply_inventory_movements_single_seed
      ON ${TableNames.supplyInventoryMovements}(supply_id)
      WHERE source_type = 'migration_seed'
    ''');

    await db.execute('''
      UPDATE ${TableNames.supplies}
      SET current_stock_mil = (
        SELECT CASE
          WHEN COUNT(*) = 0 THEN NULL
          ELSE COALESCE(SUM(sim.quantity_delta_mil), 0)
        END
        FROM ${TableNames.supplyInventoryMovements} sim
        WHERE sim.supply_id = ${TableNames.supplies}.id
      )
      WHERE EXISTS (
        SELECT 1
        FROM ${TableNames.supplyInventoryMovements} sim
        WHERE sim.supply_id = ${TableNames.supplies}.id
      )
    ''');
  }

  static Future<void> _createVersion29Schema(DatabaseExecutor db) async {
    await _ensureColumnExists(
      db,
      tableName: TableNames.itensCompra,
      columnName: 'produto_variante_id',
      columnDefinition: 'INTEGER',
    );
    await _ensureColumnExists(
      db,
      tableName: TableNames.itensCompra,
      columnName: 'sku_variante_snapshot',
      columnDefinition: 'TEXT',
    );
    await _ensureColumnExists(
      db,
      tableName: TableNames.itensCompra,
      columnName: 'cor_variante_snapshot',
      columnDefinition: 'TEXT',
    );
    await _ensureColumnExists(
      db,
      tableName: TableNames.itensCompra,
      columnName: 'tamanho_variante_snapshot',
      columnDefinition: 'TEXT',
    );

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_itens_compra_produto_variante
      ON ${TableNames.itensCompra}(produto_variante_id)
    ''');
  }

  static Future<void> _createVersion30Schema(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${TableNames.saleReturns} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        uuid TEXT NOT NULL UNIQUE,
        sale_id INTEGER NOT NULL,
        client_id INTEGER,
        exchange_mode TEXT NOT NULL CHECK (
          exchange_mode IN ('return_only', 'exchange_with_new_sale')
        ),
        reason TEXT,
        refund_amount_cents INTEGER NOT NULL DEFAULT 0,
        credited_amount_cents INTEGER NOT NULL DEFAULT 0,
        applied_discount_cents INTEGER NOT NULL DEFAULT 0,
        replacement_sale_id INTEGER,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (sale_id) REFERENCES ${TableNames.vendas}(id) ON DELETE CASCADE,
        FOREIGN KEY (client_id) REFERENCES ${TableNames.clientes}(id) ON DELETE SET NULL,
        FOREIGN KEY (replacement_sale_id) REFERENCES ${TableNames.vendas}(id) ON DELETE SET NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${TableNames.saleReturnItems} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        uuid TEXT NOT NULL UNIQUE,
        sale_return_id INTEGER NOT NULL,
        sale_item_id INTEGER NOT NULL,
        product_id INTEGER NOT NULL,
        product_variant_id INTEGER,
        product_name_snapshot TEXT NOT NULL,
        variant_sku_snapshot TEXT,
        variant_color_snapshot TEXT,
        variant_size_snapshot TEXT,
        quantity_mil INTEGER NOT NULL,
        unit_price_cents INTEGER NOT NULL,
        subtotal_cents INTEGER NOT NULL,
        reason TEXT,
        created_at TEXT NOT NULL,
        FOREIGN KEY (sale_return_id) REFERENCES ${TableNames.saleReturns}(id) ON DELETE CASCADE,
        FOREIGN KEY (sale_item_id) REFERENCES ${TableNames.itensVenda}(id) ON DELETE RESTRICT,
        FOREIGN KEY (product_id) REFERENCES ${TableNames.produtos}(id) ON DELETE RESTRICT,
        FOREIGN KEY (product_variant_id) REFERENCES ${TableNames.produtoVariantes}(id) ON DELETE SET NULL
      )
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_sale_returns_sale
      ON ${TableNames.saleReturns}(sale_id, created_at DESC, id DESC)
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_sale_returns_replacement_sale
      ON ${TableNames.saleReturns}(replacement_sale_id)
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_sale_return_items_return
      ON ${TableNames.saleReturnItems}(sale_return_id, sale_item_id)
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_sale_return_items_sale_item
      ON ${TableNames.saleReturnItems}(sale_item_id)
    ''');
  }
}

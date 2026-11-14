import 'package:sqflite/sqflite.dart';
import '../../../app/core/app_context/app_operational_context.dart';
import '../../../app/core/database/app_database.dart';
import '../../../app/core/database/table_names.dart';
import '../../../app/core/sync/operational_sync_event.dart';
import '../../../app/core/sync/sqlite_operational_sync_queue_repository.dart';
import '../../../app/core/sync/sync_feature_keys.dart';
import '../../../app/core/utils/id_generator.dart';

class SaleCustomerAssignmentRepository {
  SaleCustomerAssignmentRepository(this.database, this.context);
  final AppDatabase database;
  final AppOperationalContext context;

  Future<Map<String, Object?>> _sale(DatabaseExecutor db, int saleId) async {
    final rows = await db.rawQuery(
      '''SELECT v.*,
      EXISTS(SELECT 1 FROM ${TableNames.saleReturns} r WHERE r.sale_id=v.id OR r.replacement_sale_id=v.id) AS has_returns,
      EXISTS(SELECT 1 FROM ${TableNames.fiado} f WHERE f.venda_id=v.id) AS has_fiado
      FROM ${TableNames.vendas} v WHERE v.id=?''',
      [saleId],
    );
    if (rows.isEmpty) throw StateError('Venda não encontrada.');
    return rows.single;
  }

  String? _restriction(Map<String, Object?> sale) {
    final session = context.session;
    final role = (session.employee?.role ?? session.membership?.role ?? '')
        .toUpperCase();
    final privileged = session.isCompanyOwner || role == 'ADMIN';
    if (!privileged &&
        (!session.canAccessPermission('sales.create') ||
            sale['seller_remote_user_id'] == null ||
            sale['seller_remote_user_id'] != session.user.remoteId)) {
      return 'Somente o dono, administrador ou vendedor responsável pode alterar o cliente.';
    }
    if (sale['customer_assignment_locked'] == 1 ||
        sale['status'] != 'ativa' ||
        sale['tipo_venda'] == 'fiado' ||
        sale['has_fiado'] == 1 ||
        (sale['haver_utilizado_centavos'] as int? ?? 0) > 0 ||
        (sale['haver_gerado_centavos'] as int? ?? 0) > 0 ||
        sale['has_returns'] == 1) {
      return 'Alteração disponível apenas para venda ativa sem fiado, haver, troca ou devolução.';
    }
    return null;
  }

  Future<String?> restriction(int saleId) async {
    final db = await database.database;
    return _restriction(await _sale(db, saleId));
  }

  Future<String?> syncMessage(int saleId) async {
    final db = await database.database;
    final rows = await db.rawQuery(
      '''SELECT e.status, e.error_message FROM sale_customer_assignments a
      JOIN ${TableNames.operationalSyncEvents} e ON e.event_id=a.event_id
      WHERE a.sale_id=? ORDER BY a.expected_revision DESC LIMIT 1''',
      [saleId],
    );
    if (rows.isEmpty ||
        ['accepted', 'duplicate'].contains(rows.single['status'])) {
      return null;
    }
    if (['conflict', 'rejected'].contains(rows.single['status'])) {
      return 'Alteração não confirmada: ${rows.single['error_message'] ?? "consulte a sincronização para resolver o conflito"}';
    }
    return 'Alteração pendente de sincronização.';
  }

  Future<Map<String, Object?>?> _customer(
    DatabaseExecutor db,
    int? id, {
    bool activeOnly = true,
  }) async {
    if (id == null) return null;
    final rows = await db.rawQuery(
      '''SELECT c.*, s.remote_id FROM ${TableNames.clientes} c
      LEFT JOIN ${TableNames.syncRegistros} s ON s.feature_key=? AND s.local_id=c.id
      WHERE c.id=? ${activeOnly ? 'AND c.ativo=1 AND c.deletado_em IS NULL' : ''}''',
      [SyncFeatureKeys.customers, id],
    );
    return rows.isEmpty ? null : rows.single;
  }

  Future<void> assign(int saleId, int clientId) async {
    context.ensureOperationalWriteAllowed();
    final db = await database.database;
    await db.transaction((tx) async {
      final sale = await _sale(tx, saleId);
      final restriction = _restriction(sale);
      if (restriction != null) throw StateError(restriction);
      if (sale['cliente_id'] == clientId) return;
      final pending = await tx.rawQuery(
        '''SELECT e.status FROM sale_customer_assignments a
        JOIN ${TableNames.operationalSyncEvents} e ON e.event_id=a.event_id
        WHERE a.sale_id=? AND e.status NOT IN ('accepted','duplicate') LIMIT 1''',
        [saleId],
      );
      if (pending.isNotEmpty) {
        throw StateError(
          'Sincronize ou resolva a alteração anterior antes de mudar novamente.',
        );
      }
      final client = await _customer(tx, clientId);
      if (client == null) {
        throw StateError('Cliente indisponível nesta empresa.');
      }
      final previous = await _customer(
        tx,
        sale['cliente_id'] as int?,
        activeOnly: false,
      );
      final revision = sale['customer_assignment_revision'] as int;
      final eventId = IdGenerator.next();
      final now = DateTime.now();
      final session = context.session;
      final actor = session.user.remoteId;
      final device = session.clientInstanceId;
      if (actor == null || device == null) {
        throw StateError('Entre novamente para associar o cliente.');
      }
      await tx.insert('sale_customer_assignments', {
        'event_id': eventId,
        'sale_id': saleId,
        'previous_client_id': sale['cliente_id'],
        'client_id': clientId,
        'expected_revision': revision,
        'actor_user_id': actor,
        'device_id': device,
        'occurred_at': now.toUtc().toIso8601String(),
      });
      await tx.update(
        TableNames.vendas,
        {'cliente_id': clientId, 'customer_assignment_revision': revision + 1},
        where: 'id=?',
        whereArgs: [saleId],
      );
      final queued = await SqliteOperationalSyncQueueRepository(database)
          .enqueue(
            tx,
            event: OperationalSyncEvent(
              eventId: eventId,
              feature: 'pdv',
              entity: 'saleCustomerAssignment',
              operation: 'append',
              entityLocalId: eventId,
              occurredAt: now,
              payload: {
                'saleUuid': sale['uuid'],
                'customerServerId': client['remote_id'],
                'customerUuid': client['uuid'],
                'previousCustomerServerId': previous?['remote_id'],
                'previousCustomerUuid': previous?['uuid'],
                'expectedRevision': revision,
              },
            ),
          );
      if (!queued) {
        throw StateError(
          'Não foi possível registrar a alteração para sincronização.',
        );
      }
    });
  }
}

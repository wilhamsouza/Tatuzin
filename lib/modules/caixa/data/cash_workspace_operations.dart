part of 'sqlite_cash_repository.dart';

/// Shared employee cash keeps the cloud-confirmed balance separate from local
/// effects awaiting acceptance, keyed by immutable movement UUID/outbox event.
extension CashWorkspaceOperations on SqliteCashRepository {
  Future<void> recordEmployeeWorkspaceError(String? message) async =>
      CashWorkspaceStore.write(
        await _appDatabase.database,
        'cash.workspace.error:${_operationalContext.currentRemoteUserId}',
        {
          if (message != null) 'message': message,
          'at': DateTime.now().toIso8601String(),
        },
      );

  Future<bool> employeeOpenJoinedExisting() async =>
      (await CashWorkspaceStore.read(
        await _appDatabase.database,
        'cash.open.result:${_operationalContext.currentRemoteUserId}',
      ))['joinedExisting'] ==
      true;

  Future<List<Map<String, dynamic>>> employeeClosureArchives(
    String uuid,
  ) async {
    final db = await _appDatabase.database;
    final owner = await CashWorkspaceStore.read(db, 'cash.owner:$uuid');
    if (owner['employeeId'] != _operationalContext.currentRemoteUserId) {
      return [];
    }
    final rows = await db.query(
      TableNames.configuracoes,
      columns: ['valor_json'],
      where: 'chave LIKE ?',
      whereArgs: ['cash.closure.archive:$uuid:%'],
    );
    return rows
        .map(
          (row) => Map<String, dynamic>.from(
            jsonDecode(row['valor_json'] as String) as Map,
          ),
        )
        .toList();
  }

  Future<Map<String, dynamic>> employeeClosureDetails(String uuid) async =>
      CashWorkspaceStore.read(
        await _appDatabase.database,
        'cash.pending:$uuid',
      );

  Future<void> _assertEmployeeContext(DatabaseExecutor db) async {
    final active = await CashWorkspaceStore.read(db, 'cash.employee.context');
    if (active['employeeId'] != null &&
        active['employeeId'] != _operationalContext.currentRemoteUserId) {
      throw const ValidationException(
        'O funcionário mudou. Abra novamente o caixa da conta atual.',
      );
    }
  }

  Future<List<Map<String, Object?>>> _unresolvedWorkspaceEvents(
    DatabaseExecutor db,
    String uuid,
  ) async {
    final rows = await db.query(
      TableNames.operationalSyncEvents,
      where: "status NOT IN ('accepted', 'duplicate')",
      orderBy: 'id',
    );
    return rows.where((row) {
      final payload =
          jsonDecode(row['payload_json'] as String) as Map<String, dynamic>;
      if (payload['cashEmployeeId'] != null &&
          payload['cashEmployeeId'] != _operationalContext.currentRemoteUserId) {
        return false;
      }
      return payload['cashSessionUuid'] == uuid ||
          payload['cashSessionLocalId'] == uuid;
    }).toList();
  }

  Future<int> _pendingCashDelta(DatabaseExecutor db, String uuid) async {
    final workspace = await CashWorkspaceStore.read(db, 'cash.workspace:$uuid');
    final confirmed = (workspace['confirmedMovementUuids'] as List? ?? [])
        .whereType<String>()
        .toSet();
    final hasCoverage = workspace['confirmedMovementUuids'] is List;
    var delta = 0;
    final rows = await db.query(
      TableNames.operationalSyncEvents,
      where: "entity = 'cashMovement'",
    );
    for (final row in rows) {
      final payload =
          jsonDecode(row['payload_json'] as String) as Map<String, dynamic>;
      if (payload['cashSessionUuid'] != uuid &&
          payload['cashSessionLocalId'] != uuid) {
        continue;
      }
      if (payload['cashEmployeeId'] != null &&
          payload['cashEmployeeId'] != _operationalContext.currentRemoteUserId) {
        continue;
      }
      final movementUuid =
          payload['uuid'] as String? ?? row['entity_local_id'] as String?;
      if (confirmed.contains(movementUuid)) continue;
      if (!hasCoverage &&
          (row['status'] == 'accepted' || row['status'] == 'duplicate')) {
        continue;
      }
      final method =
          payload['paymentMethod'] as String? ??
          PaymentMethodNoteCodec.parse(
            payload['description'] as String?,
          )?.dbValue;
      if (method != null && method != 'dinheiro') continue;
      final type = payload['type'] as String?;
      if (method == null &&
          (type == 'venda' ||
              type == 'recebimento_fiado' ||
              type == 'cancelamento')) {
        continue;
      }
      delta += payload['amountCents'] as int? ?? 0;
    }
    return delta;
  }

  Future<Map<String, Object?>> _withEmployeePendingBalance(
    DatabaseExecutor db,
    Map<String, Object?> row,
  ) async {
    final raw = row['cash_workspace_json'];
    if (raw == null) return row;
    final workspace = jsonDecode(raw as String) as Map<String, dynamic>;
    final closed = workspace['status'] == 'CLOSED';
    final confirmed = workspace['expectedBalanceCents'] as int?;
    return {
      ...row,
      if (confirmed != null)
        'cash_workspace_expected':
            confirmed +
            (closed ? 0 : await _pendingCashDelta(db, row['uuid'] as String)),
    };
  }

  Future<CashSession> openEmployeeWorkspace({
    required int initialFloatCents,
    CashCountResult? count,
  }) async {
    final db = await _appDatabase.database;
    await _assertEmployeeContext(db);
    final current = await CashDatabaseSupport.getOpenSessionRow(db);
    if (current != null) {
      final state = await CashWorkspaceStore.read(
        db,
        'cash.workspace:${current['uuid']}',
      );
      if (state['status'] != null && state['status'] != 'OPEN') {
        throw const ValidationException(
          'Conclua ou revise a conferência pendente deste funcionário antes de abrir outro caixa.',
        );
      }
    }
    final employee = _operationalContext.currentRemoteUserId!;
    final draft = await CashWorkspaceStore.read(
      db,
      'cash.open.request:$employee',
    );
    final requestId = draft['requestId'] as String? ?? IdGenerator.next();
    await CashWorkspaceStore.write(db, 'cash.open.request:$employee', {
      'requestId': requestId,
    });
    final response = await _workspaceRemote!.post('sessions/open', {
      'requestId': requestId,
      'openingBalanceCents': initialFloatCents,
      if (count != null) 'denominations': count.breakdown,
      if (count != null) 'coinsCents': count.coinsCents,
    });
    await CashWorkspaceStore.write(db, 'cash.open.result:$employee', {
      'joinedExisting':
          response['joinedExisting'] == true ||
          (response['session'] is Map &&
              (response['session'] as Map)['openingBalanceCents'] !=
                  initialFloatCents),
    });
    final session = await applyEmployeeWorkspace(response);
    if (session == null) {
      throw const ValidationException(
        'A nuvem não retornou o caixa do funcionário.',
      );
    }
    await CashWorkspaceStore.write(db, 'cash.open.request:$employee', {});
    return session;
  }

  Future<CashSession?> refreshEmployeeWorkspace({
    bool joinIfNeeded = false,
  }) async {
    if (!_usesSharedWorkspace) return null;
    var response = await _workspaceRemote!.read();
    final value = response['session'];
    if (value is Map &&
        value['employeeId'] != _operationalContext.currentRemoteUserId) {
      throw const ValidationException(
        'O caixa recebido pertence a outro funcionário.',
      );
    }
    if (joinIfNeeded && value is Map && value['status'] == 'OPEN') {
      if (value['currentDeviceJoined'] != true) {
        response = await _workspaceRemote.post(
          'sessions/${value['uuid']}/join',
          {'requestId': IdGenerator.next()},
        );
      }
    }
    return applyEmployeeWorkspace(response);
  }

  Future<CashSession?> applyEmployeeWorkspace(
    Map<String, dynamic> response,
  ) async {
    if (response['version'] != 3) {
      throw const ValidationException(
        'Atualize a conexão para acessar o caixa compartilhado.',
      );
    }
    final raw = response['session'];
    if (raw == null) return null;
    final server = Map<String, dynamic>.from(raw as Map);
    final employee = _operationalContext.currentRemoteUserId;
    if (employee == null || server['employeeId'] != employee) {
      throw const ValidationException(
        'O caixa recebido pertence a outro funcionário.',
      );
    }
    final uuid = server['uuid'] as String;
    final db = await _appDatabase.database;
    return db.transaction((txn) async {
      await _assertEmployeeContext(txn);
      final existing = await _findSessionRowByUuid(txn, uuid);
      final pending = await CashWorkspaceStore.read(txn, 'cash.pending:$uuid');
      var status = server['status'] as String;
      final request = server['closureRequest'] is Map
          ? Map<String, dynamic>.from(server['closureRequest'] as Map)
          : <String, dynamic>{};
      final unsentReconfirmation =
          pending['status'] == 'LOCAL_PENDING' &&
          pending['sent'] != true &&
          request['requestId'] != pending['requestId'];
      if (status != 'CLOSED' && request.isNotEmpty && !unsentReconfirmation) {
        await CashWorkspaceStore.write(txn, 'cash.pending:$uuid', {
          ...pending,
          ...request,
          'serverRequestId': request['requestId'],
          'status': request['status'] ?? status,
          'sent': true,
        });
      } else if (status != 'CLOSED' &&
          unsentReconfirmation &&
          request.isNotEmpty) {
        status = 'PENDING_SYNC';
      } else if (pending.isNotEmpty &&
          pending['status'] != 'CLOSED' &&
          status == 'OPEN') {
        status = pending['status'] == 'REVIEW_REQUIRED'
            ? 'REVIEW_REQUIRED'
            : 'PENDING_SYNC';
        if (server['expectedBalanceCents'] != null &&
            pending['localExpectedBalanceCents'] !=
                server['expectedBalanceCents']) {
          status = 'REVIEW_REQUIRED';
          await CashWorkspaceStore.write(txn, 'cash.pending:$uuid', {
            ...pending,
            'status': status,
          });
        }
      }
      await CashWorkspaceStore.write(txn, 'cash.owner:$uuid', {
        'version': 3,
        'employeeId': employee,
        'joined': server['currentDeviceJoined'] == true,
        if (server['currentDeviceJoined'] == true)
          'joinedClientInstanceId':
              _operationalContext.session.clientInstanceId,
      });
      await txn.delete(
        TableNames.configuracoes,
        where: 'chave = ?',
        whereArgs: ['cash.remote:$uuid'],
      );
      final workspace = {
        ...server,
        'status': status,
        'serverStatus': server['status'],
      };
      await CashWorkspaceStore.write(txn, 'cash.workspace:$uuid', workspace);
      final opening = await CashWorkspaceStore.read(txn, 'cash.opening:$uuid');
      if (opening.isEmpty) {
        await CashWorkspaceStore.write(txn, 'cash.opening:$uuid', {
          'version': 3,
          'countedAmountCents': server['openingBalanceCents'],
          'blindClosureEnabled': server['blindClosureEnabled'] == true,
          'policyRevision': server['policyRevision'] ?? 0,
        });
      }
      final confirmedBalance = server['expectedBalanceCents'] as int?;
      final expected = confirmedBalance == null
          ? (existing?['saldo_esperado_centavos'] as int? ?? 0)
          : confirmedBalance +
                (status == 'CLOSED' ? 0 : await _pendingCashDelta(txn, uuid));
      final values = <String, Object?>{
        'troco_inicial_centavos': server['openingBalanceCents'] as int? ?? 0,
        'aguardando_confirmacao_troco_inicial': 0,
        'saldo_esperado_centavos': expected,
        'saldo_final_centavos': expected,
        'status': status == 'CLOSED' ? 'fechado' : 'aberto',
        'fechada_em': status == 'CLOSED'
            ? (server['closedAt'] as String? ??
                  DateTime.now().toIso8601String())
            : null,
      };
      late final int id;
      if (existing == null) {
        id = await txn.insert(TableNames.caixaSessoes, {
          'uuid': uuid,
          'usuario_id': _operationalContext.currentLocalUserId,
          'aberta_em':
              server['openedAt'] as String? ?? DateTime.now().toIso8601String(),
          'total_entradas_dinheiro_centavos': 0,
          'total_suprimentos_centavos': 0,
          'total_sangrias_centavos': 0,
          'total_vendas_centavos': 0,
          'total_recebimentos_fiado_centavos': 0,
          'total_recebimentos_fiado_dinheiro_centavos': 0,
          'total_recebimentos_fiado_pix_centavos': 0,
          'total_recebimentos_fiado_cartao_centavos': 0,
          ...values,
        });
      } else {
        id = existing['id'] as int;
        await txn.update(
          TableNames.caixaSessoes,
          values,
          where: 'id = ?',
          whereArgs: [id],
        );
      }
      if (status == 'CLOSED') {
        final sameRequest = pending['requestId'] == request['requestId'];
        if (pending.isNotEmpty &&
            !sameRequest &&
            pending['status'] != 'CLOSED') {
          final draft = await CashWorkspaceStore.read(
            txn,
            'cash.draft:$_draftOwner:close:$uuid',
          );
          await CashWorkspaceStore.write(
            txn,
            'cash.closure.archive:$uuid:${pending['requestId'] ?? IdGenerator.next()}',
            {
              ...pending,
              'draft': draft,
              'sessionUuid': uuid,
              'employeeId': employee,
              'archivedAt': DateTime.now().toIso8601String(),
              'message':
                  'Outro fechamento foi concluído na nuvem. Esta conferência local foi preservada e não foi aplicada.',
            },
          );
        }
        if (server['closingDetails'] is! Map) {
          throw const ValidationException(
            'A nuvem não retornou os detalhes finais do fechamento. A conferência local foi preservada para tentar novamente.',
          );
        }
        final frozen = Map<String, dynamic>.from(
          server['closingDetails'] as Map,
        );
        await CashWorkspaceStore.write(txn, 'cash.closing:$uuid', frozen);
        await CashWorkspaceStore.write(txn, 'cash.pending:$uuid', {
          if (sameRequest) ...pending,
          ...request,
          'status': 'CLOSED',
        });
        await CashWorkspaceStore.write(
          txn,
          'cash.draft:$_draftOwner:close:$uuid',
          {},
        );
      }
      return _mapSession(await _loadSessionRow(txn, id));
    });
  }

  Future<CashSession> saveEmployeeClosure({
    required CashClosurePreview preview,
    required int countedBalanceCents,
    String? reason,
    String? notes,
    CashCountResult? count,
  }) async {
    final db = await _appDatabase.database;
    return db.transaction((txn) async {
      await _assertEmployeeContext(txn);
      final row = await _findSessionRowByUuid(txn, preview.session.uuid);
      if (row == null) throw const ValidationException('Caixa não encontrado.');
      final uuid = preview.session.uuid;
      final owner = await CashWorkspaceStore.read(txn, 'cash.owner:$uuid');
      if (owner['employeeId'] != _operationalContext.currentRemoteUserId) {
        throw const ValidationException(
          'Este caixa pertence a outro funcionário.',
        );
      }
      if (owner['joined'] != true ||
          owner['joinedClientInstanceId'] !=
              _operationalContext.session.clientInstanceId) {
        throw const ValidationException(
          'Conecte este aparelho e associe o caixa antes de iniciar a conferência.',
        );
      }
      final current = _mapSession(await _loadSessionRow(txn, row['id'] as int));
      final prior = await CashWorkspaceStore.read(txn, 'cash.pending:$uuid');
      final requestValues = {
        'countedBalanceCents': countedBalanceCents,
        if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
        if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
        if (count != null) 'denominations': count.breakdown,
        if (count != null) 'coinsCents': count.coinsCents,
      };
      if (prior['localSnapshotToken'] == preview.snapshotToken &&
          jsonEncode(prior['localRequest']) == jsonEncode(requestValues)) {
        return current;
      }
      if (!current.isOpen && !current.needsReview) {
        throw const ValidationException(
          'Esta conferência já está pendente. Aguarde os aparelhos sincronizarem.',
        );
      }
      if (await _snapshot(txn, row) != preview.snapshotToken) {
        throw const ValidationException(
          'O caixa recebeu movimentações. Revise novamente.',
        );
      }
      if ((current.blindClosureEnabled ||
              countedBalanceCents != current.expectedBalanceCents) &&
          (reason == null || reason.trim().isEmpty)) {
        throw const ValidationException('Informe o motivo da conferência.');
      }
      final requestId = IdGenerator.next();
      final pending = {
        'requestId': requestId,
        'expectedRevision': current.revision,
        'localExpectedBalanceCents': current.blindClosureEnabled
            ? null
            : current.expectedBalanceCents,
        ...requestValues,
        'status': 'LOCAL_PENDING',
        'sent': false,
        if (current.needsReview && prior['serverRequestId'] != null)
          'previousRequestId': prior['serverRequestId'],
        'localSnapshotToken': preview.snapshotToken,
        'localRequest': requestValues,
      };
      await CashWorkspaceStore.write(txn, 'cash.pending:$uuid', pending);
      final workspace = await CashWorkspaceStore.read(
        txn,
        'cash.workspace:$uuid',
      );
      await CashWorkspaceStore.write(txn, 'cash.workspace:$uuid', {
        ...workspace,
        'status': 'PENDING_SYNC',
      });
      return _mapSession(await _loadSessionRow(txn, row['id'] as int));
    });
  }

  Future<void> prepareEmployeeWorkspaceSynchronization() async {
    _workspaceSyncProof = null;
    if (!_usesSharedWorkspace) return;
    final session = await refreshEmployeeWorkspace();
    if (session == null) return;
    final db = await _appDatabase.database;
    final workspace = await CashWorkspaceStore.read(
      db,
      'cash.workspace:${session.uuid}',
    );
    final closure = workspace['closureRequest'] as Map?;
    _workspaceSyncProof = {
      'uuid': session.uuid,
      'revision': workspace['revision'],
      'generation': closure?['generation'],
      'clientInstanceId': _operationalContext.session.clientInstanceId,
    };
  }

  /// Called only after a successful pull and when local outbox effects drained.
  Future<void> synchronizeEmployeeWorkspaceAfterDrain() async {
    if (!_usesSharedWorkspace) return;
    await refreshEmployeeWorkspace();
    final db = await _appDatabase.database;
    final row = await CashDatabaseSupport.getOpenSessionRow(db);
    if (row == null) return;
    final uuid = row['uuid'] as String;
    if ((await _unresolvedWorkspaceEvents(db, uuid)).isNotEmpty) return;
    var pending = await CashWorkspaceStore.read(db, 'cash.pending:$uuid');
    var workspace = await CashWorkspaceStore.read(db, 'cash.workspace:$uuid');
    if (pending['status'] == 'LOCAL_PENDING' && pending['sent'] != true) {
      final body = <String, dynamic>{
        for (final key in [
          'requestId',
          'expectedRevision',
          'countedBalanceCents',
          'localExpectedBalanceCents',
          'reason',
          'notes',
          'denominations',
          'coinsCents',
        ])
          if (pending.containsKey(key)) key: pending[key],
      };
      final previous = pending['previousRequestId'] as String?;
      final path = previous == null
          ? 'sessions/$uuid/closure-requests'
          : 'sessions/$uuid/closure-requests/$previous/reconfirm';
      await applyEmployeeWorkspace(await _workspaceRemote!.post(path, body));
      pending = await CashWorkspaceStore.read(db, 'cash.pending:$uuid');
      workspace = await CashWorkspaceStore.read(db, 'cash.workspace:$uuid');
    }
    final proof = _workspaceSyncProof;
    _workspaceSyncProof = null;
    if (proof != null &&
        proof['uuid'] == uuid &&
        proof['revision'] == workspace['revision'] &&
        proof['generation'] == pending['generation'] &&
        proof['clientInstanceId'] ==
            _operationalContext.session.clientInstanceId &&
        workspace['serverStatus'] == 'PENDING_SYNC' &&
        pending['serverRequestId'] != null &&
        (await _unresolvedWorkspaceEvents(db, uuid)).isEmpty) {
      final response = await _workspaceRemote!.post(
        'sessions/$uuid/closure-requests/${pending['serverRequestId']}/ack',
        {
          'generation': pending['generation'],
          'revision': workspace['revision'],
          'drained': true,
        },
      );
      await applyEmployeeWorkspace(response);
    }
  }
}

import 'package:tatuzin/modules/caixa/domain/entities/cash_closure_preview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tatuzin/app/core/app_context/app_operational_context.dart';
import 'package:tatuzin/app/core/config/app_environment.dart';
import 'package:tatuzin/app/core/database/app_database.dart';
import 'package:tatuzin/app/core/errors/app_exceptions.dart';
import 'package:tatuzin/app/core/network/contracts/api_client_contract.dart';
import 'package:tatuzin/app/core/session/app_session.dart';
import 'package:tatuzin/app/core/session/app_user.dart';
import 'package:tatuzin/app/core/session/auth_token_storage.dart';
import 'package:tatuzin/app/core/session/company_context.dart';
import 'package:tatuzin/app/core/sync/operational_sync_queue_item.dart';
import 'package:tatuzin/app/core/sync/sqlite_operational_sync_queue_repository.dart';
import 'package:tatuzin/app/core/utils/id_generator.dart';
import 'package:tatuzin/modules/caixa/data/cash_database_support.dart';
import 'package:tatuzin/modules/caixa/data/cash_workspace_remote.dart';
import 'package:tatuzin/modules/caixa/data/sqlite_cash_repository.dart';
import 'package:tatuzin/modules/caixa/domain/entities/cash_manual_movement_input.dart';
import 'package:tatuzin/modules/caixa/domain/entities/cash_enums.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  Future<_Device> device(
    _Cloud cloud,
    String name, {
    String employee = 'employee-a',
    AppDatabase? sharedDatabase,
  }) async {
    final session = _session(employee, name);
    final app =
        sharedDatabase ??
        AppDatabase.forIsolationKey(
          'cash-v3-$name-${DateTime.now().microsecondsSinceEpoch}',
        );
    app.configureCashEmployeeContext(session);
    app.configureCashPolicy(session.company);
    await app.database;
    if (sharedDatabase == null) addTearDown(app.close);
    final remote = _Remote(cloud, employee, name);
    return _Device(
      app,
      SqliteCashRepository(
        app,
        AppOperationalContext(
          environment: AppEnvironment.remoteDefault(),
          session: session,
        ),
        workspaceRemote: remote,
      ),
      remote,
    );
  }

  test(
    'two devices join one employee cash and preserve opening float exactly once',
    () async {
      final cloud = _Cloud();
      final a = await device(cloud, 'device-a');
      final b = await device(cloud, 'device-b');
      final first = await a.repo.openSession(initialFloatCents: 1000);
      final joined = await b.repo.openSession(initialFloatCents: 9900);
      expect(first.uuid, joined.uuid);
      expect(joined.initialFloatCents, 1000);
      expect(await b.repo.employeeOpenJoinedExisting(), isTrue);
      expect(cloud.sessions['employee-a']!['openingBalanceCents'], 1000);
      expect((cloud.sessions['employee-a']!['devices'] as Set).length, 2);
    },
  );

  test(
    'GET is read-only until explicit join and proof cannot be restored on another client',
    () async {
      final cloud = _Cloud();
      final a = await device(cloud, 'device-a');
      final opened = await a.repo.openSession(initialFloatCents: 1000);
      final b = await device(cloud, 'device-b');
      await _sync(b);
      final db = await b.app.database;
      expect(await CashDatabaseSupport.getOpenSessionRow(db), isNull);
      await expectLater(b.repo.prepareClosure(opened.uuid), throwsA(anything));
      await expectLater(
        b.repo.commitClosure(
          preview: await a.repo.prepareClosure(opened.uuid),
          countedBalanceCents: 1000,
        ),
        throwsA(anything),
      );
      await expectLater(
        b.repo.registerManualMovement(_supply(5)),
        throwsA(anything),
      );
      expect(
        (cloud.sessions['employee-a']!['devices'] as Set).contains('device-b'),
        isFalse,
      );
      expect((await b.repo.getCurrentSession())!.uuid, opened.uuid);
      expect(b.remote.calls.any((call) => call.$1.endsWith('/join')), isTrue);
      await b.repo.registerManualMovement(_supply(5));
      // A restored cache's proof is bound to the original stable client id.
      final copied = await device(cloud, 'device-c', sharedDatabase: b.app);
      expect(
        await CashDatabaseSupport.getOpenSessionRow(await copied.app.database),
        isNull,
      );
      copied.remote.offline = true;
      await expectLater(copied.repo.getCurrentSession(), throwsA(anything));
      await expectLater(
        copied.repo.registerManualMovement(_supply(1)),
        throwsA(anything),
      );
    },
  );

  test(
    'confirmed base plus UUID ledger survives pending/accepted/echo without duplicate cash',
    () async {
      final cloud = _Cloud();
      final a = await device(cloud, 'device-a');
      final opened = await a.repo.openSession(initialFloatCents: 1000);
      await a.repo.registerManualMovement(_supply(101));
      final items = await a.queue.listPending(
        limit: 20,
        retryOnly: false,
        ignoreRetryBackoff: true,
      );
      expect(items.single.event.payload['cashWorkspaceVersion'], 3);
      cloud.addMovement('employee-a', 'other-pix', 202, cash: false);
      cloud.addMovement('employee-a', 'other-cash', 303);
      await a.repo.refreshEmployeeWorkspace();
      expect((await a.repo.getCurrentSession())!.expectedBalanceCents, 1404);
      // Local acceptance alone must not remove its effect before a confirming server snapshot.
      await a.queue.markAccepted(
        eventId: items.single.event.eventId,
        serverVersion: '5',
        processedAt: DateTime.now(),
      );
      expect((await a.repo.getCurrentSession())!.expectedBalanceCents, 1404);
      cloud.addMovement(
        'employee-a',
        items.single.event.payload['uuid'] as String,
        101,
      );
      await a.repo.refreshEmployeeWorkspace();
      expect((await a.repo.getCurrentSession())!.expectedBalanceCents, 1404);
      expect((await a.repo.getCurrentSession())!.uuid, opened.uuid);
    },
  );

  test(
    'offline pending closure survives restart, blocks moves, and waits for every participant',
    () async {
      final cloud = _Cloud();
      final a = await device(cloud, 'device-a');
      final b = await device(cloud, 'device-b');
      final opened = await a.repo.openSession(initialFloatCents: 1000);
      await b.repo.getCurrentSession();
      final preview = await a.repo.prepareClosure(opened.uuid);
      a.remote.offline = true;
      final pending = await a.repo.commitClosure(
        preview: preview,
        countedBalanceCents: 1000,
      );
      expect(pending.status, CashSessionStatus.pendingSync);
      expect(pending.isClosed, isFalse);
      await expectLater(
        a.repo.registerManualMovement(_supply(1)),
        throwsA(anything),
      );
      await expectLater(
        a.repo.openSession(initialFloatCents: 999),
        throwsA(anything),
      );
      await a.app.close();
      expect(
        (await a.repo.getCurrentSession())!.status,
        CashSessionStatus.pendingSync,
      );
      await expectLater(
        a.repo.synchronizeEmployeeWorkspaceAfterDrain(),
        throwsA(anything),
      );
      a.remote.offline = false;
      await _sync(a);
      expect((await a.repo.getCurrentSession())!.isClosurePending, isTrue);
      await _sync(b);
      await _sync(a);
      await a.repo.refreshEmployeeWorkspace();
      final closed = (await a.repo.listSessions()).firstWhere(
        (s) => s.uuid == opened.uuid,
      );
      expect(closed.isClosed, isTrue);
      expect(closed.countedBalanceCents, 1000);
      final next = await a.repo.openSession(initialFloatCents: 50);
      final retry = await a.repo.commitClosure(
        preview: preview,
        countedBalanceCents: 1000,
      );
      expect(retry.uuid, opened.uuid);
      expect((await a.repo.getCurrentSession())!.uuid, next.uuid);
    },
  );

  test(
    'late other-device money requires manual review and explicit reconfirmation',
    () async {
      final cloud = _Cloud();
      final a = await device(cloud, 'device-a');
      final b = await device(cloud, 'device-b');
      final opened = await a.repo.openSession(initialFloatCents: 1000);
      await b.repo.getCurrentSession();
      await a.repo.commitClosure(
        preview: await a.repo.prepareClosure(opened.uuid),
        countedBalanceCents: 1000,
      );
      await _sync(a);
      cloud.addMovement('employee-a', 'late-cash', 200);
      await _sync(b);
      await _sync(a);
      await a.repo.refreshEmployeeWorkspace();
      expect((await a.repo.getCurrentSession())!.needsReview, isTrue);
      expect(cloud.sessions['employee-a']!['status'], 'REVIEW_REQUIRED');
      await expectLater(
        a.repo.registerManualMovement(_supply(3)),
        throwsA(anything),
      );
      final reviewed = await a.repo.prepareClosure(opened.uuid);
      await a.repo.commitClosure(
        preview: reviewed,
        countedBalanceCents: 1200,
        reason: 'Conferência após recebimento tardio',
      );
      await _sync(a);
      expect(
        a.remote.calls.any((call) => call.$1.endsWith('/reconfirm')),
        isTrue,
      );
      await _sync(b);
      await _sync(a);
      await a.repo.refreshEmployeeWorkspace();
      expect((await a.repo.listSessions()).single.isClosed, isTrue);
    },
  );

  test(
    'new generation after pull cannot be acknowledged until another full synchronization',
    () async {
      final cloud = _Cloud();
      final a = await device(cloud, 'device-a');
      final b = await device(cloud, 'device-b');
      final opened = await a.repo.openSession(initialFloatCents: 1000);
      await a.repo.commitClosure(
        preview: await a.repo.prepareClosure(opened.uuid),
        countedBalanceCents: 1000,
      );
      await _sync(a);
      await a.repo.prepareEmployeeWorkspaceSynchronization();
      await b.remote.post('sessions/${opened.uuid}/join', {
        'requestId': IdGenerator.next(),
      });
      await a.repo.synchronizeEmployeeWorkspaceAfterDrain();
      expect(a.remote.calls.where((call) => call.$1.endsWith('/ack')), isEmpty);
      await _sync(a);
      expect(
        a.remote.calls.where((call) => call.$1.endsWith('/ack')),
        hasLength(1),
      );
      await _sync(b);
      expect(cloud.sessions['employee-a']!['status'], 'CLOSED');
    },
  );

  test(
    'central CLOSED wins a concurrent local proposal and archives losing count and notes',
    () async {
      final cloud = _Cloud();
      final a = await device(cloud, 'device-a');
      final b = await device(cloud, 'device-b');
      final opened = await a.repo.openSession(initialFloatCents: 1000);
      await b.repo.getCurrentSession();
      final winning = await a.repo.prepareClosure(opened.uuid);
      final losing = await b.repo.prepareClosure(opened.uuid);
      await a.repo.commitClosure(
        preview: winning,
        countedBalanceCents: 1000,
        notes: 'Vencedora',
        count: const CashCountResult(denominations: {100: 10}, coinsCents: 0),
      );
      await b.repo.commitClosure(
        preview: losing,
        countedBalanceCents: 900,
        reason: 'Recontagem local',
        notes: 'Preservar B',
        count: const CashCountResult(denominations: {100: 9}, coinsCents: 0),
      );
      await _sync(a);
      await _sync(a);
      final server = cloud.sessions['employee-a']!;
      final request = server['closure'] as Map;
      // B's previously issued drained acknowledgement races its new local count.
      await b.remote.post(
        'sessions/${opened.uuid}/closure-requests/${request['requestId']}/ack',
        {
          'generation': server['generation'],
          'revision': server['revision'],
          'drained': true,
        },
      );
      await b.repo.refreshEmployeeWorkspace();
      final closed = (await b.repo.listSessions()).single;
      expect(closed.isClosed, isTrue);
      expect(closed.countedBalanceCents, 1000);
      expect(closed.closingDetails!['notes'], 'Vencedora');
      expect(closed.closingDetails!['denominations'], [
        {'valueCents': 100, 'quantity': 10},
      ]);
      final archive = (await b.repo.employeeClosureArchives(
        opened.uuid,
      )).single;
      expect(archive['countedBalanceCents'], 900);
      expect(archive['notes'], 'Preservar B');
      final next = await b.repo.openSession(initialFloatCents: 50);
      await expectLater(
        b.repo.commitClosure(
          preview: losing,
          countedBalanceCents: 900,
          reason: 'Recontagem local',
          notes: 'Preservar B',
        ),
        throwsA(anything),
      );
      expect((await b.repo.getCurrentSession())!.uuid, next.uuid);
    },
  );

  test(
    'blind repeated snapshots never grow local balance and reason remains mandatory',
    () async {
      final cloud = _Cloud(blind: true);
      final a = await device(cloud, 'device-a');
      final opened = await a.repo.openSession(initialFloatCents: 1000);
      await a.repo.registerManualMovement(_supply(101));
      final before = (await (await a.app.database).query(
        'caixa_sessoes',
      )).single['saldo_esperado_centavos'];
      for (var i = 0; i < 3; i++) {
        await a.repo.refreshEmployeeWorkspace();
      }
      expect(
        (await (await a.app.database).query(
          'caixa_sessoes',
        )).single['saldo_esperado_centavos'],
        before,
      );
      final preview = await a.repo.prepareClosure(opened.uuid);
      await expectLater(
        a.repo.commitClosure(preview: preview, countedBalanceCents: 1101),
        throwsA(anything),
      );
      await a.repo.commitClosure(
        preview: preview,
        countedBalanceCents: 1101,
        reason: 'Contagem física cega',
      );
      expect((await a.repo.getCurrentSession())!.isClosed, isFalse);
    },
  );

  test(
    'employee switching isolates cash, pending outbox and stale recovery without losing employee A',
    () async {
      final cloud = _Cloud();
      final a = await device(cloud, 'device-shared');
      final cashA = await a.repo.openSession(initialFloatCents: 1000);
      await a.repo.registerManualMovement(_supply(101));
      final aEvents = await a.queue.listPending(
        limit: 20,
        retryOnly: false,
        ignoreRetryBackoff: true,
      );
      await a.queue.markPushing(
        aEvents,
        startedAt: DateTime.now().subtract(const Duration(minutes: 5)),
      );
      final b = await device(
        cloud,
        'device-shared',
        employee: 'employee-b',
        sharedDatabase: a.app,
      );
      expect(await b.repo.getCurrentSession(), isNull);
      final cashB = await b.repo.openSession(initialFloatCents: 2000);
      expect(cashB.uuid, isNot(cashA.uuid));
      expect(
        await b.queue.recoverStalePushing(
          staleAfter: const Duration(minutes: 2),
        ),
        0,
      );
      expect(
        await b.queue.listPending(
          limit: 20,
          retryOnly: false,
          ignoreRetryBackoff: true,
        ),
        isEmpty,
      );
      await b.repo.commitClosure(
        preview: await b.repo.prepareClosure(cashB.uuid),
        countedBalanceCents: 2000,
      );
      await _sync(b);
      await _sync(b);
      expect(
        (await b.repo.listSessions())
            .firstWhere((s) => s.uuid == cashB.uuid)
            .isClosed,
        isTrue,
      );
      final again = await device(cloud, 'device-shared', sharedDatabase: a.app);
      expect(
        await again.queue.recoverStalePushing(
          staleAfter: const Duration(minutes: 2),
        ),
        1,
      );
      final recovered = await again.queue.listPending(
        limit: 20,
        retryOnly: false,
        ignoreRetryBackoff: true,
      );
      expect(recovered.single.event.eventId, aEvents.single.event.eventId);
      await _accept(again, recovered.single, cloud);
      expect(
        await again.queue.listPending(
          limit: 20,
          retryOnly: false,
          ignoreRetryBackoff: true,
        ),
        isEmpty,
      );
      await again.repo.refreshEmployeeWorkspace();
      expect(
        (await again.repo.getCurrentSession())!.expectedBalanceCents,
        1101,
      );
    },
  );

  test(
    'new device cannot invent offline float and a SELLER gets no cash permission',
    () async {
      final cloud = _Cloud();
      final a = await device(cloud, 'device-new');
      a.remote.offline = true;
      await expectLater(
        a.repo.openSession(initialFloatCents: 999),
        throwsA(anything),
      );
      expect(await (await a.app.database).query('caixa_sessoes'), isEmpty);
      await expectLater(
        (await a.app.database).transaction(
          (txn) => CashDatabaseSupport.ensureOpenSession(
            txn,
            timestamp: DateTime.now(),
          ),
        ),
        throwsA(anything),
      );
      final seller = _session('employee-seller', 'device-seller').copyWith(
        membership: const AppMembershipContext(
          role: 'SELLER',
          permissions: {'sales.create'},
        ),
      );
      final denied = SqliteCashRepository(
        a.app,
        AppOperationalContext(
          environment: AppEnvironment.remoteDefault(),
          session: seller,
        ),
        workspaceRemote: a.remote,
      );
      await expectLater(
        denied.openSession(initialFloatCents: 1),
        throwsA(anything),
      );
    },
  );

  test(
    'API transport carries exact app cash paths, typed body, bearer and stable device header',
    () async {
      final api = _Api();
      final remote = ApiCashWorkspaceRemote(api, _Tokens());
      await remote.read();
      final calls = <(String, Map<String, dynamic>)>[
        (
          'sessions/open',
          {'requestId': 'open-id', 'openingBalanceCents': 1000},
        ),
        ('sessions/uuid/join', {'requestId': 'join-id'}),
        (
          'sessions/uuid/closure-requests',
          {
            'requestId': 'close-id',
            'expectedRevision': 3,
            'countedBalanceCents': 1000,
            'localExpectedBalanceCents': 1000,
          },
        ),
        (
          'sessions/uuid/closure-requests/close-id/ack',
          {'generation': 2, 'revision': 3, 'drained': true},
        ),
        (
          'sessions/uuid/closure-requests/close-id/reconfirm',
          {
            'requestId': 'new-close',
            'expectedRevision': 4,
            'countedBalanceCents': 1200,
            'localExpectedBalanceCents': 1200,
          },
        ),
      ];
      for (final call in calls) {
        await remote.post(call.$1, call.$2);
      }
      expect(api.calls.first.$1, '/app/cash/workspace');
      for (var i = 0; i < calls.length; i++) {
        expect(api.calls[i + 1].$1, '/app/cash/${calls[i].$1}');
        expect(api.calls[i + 1].$2, calls[i].$2);
      }
      for (final call in api.calls) {
        expect(call.$3.headers, {
          'Authorization': 'Bearer test-token',
          'X-Client-Instance-Id': 'device-http',
        });
      }
    },
  );
}

CashManualMovementInput _supply(int amount) => CashManualMovementInput(
  type: CashMovementType.supply,
  amountCents: amount,
  description: 'Suprimento físico',
);
AppSession _session(String employee, String client) => AppSession(
  scope: SessionScope.authenticatedRemote,
  user: AppUser(
    localId: null,
    remoteId: employee,
    displayName: employee,
    email: null,
    roleLabel: 'OWNER',
    kind: AppUserKind.remoteAuthenticated,
  ),
  company: const CompanyContext(
    localId: null,
    remoteId: 'company-test',
    displayName: 'Empresa',
    legalName: 'Empresa',
    documentNumber: null,
    syncEnabled: true,
  ),
  startedAt: DateTime.now(),
  isOfflineFallback: false,
  clientInstanceId: client,
  membership: const AppMembershipContext(
    role: 'OWNER',
    permissions: {'cash.open', 'cash.close', 'cash.withdraw', 'sales.create'},
  ),
);

class _Device {
  _Device(this.app, this.repo, this.remote);
  final AppDatabase app;
  final SqliteCashRepository repo;
  final _Remote remote;
  SqliteOperationalSyncQueueRepository get queue =>
      SqliteOperationalSyncQueueRepository(app);
}

Future<void> _accept(
  _Device device,
  OperationalSyncQueueItem item,
  _Cloud cloud,
) async {
  cloud.addMovement(
    device.remote.employee,
    item.event.payload['uuid'] as String,
    item.event.payload['amountCents'] as int,
  );
  await device.queue.markAccepted(
    eventId: item.event.eventId,
    serverVersion: '1',
    processedAt: DateTime.now(),
  );
}

class _Cloud {
  _Cloud({this.blind = false});
  final bool blind;
  final sessions = <String, Map<String, dynamic>>{};
  Map<String, dynamic> snapshot(String employee, String device) {
    final session = sessions[employee];
    if (session == null) {
      return {'version': 3, 'session': null, 'legacySessionsPresent': false};
    }
    final closure = session['closure'] as Map<String, dynamic>?;
    return {
      'version': 3,
      'legacySessionsPresent': false,
      'session': {
        'uuid': session['uuid'],
        'id': session['uuid'],
        'employeeId': employee,
        'status': session['status'],
        'revision': session['revision'],
        'openingBalanceCents': session['openingBalanceCents'],
        'expectedBalanceCents': blind && session['status'] != 'CLOSED'
            ? null
            : session['expected'],
        'blindClosureEnabled': blind,
        'policyRevision': 1,
        'openedAt': session['openedAt'],
        'closedAt': session['closedAt'],
        'currentDeviceJoined': (session['devices'] as Set).contains(device),
        'confirmedMovementUuids': (session['movements'] as Set).toList(),
        'participants': [
          for (final participant in session['devices'] as Set)
            {
              'deviceId': participant,
              'name': participant,
              'lastAckGeneration':
                  (session['acks'] as Set).contains(participant)
                  ? session['generation']
                  : null,
            },
        ],
        'closingDetails': session['status'] != 'CLOSED' || closure == null
            ? null
            : {
                'version': 2,
                'sessionUuid': session['uuid'],
                'expectedBalanceCents': session['expected'],
                'countedBalanceCents': closure['countedBalanceCents'],
                'differenceCents':
                    (closure['countedBalanceCents'] as int) -
                    (session['expected'] as int),
                'blindClosureEnabled': blind,
                'policyRevision': 1,
                if (closure['reason'] != null) 'reason': closure['reason'],
                if (closure['notes'] != null) 'notes': closure['notes'],
                if (closure['denominations'] != null)
                  'denominations': closure['denominations'],
                if (closure['coinsCents'] != null)
                  'coinsCents': closure['coinsCents'],
              },
        'closureRequest': closure == null
            ? null
            : {
                ...closure,
                'generation': session['generation'],
                'revision': session['revision'],
                'status': session['status'],
                'expectedBalanceCents': blind && session['status'] != 'CLOSED'
                    ? null
                    : session['expected'],
                'differenceCents': blind && session['status'] != 'CLOSED'
                    ? null
                    : (closure['countedBalanceCents'] as int) -
                          (session['expected'] as int),
              },
      },
    };
  }

  void addMovement(
    String employee,
    String uuid,
    int amount, {
    bool cash = true,
  }) {
    final s = sessions[employee]!;
    if (!(s['movements'] as Set).add(uuid)) return;
    s['revision'] = (s['revision'] as int) + 1;
    if (cash) s['expected'] = (s['expected'] as int) + amount;
    if (s['closure'] != null) {
      s['generation'] = (s['generation'] as int) + 1;
      (s['acks'] as Set).clear();
      if (cash && amount != 0) s['status'] = 'REVIEW_REQUIRED';
    }
  }
}

class _Remote implements CashWorkspaceRemote {
  _Remote(this.cloud, this.employee, this.device);
  final _Cloud cloud;
  final String employee, device;
  bool offline = false;
  final calls = <(String, Map<String, dynamic>)>[];
  void _online() {
    if (offline) throw const NetworkRequestException('Sem conexão.');
  }

  @override
  Future<Map<String, dynamic>> read() async {
    _online();
    return cloud.snapshot(employee, device);
  }

  @override
  Future<Map<String, dynamic>> post(
    String path,
    Map<String, dynamic> body,
  ) async {
    _online();
    calls.add((path, Map.from(body)));
    var s = cloud.sessions[employee];
    if (path == 'sessions/open') {
      final joined = s != null && s['status'] != 'CLOSED';
      if (!joined) {
        s = {
          'uuid': IdGenerator.next(),
          'openingBalanceCents': body['openingBalanceCents'],
          'expected': body['openingBalanceCents'],
          'revision': 1,
          'status': 'OPEN',
          'openedAt': DateTime.now().toIso8601String(),
          'closedAt': null,
          'devices': <String>{},
          'movements': <String>{},
          'acks': <String>{},
          'generation': 0,
          'closure': null,
        };
        cloud.sessions[employee] = s;
      }
      (s['devices'] as Set).add(device);
      return {...cloud.snapshot(employee, device), 'joinedExisting': joined};
    }
    if (s == null) throw const ValidationException('Caixa não encontrado.');
    if (path.endsWith('/join')) {
      (s['devices'] as Set).add(device);
      if (s['closure'] != null) {
        s['generation'] = (s['generation'] as int) + 1;
        (s['acks'] as Set).clear();
      }
      return cloud.snapshot(employee, device);
    }
    if (!(s['devices'] as Set).contains(device)) {
      throw const ValidationException('Associe este aparelho.');
    }
    if (path.endsWith('/ack')) {
      if (body['revision'] == s['revision'] &&
          body['generation'] == s['generation'] &&
          s['status'] == 'PENDING_SYNC') {
        (s['acks'] as Set).add(device);
        if ((s['acks'] as Set).containsAll(s['devices'] as Set)) {
          s['status'] = 'CLOSED';
          s['closedAt'] = DateTime.now().toIso8601String();
        }
      }
      return cloud.snapshot(employee, device);
    }
    if (path.endsWith('/closure-requests') || path.endsWith('/reconfirm')) {
      final stale =
          body['expectedRevision'] != s['revision'] ||
          (!cloud.blind && body['localExpectedBalanceCents'] != s['expected']);
      s['status'] = stale ? 'REVIEW_REQUIRED' : 'PENDING_SYNC';
      s['generation'] = (s['generation'] as int) + 1;
      (s['acks'] as Set).clear();
      s['closure'] = {
        'requestId': body['requestId'],
        'countedBalanceCents': body['countedBalanceCents'],
        if (body['reason'] != null) 'reason': body['reason'],
        if (body['notes'] != null) 'notes': body['notes'],
        if (body['denominations'] != null)
          'denominations': body['denominations'],
        if (body['coinsCents'] != null) 'coinsCents': body['coinsCents'],
      };
      return cloud.snapshot(employee, device);
    }
    throw StateError('Unexpected $path');
  }
}

class _Tokens implements AuthTokenStorage {
  @override
  Future<String?> readAccessToken() async => 'test-token';
  @override
  Future<AuthClientContext?> readClientContext() async =>
      const AuthClientContext(
        clientType: 'app',
        clientInstanceId: 'device-http',
      );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Api implements ApiClientContract {
  final calls = <(String, Map<String, dynamic>?, ApiRequestOptions)>[];
  @override
  Future<ApiResponse<Map<String, dynamic>>> getJson(
    String path, {
    ApiRequestOptions options = const ApiRequestOptions(),
  }) async {
    calls.add((path, null, options));
    return const ApiResponse(
      statusCode: 200,
      data: {'version': 3, 'session': null},
      headers: {},
    );
  }

  @override
  Future<ApiResponse<Map<String, dynamic>>> postJson(
    String path, {
    Map<String, dynamic>? body,
    ApiRequestOptions options = const ApiRequestOptions(),
  }) async {
    calls.add((path, body, options));
    return const ApiResponse(
      statusCode: 200,
      data: {'version': 3, 'session': null},
      headers: {},
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _sync(_Device device) async {
  await device.repo.prepareEmployeeWorkspaceSynchronization();
  await device.repo.synchronizeEmployeeWorkspaceAfterDrain();
}

import 'package:erp_pdv_app/app/core/app_context/app_operational_context.dart';
import 'package:erp_pdv_app/app/core/app_context/data_access_policy.dart';
import 'package:erp_pdv_app/app/core/config/app_data_mode.dart';
import 'package:erp_pdv_app/app/core/config/app_environment.dart';
import 'package:erp_pdv_app/app/core/database/app_database.dart';
import 'package:erp_pdv_app/app/core/errors/app_exceptions.dart';
import 'package:erp_pdv_app/app/core/network/endpoint_config.dart';
import 'package:erp_pdv_app/app/core/network/remote_feature_diagnostic.dart';
import 'package:erp_pdv_app/app/core/session/app_session.dart';
import 'package:erp_pdv_app/app/core/session/app_user.dart';
import 'package:erp_pdv_app/app/core/session/company_context.dart';
import 'package:erp_pdv_app/app/core/sync/sync_status.dart';
import 'package:erp_pdv_app/modules/clientes/data/customers_repository_impl.dart';
import 'package:erp_pdv_app/modules/clientes/data/datasources/customers_remote_datasource.dart';
import 'package:erp_pdv_app/modules/clientes/data/models/remote_customer_record.dart';
import 'package:erp_pdv_app/modules/clientes/data/sqlite_client_repository.dart';
import 'package:erp_pdv_app/modules/clientes/domain/entities/client.dart';
import 'package:erp_pdv_app/modules/clientes/domain/repositories/client_repository.dart';
import 'package:erp_pdv_app/modules/clientes/presentation/providers/client_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('CRM listagem retorna remoto quando API responde', () async {
    final local = _FakeLocalClientRepository();
    final remote = _FakeCustomersRemoteDatasource(
      records: [_remoteCustomer('customer-remote', 'Cliente remoto')],
    );
    final repository = _customersRepository(local: local, remote: remote);

    final clients = await repository.search();

    expect(clients.map((client) => client.name), ['Cliente remoto']);
    expect(remote.listCalls, 1);
    expect(local.searchCalls, 0);
    expect(local.upsertedRemoteIds, ['customer-remote']);
  });

  test('CRM listagem usa cache somente quando API falha', () async {
    final local = _FakeLocalClientRepository([
      _client(id: 1, remoteId: 'customer-cache', name: 'Cliente cache'),
    ]);
    final repository = _customersRepository(
      local: local,
      remote: _FakeCustomersRemoteDatasource(throwOnList: true),
    );

    final clients = await repository.search();

    expect(clients.map((client) => client.name), ['Cliente cache']);
    expect(local.searchCalls, 1);
  });

  test('CRM detalhe busca remoto primeiro quando ha remoteId', () async {
    final local = _FakeLocalClientRepository([
      _client(id: 1, remoteId: 'customer-remote', name: 'Cliente cache'),
    ]);
    final remote = _FakeCustomersRemoteDatasource(
      records: [_remoteCustomer('customer-remote', 'Cliente remoto detalhe')],
    );
    final repository = _customersRepository(local: local, remote: remote);

    final client = await repository.findById(1);

    expect(client?.name, 'Cliente remoto detalhe');
    expect(remote.fetchCalls, 1);
    expect(local.upsertedRemoteIds, ['customer-remote']);
  });

  test('CRM create chama API primeiro e atualiza cache com remoteId', () async {
    final local = _FakeLocalClientRepository();
    final remote = _FakeCustomersRemoteDatasource(
      createResult: _remoteCustomer('customer-created', 'Cliente criado'),
    );
    final repository = _customersRepository(local: local, remote: remote);

    final id = await repository.create(const ClientInput(name: 'Cliente novo'));

    expect(id, 1);
    expect(remote.createCalls, 1);
    expect(local.createCalls, 0);
    expect(local.upsertedRemoteIds, ['customer-created']);
  });

  test('CRM update chama API primeiro e atualiza cache', () async {
    final local = _FakeLocalClientRepository([
      _client(id: 1, remoteId: 'customer-remote', name: 'Cliente cache'),
    ]);
    final remote = _FakeCustomersRemoteDatasource(
      updateResult: _remoteCustomer('customer-remote', 'Cliente atualizado'),
    );
    final repository = _customersRepository(local: local, remote: remote);

    await repository.update(1, const ClientInput(name: 'Cliente atualizado'));

    expect(remote.updateCalls, 1);
    expect(local.updateCalls, 0);
    expect(local.appliedRemoteIds, ['customer-remote']);
  });

  test('CRM delete chama API primeiro e atualiza cache', () async {
    final local = _FakeLocalClientRepository([
      _client(id: 1, remoteId: 'customer-remote', name: 'Cliente cache'),
    ]);
    final remote = _FakeCustomersRemoteDatasource();
    final repository = _customersRepository(local: local, remote: remote);

    await repository.delete(1);

    expect(remote.deleteCalls, 1);
    expect(local.deleteCalls, 0);
    expect(local.appliedRemoteIds, ['customer-remote']);
    expect(local.clientsById[1]?.deletedAt, isNotNull);
  });

  test(
    'Falha remota em create update delete nao vira sucesso local falso',
    () async {
      final local = _FakeLocalClientRepository([
        _client(id: 1, remoteId: 'customer-remote', name: 'Cliente cache'),
      ]);

      await expectLater(
        _customersRepository(
          local: local,
          remote: _FakeCustomersRemoteDatasource(throwOnCreate: true),
        ).create(const ClientInput(name: 'Falha')),
        throwsA(isA<NetworkRequestException>()),
      );
      await expectLater(
        _customersRepository(
          local: local,
          remote: _FakeCustomersRemoteDatasource(throwOnUpdate: true),
        ).update(1, const ClientInput(name: 'Falha')),
        throwsA(isA<NetworkRequestException>()),
      );
      await expectLater(
        _customersRepository(
          local: local,
          remote: _FakeCustomersRemoteDatasource(throwOnDelete: true),
        ).delete(1),
        throwsA(isA<NetworkRequestException>()),
      );

      expect(local.createCalls, 0);
      expect(local.updateCalls, 0);
      expect(local.deleteCalls, 0);
    },
  );

  test('pdvCustomerLookupProvider continua local-first', () async {
    final local = _FakeLocalClientRepository([
      _client(id: 1, remoteId: 'customer-local', name: 'Cliente local'),
    ]);
    final container = ProviderContainer(
      overrides: [
        localClientRepositoryProvider.overrideWithValue(local),
        clientRepositoryProvider.overrideWithValue(_FailingClientRepository()),
      ],
    );
    addTearDown(container.dispose);

    final clients = await container.read(
      pdvCustomerLookupProvider('local').future,
    );

    expect(clients.map((client) => client.name), ['Cliente local']);
    expect(local.searchCalls, 1);
  });

  test('clientListProvider propaga erro e nao fica carregando', () async {
    final container = ProviderContainer(
      overrides: [
        clientRepositoryProvider.overrideWithValue(_FailingClientRepository()),
      ],
    );
    addTearDown(container.dispose);

    await expectLater(
      container.read(clientListProvider.future),
      throwsA(isA<StateError>()),
    );
    expect(container.read(clientListProvider).hasError, isTrue);
  });
}

CustomersRepositoryImpl _customersRepository({
  required _FakeLocalClientRepository local,
  required CustomersRemoteDatasource remote,
}) {
  return CustomersRepositoryImpl(
    localRepository: local,
    remoteDatasource: remote,
    operationalContext: _remoteOperationalContext(),
    dataAccessPolicy: DataAccessPolicy.fromMode(AppDataMode.futureRemoteReady),
  );
}

AppOperationalContext _remoteOperationalContext() {
  return AppOperationalContext(
    environment: const AppEnvironment.localDefault().copyWith(
      dataMode: AppDataMode.futureRemoteReady,
      remoteSyncEnabled: true,
    ),
    session: AppSession(
      scope: SessionScope.authenticatedRemote,
      user: const AppUser(
        localId: 1,
        remoteId: 'user-1',
        displayName: 'Operador',
        email: null,
        roleLabel: 'Operador',
        kind: AppUserKind.remoteAuthenticated,
      ),
      company: const CompanyContext(
        localId: 1,
        remoteId: 'company-1',
        displayName: 'Empresa',
        legalName: 'Empresa',
        documentNumber: null,
        licensePlan: 'pro',
        licenseStatus: 'active',
        syncEnabled: true,
      ),
      startedAt: DateTime(2026, 4, 26, 10),
      isOfflineFallback: false,
    ),
  );
}

Client _client({
  required int id,
  required String remoteId,
  required String name,
  DateTime? deletedAt,
}) {
  final now = DateTime(2026, 4, 26, 10);
  return Client(
    id: id,
    uuid: 'client-$id',
    name: name,
    phone: '11999990000',
    address: null,
    notes: null,
    debtorBalanceCents: 0,
    creditBalanceCents: 0,
    isActive: deletedAt == null,
    createdAt: now,
    updatedAt: now,
    deletedAt: deletedAt,
    remoteId: remoteId,
    syncStatus: SyncStatus.synced,
    lastSyncedAt: now,
  );
}

RemoteCustomerRecord _remoteCustomer(String remoteId, String name) {
  final now = DateTime(2026, 4, 26, 10);
  return RemoteCustomerRecord(
    remoteId: remoteId,
    localUuid: 'local-$remoteId',
    name: name,
    phone: '11999990000',
    address: null,
    notes: null,
    isActive: true,
    createdAt: now,
    updatedAt: now,
    deletedAt: null,
  );
}

class _FakeLocalClientRepository extends SqliteClientRepository {
  _FakeLocalClientRepository([List<Client> initial = const <Client>[]])
    : clientsById = {for (final client in initial) client.id: client},
      super(AppDatabase.instance);

  final Map<int, Client> clientsById;
  final upsertedRemoteIds = <String>[];
  final appliedRemoteIds = <String>[];
  int searchCalls = 0;
  int createCalls = 0;
  int updateCalls = 0;
  int deleteCalls = 0;

  @override
  Future<int> create(ClientInput input) async {
    createCalls++;
    return 999;
  }

  @override
  Future<void> delete(int id) async {
    deleteCalls++;
  }

  @override
  Future<Client?> findById(int id, {bool includeDeleted = true}) async {
    return clientsById[id];
  }

  @override
  Future<Client?> findByRemoteId(String remoteId) async {
    for (final client in clientsById.values) {
      if (client.remoteId == remoteId) {
        return client;
      }
    }
    return null;
  }

  @override
  Future<List<Client>> search({String query = ''}) async {
    searchCalls++;
    return clientsById.values
        .where((client) => client.deletedAt == null)
        .toList(growable: false);
  }

  @override
  Future<void> update(int id, ClientInput input) async {
    updateCalls++;
  }

  @override
  Future<void> upsertFromRemote(
    RemoteCustomerRecord remote, {
    bool preserveLocalPendingChanges = true,
  }) async {
    upsertedRemoteIds.add(remote.remoteId);
    final existing = await findByRemoteId(remote.remoteId);
    final id = existing?.id ?? clientsById.length + 1;
    clientsById[id] = _client(
      id: id,
      remoteId: remote.remoteId,
      name: remote.name,
      deletedAt: remote.deletedAt,
    );
  }

  @override
  Future<void> applyPushResult({
    required Client client,
    required RemoteCustomerRecord remote,
  }) async {
    appliedRemoteIds.add(remote.remoteId);
    clientsById[client.id] = _client(
      id: client.id,
      remoteId: remote.remoteId,
      name: remote.name,
      deletedAt: remote.deletedAt,
    );
  }
}

class _FakeCustomersRemoteDatasource implements CustomersRemoteDatasource {
  _FakeCustomersRemoteDatasource({
    this.records = const <RemoteCustomerRecord>[],
    this.createResult,
    this.updateResult,
    this.throwOnList = false,
    this.throwOnCreate = false,
    this.throwOnUpdate = false,
    this.throwOnDelete = false,
  });

  final List<RemoteCustomerRecord> records;
  final RemoteCustomerRecord? createResult;
  final RemoteCustomerRecord? updateResult;
  final bool throwOnList;
  final bool throwOnCreate;
  final bool throwOnUpdate;
  final bool throwOnDelete;

  int listCalls = 0;
  int fetchCalls = 0;
  int createCalls = 0;
  int updateCalls = 0;
  int deleteCalls = 0;

  @override
  EndpointConfig get endpointConfig => const EndpointConfig.localDevelopment();

  @override
  String get featureKey => 'customers';

  @override
  bool get requiresAuthentication => true;

  @override
  Future<bool> canReachRemote() async => true;

  @override
  Future<RemoteCustomerRecord> create(RemoteCustomerRecord record) async {
    createCalls++;
    if (throwOnCreate) {
      throw const NetworkRequestException('Falha remota');
    }
    return createResult ?? _remoteCustomer('customer-created', record.name);
  }

  @override
  Future<void> delete(String remoteId) async {
    deleteCalls++;
    if (throwOnDelete) {
      throw const NetworkRequestException('Falha remota');
    }
  }

  @override
  Future<RemoteFeatureDiagnostic> fetchDiagnostic() {
    throw UnimplementedError();
  }

  @override
  Future<RemoteCustomerRecord> fetchById(String remoteId) async {
    fetchCalls++;
    return records.firstWhere((record) => record.remoteId == remoteId);
  }

  @override
  Future<List<RemoteCustomerRecord>> listAll() async {
    listCalls++;
    if (throwOnList) {
      throw const NetworkRequestException('Falha remota');
    }
    return records;
  }

  @override
  Future<RemoteCustomerRecord> update(
    String remoteId,
    RemoteCustomerRecord record,
  ) async {
    updateCalls++;
    if (throwOnUpdate) {
      throw const NetworkRequestException('Falha remota');
    }
    return updateResult ?? record;
  }
}

class _FailingClientRepository implements ClientRepository {
  @override
  Future<int> create(ClientInput input) async => 1;

  @override
  Future<void> delete(int id) async {}

  @override
  Future<List<Client>> search({String query = ''}) async {
    throw StateError('falha clientes');
  }

  @override
  Future<void> update(int id, ClientInput input) async {}
}

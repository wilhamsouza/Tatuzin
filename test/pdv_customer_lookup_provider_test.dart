import 'package:erp_pdv_app/app/core/database/app_database.dart';
import 'package:erp_pdv_app/modules/clientes/data/sqlite_client_repository.dart';
import 'package:erp_pdv_app/modules/clientes/domain/entities/client.dart';
import 'package:erp_pdv_app/modules/clientes/domain/repositories/client_repository.dart';
import 'package:erp_pdv_app/modules/clientes/presentation/providers/client_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('PDV customer lookup usa cache local sem chamar provider CRM', () async {
    final localRepository = _FakeLocalClientRepository([
      _client(id: 1, name: 'Ana Local'),
    ]);
    final crmRepository = _ThrowingClientRepository();
    final container = ProviderContainer(
      overrides: [
        localClientRepositoryProvider.overrideWithValue(localRepository),
        clientRepositoryProvider.overrideWithValue(crmRepository),
      ],
    );
    addTearDown(container.dispose);

    final clients = await container.read(
      pdvCustomerLookupProvider('Ana').future,
    );

    expect(clients.map((client) => client.name), ['Ana Local']);
    expect(localRepository.searchCount, 1);
    expect(crmRepository.searchCount, 0);
  });

  test(
    'CRM client lookup continua usando provider gerencial API-first',
    () async {
      final crmRepository = _RecordingClientRepository([
        _client(id: 2, name: 'Bruno CRM'),
      ]);
      final container = ProviderContainer(
        overrides: [
          localClientRepositoryProvider.overrideWithValue(
            _FakeLocalClientRepository([_client(id: 1, name: 'Ana Local')]),
          ),
          clientRepositoryProvider.overrideWithValue(crmRepository),
        ],
      );
      addTearDown(container.dispose);

      final clients = await container.read(
        clientLookupProvider('Bruno').future,
      );

      expect(clients.map((client) => client.name), ['Bruno CRM']);
      expect(crmRepository.searchCount, 1);
    },
  );
}

Client _client({required int id, required String name}) {
  final now = DateTime(2026, 4, 26, 10);
  return Client(
    id: id,
    uuid: 'client-$id',
    name: name,
    phone: null,
    address: null,
    notes: null,
    debtorBalanceCents: 0,
    creditBalanceCents: 0,
    isActive: true,
    createdAt: now,
    updatedAt: now,
    deletedAt: null,
  );
}

class _FakeLocalClientRepository extends SqliteClientRepository {
  _FakeLocalClientRepository(this.clients) : super(AppDatabase.instance);

  final List<Client> clients;
  int searchCount = 0;

  @override
  Future<List<Client>> search({String query = ''}) async {
    searchCount++;
    final normalizedQuery = query.trim().toLowerCase();
    if (normalizedQuery.isEmpty) {
      return clients;
    }
    return clients
        .where((client) => client.name.toLowerCase().contains(normalizedQuery))
        .toList(growable: false);
  }
}

class _ThrowingClientRepository implements ClientRepository {
  int searchCount = 0;

  @override
  Future<List<Client>> search({String query = ''}) async {
    searchCount++;
    throw StateError('CRM repository must not be used by PDV lookup.');
  }

  @override
  Future<int> create(ClientInput input) async => throw UnimplementedError();

  @override
  Future<void> update(int id, ClientInput input) async =>
      throw UnimplementedError();

  @override
  Future<void> delete(int id) async => throw UnimplementedError();
}

class _RecordingClientRepository implements ClientRepository {
  _RecordingClientRepository(this.clients);

  final List<Client> clients;
  int searchCount = 0;

  @override
  Future<List<Client>> search({String query = ''}) async {
    searchCount++;
    return clients;
  }

  @override
  Future<int> create(ClientInput input) async => throw UnimplementedError();

  @override
  Future<void> update(int id, ClientInput input) async =>
      throw UnimplementedError();

  @override
  Future<void> delete(int id) async => throw UnimplementedError();
}

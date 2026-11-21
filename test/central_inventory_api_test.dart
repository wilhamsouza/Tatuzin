import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tatuzin/app/core/errors/app_exceptions.dart';
import 'package:tatuzin/app/core/network/contracts/api_client_contract.dart';
import 'package:tatuzin/app/core/session/auth_token_storage.dart';
import 'package:tatuzin/modules/estoque/data/central_inventory_api.dart';

class InventoryTestTokens extends Fake implements AuthTokenStorage {
  @override
  Future<String?> readAccessToken() async => 'isolated-test-token';
}

class InventoryTestClient extends Fake implements ApiClientContract {
  bool offline = false, forbidden = false, failItems = false;
  final writes = <InventoryJson>[];
  InventoryJson capabilities = {
    'enabled': true,
    'canAdjust': true,
    'canCount': true,
    'canInitializeStock': true,
  };
  InventoryJson items = {
    'items': <InventoryJson>[],
    'pagination': {'total': 0},
  };
  @override
  Future<ApiResponse<InventoryJson>> getJson(
    String path, {
    ApiRequestOptions options = const ApiRequestOptions(),
  }) async {
    if (forbidden) {
      throw const NetworkRequestException('Acesso recusado', cause: 403);
    }
    if (offline) throw const NetworkRequestException('Sem conexão');
    return ApiResponse(
      statusCode: 200,
      data: path.endsWith('/capabilities') ? capabilities : items,
      headers: const {},
    );
  }

  @override
  Future<ApiResponse<InventoryJson>> postJson(
    String path, {
    InventoryJson? body,
    ApiRequestOptions options = const ApiRequestOptions(),
  }) async {
    writes.add({'method': 'POST', 'path': path, 'body': body});
    return ApiResponse(
      statusCode: 200,
      data: path.endsWith('/counts')
          ? {
              'session': {
                'id': 'server-count',
                'revision': 0,
                'assigneeUserId': 'operator',
              },
            }
          : {'item': {}},
      headers: const {},
    );
  }

  @override
  Future<ApiResponse<InventoryJson>> putJson(
    String path, {
    InventoryJson? body,
    ApiRequestOptions options = const ApiRequestOptions(),
  }) async {
    writes.add({'method': 'PUT', 'path': path, 'body': body});
    if (failItems) throw const NetworkRequestException('Resposta interrompida');
    return ApiResponse(
      statusCode: 200,
      data: {
        'session': {'id': 'server-count', 'revision': 1},
        'items': body?['items'] ?? [],
      },
      headers: const {},
    );
  }
}

CentralInventoryApi testInventoryApi(
  InventoryTestClient client, {
  String namespace = 'company-a:operator',
  String userId = 'operator',
  bool canWrite = true,
  Future<void> Function()? prepareWrite,
}) => CentralInventoryApi(
  client: client,
  tokens: InventoryTestTokens(),
  namespace: namespace,
  userId: userId,
  canWrite: canWrite,
  prepareWrite: prepareWrite ?? () async {},
  ensureCurrent: () {},
);
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
    'rascunhos persistem sem alterar saldo e ficam isolados por empresa e usuário',
    () async {
      final client = InventoryTestClient();
      final api = testInventoryApi(client);
      final draft = api.newDraft('Conferência');
      await api.saveDraft({
        ...draft,
        'items': [
          {
            'productId': 'p',
            'countedStockMil': null,
            'expectedStockRevision': 2,
          },
        ],
      });
      final restored = await testInventoryApi(client).drafts();
      expect(restored.single['requestId'], draft['requestId']);
      expect(
        inventoryRows(restored.single['items']).single['countedStockMil'],
        isNull,
      );
      expect(
        await testInventoryApi(
          client,
          namespace: 'company-b:operator',
        ).drafts(),
        isEmpty,
      );
      expect(
        await testInventoryApi(client, namespace: 'company-a:other').drafts(),
        isEmpty,
      );
      expect(client.writes, isEmpty);
      expect(
        draft['requestId'],
        matches(
          RegExp(
            r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
          ),
        ),
      );
    },
  );
  test('dois operadores do mesmo banco não compartilham rascunhos', () async {
    final client = InventoryTestClient();
    final first = testInventoryApi(
      client,
      namespace: 'same-company',
      userId: 'first',
    );
    await first.saveDraft(first.newDraft('Privado do primeiro operador'));
    final second = testInventoryApi(
      client,
      namespace: 'same-company',
      userId: 'second',
    );
    expect(await second.drafts(), isEmpty);
    expect(await first.drafts(), hasLength(1));
  });
  test(
    'confirmação bloqueia antes da API quando a sincronização está pendente',
    () async {
      final client = InventoryTestClient();
      final api = testInventoryApi(
        client,
        prepareWrite: () async {
          throw const ValidationException('Pendências locais');
        },
      );
      await expectLater(
        api.write('POST', '/adjustments', {'requestId': inventoryRequestId()}),
        throwsA(isA<ValidationException>()),
      );
      expect(client.writes, isEmpty);
    },
  );
  test(
    'consulta não concede escrita e piloto desligado bloqueia alterações',
    () async {
      final client = InventoryTestClient();
      await expectLater(
        testInventoryApi(
          client,
          canWrite: false,
        ).write('POST', '/adjustments', {}),
        throwsA(isA<ValidationException>()),
      );
      client.capabilities = {'enabled': false, 'canAdjust': true};
      await expectLater(
        testInventoryApi(client).write('POST', '/adjustments', {}),
        throwsA(isA<ValidationException>()),
      );
      expect(client.writes, isEmpty);
    },
  );
  test(
    'resposta cacheada é identificada e 403 não revela cache antigo',
    () async {
      final client = InventoryTestClient()
        ..items = {
          'items': [
            {'name': 'Produto de teste'},
          ],
        };
      final api = testInventoryApi(client);
      await api.read('');
      client.offline = true;
      expect((await api.read(''))['isCached'], isTrue);
      client.forbidden = true;
      await expectLater(api.read(''), throwsA(isA<NetworkRequestException>()));
    },
  );
  test(
    'publicação retém identidade entre criar sessão e enviar itens, preservando null e revisão',
    () async {
      final client = InventoryTestClient()..failItems = true;
      final api = testInventoryApi(client);
      final draft = {
        ...api.newDraft('Contagem'),
        'items': [
          {
            'productId': 'product',
            'productVariantId': 'variant',
            'countedStockMil': null,
            'expectedStockRevision': 4,
          },
        ],
      };
      await api.saveDraft(draft);
      await expectLater(
        api.publishDraft(draft),
        throwsA(isA<NetworkRequestException>()),
      );
      final saved = (await api.drafts()).single;
      expect(inventoryJson(saved['session'])['id'], 'server-count');
      client.failItems = false;
      await api.publishDraft(saved);
      expect(
        client.writes.where((row) => row['method'] == 'POST'),
        hasLength(1),
      );
      final body = inventoryJson(client.writes.last['body']);
      expect(body['expectedRevision'], 0);
      final item = inventoryRows(body['items']).single;
      expect(item['countedStockMil'], isNull);
      expect(item['expectedStockRevision'], 4);
      expect(await api.drafts(), isEmpty);
    },
  );
  test(
    'saldo inicial usa permissão própria sem liberar ajuste avançado',
    () async {
      final client = InventoryTestClient()
        ..capabilities = {
          'enabled': true,
          'canInitializeStock': true,
          'canAdjust': false,
        };
      final api = testInventoryApi(client);
      await api.write('POST', '/initial-balances', {
        'requestId': inventoryRequestId(),
        'quantityDeltaMil': 1000,
      });
      await expectLater(
        api.write('POST', '/adjustments', {}),
        throwsA(isA<ValidationException>()),
      );
      expect(client.writes, hasLength(1));
      expect(client.writes.single['path'], '/inventory/initial-balances');
    },
  );
}

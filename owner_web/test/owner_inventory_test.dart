import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tatuzin_owner_web/src/app/owner_web_router.dart';
import 'package:tatuzin_owner_web/src/core/auth/owner_auth_controller.dart';
import 'package:tatuzin_owner_web/src/core/auth/owner_auth_storage.dart';
import 'package:tatuzin_owner_web/src/core/auth/owner_providers.dart';
import 'package:tatuzin_owner_web/src/core/auth/owner_return_location.dart';
import 'package:tatuzin_owner_web/src/core/models/owner_models.dart';
import 'package:tatuzin_owner_web/src/core/network/owner_api_client.dart';
import 'package:tatuzin_owner_web/src/core/network/owner_api_service.dart';
import 'package:tatuzin_owner_web/src/features/inventory/data/owner_inventory_api.dart';
import 'package:tatuzin_owner_web/src/theme/owner_theme.dart';

const capabilities = {
  'enabled': true,
  'canRead': true,
  'canCount': true,
  'canAdjust': true,
  'canWriteProducts': true,
  'canReadProducts': true,
  'canViewCosts': true,
  'canTransferCounts': true,
};
const product = {
  'id': 'product-test',
  'localUuid': 'local-product-test',
  'name': 'Camiseta da loja',
  'barcode': '123456',
  'isActive': true,
  'salePriceCents': 4990,
  'costPriceCents': 2100,
  'manualCostCents': 2100,
  'costSource': 'manual',
  'unitMeasure': 'un',
  'catalogRevision': 2,
  'variants': <Object>[],
};
const stock = {
  'productId': 'product-test',
  'productVariantId': null,
  'name': 'Camiseta da loja',
  'sku': '123456',
  'unitMeasure': 'un',
  'isActive': true,
  'status': 'active',
  'currentStockMil': 5000,
  'stockRevision': 3,
  'minimumStockMil': 1000,
  'reorderPointMil': 2000,
  'updatedAt': '2026-11-15T10:00:00Z',
};
const session = {
  'id': 'count-test',
  'name': 'Conferência da loja',
  'assigneeUserId': 'user-test',
  'assigneeName': 'Responsável de teste',
  'status': 'COUNTING',
  'revision': 1,
  'updatedAt': '2026-11-15T10:00:00Z',
};
const countItem = {
  'id': 'item-test',
  'productId': 'product-test',
  'productVariantId': null,
  'productName': 'Camiseta da loja',
  'sku': '123456',
  'unitMeasure': 'un',
  'countedStockMil': null,
  'referenceStockMil': 5000,
  'currentStockMil': 5000,
  'expectedStockRevision': 3,
  'stockRevision': 3,
  'isStale': false,
};
OwnerApiClient dummyClient() => OwnerApiClient(
  baseUrl: 'https://test.invalid/api',
  authStorage: OwnerAuthStorage(),
  httpClient: MockClient((_) async => http.Response('{}', 200)),
);

class ReadyAuth extends OwnerAuthController {
  ReadyAuth()
    : super(
        apiService: OwnerApiService(
          apiClient: dummyClient(),
          authStorage: OwnerAuthStorage(),
        ),
        authStorage: OwnerAuthStorage(),
        restoreOnStart: false,
      );
  @override
  bool get isAuthenticated => true;
  @override
  bool get isRestoring => false;
  @override
  OwnerSession get session => OwnerSession.fromLoginResponse({
    'accessToken': 'fixture-only',
    'user': {
      'id': 'user-test',
      'name': 'Responsável de teste',
      'email': 'test@example.invalid',
    },
    'company': {
      'id': 'company-test',
      'name': 'Loja de teste',
      'license': {'plan': 'PRO', 'status': 'ACTIVE'},
    },
    'membership': {'id': 'membership-test', 'role': 'OWNER', 'isDefault': true},
  });
}

class RestoringAuth extends ReadyAuth {
  bool restoring = true;
  @override
  bool get isRestoring => restoring;
  @override
  bool get isAuthenticated => !restoring;
  void finish() {
    restoring = false;
    notifyListeners();
  }
}

class FakeInventoryApi extends OwnerInventoryApi {
  FakeInventoryApi({this.allowWrite = true})
    : super(dummyClient(), () async => 'fixture-only');
  final bool allowWrite;
  final reads = <String>[];
  final writes = <({String path, InventoryMap body})>[];
  InventoryMap count = Map.from(countItem);
  bool failNext = false, empty = false;
  Completer<InventoryMap>? pending;
  @override
  Future<InventoryMap> get(String resource) async {
    reads.add(resource);
    final p = Uri.parse(resource).path;
    if (p == '/inventory/capabilities') {
      return {
        ...capabilities,
        'canAdjust': allowWrite,
        'canCount': allowWrite,
        'canWriteProducts': allowWrite,
      };
    }
    if (p == '/products') {
      return {
        'items': [product],
        'pagination': {'total': 1, 'pageSize': 20},
      };
    }
    if (p == '/products/product-test') return {'product': product};
    if (p == '/categories') return {'items': <Object>[]};
    if (p == '/inventory') {
      if (pending != null) return pending!.future;
      if (failNext) {
        throw const OwnerApiException(
          message: 'Consulta indisponível',
          statusCode: 503,
        );
      }
      return {
        'items': empty ? <Object>[] : [stock],
        'pagination': {'total': empty ? 0 : 1, 'pageSize': 20},
      };
    }
    if (p == '/inventory/summary') {
      return {
        'summary': {
          'totalItemsCount': 1,
          'belowMinimumItemsCount': 0,
          'zeroedItemsCount': 0,
        },
      };
    }
    if (p == '/inventory/items/product-test') return {'item': stock};
    if (p == '/inventory/movements') {
      return {
        'items': <Object>[],
        'pagination': {'total': 0},
      };
    }
    if (p == '/inventory/counts') {
      return {
        'items': [session],
        'pagination': {'total': 1, 'pageSize': 20},
      };
    }
    if (p == '/inventory/counts/count-test') {
      return {
        'session': session,
        'items': [count],
      };
    }
    if (p == '/inventory/count-assignees') {
      return {
        'items': [
          {'userId': 'user-test', 'name': 'Responsável de teste'},
        ],
      };
    }
    return {'items': <Object>[]};
  }

  @override
  Future<InventoryMap> post(String path, InventoryMap body) async {
    writes.add((path: path, body: body));
    if (path == '/inventory/counts') return {'session': session};
    return {'item': stock, 'session': session};
  }

  @override
  Future<InventoryMap> put(String path, InventoryMap body) async {
    writes.add((path: path, body: body));
    if (path.contains('/counts/')) {
      count = {
        ...countItem,
        'countedStockMil': inventoryRows(
          body['items'],
        ).first['countedStockMil'],
      };
    }
    return {
      'product': product,
      'session': session,
      'items': [count],
    };
  }

  @override
  Future<InventoryMap> patch(String path, InventoryMap body) async {
    writes.add((path: path, body: body));
    return {'item': stock, 'session': session};
  }
}

Future<ProviderContainer> pumpInventory(
  WidgetTester tester, {
  String location = '/inventory',
  FakeInventoryApi? api,
  GlobalKey? capture,
  bool settle = true,
}) async {
  final container = ProviderContainer(
    overrides: [
      ownerAuthControllerProvider.overrideWith((ref) => ReadyAuth()),
      ownerInventoryApiProvider.overrideWithValue(api ?? FakeInventoryApi()),
    ],
  );
  addTearDown(container.dispose);
  final router = container.read(ownerRouterProvider);
  router.go(location);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        theme: OwnerTheme.light(),
        routerConfig: router,
        builder: (context, child) =>
            RepaintBoundary(key: capture, child: child!),
      ),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump(const Duration(milliseconds: 500));
  }
  return container;
}

Finder field(String label) => find.byWidgetPredicate(
  (w) => w is TextField && w.decoration?.labelText == label,
);
void main() {
  setUpAll(() async {
    final loader = FontLoader('NotoSans');
    loader.addFont(rootBundle.load('assets/fonts/NotoSans-Regular.ttf'));
    loader.addFont(rootBundle.load('assets/fonts/NotoSans-Bold.ttf'));
    await loader.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
    'retorno de autenticação aceita somente destinos locais com filtros',
    () {
      expect(
        ownerReturnLocation('/inventory?tab=counts&page=2'),
        '/inventory?tab=counts&page=2',
      );
      expect(
        ownerReturnLocation('/products?search=camiseta'),
        '/products?search=camiseta',
      );
      for (final input in <String?>[
        null,
        'https://example.invalid',
        '//example.invalid',
        '/\\example.invalid',
        '/login?from=/inventory',
        '/',
      ]) {
        expect(ownerReturnLocation(input), isNull, reason: input);
      }
    },
  );
  test('quantidades e moeda mantêm precisão sem arredondamento silencioso', () {
    expect(inventoryScaled('1,125'), 1125);
    expect(inventoryScaled('0'), 0);
    expect(inventoryScaled(''), isNull);
    expect(inventoryScaled('-1'), isNull);
    expect(inventoryScaled('12,34', scale: 100), 1234);
    expect(inventoryScaled('12,345', scale: 100), isNull);
    expect(inventoryScaled('2147484'), isNull);
  });
  for (final width in [360, 390, 768, 1280, 1440]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('Produtos e Estoque $width texto $scale', (tester) async {
        tester.view.physicalSize = Size(width.toDouble(), 1000);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final capture = GlobalKey();
        final c = await pumpInventory(tester, capture: capture);
        expect(find.text('Saldos'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.runAsync(() async {
          final image =
              await (capture.currentContext!.findRenderObject()
                      as RenderRepaintBoundary)
                  .toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await Directory('build/products-stock').create(recursive: true);
          await File(
            'build/products-stock/owner-$width-$scale.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
        for (final route in [
          '/products?search=camiseta',
          '/products/product-test',
          '/inventory?tab=movements',
          '/inventory?tab=counts',
          '/inventory/counts/count-test',
          '/inventory/items/product-test',
        ]) {
          c.read(ownerRouterProvider).go(route);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: route);
        }
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }
  testWidgets(
    'restauração preserva rota e filtros sem consultas ou dados antigos',
    (tester) async {
      final auth = RestoringAuth();
      final api = FakeInventoryApi();
      final c = ProviderContainer(
        overrides: [
          ownerAuthControllerProvider.overrideWith((_) => auth),
          ownerInventoryApiProvider.overrideWithValue(api),
        ],
      );
      addTearDown(c.dispose);
      final router = c.read(ownerRouterProvider);
      router.go('/inventory?tab=counts&page=2');
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: MaterialApp.router(
            theme: OwnerTheme.light(),
            routerConfig: router,
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Restaurando acesso…'), findsOneWidget);
      expect(api.reads, isEmpty);
      expect(
        router.routeInformationProvider.value.uri.toString(),
        '/inventory?tab=counts&page=2',
      );
      auth.finish();
      await tester.pumpAndSettle();
      expect(find.text('Restaurando acesso…'), findsNothing);
      expect(find.text('Contagens'), findsOneWidget);
      expect(
        router.routeInformationProvider.value.uri.toString(),
        '/inventory?tab=counts&page=2',
      );
      expect(api.reads, contains('/inventory/counts?page=2&pageSize=20'));
    },
  );
  testWidgets('ajuste só executa após prévia e confirmação', (tester) async {
    final api = FakeInventoryApi();
    await pumpInventory(
      tester,
      location: '/inventory/items/product-test',
      api: api,
    );
    await tester.ensureVisible(find.text('Movimentar estoque'));
    await tester.tap(find.text('Movimentar estoque'));
    await tester.pumpAndSettle();
    await tester.enterText(field('Quantidade (un)'), '2');
    await tester.enterText(field('Motivo obrigatório'), 'Reposição conferida');
    await tester.tap(find.text('Revisar movimentação'));
    await tester.pumpAndSettle();
    expect(api.writes, isEmpty);
    expect(find.textContaining('Saldo previsto: 7 un'), findsOneWidget);
    await tester.tap(find.text('Confirmar'));
    await tester.pumpAndSettle();
    expect(api.writes.length, 1);
    expect(api.writes.single.path, '/inventory/adjustments');
    expect(api.writes.single.body['quantityDeltaMil'], 2000);
    expect(api.writes.single.body['expectedRevision'], 3);
    expect(
      api.writes.single.body['requestId'],
      matches(RegExp(r'^[a-f0-9-]{36}$')),
    );
    expect(find.text('Revisar movimentação'), findsNothing);
  });
  testWidgets(
    'contagem não converte pendência em zero nem aplica antes da revisão',
    (tester) async {
      final api = FakeInventoryApi();
      await pumpInventory(
        tester,
        location: '/inventory/counts/count-test',
        api: api,
      );
      expect(find.textContaining('0 de 1 itens contados'), findsOneWidget);
      expect(find.text('Aplicar ao estoque'), findsNothing);
      expect(find.text('Revisar contagem'), findsNothing);
      await tester.ensureVisible(find.text('Informar contagem'));
      await tester.tap(find.text('Informar contagem'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Salvar contagem'));
      await tester.pumpAndSettle();
      expect(api.writes, isEmpty);
      await tester.enterText(field('Quantidade física (un)'), '0');
      await tester.tap(find.text('Salvar contagem'));
      await tester.pumpAndSettle();
      expect(api.writes.single.path, '/inventory/counts/count-test/items');
      expect(
        inventoryRows(
          api.writes.single.body['items'],
        ).single['countedStockMil'],
        0,
      );
      expect(
        inventoryRows(
          api.writes.single.body['items'],
        ).single['expectedStockRevision'],
        3,
      );
    },
  );
  testWidgets('edição cadastral envia metadados sem saldo e preserva revisão', (
    tester,
  ) async {
    final api = FakeInventoryApi();
    await pumpInventory(tester, location: '/products/product-test', api: api);
    await tester.tap(find.text('Editar produto'));
    await tester.pumpAndSettle();
    await tester.enterText(field('Nome do produto'), 'Camiseta atualizada');
    await tester.tap(find.text('Salvar produto'));
    await tester.pumpAndSettle();
    expect(api.writes.length, 1);
    final body = api.writes.single.body;
    expect(body['metadataOnly'], true);
    expect(body['expectedCatalogRevision'], 2);
    expect(body.containsKey('stockMil'), false);
    expect(body.containsKey('costPriceCents'), false);
    expect(body.containsKey('modifierGroups'), false);
    expect(body['name'], 'Camiseta atualizada');
  });
  testWidgets('sem permissão esconde edição e ajuste', (tester) async {
    final api = FakeInventoryApi(allowWrite: false);
    final c = await pumpInventory(
      tester,
      location: '/products/product-test',
      api: api,
    );
    expect(find.text('Editar produto'), findsNothing);
    c.read(ownerRouterProvider).go('/inventory/items/product-test');
    await tester.pumpAndSettle();
    expect(find.text('Movimentar estoque'), findsNothing);
    expect(find.text('Reposição'), findsNothing);
    expect(api.writes, isEmpty);
  });
  testWidgets('carregamento, vazio e erro de saldo preservam o resumo', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final pending = Completer<InventoryMap>();
    final api = FakeInventoryApi()..pending = pending;
    final key = GlobalKey();
    final c = await pumpInventory(
      tester,
      api: api,
      capture: key,
      settle: false,
    );
    Future<void> capture(String name) async {
      await tester.runAsync(() async {
        final image =
            await (key.currentContext!.findRenderObject()
                    as RenderRepaintBoundary)
                .toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await Directory('build/products-stock').create(recursive: true);
        await File(
          'build/products-stock/owner-state-$name.png',
        ).writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }

    expect(find.text('Carregando dados…'), findsWidgets);
    await capture('loading');
    api.pending = null;
    pending.complete({
      'items': [stock],
      'pagination': {'total': 1, 'pageSize': 20},
    });
    await tester.pumpAndSettle();
    api.failNext = true;
    c.invalidate(ownerInventoryResourceProvider);
    await tester.pumpAndSettle();
    expect(find.textContaining('Itens monitorados:'), findsOneWidget);
    expect(find.textContaining('Consulta indisponível'), findsOneWidget);
    await capture('error-partial');
    api.failNext = false;
    api.empty = true;
    c.invalidate(ownerInventoryResourceProvider);
    await tester.pumpAndSettle();
    expect(
      find.text('Nenhum item encontrado para os filtros selecionados.'),
      findsOneWidget,
    );
    await capture('empty');
    api.empty = false;
    c.invalidate(ownerInventoryResourceProvider);
    await tester.pumpAndSettle();
    expect(find.textContaining('Consulta indisponível'), findsNothing);
    expect(find.text('Camiseta da loja'), findsOneWidget);
  });
  test('fixtures do navegador identificam somente dados de teste', () async {
    await Directory('build/products-stock').create(recursive: true);
    await File('build/products-stock/browser-fixtures.json').writeAsString(
      jsonEncode({
        'storageKey': 'flutter.tatuzin_owner_access_token',
        'token': 'ISOLATED_OWNER_BROWSER_FIXTURE',
        'identity': {
          'user': {
            'id': 'user-test',
            'name': 'Responsável de demonstração',
            'email': 'test@example.invalid',
          },
          'company': {
            'id': 'company-test',
            'name': 'Loja de demonstração',
            'license': {'plan': 'PRO', 'status': 'ACTIVE'},
          },
          'membership': {
            'id': 'membership-test',
            'role': 'OWNER',
            'isDefault': true,
          },
        },
        'capabilities': capabilities,
        'product': product,
        'stock': stock,
        'session': session,
        'countItem': countItem,
      }),
    );
  });
}

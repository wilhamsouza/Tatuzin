import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tatuzin_admin_web/src/app/admin_web_app.dart';
import 'package:tatuzin_admin_web/src/app/admin_web_router.dart';
import 'package:tatuzin_admin_web/src/core/auth/admin_auth_controller.dart';
import 'package:tatuzin_admin_web/src/core/auth/admin_auth_storage.dart';
import 'package:tatuzin_admin_web/src/core/auth/admin_providers.dart';
import 'package:tatuzin_admin_web/src/core/models/admin_models.dart';
import 'package:tatuzin_admin_web/src/core/network/admin_api_client.dart';
import 'package:tatuzin_admin_web/src/core/network/admin_api_service.dart';
import 'package:tatuzin_admin_web/src/features/platform/data/platform_api.dart';

final cap = <String, dynamic>{
  'experienceEnabled': true,
  'sections': [
    for (final key in [
      'overview',
      'companies',
      'support',
      'sync',
      'billing',
      'devices',
      'usage',
      'audit',
      'administration',
    ])
      {'key': key, 'allowed': true},
  ],
  'actions': [
    for (final key in [
      'admin.support.manage',
      'license.extend',
      'access.block',
    ])
      {
        'key': key,
        'allowed': true,
        'scopes': [
          {'scope': 'platform', 'scopeId': '*'},
        ],
      },
  ],
  'templates': [],
};
const identity = <String, dynamic>{
  'user': {
    'id': 'admin-test',
    'name': 'Administrador de demonstração',
    'email': 'admin@test.invalid',
    'isPlatformAdmin': true,
  },
  'company': {
    'id': 'company-test',
    'name': 'Empresa de demonstração',
    'slug': 'demo',
  },
  'membership': {'id': 'membership-test', 'role': 'OWNER'},
};
const sampleCase = <String, dynamic>{
  'id': 'case-test',
  'companyId': 'company-test',
  'companyName': 'Empresa de demonstração',
  'subject': 'Verificar sincronização',
  'description': 'Descrição de teste',
  'priority': 'NORMAL',
  'status': 'OPEN',
  'revision': 0,
  'createdAt': '2026-11-14T10:00:00Z',
  'updatedAt': '2026-11-14T10:00:00Z',
  'events': [],
};
PlatformMap overview() => {
  'generatedAt': '2026-11-14T10:00:00Z',
  'period': {'timezone': 'UTC'},
  'companies': {
    'available': true,
    'total': 125,
    'newInPeriod': 3,
    'series': [
      {'date': '2026-11-14', 'count': 3},
    ],
  },
  'subscriptions': {'available': true, 'activePaid': 20},
  'billing': {'available': false, 'reason': 'SOURCE_UNAVAILABLE'},
  'operations': {'available': true, 'problemCompanies': 0, 'items': []},
  'support': {
    'available': true,
    'openCount': 1,
    'mine': [sampleCase],
  },
  'audit': {'available': true, 'items': []},
};

class ReadyAuth extends AdminAuthController {
  ReadyAuth()
    : super(
        apiService: AdminApiService(
          apiClient: AdminApiClient(
            baseUrl: 'https://test.invalid',
            authStorage: AdminAuthStorage(),
          ),
          authStorage: AdminAuthStorage(),
        ),
        authStorage: AdminAuthStorage(),
      );
  @override
  Future<void> restoreSession() async {}
  @override
  AdminSession get session => AdminSession.fromLoginResponse({
    ...identity,
    'accessToken': 'fake-test-token',
  });
  @override
  bool get isAuthenticated => true;
  @override
  bool get isPlatformAdmin => true;
  @override
  bool get isRestoring => false;
}

class TestApi extends PlatformApi {
  TestApi()
    : super(
        AdminApiClient(
          baseUrl: 'https://test.invalid',
          authStorage: AdminAuthStorage(),
        ),
        AdminAuthStorage(),
      );
  final calls = <String>[];
  final bodies = <PlatformMap>[];
  @override
  Future<PlatformMap> get(String resource) async {
    calls.add(resource);
    final path = Uri.parse(resource).path;
    if (path == '/admin/capabilities') return cap;
    if (path == '/admin/overview') return overview();
    if (path.endsWith('/access-summary')) {
      return {
        'employees': [
          {
            'employeeProfileId': 'employee-test',
            'name': 'Operador de teste',
            'employeeRole': 'SELLER',
            'status': 'ACTIVE',
          },
        ],
      };
    }
    if (path == '/admin/search') {
      return {
        'total': 1,
        'groups': [
          {
            'type': 'company',
            'items': [
              {
                'id': 'company-test',
                'companyId': 'company-test',
                'label': 'Empresa de demonstração',
                'subtitle': 'demo',
                'href': '/companies/company-test',
              },
            ],
          },
        ],
      };
    }
    if (path == '/admin/support/cases/case-test') return {'item': sampleCase};
    if (path == '/admin/support/cases') {
      return {
        'items': [sampleCase],
        'total': 1,
      };
    }
    if (path == '/admin/platform-companies') {
      return {
        'items': [
          {
            'id': 'company-test',
            'name': 'Empresa de demonstração',
            'slug': 'demo',
          },
        ],
        'pagination': {'total': 125, 'page': 2, 'pageSize': 20},
      };
    }
    if (path == '/admin/companies/company-test') {
      return {
        'company': {
          'id': 'company-test',
          'name': 'Empresa de demonstração',
          'slug': 'demo',
          'license': {'plan': 'PRO', 'status': 'ACTIVE'},
        },
      };
    }
    if (path == '/admin/usage') {
      return {
        'activeCompanies': 1,
        'events': [
          {'name': 'sale_completed', 'count': 2},
        ],
        'versions': [
          {'appVersion': '1.0.3', 'count': 2},
        ],
      };
    }
    return {'items': [], 'total': 0};
  }

  @override
  Future<PlatformMap> post(String resource, PlatformMap body) async {
    calls.add(resource);
    bodies.add(body);
    if (resource.endsWith('/preview')) {
      return {
        'previewId': 'preview-test',
        'allowed': true,
        'summary': 'Prorrogar por um dia',
        'expectedConfirmationText': 'ESTENDER',
        'expiresAt': '2026-11-14T11:00:00Z',
      };
    }
    if (resource.endsWith('/execute')) {
      return {'ok': true, 'status': 'succeeded'};
    }
    return {'item': sampleCase};
  }
}

class DelayedApi extends TestApi {
  final first = Completer<PlatformMap>();
  int reads = 0;
  @override
  Future<PlatformMap> get(String resource) {
    if (Uri.parse(resource).path == '/admin/overview' && reads++ == 0) {
      return first.future;
    }
    return super.get(resource);
  }
}

class ReadOnlyApi extends TestApi {
  @override
  Future<PlatformMap> get(String resource) async =>
      Uri.parse(resource).path == '/admin/capabilities'
      ? {...cap, 'actions': []}
      : super.get(resource);
}

Future<void> stateCapture(
  WidgetTester tester,
  GlobalKey key,
  String name,
) async {
  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await Directory('build/admin-platform').create(recursive: true);
    await File(
      'build/admin-platform/$name.png',
    ).writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

Future<({ProviderContainer container, TestApi api})> pump(
  WidgetTester tester, {
  String route = '/dashboard',
  GlobalKey? capture,
  TestApi? apiOverride,
  bool settle = true,
}) async {
  final fonts = FontLoader('NotoSans')
    ..addFont(rootBundle.load('assets/fonts/NotoSans-Regular.ttf'))
    ..addFont(rootBundle.load('assets/fonts/NotoSans-Bold.ttf'));
  await fonts.load();
  final icons = FontLoader('MaterialIcons')
    ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
  await icons.load();
  final api = apiOverride ?? TestApi();
  final container = ProviderContainer(
    overrides: [
      adminAuthControllerProvider.overrideWith((_) => ReadyAuth()),
      platformApiProvider.overrideWithValue(api),
    ],
  );
  addTearDown(container.dispose);
  container.read(adminRouterProvider).go(route);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: RepaintBoundary(key: capture, child: const AdminWebApp()),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }
  return (container: container, api: api);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  for (final width in [360, 390, 768, 1280, 1440]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('plataforma responsiva $width texto $scale', (tester) async {
        tester.view.physicalSize = Size(width.toDouble(), 960);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final key = GlobalKey();
        final test = await pump(tester, capture: key);
        expect(find.text('Empresas cadastradas'), findsOneWidget);
        expect(find.text('125'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.runAsync(() async {
          final boundary =
              key.currentContext!.findRenderObject() as RenderRepaintBoundary;
          final img = await boundary.toImage(pixelRatio: 1);
          final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
          await Directory('build/admin-platform').create(recursive: true);
          await File(
            'build/admin-platform/$width-$scale-overview.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
          img.dispose();
        });
        for (final route in [
          '/companies?search=demo&page=2',
          '/support/cases',
          '/support',
          '/commercial',
          '/billing',
          '/billing/company-test',
          '/devices',
          '/sync',
          '/audit',
          '/usage',
          '/administration',
          '/companies/company-test',
          '/companies/company-test/operations',
          '/companies/company-test/commercial',
          '/support/cases/case-test',
        ]) {
          test.container.read(adminRouterProvider).go(route);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: route);
        }
        if (width < 768) {
          await tester.tap(find.byTooltip('Abrir menu'));
          await tester.pumpAndSettle();
          expect(find.text('Tatuzin Admin'), findsOneWidget);
          expect(tester.takeException(), isNull);
        }
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }
  testWidgets('busca usa debounce e fechar preserva a rota real', (
    tester,
  ) async {
    final test = await pump(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    final field = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(TextField),
    );
    await tester.enterText(field, 'dem');
    await tester.pump(const Duration(milliseconds: 100));
    expect(test.api.calls.where((r) => r.contains('q=dem')), isEmpty);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(test.api.calls.any((r) => r.contains('q=dem')), isTrue);
    await tester.tap(find.text('Fechar'));
    await tester.pumpAndSettle();
    expect(
      test.container
          .read(adminRouterProvider)
          .routeInformationProvider
          .value
          .uri
          .path,
      '/dashboard',
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
    'prévia e confirmação precedem a execução e preservam a empresa',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final test = await pump(
        tester,
        route: '/companies/company-test/operations',
      );
      await tester.tap(find.byType(DropdownButtonFormField<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Prorrogar licença').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField).first,
        'Atendimento com extensão de teste',
      );
      await tester.ensureVisible(find.text('Ver prévia de impacto'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ver prévia de impacto'));
      await tester.pumpAndSettle();
      expect(test.api.calls.where((r) => r.endsWith('/execute')), isEmpty);
      await tester.ensureVisible(find.text('Confirmação'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'ESTENDER');
      await tester.ensureVisible(find.text('Confirmar operação'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirmar operação'));
      await tester.pumpAndSettle();
      expect(test.api.bodies.last['previewId'], 'preview-test');
      expect(test.api.calls.where((r) => r.endsWith('/execute')).length, 1);
      expect(
        test.container
            .read(adminRouterProvider)
            .routeInformationProvider
            .value
            .uri
            .path,
        '/companies/company-test/operations',
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets('seletor de acesso usa employeeProfileId do contrato real', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final test = await pump(
      tester,
      route: '/companies/company-test/operations',
    );
    await tester.tap(find.byType(DropdownButtonFormField<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bloquear acesso').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<String>).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Operador de teste').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField).first,
      'Testar o bloqueio autorizado de acesso',
    );
    await tester.ensureVisible(find.text('Ver prévia de impacto'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ver prévia de impacto'));
    await tester.pumpAndSettle();
    expect(test.api.bodies.last['targetId'], 'employee-test');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
    'novo chamado em tela pequena salva e abre o detalhe sem perder a navegação',
    (tester) async {
      tester.view.physicalSize = const Size(390, 960);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final test = await pump(tester, route: '/companies/company-test/support');
      await tester.ensureVisible(find.text('Novo chamado'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Novo chamado'));
      await tester.pumpAndSettle();
      final fields = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      );
      await tester.enterText(fields.at(0), 'Problema de sincronização');
      await tester.enterText(
        fields.at(1),
        'Diagnóstico feito com dados exclusivamente de teste.',
      );
      await tester.tap(find.text('Criar chamado'));
      await tester.pumpAndSettle();
      expect(test.api.bodies.last['companyId'], 'company-test');
      expect(test.api.bodies.last['requestKey'], isNotEmpty);
      expect(
        test.container
            .read(adminRouterProvider)
            .routeInformationProvider
            .value
            .uri
            .path,
        '/support/cases/case-test',
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets('carregamento erro e recuperação mantêm o painel usável', (
    tester,
  ) async {
    final api = DelayedApi();
    final key = GlobalKey();
    await pump(tester, apiOverride: api, settle: false, capture: key);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    await stateCapture(tester, key, 'state-loading');
    api.first.completeError(
      const AdminApiException(
        message: 'Fonte de teste temporariamente indisponível',
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Fonte de teste'), findsOneWidget);
    await stateCapture(tester, key, 'state-error');
    await tester.tap(find.text('Tentar novamente'));
    await tester.pumpAndSettle();
    expect(find.text('125'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('sem concessão operacional não exibe ações de alteração', (
    tester,
  ) async {
    final key = GlobalKey();
    final test = await pump(
      tester,
      route: '/companies/company-test/operations',
      apiOverride: ReadOnlyApi(),
      capture: key,
    );
    expect(find.text('Ver prévia de impacto'), findsNothing);
    expect(find.textContaining('não possui operações'), findsOneWidget);
    expect(test.api.bodies, isEmpty);
    await stateCapture(tester, key, 'state-permission');
    await tester.pumpWidget(const SizedBox.shrink());
  });
  test(
    'fixtures para a checagem de navegador não contêm dados reais',
    () async {
      await Directory('build/admin-platform').create(recursive: true);
      await File('build/admin-platform/browser-fixtures.json').writeAsString(
        jsonEncode({
          'identity': identity,
          'capabilities': cap,
          'overview': overview(),
          'case': sampleCase,
        }),
      );
    },
  );
}

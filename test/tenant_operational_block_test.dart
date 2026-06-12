import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tatuzin/app/core/errors/app_exceptions.dart';
import 'package:tatuzin/app/core/network/endpoint_config.dart';
import 'package:tatuzin/app/core/session/app_session.dart';
import 'package:tatuzin/app/core/session/app_user.dart';
import 'package:tatuzin/app/core/session/company_context.dart';
import 'package:tatuzin/app/core/session/tenant_operational_block.dart';
import 'package:tatuzin/app/core/widgets/tenant_pending_deletion_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(const <String, Object>{});
  });

  test('persiste apenas marcador e reconhecimento local do bloqueio', () async {
    const storage = SharedPreferencesTenantOperationalBlockStorage();
    final detectedAt = DateTime.utc(2026, 6, 11, 12);
    final acknowledgedAt = DateTime.utc(2026, 6, 11, 13);

    await storage.save(
      TenantOperationalBlock(
        companyId: 'company-1',
        companyName: 'Cafe Tatuzin',
        detectedAt: detectedAt,
        acknowledgedAt: acknowledgedAt,
      ),
    );

    final restored = await storage.load();
    expect(restored?.companyId, 'company-1');
    expect(restored?.companyName, 'Cafe Tatuzin');
    expect(restored?.detectedAt, detectedAt);
    expect(restored?.acknowledgedAt, acknowledgedAt);
  });

  test('bloqueia escrita apenas para o tenant marcado', () {
    final block = TenantOperationalBlock(
      companyId: 'company-1',
      companyName: 'Cafe Tatuzin',
      detectedAt: DateTime.utc(2026, 6, 11, 12),
    );

    expect(
      () => ensureTenantOperationalWriteAllowed(
        block,
        _remoteSession('company-1'),
      ),
      throwsA(isA<TenantPendingDeletionException>()),
    );
    expect(
      () => ensureTenantOperationalWriteAllowed(
        block,
        _remoteSession('company-2'),
      ),
      returnsNormally,
    );
  });

  test('sessao online limpa marcador mesmo durante carga inicial', () async {
    final storage = _MemoryTenantOperationalBlockStorage(
      TenantOperationalBlock(
        companyId: 'company-1',
        companyName: 'Cafe Tatuzin',
        detectedAt: DateTime.utc(2026, 6, 11, 12),
      ),
    );
    final container = ProviderContainer(
      overrides: [
        tenantOperationalBlockStorageProvider.overrideWith((ref) => storage),
        tenantDeletionAcknowledgementTokenStorageProvider.overrideWith(
          (ref) => _MemoryAcknowledgementTokenStorage(),
        ),
      ],
    );
    addTearDown(container.dispose);

    await container
        .read(tenantOperationalBlockControllerProvider.notifier)
        .clearIfOperational('company-1');

    expect(await storage.load(), isNull);
    expect(
      await container.read(tenantOperationalBlockControllerProvider.future),
      isNull,
    );
  });

  test('agenda e envia acknowledgement quando ha capability', () async {
    final storage = _MemoryTenantOperationalBlockStorage(null);
    final tokenStorage = _MemoryAcknowledgementTokenStorage();
    final sender = _MemoryAcknowledgementSender();
    final container = ProviderContainer(
      overrides: [
        tenantOperationalBlockStorageProvider.overrideWith((ref) => storage),
        tenantDeletionAcknowledgementTokenStorageProvider.overrideWith(
          (ref) => tokenStorage,
        ),
        tenantDeletionAcknowledgementSenderProvider.overrideWith(
          (ref) => sender,
        ),
      ],
    );
    addTearDown(container.dispose);

    await container
        .read(tenantOperationalBlockControllerProvider.notifier)
        .markPendingDeletion(
          companyId: 'company-1',
          companyName: 'Cafe Tatuzin',
          acknowledgementToken: 'signed-ack-token',
          tenantDeletionRequestId: 'request-1',
          clientInstanceId: 'device-1',
          platform: 'android',
          appVersion: '1.0.0',
        );
    await _waitUntil(() => sender.calls == 1);

    final block = await container.read(
      tenantOperationalBlockControllerProvider.future,
    );
    expect(block?.isRemotelyAcknowledged, isTrue);
    expect(block?.companyId, 'company-1');
    expect(tokenStorage.token, isNull);
  });

  test('falha de envio preserva bloqueio e respeita backoff', () async {
    final storage = _MemoryTenantOperationalBlockStorage(null);
    final tokenStorage = _MemoryAcknowledgementTokenStorage();
    final sender = _MemoryAcknowledgementSender(shouldFail: true);
    final container = ProviderContainer(
      overrides: [
        tenantOperationalBlockStorageProvider.overrideWith((ref) => storage),
        tenantDeletionAcknowledgementTokenStorageProvider.overrideWith(
          (ref) => tokenStorage,
        ),
        tenantDeletionAcknowledgementSenderProvider.overrideWith(
          (ref) => sender,
        ),
      ],
    );
    addTearDown(container.dispose);

    final controller = container.read(
      tenantOperationalBlockControllerProvider.notifier,
    );
    await controller.markPendingDeletion(
      companyId: 'company-1',
      acknowledgementToken: 'signed-ack-token',
      tenantDeletionRequestId: 'request-1',
      clientInstanceId: 'device-1',
    );
    await _waitUntil(() => sender.calls == 1);
    await controller.attemptPendingAcknowledgement();

    final block = await container.read(
      tenantOperationalBlockControllerProvider.future,
    );
    expect(sender.calls, 1);
    expect(block?.appliesTo(_remoteSession('company-1')), isTrue);
    expect(block?.isRemotelyAcknowledged, isFalse);
    expect(block?.acknowledgementAttemptCount, 1);
    expect(block?.acknowledgementNextAttemptAt, isNotNull);
    expect(tokenStorage.token, 'signed-ack-token');
  });

  test('envio nao inclui tokens de sessao nem Authorization', () async {
    late http.Request captured;
    final sender = HttpTenantDeletionAcknowledgementSender(
      const EndpointConfig(
        baseUrl: 'https://api.tatuzin.test',
        apiVersion: EndpointConfig.defaultApiVersion,
      ),
      httpClient: MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode({
            'ok': true,
            'acknowledgedAt': '2026-06-12T12:00:00.000Z',
          }),
          200,
        );
      }),
    );

    await sender.send(
      block: TenantOperationalBlock(
        companyId: 'company-1',
        companyName: null,
        detectedAt: DateTime.utc(2026, 6, 12),
        tenantDeletionRequestId: 'request-1',
        clientInstanceId: 'device-1',
        platform: 'android',
        appVersion: '1.0.0',
      ),
      acknowledgementToken: 'signed-ack-token',
    );

    final body = jsonDecode(captured.body) as Map<String, dynamic>;
    expect(
      captured.headers.keys.map((key) => key.toLowerCase()),
      isNot(contains('authorization')),
    );
    expect(body['acknowledgementToken'], 'signed-ack-token');
    expect(jsonEncode(body), isNot(contains('access_token')));
    expect(jsonEncode(body), isNot(contains('refresh_token')));
    expect(jsonEncode(body), isNot(contains('password')));
  });

  testWidgets('tela informa bloqueio sem oferecer exclusao local', (
    tester,
  ) async {
    var acknowledged = false;
    await tester.pumpWidget(
      MaterialApp(
        home: TenantPendingDeletionPage(
          block: TenantOperationalBlock(
            companyId: 'company-1',
            companyName: 'Cafe Tatuzin',
            detectedAt: DateTime.utc(2026, 6, 11, 12),
          ),
          onAcknowledge: () {
            acknowledged = true;
          },
        ),
      ),
    );

    expect(find.text('Empresa em processo de exclusao'), findsOneWidget);
    expect(
      find.textContaining('nao foram apagados automaticamente'),
      findsOneWidget,
    );
    expect(find.text('Excluir dados locais'), findsNothing);
    expect(find.text('Excluir empresa'), findsNothing);
    expect(
      find.textContaining('registro deste dispositivo sera enviado'),
      findsOneWidget,
    );

    final acknowledgeButton = find.byKey(
      const Key('tenant-pending-deletion-acknowledge'),
    );
    await tester.ensureVisible(acknowledgeButton);
    await tester.tap(acknowledgeButton);
    expect(acknowledged, isTrue);
  });
}

AppSession _remoteSession(String companyId) {
  return AppSession(
    scope: SessionScope.authenticatedRemote,
    user: const AppUser(
      localId: null,
      remoteId: 'user-1',
      displayName: 'Operador',
      email: 'operador@tatuzin.test',
      roleLabel: 'Operador',
      kind: AppUserKind.remoteAuthenticated,
    ),
    company: CompanyContext(
      localId: null,
      remoteId: companyId,
      displayName: 'Cafe Tatuzin',
      legalName: 'Cafe Tatuzin',
      documentNumber: null,
      syncEnabled: true,
    ),
    startedAt: DateTime.utc(2026, 6, 11, 12),
    isOfflineFallback: false,
    clientInstanceId: 'device-1',
  );
}

class _MemoryTenantOperationalBlockStorage
    implements TenantOperationalBlockStorage {
  _MemoryTenantOperationalBlockStorage(this.block);

  TenantOperationalBlock? block;

  @override
  Future<void> clear() async {
    block = null;
  }

  @override
  Future<TenantOperationalBlock?> load() async => block;

  @override
  Future<void> save(TenantOperationalBlock block) async {
    this.block = block;
  }
}

class _MemoryAcknowledgementTokenStorage
    implements TenantDeletionAcknowledgementTokenStorage {
  String? token;

  @override
  Future<void> clear() async {
    token = null;
  }

  @override
  Future<String?> read() async => token;

  @override
  Future<void> save(String token) async {
    this.token = token;
  }
}

class _MemoryAcknowledgementSender
    implements TenantDeletionAcknowledgementSender {
  _MemoryAcknowledgementSender({this.shouldFail = false});

  final bool shouldFail;
  int calls = 0;

  @override
  Future<TenantDeletionAcknowledgementResult> send({
    required TenantOperationalBlock block,
    required String acknowledgementToken,
  }) async {
    calls++;
    if (shouldFail) {
      throw const NetworkRequestException('offline');
    }
    return TenantDeletionAcknowledgementResult(
      acknowledgedAt: DateTime.utc(2026, 6, 12, 12),
    );
  }
}

Future<void> _waitUntil(bool Function() predicate) async {
  for (var index = 0; index < 50; index++) {
    if (predicate()) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('Condition was not reached in time.');
}

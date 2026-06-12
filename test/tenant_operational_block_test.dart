import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tatuzin/app/core/errors/app_exceptions.dart';
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

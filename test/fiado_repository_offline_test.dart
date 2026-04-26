import 'dart:async';

import 'package:erp_pdv_app/app/core/app_context/app_operational_context.dart';
import 'package:erp_pdv_app/app/core/app_context/data_access_policy.dart';
import 'package:erp_pdv_app/app/core/config/app_data_mode.dart';
import 'package:erp_pdv_app/app/core/config/app_environment.dart';
import 'package:erp_pdv_app/app/core/network/endpoint_config.dart';
import 'package:erp_pdv_app/app/core/network/remote_feature_diagnostic.dart';
import 'package:erp_pdv_app/app/core/session/app_session.dart';
import 'package:erp_pdv_app/app/core/session/app_user.dart';
import 'package:erp_pdv_app/app/core/session/company_context.dart';
import 'package:erp_pdv_app/modules/fiado/data/datasources/fiado_remote_datasource.dart';
import 'package:erp_pdv_app/modules/fiado/data/fiado_repository_impl.dart';
import 'package:erp_pdv_app/modules/fiado/data/models/remote_fiado_payment_record.dart';
import 'package:erp_pdv_app/modules/fiado/domain/entities/fiado_account.dart';
import 'package:erp_pdv_app/modules/fiado/domain/entities/fiado_detail.dart';
import 'package:erp_pdv_app/modules/fiado/domain/entities/fiado_payment_entry.dart';
import 'package:erp_pdv_app/modules/fiado/domain/entities/fiado_payment_input.dart';
import 'package:erp_pdv_app/modules/fiado/domain/repositories/fiado_repository.dart';
import 'package:erp_pdv_app/modules/vendas/domain/entities/sale_enums.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('fiado lista offline sem aguardar canReachRemote bloqueante', () async {
    final localRepository = _FakeFiadoRepository();
    final remoteDatasource = _BlockingFiadoRemoteDatasource();
    final repository = _repository(localRepository, remoteDatasource);

    final accounts = await repository.search().timeout(
      const Duration(milliseconds: 100),
    );

    expect(accounts, hasLength(1));
    expect(localRepository.searchCount, 1);
    expect(remoteDatasource.canReachCalls, 1);
    remoteDatasource.releaseAll();
  });

  test('fiado detalhe abre offline pelo cache local', () async {
    final localRepository = _FakeFiadoRepository();
    final remoteDatasource = _BlockingFiadoRemoteDatasource();
    final repository = _repository(localRepository, remoteDatasource);

    final detail = await repository
        .fetchDetail(1)
        .timeout(const Duration(milliseconds: 100));

    expect(detail.account.id, 1);
    expect(localRepository.detailCount, 1);
    expect(remoteDatasource.canReachCalls, 1);
    remoteDatasource.releaseAll();
  });

  test(
    'pagamento de fiado grava local antes de qualquer disponibilidade remota',
    () async {
      final localRepository = _FakeFiadoRepository();
      final remoteDatasource = _BlockingFiadoRemoteDatasource();
      final repository = _repository(localRepository, remoteDatasource);

      final detail = await repository
          .registerPayment(
            const FiadoPaymentInput(
              fiadoId: 1,
              amountCents: 5000,
              paymentMethod: PaymentMethod.cash,
            ),
          )
          .timeout(const Duration(milliseconds: 100));

      expect(detail.account.openCents, 0);
      expect(localRepository.paymentCount, 1);
      expect(remoteDatasource.canReachCalls, 1);
      remoteDatasource.releaseAll();
    },
  );
}

FiadoRepositoryImpl _repository(
  FiadoRepository localRepository,
  FiadoRemoteDatasource remoteDatasource,
) {
  return FiadoRepositoryImpl(
    localRepository: localRepository,
    remoteDatasource: remoteDatasource,
    operationalContext: _remoteOperationalContext(),
    dataAccessPolicy: DataAccessPolicy.fromMode(AppDataMode.futureHybridReady),
  );
}

AppOperationalContext _remoteOperationalContext() {
  return AppOperationalContext(
    environment: const AppEnvironment.localDefault().copyWith(
      dataMode: AppDataMode.futureHybridReady,
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

FiadoAccount _account({int openCents = 5000}) {
  final now = DateTime(2026, 4, 26, 10);
  return FiadoAccount(
    id: 1,
    uuid: 'fiado-1',
    saleId: 10,
    clientId: 7,
    clientName: 'Cliente local',
    originalCents: 5000,
    openCents: openCents,
    dueDate: DateTime(2026, 5, 26),
    status: openCents == 0 ? 'quitado' : 'pendente',
    createdAt: now,
    updatedAt: now,
    settledAt: openCents == 0 ? now : null,
    receiptNumber: 'TAT-1',
  );
}

class _FakeFiadoRepository implements FiadoRepository {
  int searchCount = 0;
  int detailCount = 0;
  int paymentCount = 0;

  @override
  Future<List<FiadoAccount>> search({
    String query = '',
    String? status,
    bool overdueOnly = false,
  }) async {
    searchCount++;
    return [_account()];
  }

  @override
  Future<FiadoDetail> fetchDetail(int fiadoId) async {
    detailCount++;
    return FiadoDetail(
      account: _account(),
      entries: const <FiadoPaymentEntry>[],
    );
  }

  @override
  Future<FiadoDetail> registerPayment(FiadoPaymentInput input) async {
    paymentCount++;
    return FiadoDetail(
      account: _account(openCents: 0),
      entries: [
        FiadoPaymentEntry(
          id: 1,
          uuid: 'payment-1',
          fiadoId: input.fiadoId,
          clientId: 7,
          entryType: 'pagamento',
          amountCents: input.amountCents,
          registeredAt: DateTime(2026, 4, 26, 10),
          notes: input.notes,
          cashMovementId: null,
          paymentMethod: input.paymentMethod,
        ),
      ],
    );
  }
}

class _BlockingFiadoRemoteDatasource implements FiadoRemoteDatasource {
  final _pendingReachability = <Completer<bool>>[];
  int canReachCalls = 0;

  @override
  EndpointConfig get endpointConfig => const EndpointConfig();

  @override
  String get featureKey => 'fiado';

  @override
  bool get requiresAuthentication => true;

  @override
  Future<bool> canReachRemote() {
    canReachCalls++;
    final completer = Completer<bool>();
    _pendingReachability.add(completer);
    return completer.future;
  }

  void releaseAll() {
    for (final completer in _pendingReachability) {
      if (!completer.isCompleted) {
        completer.complete(false);
      }
    }
  }

  @override
  Future<RemoteFiadoPaymentRecord> createPayment(
    RemoteFiadoPaymentRecord record,
  ) async {
    throw StateError('Remote payment must not run in operational fiado tests.');
  }

  @override
  Future<RemoteFeatureDiagnostic> fetchDiagnostic() async {
    return RemoteFeatureDiagnostic(
      featureKey: featureKey,
      displayName: 'Fiado',
      reachable: false,
      requiresAuthentication: true,
      isAuthenticated: true,
      endpointLabel: 'teste',
      summary: 'offline',
      lastCheckedAt: DateTime(2026, 4, 26, 10),
      capabilities: const <String>[],
    );
  }
}

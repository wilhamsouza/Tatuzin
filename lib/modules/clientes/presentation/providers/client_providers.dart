import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/core/app_context/app_operational_context.dart';
import '../../../../app/core/app_context/data_access_policy.dart';
import '../../../../app/core/config/app_environment.dart';
import '../../../../app/core/database/app_database.dart';
import '../../../../app/core/network/network_providers.dart';
import '../../../../app/core/providers/app_data_refresh_provider.dart';
import '../../../../app/core/session/auth_token_storage.dart';
import '../../../../app/core/sync/sync_action_result.dart';
import '../../data/customers_repository_impl.dart';
import '../../data/sqlite_customer_credit_repository.dart';
import '../../data/datasources/customers_remote_datasource.dart';
import '../../data/real/real_customers_remote_datasource.dart';
import '../../data/sqlite_client_repository.dart';
import '../../domain/entities/client.dart';
import '../../domain/entities/customer_credit_transaction.dart';
import '../../domain/repositories/client_repository.dart';
import '../../domain/repositories/customer_credit_repository.dart';

final localClientRepositoryProvider = Provider<SqliteClientRepository>((ref) {
  return SqliteClientRepository(ref.read(appDatabaseProvider));
});

final localCustomerCreditRepositoryProvider =
    Provider<SqliteCustomerCreditRepository>((ref) {
      return SqliteCustomerCreditRepository(ref.read(appDatabaseProvider));
    });

final customersRemoteDatasourceProvider = Provider<CustomersRemoteDatasource>((
  ref,
) {
  return RealCustomersRemoteDatasource(
    apiClient: ref.read(realApiClientProvider),
    tokenStorage: ref.read(authTokenStorageProvider),
    environment: ref.watch(appEnvironmentProvider),
    operationalContext: ref.watch(appOperationalContextProvider),
  );
});

final clientHybridRepositoryProvider = Provider<CustomersRepositoryImpl>((ref) {
  return CustomersRepositoryImpl(
    localRepository: ref.read(localClientRepositoryProvider),
    remoteDatasource: ref.read(customersRemoteDatasourceProvider),
    operationalContext: ref.watch(appOperationalContextProvider),
    dataAccessPolicy: ref.watch(appDataAccessPolicyProvider),
  );
});

final clientRepositoryProvider = Provider<ClientRepository>((ref) {
  return ref.watch(clientHybridRepositoryProvider);
});

final customerCreditRepositoryProvider = Provider<CustomerCreditRepository>((
  ref,
) {
  return ref.watch(localCustomerCreditRepositoryProvider);
});

final clientSearchQueryProvider = StateProvider<String>((ref) => '');

final clientListProvider = FutureProvider<List<Client>>((ref) async {
  ref.watch(appDataRefreshProvider);
  final query = ref.watch(clientSearchQueryProvider);
  return ref.watch(clientRepositoryProvider).search(query: query);
});

final clientLookupProvider = FutureProvider.family<List<Client>, String>((
  ref,
  query,
) async {
  ref.watch(appDataRefreshProvider);
  return ref.watch(clientRepositoryProvider).search(query: query);
});

final customerCreditBalanceProvider = FutureProvider.family<int, int>((
  ref,
  customerId,
) async {
  ref.watch(appDataRefreshProvider);
  return ref
      .watch(customerCreditRepositoryProvider)
      .getCustomerCreditBalance(customerId);
});

final customerCreditTransactionsProvider =
    FutureProvider.family<List<CustomerCreditTransaction>, int>((
      ref,
      customerId,
    ) async {
      ref.watch(appDataRefreshProvider);
      return ref
          .watch(customerCreditRepositoryProvider)
          .getCustomerCreditTransactions(customerId);
    });

final customerCreditTransactionProvider =
    FutureProvider.family<CustomerCreditTransaction, int>((
      ref,
      transactionId,
    ) async {
      ref.watch(appDataRefreshProvider);
      return ref
          .watch(customerCreditRepositoryProvider)
          .getTransactionById(transactionId);
    });

final customerCreditControllerProvider =
    AsyncNotifierProvider<CustomerCreditController, void>(
      CustomerCreditController.new,
    );

final clientSyncControllerProvider =
    AsyncNotifierProvider<ClientSyncController, void>(ClientSyncController.new);

class ClientSyncController extends AsyncNotifier<void> {
  @override
  FutureOr<void> build() {}

  Future<SyncActionResult> syncNow() async {
    state = const AsyncLoading();
    try {
      final result = await ref.read(clientHybridRepositoryProvider).syncNow();
      ref.read(appDataRefreshProvider.notifier).state++;
      state = const AsyncData(null);
      return result;
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
      rethrow;
    }
  }
}

class CustomerCreditController extends AsyncNotifier<void> {
  @override
  FutureOr<void> build() {}

  Future<CustomerCreditTransaction> addManualCredit({
    required int customerId,
    required int amountCents,
    String? description,
  }) async {
    state = const AsyncLoading();
    try {
      final transaction = await ref
          .read(customerCreditRepositoryProvider)
          .addManualCredit(
            customerId: customerId,
            amountCents: amountCents,
            description: description,
          );
      ref.read(appDataRefreshProvider.notifier).state++;
      state = const AsyncData(null);
      return transaction;
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
      rethrow;
    }
  }

  Future<CustomerCreditTransaction> addManualDebit({
    required int customerId,
    required int amountCents,
    String? description,
  }) async {
    state = const AsyncLoading();
    try {
      final transaction = await ref
          .read(customerCreditRepositoryProvider)
          .addManualDebit(
            customerId: customerId,
            amountCents: amountCents,
            description: description,
          );
      ref.read(appDataRefreshProvider.notifier).state++;
      state = const AsyncData(null);
      return transaction;
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
      rethrow;
    }
  }
}

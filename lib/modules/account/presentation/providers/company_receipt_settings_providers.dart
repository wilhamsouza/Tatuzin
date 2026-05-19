import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/core/network/network_providers.dart';
import '../../../../app/core/providers/app_data_refresh_provider.dart';
import '../../../../app/core/session/auth_token_storage.dart';
import '../../../../app/core/session/cached_session_storage.dart';
import '../../../../app/core/session/session_provider.dart';
import '../../data/company_receipt_settings_repository.dart';
import '../../domain/company_receipt_settings.dart';

final companyReceiptSettingsRepositoryProvider =
    Provider<CompanyReceiptSettingsRepository>((ref) {
      return RemoteCompanyReceiptSettingsRepository(
        apiClient: ref.watch(apiClientProvider),
        tokenStorage: ref.watch(authTokenStorageProvider),
      );
    });

final companyReceiptSettingsProvider =
    FutureProvider<CompanyReceiptSettingsSnapshot>((ref) async {
      ref.watch(appDataRefreshProvider);
      final snapshot = await ref
          .watch(companyReceiptSettingsRepositoryProvider)
          .fetch();
      final current = ref.read(currentCompanyContextProvider);
      ref
          .read(appSessionProvider.notifier)
          .updateCompany(snapshot.mergeInto(current));
      return snapshot;
    });

final companyReceiptSettingsControllerProvider =
    AsyncNotifierProvider<CompanyReceiptSettingsController, void>(
      CompanyReceiptSettingsController.new,
    );

class CompanyReceiptSettingsController extends AsyncNotifier<void> {
  @override
  FutureOr<void> build() {}

  Future<void> save(CompanyReceiptSettingsDraft draft) async {
    state = const AsyncLoading();
    try {
      final snapshot = await ref
          .read(companyReceiptSettingsRepositoryProvider)
          .save(draft);
      final current = ref.read(currentCompanyContextProvider);
      final updatedCompany = snapshot.mergeInto(current);
      ref.read(appSessionProvider.notifier).updateCompany(updatedCompany);
      final updatedSession = ref.read(appSessionProvider);
      if (updatedSession.isRemoteAuthenticated &&
          !updatedSession.isOfflineFallback) {
        await ref
            .read(cachedSessionStorageProvider)
            .saveSession(updatedSession);
      }
      ref.invalidate(companyReceiptSettingsProvider);
      ref.invalidate(appDataRefreshProvider);
      state = const AsyncData(null);
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
      rethrow;
    }
  }
}

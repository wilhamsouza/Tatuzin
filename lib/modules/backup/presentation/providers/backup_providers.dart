import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/core/database/app_database.dart';
import '../../../../app/core/database/database_file_locator.dart';
import '../../../../app/core/errors/app_exceptions.dart';
import '../../../../app/core/providers/app_data_refresh_provider.dart';
import '../../../../app/core/providers/tenant_bootstrap_gate.dart';
import '../../../carrinho/presentation/providers/cart_provider.dart';
import '../../data/backup_file_picker_service.dart';
import '../../data/backup_security_policy.dart';
import '../../data/backup_share_service.dart';
import '../../data/backup_validation_service.dart';
import '../../data/database_backup_service.dart';
import '../../data/database_restore_service.dart';
import '../../domain/entities/backup_file_info.dart';
import '../../domain/entities/backup_restore_result.dart';
import '../../domain/entities/backup_validation_result.dart';

final databaseFileLocatorProvider = Provider<DatabaseFileLocator>((ref) {
  return DatabaseFileLocator();
});

final backupSecurityPolicyProvider = Provider<BackupSecurityPolicy>((ref) {
  return const BackupSecurityPolicy();
});

final backupValidationServiceProvider = Provider<BackupValidationService>((
  ref,
) {
  return BackupValidationService();
});

final backupFilePickerServiceProvider = Provider<BackupFilePickerService>((
  ref,
) {
  return BackupFilePickerService(
    securityPolicy: ref.read(backupSecurityPolicyProvider),
  );
});

final backupShareServiceProvider = Provider<BackupShareService>((ref) {
  return BackupShareService(
    securityPolicy: ref.read(backupSecurityPolicyProvider),
  );
});

final databaseBackupServiceProvider = Provider<DatabaseBackupService>((ref) {
  return DatabaseBackupService(
    appDatabase: ref.watch(appDatabaseProvider),
    fileLocator: ref.read(databaseFileLocatorProvider),
    validationService: ref.read(backupValidationServiceProvider),
    securityPolicy: ref.read(backupSecurityPolicyProvider),
  );
});

final databaseRestoreServiceProvider = Provider<DatabaseRestoreService>((ref) {
  return DatabaseRestoreService(
    appDatabase: ref.watch(appDatabaseProvider),
    fileLocator: ref.read(databaseFileLocatorProvider),
    validationService: ref.read(backupValidationServiceProvider),
    backupService: ref.read(databaseBackupServiceProvider),
    securityPolicy: ref.read(backupSecurityPolicyProvider),
  );
});

final lastGeneratedBackupProvider = StateProvider<BackupFileInfo?>(
  (ref) => null,
);
final selectedRestoreCandidateProvider = StateProvider<BackupValidationResult?>(
  (ref) => null,
);

final backupActionControllerProvider =
    AsyncNotifierProvider<BackupActionController, void>(
      BackupActionController.new,
    );

class BackupActionController extends AsyncNotifier<void> {
  @override
  FutureOr<void> build() {}

  Future<BackupFileInfo> createManualBackup() async {
    state = const AsyncLoading();
    try {
      _ensureCanExportRawDatabase();
      await requireTenantBootstrapReady(
        ref,
        'BackupActionController.createManualBackup',
      );
      final backup = await ref
          .read(databaseBackupServiceProvider)
          .createBackup();
      ref.read(lastGeneratedBackupProvider.notifier).state = backup;
      state = const AsyncData(null);
      return backup;
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
      rethrow;
    }
  }

  Future<void> shareBackup(BackupFileInfo backupFile) async {
    state = const AsyncLoading();
    try {
      _ensureCanShareRawDatabase();
      await ref.read(backupShareServiceProvider).share(backupFile);
      state = const AsyncData(null);
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
      rethrow;
    }
  }

  Future<BackupValidationResult?> pickRestoreCandidate() async {
    state = const AsyncLoading();
    try {
      _ensureCanImportRawDatabase();
      final selectedPath = await ref
          .read(backupFilePickerServiceProvider)
          .pickBackupFilePath();
      if (selectedPath == null) {
        state = const AsyncData(null);
        return null;
      }

      final validation = await ref
          .read(backupValidationServiceProvider)
          .validate(selectedPath);
      ref.read(selectedRestoreCandidateProvider.notifier).state = validation;
      state = const AsyncData(null);
      return validation;
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
      rethrow;
    }
  }

  void clearRestoreCandidate() {
    ref.read(selectedRestoreCandidateProvider.notifier).state = null;
    state = const AsyncData(null);
  }

  Future<BackupRestoreResult> restoreSelectedBackup() async {
    _ensureCanImportRawDatabase();
    final candidate = ref.read(selectedRestoreCandidateProvider);
    if (candidate == null) {
      throw const ValidationException(
        'Selecione e valide um backup antes de restaurar.',
      );
    }

    state = const AsyncLoading();
    try {
      await requireTenantBootstrapReady(
        ref,
        'BackupActionController.restoreSelectedBackup',
      );
      final result = await ref
          .read(databaseRestoreServiceProvider)
          .restoreFromBackup(candidate.filePath);
      ref.read(selectedRestoreCandidateProvider.notifier).state = null;
      ref.read(cartProvider.notifier).clear();
      ref.read(appDataRefreshProvider.notifier).state++;
      state = const AsyncData(null);
      return result;
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
      rethrow;
    }
  }

  void _ensureCanExportRawDatabase() {
    if (!ref.read(backupSecurityPolicyProvider).canExportRawDatabase) {
      throw const ValidationException(
        BackupSecurityPolicy.rawDatabaseBlockedReason,
      );
    }
  }

  void _ensureCanShareRawDatabase() {
    if (!ref.read(backupSecurityPolicyProvider).canShareRawDatabase) {
      throw const ValidationException(
        BackupSecurityPolicy.rawDatabaseBlockedReason,
      );
    }
  }

  void _ensureCanImportRawDatabase() {
    if (!ref.read(backupSecurityPolicyProvider).canImportRawDatabase) {
      throw const ValidationException(
        BackupSecurityPolicy.rawDatabaseBlockedReason,
      );
    }
  }
}

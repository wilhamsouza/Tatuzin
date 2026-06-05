import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tatuzin/app/core/database/app_database.dart';
import 'package:tatuzin/app/core/database/database_file_locator.dart';
import 'package:tatuzin/app/core/errors/app_exceptions.dart';
import 'package:tatuzin/modules/backup/data/backup_file_picker_service.dart';
import 'package:tatuzin/modules/backup/data/backup_security_policy.dart';
import 'package:tatuzin/modules/backup/data/backup_share_service.dart';
import 'package:tatuzin/modules/backup/data/backup_validation_service.dart';
import 'package:tatuzin/modules/backup/data/database_backup_service.dart';
import 'package:tatuzin/modules/backup/data/database_restore_service.dart';
import 'package:tatuzin/modules/backup/domain/entities/backup_file_info.dart';
import 'package:tatuzin/modules/backup/presentation/providers/backup_providers.dart';

void main() {
  group('BackupSecurityPolicy', () {
    test(
      'release bloqueia exportacao, compartilhamento e importacao bruta',
      () {
        const policy = BackupSecurityPolicy(isReleaseMode: true);

        expect(policy.canExportRawDatabase, isFalse);
        expect(policy.canShareRawDatabase, isFalse);
        expect(policy.canImportRawDatabase, isFalse);
        expect(policy.shouldWarnAboutRawDatabase, isFalse);
        expect(
          BackupSecurityPolicy.rawDatabaseBlockedReason,
          contains('Backup local bruto'),
        );
      },
    );

    test(
      'debug/profile permite exportacao, compartilhamento e importacao bruta',
      () {
        const policy = BackupSecurityPolicy(isReleaseMode: false);

        expect(policy.canExportRawDatabase, isTrue);
        expect(policy.canShareRawDatabase, isTrue);
        expect(policy.canImportRawDatabase, isTrue);
        expect(policy.shouldWarnAboutRawDatabase, isTrue);
      },
    );
  });

  group('raw database backup blockers', () {
    test(
      'BackupShareService nao compartilha db/sqlite quando politica bloqueia',
      () async {
        const service = BackupShareService(
          securityPolicy: BackupSecurityPolicy(isReleaseMode: true),
        );

        await expectLater(
          service.share(
            BackupFileInfo(
              filePath: 'backup.db',
              fileName: 'backup.db',
              sizeBytes: 100,
              createdAt: _fixedDate,
              isSafetyCopy: false,
            ),
          ),
          _throwsRawBackupBlocked,
        );

        await expectLater(
          service.share(
            BackupFileInfo(
              filePath: 'backup.sqlite',
              fileName: 'backup.sqlite',
              sizeBytes: 100,
              createdAt: _fixedDate,
              isSafetyCopy: false,
            ),
          ),
          _throwsRawBackupBlocked,
        );
      },
    );

    test(
      'DatabaseBackupService nao chega ao VACUUM INTO quando politica bloqueia',
      () async {
        final locator = _CountingDatabaseFileLocator();
        final service = DatabaseBackupService(
          appDatabase: AppDatabase.instance,
          fileLocator: locator,
          validationService: BackupValidationService(),
          securityPolicy: const BackupSecurityPolicy(isReleaseMode: true),
        );

        await expectLater(service.createBackup, _throwsRawBackupBlocked);

        expect(locator.ensureBackupDirectoryCalls, 0);
        expect(locator.buildBackupFileNameCalls, 0);
      },
    );

    test(
      'BackupFilePickerService nao abre picker quando importacao bruta bloqueia',
      () async {
        const service = BackupFilePickerService(
          securityPolicy: BackupSecurityPolicy(isReleaseMode: true),
        );

        await expectLater(service.pickBackupFilePath, _throwsRawBackupBlocked);
      },
    );

    test(
      'DatabaseRestoreService rejeita db bruto antes de validar ou sobrescrever',
      () async {
        final locator = _CountingDatabaseFileLocator();
        final backupService = DatabaseBackupService(
          appDatabase: AppDatabase.instance,
          fileLocator: locator,
          validationService: BackupValidationService(),
          securityPolicy: const BackupSecurityPolicy(isReleaseMode: true),
        );
        final restoreService = DatabaseRestoreService(
          appDatabase: AppDatabase.instance,
          fileLocator: locator,
          validationService: BackupValidationService(),
          backupService: backupService,
          securityPolicy: const BackupSecurityPolicy(isReleaseMode: true),
        );

        await expectLater(
          () => restoreService.restoreFromBackup('backup.db'),
          _throwsRawBackupBlocked,
        );

        expect(locator.resolveDatabasePathCalls, 0);
        expect(locator.ensureBackupDirectoryCalls, 0);
      },
    );

    test(
      'BackupActionController mostra erro de seguranca e nao gera backup',
      () async {
        final container = ProviderContainer(
          overrides: <Override>[
            backupSecurityPolicyProvider.overrideWithValue(
              const BackupSecurityPolicy(isReleaseMode: true),
            ),
          ],
        );
        addTearDown(container.dispose);

        await expectLater(
          container
              .read(backupActionControllerProvider.notifier)
              .createManualBackup,
          _throwsRawBackupBlocked,
        );

        final state = container.read(backupActionControllerProvider);
        expect(state.hasError, isTrue);
        expect(state.error, isA<ValidationException>());
      },
    );
  });
}

final _throwsRawBackupBlocked = throwsA(
  isA<ValidationException>().having(
    (error) => error.message,
    'message',
    BackupSecurityPolicy.rawDatabaseBlockedReason,
  ),
);

final _fixedDate = DateTime(2026, 1, 1);

class _CountingDatabaseFileLocator implements DatabaseFileLocator {
  int resolveDatabasePathCalls = 0;
  int ensureBackupDirectoryCalls = 0;
  int buildBackupFileNameCalls = 0;

  @override
  Future<String> resolveDatabasePath() async {
    resolveDatabasePathCalls++;
    return 'current.db';
  }

  @override
  Future<Directory> ensureBackupDirectory() async {
    ensureBackupDirectoryCalls++;
    throw StateError('ensureBackupDirectory should not be called');
  }

  @override
  String buildBackupFileName({
    required DateTime timestamp,
    bool safetyCopy = false,
  }) {
    buildBackupFileNameCalls++;
    return 'backup.db';
  }

  @override
  List<String> sidecarPathsFor(String databasePath) {
    return <String>['$databasePath-wal', '$databasePath-shm'];
  }
}

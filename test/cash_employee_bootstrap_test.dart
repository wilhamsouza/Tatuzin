import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tatuzin/app/core/database/app_database.dart';
import 'package:tatuzin/app/core/session/session_provider.dart';
import 'package:tatuzin/modules/caixa/data/cash_workspace_store.dart';

import 'test_tenant_session.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test(
    'troca de funcionário atualiza identidade antes da próxima escrita no mesmo banco',
    () async {
      final company =
          'cash-employee-bootstrap-${DateTime.now().microsecondsSinceEpoch}';
      final container = ProviderContainer();
      setTestTenantSession(container, companyId: company, userId: 'employee-a');
      final app = container.read(appDatabaseProvider);
      addTearDown(() async {
        container.dispose();
        await app.close();
        await AppDatabase.deleteDatabaseForIsolationKeyForTesting(
          'remote:$company',
        );
      });
      final first = await app.database;
      expect(
        (await CashWorkspaceStore.read(
          first,
          'cash.employee.context',
        ))['employeeId'],
        'employee-a',
      );
      setTestTenantSession(container, companyId: company, userId: 'employee-b');
      await container.pump();
      final sameApp = container.read(appDatabaseProvider);
      final second = await sameApp.database;
      expect(identical(app, sameApp), isTrue);
      expect(identical(first, second), isTrue);
      final identity = await CashWorkspaceStore.read(
        second,
        'cash.employee.context',
      );
      expect(identity['employeeId'], 'employee-b');
      expect(identity['companyId'], company);
      expect(identity['clientInstanceId'], 'device-1');
    },
  );

  test(
    'alterar política não fecha a conexão operacional e preserva funcionário',
    () async {
      final company =
          'cash-policy-bootstrap-${DateTime.now().microsecondsSinceEpoch}';
      final container = ProviderContainer();
      setTestTenantSession(
        container,
        companyId: company,
        userId: 'employee-owner',
      );
      final app = container.read(appDatabaseProvider);
      addTearDown(() async {
        container.dispose();
        await app.close();
        await AppDatabase.deleteDatabaseForIsolationKeyForTesting(
          'remote:$company',
        );
      });
      final original = await app.database;
      final current = container.read(currentCompanyContextProvider);
      container
          .read(appSessionProvider.notifier)
          .updateCompany(
            current.copyWith(
              cashBlindClosureEnabled: true,
              cashPolicyRevision: 1,
            ),
          );
      await container.pump();
      final updated = await container.read(appDatabaseProvider).database;
      expect(identical(original, updated), isTrue);
      expect(original.isOpen, isTrue);
      expect(
        (await CashWorkspaceStore.read(
          updated,
          'cash.policy',
        ))['cashBlindClosureEnabled'],
        isTrue,
      );
      expect(
        (await CashWorkspaceStore.read(
          updated,
          'cash.employee.context',
        ))['employeeId'],
        'employee-owner',
      );
    },
  );

  test(
    'a mesma identidade não compartilha contexto de caixa entre empresas',
    () async {
      final suffix = DateTime.now().microsecondsSinceEpoch;
      final firstCompany = 'cash-tenant-a-$suffix';
      final secondCompany = 'cash-tenant-b-$suffix';
      final container = ProviderContainer();
      setTestTenantSession(
        container,
        companyId: firstCompany,
        userId: 'same-employee',
      );
      final first = container.read(appDatabaseProvider);
      final firstDb = await first.database;
      expect(
        (await CashWorkspaceStore.read(
          firstDb,
          'cash.employee.context',
        ))['companyId'],
        firstCompany,
      );
      setTestTenantSession(
        container,
        companyId: secondCompany,
        userId: 'same-employee',
      );
      await container.pump();
      final second = container.read(appDatabaseProvider);
      final secondDb = await second.database;
      addTearDown(() async {
        container.dispose();
        await first.close();
        await second.close();
        await AppDatabase.deleteDatabaseForIsolationKeyForTesting(
          'remote:$firstCompany',
        );
        await AppDatabase.deleteDatabaseForIsolationKeyForTesting(
          'remote:$secondCompany',
        );
      });
      expect(identical(first, second), isFalse);
      expect(
        (await CashWorkspaceStore.read(
          secondDb,
          'cash.employee.context',
        ))['companyId'],
        secondCompany,
      );
    },
  );
}

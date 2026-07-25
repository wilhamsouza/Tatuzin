import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tatuzin_admin_web/src/core/auth/admin_providers.dart';
import 'package:tatuzin_admin_web/src/core/models/admin_support_models.dart';
import 'package:tatuzin_admin_web/src/features/support/presentation/support_triage_page.dart';

void main() {
  testWidgets('/support renderiza fila de triagem priorizada', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          adminSupportTriageProvider.overrideWith(
            (ref) async => _triageSnapshot(),
          ),
        ],
        child: const MaterialApp(home: Scaffold(body: SupportTriagePage())),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Triagem global de suporte'), findsOneWidget);
    expect(find.text('Empresas priorizadas'), findsOneWidget);
    expect(find.text('Empresa Critica'), findsOneWidget);
    expect(find.text('Critico'), findsWidgets);
    expect(find.textContaining('Licenca bloqueada'), findsOneWidget);
    expect(find.textContaining('Conflitos abertos'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Workspace'), findsOneWidget);
    expect(find.text('Fallback seguro ativo'), findsOneWidget);
    expect(find.textContaining('sessoes suspeitas'), findsWidgets);
  });
}

AdminSupportTriageSnapshot _triageSnapshot() {
  return AdminSupportTriageSnapshot(
    generatedAt: DateTime.parse('2026-06-25T12:00:00.000Z'),
    usesFallback: true,
    unavailableSignals: const ['sessoes suspeitas consolidadas'],
    items: [
      AdminSupportTriageItem(
        companyId: 'company-1',
        companyName: 'Empresa Critica',
        severity: AdminSupportSeverity.critical,
        score: 95,
        status: 'Requer triagem',
        probableCauses: const ['Licenca bloqueada apesar de plano pago'],
        signals: const [
          AdminSupportSignal(
            type: 'sync',
            label: 'Conflitos abertos',
            value: '2',
            severity: AdminSupportSeverity.high,
          ),
        ],
        nextBestActions: [
          AdminSupportActionDefinition.openWorkspace('company-1'),
        ],
        lastActivityAt: DateTime.parse('2026-06-25T11:00:00.000Z'),
        routeToCompanyWorkspace: '/companies/company-1/support',
      ),
    ],
  );
}

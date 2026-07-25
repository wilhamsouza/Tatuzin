import 'package:flutter_test/flutter_test.dart';
import 'package:tatuzin_admin_web/src/core/models/admin_billing_models.dart';
import 'package:tatuzin_admin_web/src/core/models/admin_models.dart';
import 'package:tatuzin_admin_web/src/core/models/admin_support_models.dart';
import 'package:tatuzin_admin_web/src/core/models/admin_sync_center_models.dart';

void main() {
  test('fallback triage calcula score e ordena por criticidade', () {
    final snapshot = buildFallbackSupportTriageSnapshot(
      now: DateTime.parse('2026-06-25T12:00:00.000Z'),
      companies: [
        AdminCompanySummary.fromMap(_companyMap(id: 'ok', name: 'OK')),
        AdminCompanySummary.fromMap(
          _companyMap(
            id: 'critical',
            name: 'Critica',
            licenseStatus: 'blocked',
            plan: 'PRO',
          ),
        ),
      ],
      syncCompanies: [
        AdminSyncCenterCompany.fromMap({
          'companyId': 'critical',
          'companyName': 'Critica',
          'plan': 'PRO',
          'syncStatus': 'failed',
          'failedCount': 2,
          'openConflictCount': 1,
          'pendingCount': 3,
          'lastEventAt': '2026-06-22T12:00:00.000Z',
          'requiresReview': true,
        }),
      ],
      billingCompanies: [
        AdminBillingCompanySummary.fromMap({
          'companyId': 'critical',
          'companyName': 'Critica',
          'plan': 'PRO',
          'licenseStatus': 'blocked',
          'billingSubscriptionStatus': 'past_due',
          'hasProviderSubscription': true,
          'updatedAt': '2026-06-25T10:00:00.000Z',
        }),
      ],
    );

    expect(snapshot.usesFallback, isTrue);
    expect(snapshot.items.first.companyId, 'critical');
    expect(snapshot.items.first.severity, AdminSupportSeverity.critical);
    expect(snapshot.items.first.score, greaterThanOrEqualTo(80));
    expect(
      snapshot.items.first.probableCauses,
      contains('Licenca bloqueada apesar de plano pago'),
    );
    expect(snapshot.items.last.companyId, 'ok');
    expect(snapshot.items.last.severity, AdminSupportSeverity.healthy);
  });
}

Map<String, dynamic> _companyMap({
  required String id,
  required String name,
  String plan = 'FREE',
  String licenseStatus = 'active',
}) {
  return {
    'id': id,
    'name': name,
    'legalName': '$name LTDA',
    'slug': name.toLowerCase(),
    'isActive': true,
    'updatedAt': '2026-06-25T09:00:00.000Z',
    'license': {
      'id': 'license-$id',
      'companyId': id,
      'companyName': name,
      'companyLegalName': '$name LTDA',
      'companySlug': name.toLowerCase(),
      'companyIsActive': true,
      'plan': plan,
      'status': licenseStatus,
      'syncEnabled': true,
    },
    'counts': const <String, dynamic>{},
  };
}

import 'package:flutter_test/flutter_test.dart';
import 'package:tatuzin_admin_web/src/core/models/admin_models.dart';

void main() {
  test('AdminCompanySyncHealth parseia o snapshot administrativo', () {
    final health = AdminCompanySyncHealth.fromMap(<String, dynamic>{
      'companyId': 'company-1',
      'companyName': 'Empresa Sync',
      'companySlug': 'empresa-sync',
      'currentServerVersion': '7',
      'serverFirstSnapshotVersion': '2',
      'status': 'conflict',
      'syncEnabled': true,
      'license': <String, dynamic>{
        'id': 'license-1',
        'companyId': 'company-1',
        'plan': 'pro',
        'status': 'active',
        'startsAt': '2026-05-01T12:00:00.000Z',
        'expiresAt': null,
        'maxDevices': 5,
        'syncEnabled': true,
      },
      'devices': <String, dynamic>{
        'active': 2,
        'blocked': 1,
        'revoked': 1,
        'pending': 0,
        'total': 4,
      },
      'events': <String, dynamic>{
        'accepted': 10,
        'rejected': 2,
        'conflict': 1,
        'failed': 1,
        'duplicate': 3,
        'pending': 0,
        'total': 17,
      },
      'openConflictsCount': 1,
      'lastMaterializedAt': '2026-05-05T14:00:00.000Z',
      'lastSyncAt': '2026-05-05T14:05:00.000Z',
      'deviceSyncStates': <Map<String, dynamic>>[
        <String, dynamic>{
          'deviceId': 'device-1',
          'deviceLabel': 'PDV Balcao',
          'clientInstanceId': 'client-1',
          'status': 'active',
          'lastSyncAt': '2026-05-05T14:05:00.000Z',
          'lastSeenAt': '2026-05-05T14:06:00.000Z',
        },
      ],
      'lastIncident': <String, dynamic>{
        'id': 'incident-1',
        'code': 'SYNC_MATERIALIZATION_FAILED',
        'message': 'Falha inesperada.',
        'severity': 'error',
        'createdAt': '2026-05-05T14:01:00.000Z',
      },
    });

    expect(health.companyId, 'company-1');
    expect(health.currentServerVersion, '7');
    expect(health.status, 'conflict');
    expect(health.license?.syncEnabled, isTrue);
    expect(health.devices.active, 2);
    expect(health.devices.blocked, 1);
    expect(health.events.accepted, 10);
    expect(health.events.failed, 1);
    expect(health.openConflictsCount, 1);
    expect(health.deviceSyncStates.single.clientInstanceId, 'client-1');
    expect(health.lastIncident?.severity, 'error');
  });

  test('Admin sync diagnostics parseiam listas paginadas', () {
    final event = AdminSyncEventDiagnostic.fromMap(<String, dynamic>{
      'id': 'sync-event-1',
      'eventId': 'event-1',
      'feature': 'pdv',
      'entity': 'payment',
      'operation': 'create',
      'entityLocalId': 'payment-local',
      'entityServerId': null,
      'status': 'failed',
      'occurredAt': '2026-05-05T13:59:00.000Z',
      'createdAt': '2026-05-05T14:00:00.000Z',
      'materializedAt': null,
      'serverVersion': null,
      'errorCode': 'SYNC_MATERIALIZATION_FAILED',
      'errorMessage': 'Falha inesperada.',
      'payloadSummary': '{"amountCents":3000000000}',
      'device': <String, dynamic>{
        'id': 'device-1',
        'deviceLabel': 'PDV Balcao',
        'clientInstanceId': 'client-1',
        'status': 'active',
      },
      'user': <String, dynamic>{
        'id': 'user-1',
        'name': 'Operador',
        'email': 'operador@tatuzin.test',
      },
    });

    final conflict = AdminSyncConflictDiagnostic.fromMap(<String, dynamic>{
      'id': 'conflict-1',
      'entity': 'sale',
      'entityLocalId': 'sale-local',
      'entityServerId': null,
      'code': 'SALE_IMMUTABLE',
      'message': 'Venda finalizada nao pode ser alterada.',
      'status': 'open',
      'createdAt': '2026-05-05T14:00:00.000Z',
      'resolvedAt': null,
      'payloadSummary': '{"status":"finalized"}',
      'resolutionSummary': null,
      'device': <String, dynamic>{
        'id': 'device-1',
        'deviceLabel': 'PDV Balcao',
        'clientInstanceId': 'client-1',
        'status': 'active',
      },
      'user': <String, dynamic>{
        'id': 'user-1',
        'name': 'Operador',
        'email': 'operador@tatuzin.test',
      },
      'resolvedBy': null,
      'event': <String, dynamic>{
        'id': 'sync-event-2',
        'eventId': 'event-conflict',
        'feature': 'pdv',
        'entity': 'sale',
        'operation': 'update',
        'status': 'conflict',
        'serverVersion': '3',
      },
    });

    final device = AdminCompanySyncDevice.fromMap(<String, dynamic>{
      'id': 'device-1',
      'deviceLabel': 'PDV Balcao',
      'platform': 'android',
      'appVersion': '2.0.0',
      'status': 'active',
      'lastSeenAt': '2026-05-05T14:06:00.000Z',
      'userId': 'user-1',
      'userName': 'Operador',
      'userEmail': 'operador@tatuzin.test',
      'clientInstanceId': 'client-1',
      'createdAt': '2026-05-05T13:00:00.000Z',
      'approvedAt': '2026-05-05T13:01:00.000Z',
      'revokedAt': null,
      'revokedReason': null,
    });

    expect(event.status, 'failed');
    expect(event.device.clientInstanceId, 'client-1');
    expect(event.payloadSummary, contains('amountCents'));
    expect(conflict.status, 'open');
    expect(conflict.event.serverVersion, '3');
    expect(device.deviceLabel, 'PDV Balcao');
    expect(device.userName, 'Operador');
  });
}

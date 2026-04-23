import 'package:flutter_test/flutter_test.dart';
import 'package:tatuzin_admin_web/src/core/models/admin_crm_models.dart';
import 'package:tatuzin_admin_web/src/core/models/admin_models.dart';

void main() {
  test('crm models parse customer detail and timeline payloads', () {
    final customerPayload = <String, dynamic>{
      'customer': {
        'id': 'customer_1',
        'companyId': 'company_1',
        'localUuid': 'local_customer_1',
        'name': 'Alice CRM',
        'phone': '11999990000',
        'address': 'Rua do Cliente',
        'operationalNotes': 'Observacao operacional',
        'isActive': true,
        'createdAt': '2026-04-20T10:00:00.000Z',
        'updatedAt': '2026-04-23T10:00:00.000Z',
        'tags': [
          {
            'id': 'tag_1',
            'assignmentId': 'assignment_1',
            'label': 'VIP',
            'color': '#f59e0b',
            'assignedAt': '2026-04-23T11:00:00.000Z',
          },
        ],
        'commercialSummary': {
          'totalSalesCount': 3,
          'totalRevenueCents': 120000,
          'totalProfitCents': 45000,
          'totalFiadoPaymentsCents': 8000,
          'openTasksCount': 2,
          'overdueTasksCount': 1,
          'lastSaleAt': '2026-04-23T11:30:00.000Z',
          'lastFiadoPaymentAt': '2026-04-23T12:00:00.000Z',
          'lastCrmEventAt': '2026-04-23T13:00:00.000Z',
        },
      },
      'notes': [
        {
          'id': 'note_1',
          'body': 'Cliente quer retorno na sexta.',
          'createdAt': '2026-04-23T12:10:00.000Z',
          'updatedAt': '2026-04-23T12:10:00.000Z',
          'author': {
            'id': 'user_1',
            'name': 'Gestora CRM',
            'email': 'gestora@tatuzin.test',
          },
        },
      ],
      'tasks': [
        {
          'id': 'task_1',
          'title': 'Ligar para cliente VIP',
          'description': 'Confirmar interesse na oferta.',
          'status': 'open',
          'dueAt': '2026-04-24T00:00:00.000Z',
          'completedAt': null,
          'createdAt': '2026-04-23T12:20:00.000Z',
          'updatedAt': '2026-04-23T12:20:00.000Z',
          'createdBy': {
            'id': 'user_1',
            'name': 'Gestora CRM',
            'email': 'gestora@tatuzin.test',
          },
          'assignedTo': {
            'id': 'user_1',
            'name': 'Gestora CRM',
            'email': 'gestora@tatuzin.test',
          },
        },
      ],
    };

    final timelinePayload = <String, dynamic>{
      'items': [
        {
          'id': 'crm:event_1',
          'source': 'crm',
          'eventType': 'note_added',
          'occurredAt': '2026-04-23T12:10:00.000Z',
          'headline': 'Nota CRM adicionada',
          'body': 'Cliente quer retorno na sexta.',
          'actor': {
            'id': 'user_1',
            'name': 'Gestora CRM',
            'email': 'gestora@tatuzin.test',
          },
          'amountCents': null,
          'metadata': {'noteId': 'note_1'},
        },
        {
          'id': 'sale:sale_1',
          'source': 'sales',
          'eventType': 'sale_recorded',
          'occurredAt': '2026-04-23T11:30:00.000Z',
          'headline': 'Venda sincronizada',
          'body': 'vista | pix',
          'actor': null,
          'amountCents': 6500,
          'metadata': {'saleId': 'sale_1'},
        },
      ],
      'pagination': {
        'page': 1,
        'pageSize': 20,
        'total': 2,
        'count': 2,
        'hasNext': false,
        'hasPrevious': false,
      },
      'filters': {'companyId': 'company_1', 'customerId': 'customer_1'},
      'sort': {'by': 'occurredAt', 'direction': 'desc'},
    };

    final detail = AdminCrmCustomerDetail.fromMap(customerPayload);
    final timeline = AdminPaginatedResult<AdminCrmTimelineEvent>(
      items: readAdminItems(
        timelinePayload,
      ).map(AdminCrmTimelineEvent.fromMap).toList(),
      pagination: AdminPaginationMeta.fromPayload(timelinePayload),
      filters: readAdminFilters(timelinePayload),
      sort: AdminSortMeta.fromPayload(timelinePayload),
    );

    expect(detail.customer.name, 'Alice CRM');
    expect(detail.customer.operationalNotes, 'Observacao operacional');
    expect(detail.customer.tags.single.label, 'VIP');
    expect(detail.customer.commercialSummary.totalRevenueCents, 120000);
    expect(detail.notes.single.author?.name, 'Gestora CRM');
    expect(detail.tasks.single.status, 'open');
    expect(timeline.items.length, 2);
    expect(timeline.items.first.eventType, 'note_added');
    expect(timeline.items.last.amountCents, 6500);
    expect(timeline.pagination.total, 2);
  });
}

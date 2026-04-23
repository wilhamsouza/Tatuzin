import 'package:flutter_test/flutter_test.dart';
import 'package:tatuzin_admin_web/src/core/models/admin_analytics_models.dart';

void main() {
  test('management dashboard analytics models parse payloads', () {
    final payload = <String, dynamic>{
      'company': {
        'id': 'company_1',
        'name': 'Empresa Cloud',
        'slug': 'empresa-cloud',
      },
      'period': {
        'startDate': '2026-04-01',
        'endDate': '2026-04-30',
        'dayCount': 30,
      },
      'materialization': {
        'materializedAt': '2026-04-23T18:00:00.000Z',
        'coverage': {
          'companyDailyRows': 30,
          'productDailyRows': 45,
          'customerDailyRows': 22,
        },
      },
      'headline': {
        'salesAmountCents': 120000,
        'salesProfitCents': 40000,
        'cashNetCents': 32000,
        'purchasesAmountCents': 18000,
        'fiadoPaymentsAmountCents': 5000,
        'salesCount': 42,
        'identifiedCustomersCount': 18,
        'averageTicketCents': 2857,
      },
      'salesSeries': [
        {
          'date': '2026-04-01',
          'salesCount': 2,
          'salesAmountCents': 10000,
          'salesProfitCents': 3500,
          'cashNetCents': 2800,
        },
      ],
      'topProducts': [
        {
          'productKey': 'product:burger',
          'productId': 'product_1',
          'productName': 'Burger',
          'quantityMil': 3000,
          'salesCount': 10,
          'revenueCents': 30000,
          'costCents': 12000,
          'profitCents': 18000,
        },
      ],
      'topCustomers': [
        {
          'customerKey': 'customer_1',
          'customerId': 'customer_1',
          'customerName': 'Alice',
          'salesCount': 5,
          'revenueCents': 20000,
          'costCents': 7000,
          'profitCents': 13000,
          'fiadoPaymentsCents': 3000,
        },
      ],
    };

    final snapshot = AdminManagementDashboardSnapshot.fromMap(payload);

    expect(snapshot.company.name, 'Empresa Cloud');
    expect(snapshot.period.dayCount, 30);
    expect(snapshot.materialization.coverage.productDailyRows, 45);
    expect(snapshot.headline.salesAmountCents, 120000);
    expect(snapshot.salesSeries.first.cashNetCents, 2800);
    expect(snapshot.topProducts.first.productName, 'Burger');
    expect(snapshot.topCustomers.first.customerName, 'Alice');
  });
}

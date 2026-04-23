import 'package:flutter_test/flutter_test.dart';
import 'package:tatuzin_admin_web/src/core/models/admin_hybrid_governance_models.dart';

void main() {
  test('hybrid governance models parse overview payloads', () {
    final payload = <String, dynamic>{
      'company': {
        'id': 'company_1',
        'name': 'Empresa Hibrida',
        'slug': 'empresa-hibrida',
      },
      'profile': {
        'requireCategoryForGovernedCatalog': true,
        'requireVariantSku': true,
        'requireRemoteImageForGovernedCatalog': false,
        'allowOfflinePriceOverride': true,
        'allowLocalCatalogDeactivation': true,
        'minMarginBasisPoints': 1500,
        'maxOfflineDiscountBasisPoints': 1200,
        'pricePolicyMode': 'governed',
        'stockDivergenceAlertThresholdMil': 5000,
        'allowOfflineStockAdjustments': true,
        'requireStockReconciliationReview': false,
        'customerMasterMode': 'cloud_master',
        'allowOperationalCustomerNotes': true,
        'allowOperationalCustomerAddressOverride': true,
        'requireCustomerConflictReview': false,
        'promotionMode': 'manual_preview',
        'allowPromotionStacking': false,
        'requireGovernedPriceForPromotion': true,
        'alertOnCatalogDrift': true,
        'alertOnStockDivergence': true,
        'alertOnCustomerConflict': true,
        'createdAt': '2026-04-23T20:00:00.000Z',
        'updatedAt': '2026-04-23T20:30:00.000Z',
      },
      'capabilities': {
        'remoteImageMirrorAvailable': false,
        'localStockTelemetryAvailable': false,
        'futurePromotionEngineReady': false,
      },
      'truthRules': [
        {
          'domain': 'catalog',
          'operationalSource': 'SQLite local no app.',
          'cloudSource': 'Backend consolida politicas.',
          'conflictPolicy': 'Drift gera alerta.',
          'offlineBehavior': 'Venda local nao bloqueia.',
        },
      ],
      'catalog': {
        'totalProducts': 12,
        'activeProducts': 10,
        'activeCategories': 3,
        'variantProducts': 4,
        'productsWithoutCategory': 2,
        'productsWithBlankVariantSku': 1,
        'remoteImageMirrorAvailable': false,
        'imageGovernanceStatus': 'not_mirrored_to_cloud',
        'governanceReadiness': 'needs_attention',
      },
      'pricing': {
        'pricedProductsCount': 10,
        'productsBelowMarginPolicy': 2,
        'lowestMarginBasisPoints': 800,
        'minMarginBasisPoints': 1500,
        'maxOfflineDiscountBasisPoints': 1200,
        'allowOfflinePriceOverride': true,
        'policyMode': 'governed',
      },
      'stock': {
        'totalCloudStockMil': 18500,
        'productsWithoutCloudStock': 3,
        'variantAggregationMismatchCount': 1,
        'divergenceAlertThresholdMil': 5000,
        'localTelemetryAvailable': false,
        'reconciliationReadiness': 'requires_future_local_snapshot',
      },
      'customers': {
        'totalCustomers': 8,
        'activeCustomers': 7,
        'customersWithoutPhone': 2,
        'duplicatePhoneConflictCount': 2,
        'duplicateNameConflictCount': 1,
        'crmEnrichedCustomersCount': 3,
        'masterMode': 'cloud_master',
      },
      'alerts': [
        {
          'code': 'catalog_missing_category',
          'domain': 'catalog',
          'severity': 'warning',
          'title': 'Produtos sem categoria',
          'summary': 'Ha drift de catalogo.',
          'count': 2,
        },
      ],
    };

    final overview = AdminHybridGovernanceOverview.fromMap(payload);

    expect(overview.company.slug, 'empresa-hibrida');
    expect(overview.profile.pricePolicyMode, 'governed');
    expect(overview.capabilities.remoteImageMirrorAvailable, isFalse);
    expect(overview.truthRules.single.domain, 'catalog');
    expect(overview.catalog.productsWithoutCategory, 2);
    expect(overview.pricing.productsBelowMarginPolicy, 2);
    expect(overview.stock.variantAggregationMismatchCount, 1);
    expect(overview.customers.duplicatePhoneConflictCount, 2);
    expect(overview.alerts.single.code, 'catalog_missing_category');
  });
}

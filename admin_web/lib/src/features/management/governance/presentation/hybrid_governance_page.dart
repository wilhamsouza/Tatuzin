import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/auth/admin_providers.dart';
import '../../../../core/models/admin_hybrid_governance_models.dart';
import '../../../../core/models/admin_models.dart';
import '../../../../core/utils/admin_formatters.dart';
import '../../../../core/widgets/admin_surface.dart';

class HybridGovernancePage extends ConsumerStatefulWidget {
  const HybridGovernancePage({super.key});

  @override
  ConsumerState<HybridGovernancePage> createState() =>
      _HybridGovernancePageState();
}

class _HybridGovernancePageState extends ConsumerState<HybridGovernancePage> {
  late final TextEditingController _minMarginController;
  late final TextEditingController _maxOfflineDiscountController;
  late final TextEditingController _stockThresholdController;

  String? _selectedCompanyId;
  String? _hydratedCompanyId;
  DateTime? _hydratedProfileUpdatedAt;

  bool _requireCategoryForGovernedCatalog = true;
  bool _requireVariantSku = true;
  bool _requireRemoteImageForGovernedCatalog = false;
  bool _allowOfflinePriceOverride = true;
  bool _allowLocalCatalogDeactivation = true;
  bool _allowOfflineStockAdjustments = true;
  bool _requireStockReconciliationReview = false;
  bool _allowOperationalCustomerNotes = true;
  bool _allowOperationalCustomerAddressOverride = true;
  bool _requireCustomerConflictReview = false;
  bool _allowPromotionStacking = false;
  bool _requireGovernedPriceForPromotion = true;
  bool _alertOnCatalogDrift = true;
  bool _alertOnStockDivergence = true;
  bool _alertOnCustomerConflict = true;
  String _pricePolicyMode = 'advisory';
  String _customerMasterMode = 'cloud_master';
  String _promotionMode = 'manual_preview';
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _minMarginController = TextEditingController();
    _maxOfflineDiscountController = TextEditingController();
    _stockThresholdController = TextEditingController();
  }

  @override
  void dispose() {
    _minMarginController.dispose();
    _maxOfflineDiscountController.dispose();
    _stockThresholdController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final companiesAsync = ref.watch(adminManagementCompanyOptionsProvider);

    return companiesAsync.when(
      data: (companies) {
        if (companies.isEmpty) {
          return const AdminSurface(
            title: 'Sem empresas para governanca hibrida',
            subtitle:
                'A governanca hibrida cloud-first aparece aqui quando houver empresa consolidada no backend.',
            child: SizedBox.shrink(),
          );
        }

        final effectiveCompanyId = _resolveCompanyId(companies);
        final overviewAsync = ref.watch(
          adminHybridGovernanceOverviewProvider(effectiveCompanyId),
        );

        return overviewAsync.when(
          data: (overview) {
            _hydrateDraftIfNeeded(effectiveCompanyId, overview.profile);

            return SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _ScopePanel(
                    companies: companies,
                    selectedCompanyId: effectiveCompanyId,
                    onCompanyChanged: (value) {
                      setState(() {
                        _selectedCompanyId = value;
                        _hydratedCompanyId = null;
                      });
                    },
                    onRefresh: () =>
                        ref.read(adminRefreshTickProvider.notifier).state++,
                  ),
                  const SizedBox(height: 24),
                  _HeaderSurface(overview: overview),
                  const SizedBox(height: 24),
                  _TruthRulesSurface(truthRules: overview.truthRules),
                  const SizedBox(height: 24),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final catalog = _DomainSummarySurface(
                        title: 'Catalogo hibrido',
                        subtitle:
                            'Produto, categoria, variantes, imagem e readiness de governanca remota.',
                        metrics: [
                          _MetricItem(
                            label: 'Produtos ativos',
                            value: '${overview.catalog.activeProducts}',
                            helper:
                                '${overview.catalog.activeCategories} categoria(s) ativa(s)',
                          ),
                          _MetricItem(
                            label: 'Sem categoria',
                            value:
                                '${overview.catalog.productsWithoutCategory}',
                            helper: 'Drift de classificacao remota',
                          ),
                          _MetricItem(
                            label: 'Variantes sem SKU',
                            value:
                                '${overview.catalog.productsWithBlankVariantSku}',
                            helper:
                                '${overview.catalog.variantProducts} catalogo(s) com variantes',
                          ),
                          _MetricItem(
                            label: 'Imagem cloud',
                            value: AdminFormatters.formatHybridMode(
                              overview.catalog.imageGovernanceStatus,
                            ),
                            helper:
                                overview.capabilities.remoteImageMirrorAvailable
                                ? 'Midia espelhada no backend'
                                : 'Foto ainda e local no app',
                          ),
                        ],
                      );

                      final pricing = _DomainSummarySurface(
                        title: 'Preco hibrido',
                        subtitle:
                            'Politica remota de margem e desconto sem travar override local quando permitido.',
                        metrics: [
                          _MetricItem(
                            label: 'Modo',
                            value: AdminFormatters.formatHybridMode(
                              overview.pricing.policyMode,
                            ),
                            helper: overview.pricing.allowOfflinePriceOverride
                                ? 'Override local permitido'
                                : 'Override local desaconselhado',
                          ),
                          _MetricItem(
                            label: 'Abaixo da margem',
                            value:
                                '${overview.pricing.productsBelowMarginPolicy}',
                            helper:
                                'Minimo ${AdminFormatters.formatBasisPointsPercent(overview.pricing.minMarginBasisPoints)}',
                          ),
                          _MetricItem(
                            label: 'Menor margem',
                            value:
                                overview.pricing.lowestMarginBasisPoints == null
                                ? 'Nao definido'
                                : AdminFormatters.formatBasisPointsPercent(
                                    overview.pricing.lowestMarginBasisPoints!,
                                  ),
                            helper:
                                'Produtos precificados: ${overview.pricing.pricedProductsCount}',
                          ),
                        ],
                      );

                      final stock = _DomainSummarySurface(
                        title: 'Estoque hibrido',
                        subtitle:
                            'Cloud ve consolidado sincronizado; app segue com estoque operacional local conhecido.',
                        metrics: [
                          _MetricItem(
                            label: 'Estoque cloud',
                            value: overview.stock.totalCloudStockMil.toString(),
                            helper: 'Em mil-unidades espelhadas',
                          ),
                          _MetricItem(
                            label: 'Sem saldo cloud',
                            value:
                                '${overview.stock.productsWithoutCloudStock}',
                            helper:
                                'Produto(s) com saldo zero ou negativo no espelho',
                          ),
                          _MetricItem(
                            label: 'Divergencia de variante',
                            value:
                                '${overview.stock.variantAggregationMismatchCount}',
                            helper:
                                'Threshold ${overview.stock.divergenceAlertThresholdMil}',
                          ),
                          _MetricItem(
                            label: 'Reconciliacao',
                            value: AdminFormatters.formatHybridMode(
                              overview.stock.reconciliationReadiness,
                            ),
                            helper:
                                overview
                                    .capabilities
                                    .localStockTelemetryAvailable
                                ? 'Snapshot local ja disponivel'
                                : 'Snapshot local futuro ainda necessario',
                          ),
                        ],
                      );

                      final customers = _DomainSummarySurface(
                        title: 'Clientes hibridos',
                        subtitle:
                            'Snapshot operacional leve no app com customer master e conflito governados no cloud.',
                        metrics: [
                          _MetricItem(
                            label: 'Clientes ativos',
                            value: '${overview.customers.activeCustomers}',
                            helper:
                                'CRM enriquecido: ${overview.customers.crmEnrichedCustomersCount}',
                          ),
                          _MetricItem(
                            label: 'Sem telefone',
                            value:
                                '${overview.customers.customersWithoutPhone}',
                            helper: 'Contato incompleto para governanca',
                          ),
                          _MetricItem(
                            label: 'Conflito de telefone',
                            value:
                                '${overview.customers.duplicatePhoneConflictCount}',
                            helper:
                                'Conflito de nome: ${overview.customers.duplicateNameConflictCount}',
                          ),
                          _MetricItem(
                            label: 'Master',
                            value: AdminFormatters.formatHybridMode(
                              overview.customers.masterMode,
                            ),
                            helper: _allowOperationalCustomerNotes
                                ? 'Notas operacionais locais permitidas'
                                : 'Notas operacionais restritas',
                          ),
                        ],
                      );

                      if (constraints.maxWidth < 1200) {
                        return Column(
                          children: [
                            catalog,
                            const SizedBox(height: 24),
                            pricing,
                            const SizedBox(height: 24),
                            stock,
                            const SizedBox(height: 24),
                            customers,
                          ],
                        );
                      }

                      return Column(
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(child: catalog),
                              const SizedBox(width: 24),
                              Expanded(child: pricing),
                            ],
                          ),
                          const SizedBox(height: 24),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(child: stock),
                              const SizedBox(width: 24),
                              Expanded(child: customers),
                            ],
                          ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 24),
                  _PolicyEditorSurface(
                    isSaving: _isSaving,
                    minMarginController: _minMarginController,
                    maxOfflineDiscountController: _maxOfflineDiscountController,
                    stockThresholdController: _stockThresholdController,
                    pricePolicyMode: _pricePolicyMode,
                    customerMasterMode: _customerMasterMode,
                    promotionMode: _promotionMode,
                    requireCategoryForGovernedCatalog:
                        _requireCategoryForGovernedCatalog,
                    requireVariantSku: _requireVariantSku,
                    requireRemoteImageForGovernedCatalog:
                        _requireRemoteImageForGovernedCatalog,
                    allowOfflinePriceOverride: _allowOfflinePriceOverride,
                    allowLocalCatalogDeactivation:
                        _allowLocalCatalogDeactivation,
                    allowOfflineStockAdjustments: _allowOfflineStockAdjustments,
                    requireStockReconciliationReview:
                        _requireStockReconciliationReview,
                    allowOperationalCustomerNotes:
                        _allowOperationalCustomerNotes,
                    allowOperationalCustomerAddressOverride:
                        _allowOperationalCustomerAddressOverride,
                    requireCustomerConflictReview:
                        _requireCustomerConflictReview,
                    allowPromotionStacking: _allowPromotionStacking,
                    requireGovernedPriceForPromotion:
                        _requireGovernedPriceForPromotion,
                    alertOnCatalogDrift: _alertOnCatalogDrift,
                    alertOnStockDivergence: _alertOnStockDivergence,
                    alertOnCustomerConflict: _alertOnCustomerConflict,
                    onPricePolicyModeChanged: (value) =>
                        setState(() => _pricePolicyMode = value),
                    onCustomerMasterModeChanged: (value) =>
                        setState(() => _customerMasterMode = value),
                    onPromotionModeChanged: (value) =>
                        setState(() => _promotionMode = value),
                    onRequireCategoryChanged: (value) => setState(
                      () => _requireCategoryForGovernedCatalog = value,
                    ),
                    onRequireVariantSkuChanged: (value) =>
                        setState(() => _requireVariantSku = value),
                    onRequireRemoteImageChanged: (value) => setState(
                      () => _requireRemoteImageForGovernedCatalog = value,
                    ),
                    onAllowOfflinePriceOverrideChanged: (value) =>
                        setState(() => _allowOfflinePriceOverride = value),
                    onAllowLocalCatalogDeactivationChanged: (value) =>
                        setState(() => _allowLocalCatalogDeactivation = value),
                    onAllowOfflineStockAdjustmentsChanged: (value) =>
                        setState(() => _allowOfflineStockAdjustments = value),
                    onRequireStockReviewChanged: (value) => setState(
                      () => _requireStockReconciliationReview = value,
                    ),
                    onAllowOperationalCustomerNotesChanged: (value) =>
                        setState(() => _allowOperationalCustomerNotes = value),
                    onAllowOperationalCustomerAddressOverrideChanged: (value) =>
                        setState(
                          () =>
                              _allowOperationalCustomerAddressOverride = value,
                        ),
                    onRequireCustomerConflictReviewChanged: (value) =>
                        setState(() => _requireCustomerConflictReview = value),
                    onAllowPromotionStackingChanged: (value) =>
                        setState(() => _allowPromotionStacking = value),
                    onRequireGovernedPriceForPromotionChanged: (value) =>
                        setState(
                          () => _requireGovernedPriceForPromotion = value,
                        ),
                    onAlertOnCatalogDriftChanged: (value) =>
                        setState(() => _alertOnCatalogDrift = value),
                    onAlertOnStockDivergenceChanged: (value) =>
                        setState(() => _alertOnStockDivergence = value),
                    onAlertOnCustomerConflictChanged: (value) =>
                        setState(() => _alertOnCustomerConflict = value),
                    onSave: () =>
                        _saveProfile(effectiveCompanyId, overview.profile),
                  ),
                  const SizedBox(height: 24),
                  _AlertsSurface(alerts: overview.alerts),
                ],
              ),
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => AdminSurface(
            title: 'Nao foi possivel carregar a governanca hibrida',
            subtitle: error.toString(),
            child: Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.tonal(
                onPressed: () =>
                    ref.read(adminRefreshTickProvider.notifier).state++,
                child: const Text('Tentar novamente'),
              ),
            ),
          ),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => AdminSurface(
        title: 'Nao foi possivel carregar as empresas',
        subtitle: error.toString(),
        child: const SizedBox.shrink(),
      ),
    );
  }

  String _resolveCompanyId(List<AdminCompanySummary> companies) {
    final requestedCompanyId = _selectedCompanyId;
    for (final company in companies) {
      if (company.id == requestedCompanyId) {
        return company.id;
      }
    }
    return companies.first.id;
  }

  void _hydrateDraftIfNeeded(
    String companyId,
    AdminHybridGovernanceProfile profile,
  ) {
    final shouldHydrate =
        _hydratedCompanyId != companyId ||
        _hydratedProfileUpdatedAt != profile.updatedAt;

    if (!shouldHydrate) {
      return;
    }

    _hydratedCompanyId = companyId;
    _hydratedProfileUpdatedAt = profile.updatedAt;
    _requireCategoryForGovernedCatalog =
        profile.requireCategoryForGovernedCatalog;
    _requireVariantSku = profile.requireVariantSku;
    _requireRemoteImageForGovernedCatalog =
        profile.requireRemoteImageForGovernedCatalog;
    _allowOfflinePriceOverride = profile.allowOfflinePriceOverride;
    _allowLocalCatalogDeactivation = profile.allowLocalCatalogDeactivation;
    _allowOfflineStockAdjustments = profile.allowOfflineStockAdjustments;
    _requireStockReconciliationReview =
        profile.requireStockReconciliationReview;
    _allowOperationalCustomerNotes = profile.allowOperationalCustomerNotes;
    _allowOperationalCustomerAddressOverride =
        profile.allowOperationalCustomerAddressOverride;
    _requireCustomerConflictReview = profile.requireCustomerConflictReview;
    _allowPromotionStacking = profile.allowPromotionStacking;
    _requireGovernedPriceForPromotion =
        profile.requireGovernedPriceForPromotion;
    _alertOnCatalogDrift = profile.alertOnCatalogDrift;
    _alertOnStockDivergence = profile.alertOnStockDivergence;
    _alertOnCustomerConflict = profile.alertOnCustomerConflict;
    _pricePolicyMode = profile.pricePolicyMode;
    _customerMasterMode = profile.customerMasterMode;
    _promotionMode = profile.promotionMode;
    _minMarginController.text = '${profile.minMarginBasisPoints}';
    _maxOfflineDiscountController.text =
        '${profile.maxOfflineDiscountBasisPoints}';
    _stockThresholdController.text =
        '${profile.stockDivergenceAlertThresholdMil}';
  }

  Future<void> _saveProfile(
    String companyId,
    AdminHybridGovernanceProfile currentProfile,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final nextProfile = currentProfile.copyWith(
      requireCategoryForGovernedCatalog: _requireCategoryForGovernedCatalog,
      requireVariantSku: _requireVariantSku,
      requireRemoteImageForGovernedCatalog:
          _requireRemoteImageForGovernedCatalog,
      allowOfflinePriceOverride: _allowOfflinePriceOverride,
      allowLocalCatalogDeactivation: _allowLocalCatalogDeactivation,
      minMarginBasisPoints:
          int.tryParse(_minMarginController.text.trim()) ??
          currentProfile.minMarginBasisPoints,
      maxOfflineDiscountBasisPoints:
          int.tryParse(_maxOfflineDiscountController.text.trim()) ??
          currentProfile.maxOfflineDiscountBasisPoints,
      pricePolicyMode: _pricePolicyMode,
      stockDivergenceAlertThresholdMil:
          int.tryParse(_stockThresholdController.text.trim()) ??
          currentProfile.stockDivergenceAlertThresholdMil,
      allowOfflineStockAdjustments: _allowOfflineStockAdjustments,
      requireStockReconciliationReview: _requireStockReconciliationReview,
      customerMasterMode: _customerMasterMode,
      allowOperationalCustomerNotes: _allowOperationalCustomerNotes,
      allowOperationalCustomerAddressOverride:
          _allowOperationalCustomerAddressOverride,
      requireCustomerConflictReview: _requireCustomerConflictReview,
      promotionMode: _promotionMode,
      allowPromotionStacking: _allowPromotionStacking,
      requireGovernedPriceForPromotion: _requireGovernedPriceForPromotion,
      alertOnCatalogDrift: _alertOnCatalogDrift,
      alertOnStockDivergence: _alertOnStockDivergence,
      alertOnCustomerConflict: _alertOnCustomerConflict,
    );

    setState(() => _isSaving = true);
    try {
      await ref
          .read(adminApiServiceProvider)
          .updateHybridGovernanceProfile(
            companyId: companyId,
            profile: nextProfile,
          );
      _hydratedCompanyId = null;
      ref.read(adminRefreshTickProvider.notifier).state++;
      if (!mounted) {
        return;
      }
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Perfil de governanca hibrida atualizado.'),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      messenger.showSnackBar(
        SnackBar(
          content: Text(error.toString()),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }
}

class _ScopePanel extends StatelessWidget {
  const _ScopePanel({
    required this.companies,
    required this.selectedCompanyId,
    required this.onCompanyChanged,
    required this.onRefresh,
  });

  final List<AdminCompanySummary> companies;
  final String selectedCompanyId;
  final ValueChanged<String> onCompanyChanged;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return AdminSurface(
      title: 'Escopo da governanca hibrida',
      subtitle:
          'A governanca cloud-first e lida por empresa e nunca substitui a verdade operacional local do app.',
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        crossAxisAlignment: WrapCrossAlignment.end,
        children: [
          SizedBox(
            width: 280,
            child: DropdownButtonFormField<String>(
              initialValue: selectedCompanyId,
              decoration: const InputDecoration(labelText: 'Empresa'),
              items: companies
                  .map(
                    (company) => DropdownMenuItem<String>(
                      value: company.id,
                      child: Text(company.name),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value != null) {
                  onCompanyChanged(value);
                }
              },
            ),
          ),
          FilledButton.icon(
            onPressed: onRefresh,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Atualizar leitura'),
          ),
        ],
      ),
    );
  }
}

class _HeaderSurface extends StatelessWidget {
  const _HeaderSurface({required this.overview});

  final AdminHybridGovernanceOverview overview;

  @override
  Widget build(BuildContext context) {
    return AdminSurface(
      title: overview.company.name,
      subtitle:
          'Governanca hibrida do tenant ${overview.company.slug}, separando fonte operacional local e espelho cloud de plataforma.',
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          _MutedPill(
            label: overview.capabilities.remoteImageMirrorAvailable
                ? 'Imagem cloud disponivel'
                : 'Imagem ainda local no app',
          ),
          _MutedPill(
            label: overview.capabilities.localStockTelemetryAvailable
                ? 'Snapshot local de estoque disponivel'
                : 'Snapshot local de estoque ainda futuro',
          ),
          _MutedPill(
            label: overview.capabilities.futurePromotionEngineReady
                ? 'Promocao cloud pronta'
                : 'Promocao cloud em base tecnica',
          ),
          _MutedPill(
            label:
                'Perfil atualizado em ${AdminFormatters.formatDateTime(overview.profile.updatedAt)}',
          ),
        ],
      ),
    );
  }
}

class _TruthRulesSurface extends StatelessWidget {
  const _TruthRulesSurface({required this.truthRules});

  final List<AdminHybridGovernanceTruthRule> truthRules;

  @override
  Widget build(BuildContext context) {
    return AdminSurface(
      title: 'Regras de verdade por dominio',
      subtitle:
          'Cada dominio deixa explicito o que e operacional local, o que e governado no cloud e como conflitos devem se comportar.',
      child: Column(
        children: truthRules
            .map(
              (rule) => Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      rule.domain.toUpperCase(),
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _RuleRow(
                      label: 'Operacional',
                      value: rule.operationalSource,
                    ),
                    _RuleRow(label: 'Cloud', value: rule.cloudSource),
                    _RuleRow(label: 'Conflito', value: rule.conflictPolicy),
                    _RuleRow(label: 'Offline', value: rule.offlineBehavior),
                  ],
                ),
              ),
            )
            .toList(growable: false),
      ),
    );
  }
}

class _DomainSummarySurface extends StatelessWidget {
  const _DomainSummarySurface({
    required this.title,
    required this.subtitle,
    required this.metrics,
  });

  final String title;
  final String subtitle;
  final List<_MetricItem> metrics;

  @override
  Widget build(BuildContext context) {
    return AdminSurface(
      title: title,
      subtitle: subtitle,
      child: Column(
        children: metrics
            .map(
              (metric) => Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      metric.label,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      metric.value,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(metric.helper),
                  ],
                ),
              ),
            )
            .toList(growable: false),
      ),
    );
  }
}

class _PolicyEditorSurface extends StatelessWidget {
  const _PolicyEditorSurface({
    required this.isSaving,
    required this.minMarginController,
    required this.maxOfflineDiscountController,
    required this.stockThresholdController,
    required this.pricePolicyMode,
    required this.customerMasterMode,
    required this.promotionMode,
    required this.requireCategoryForGovernedCatalog,
    required this.requireVariantSku,
    required this.requireRemoteImageForGovernedCatalog,
    required this.allowOfflinePriceOverride,
    required this.allowLocalCatalogDeactivation,
    required this.allowOfflineStockAdjustments,
    required this.requireStockReconciliationReview,
    required this.allowOperationalCustomerNotes,
    required this.allowOperationalCustomerAddressOverride,
    required this.requireCustomerConflictReview,
    required this.allowPromotionStacking,
    required this.requireGovernedPriceForPromotion,
    required this.alertOnCatalogDrift,
    required this.alertOnStockDivergence,
    required this.alertOnCustomerConflict,
    required this.onPricePolicyModeChanged,
    required this.onCustomerMasterModeChanged,
    required this.onPromotionModeChanged,
    required this.onRequireCategoryChanged,
    required this.onRequireVariantSkuChanged,
    required this.onRequireRemoteImageChanged,
    required this.onAllowOfflinePriceOverrideChanged,
    required this.onAllowLocalCatalogDeactivationChanged,
    required this.onAllowOfflineStockAdjustmentsChanged,
    required this.onRequireStockReviewChanged,
    required this.onAllowOperationalCustomerNotesChanged,
    required this.onAllowOperationalCustomerAddressOverrideChanged,
    required this.onRequireCustomerConflictReviewChanged,
    required this.onAllowPromotionStackingChanged,
    required this.onRequireGovernedPriceForPromotionChanged,
    required this.onAlertOnCatalogDriftChanged,
    required this.onAlertOnStockDivergenceChanged,
    required this.onAlertOnCustomerConflictChanged,
    required this.onSave,
  });

  final bool isSaving;
  final TextEditingController minMarginController;
  final TextEditingController maxOfflineDiscountController;
  final TextEditingController stockThresholdController;
  final String pricePolicyMode;
  final String customerMasterMode;
  final String promotionMode;
  final bool requireCategoryForGovernedCatalog;
  final bool requireVariantSku;
  final bool requireRemoteImageForGovernedCatalog;
  final bool allowOfflinePriceOverride;
  final bool allowLocalCatalogDeactivation;
  final bool allowOfflineStockAdjustments;
  final bool requireStockReconciliationReview;
  final bool allowOperationalCustomerNotes;
  final bool allowOperationalCustomerAddressOverride;
  final bool requireCustomerConflictReview;
  final bool allowPromotionStacking;
  final bool requireGovernedPriceForPromotion;
  final bool alertOnCatalogDrift;
  final bool alertOnStockDivergence;
  final bool alertOnCustomerConflict;
  final ValueChanged<String> onPricePolicyModeChanged;
  final ValueChanged<String> onCustomerMasterModeChanged;
  final ValueChanged<String> onPromotionModeChanged;
  final ValueChanged<bool> onRequireCategoryChanged;
  final ValueChanged<bool> onRequireVariantSkuChanged;
  final ValueChanged<bool> onRequireRemoteImageChanged;
  final ValueChanged<bool> onAllowOfflinePriceOverrideChanged;
  final ValueChanged<bool> onAllowLocalCatalogDeactivationChanged;
  final ValueChanged<bool> onAllowOfflineStockAdjustmentsChanged;
  final ValueChanged<bool> onRequireStockReviewChanged;
  final ValueChanged<bool> onAllowOperationalCustomerNotesChanged;
  final ValueChanged<bool> onAllowOperationalCustomerAddressOverrideChanged;
  final ValueChanged<bool> onRequireCustomerConflictReviewChanged;
  final ValueChanged<bool> onAllowPromotionStackingChanged;
  final ValueChanged<bool> onRequireGovernedPriceForPromotionChanged;
  final ValueChanged<bool> onAlertOnCatalogDriftChanged;
  final ValueChanged<bool> onAlertOnStockDivergenceChanged;
  final ValueChanged<bool> onAlertOnCustomerConflictChanged;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return AdminSurface(
      title: 'Politica de governanca por empresa',
      subtitle:
          'Essas regras orientam catalogo, preco, estoque, clientes e alertas administrativos sem virar trava de venda local.',
      trailing: FilledButton.icon(
        onPressed: isSaving ? null : onSave,
        icon: const Icon(Icons.save_rounded),
        label: Text(isSaving ? 'Salvando...' : 'Salvar politica'),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final leftColumn = _PolicyColumn(
                title: 'Catalogo e preco',
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: requireCategoryForGovernedCatalog,
                    onChanged: onRequireCategoryChanged,
                    title: const Text(
                      'Exigir categoria para catalogo governado',
                    ),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: requireVariantSku,
                    onChanged: onRequireVariantSkuChanged,
                    title: const Text('Exigir SKU em variantes'),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: requireRemoteImageForGovernedCatalog,
                    onChanged: onRequireRemoteImageChanged,
                    title: const Text('Exigir imagem cloud oficial'),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: allowOfflinePriceOverride,
                    onChanged: onAllowOfflinePriceOverrideChanged,
                    title: const Text('Permitir override local de preco'),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: allowLocalCatalogDeactivation,
                    onChanged: onAllowLocalCatalogDeactivationChanged,
                    title: const Text('Permitir desativacao local de catalogo'),
                  ),
                  DropdownButtonFormField<String>(
                    initialValue: pricePolicyMode,
                    decoration: const InputDecoration(
                      labelText: 'Modo da politica de preco',
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'advisory',
                        child: Text('Advisory'),
                      ),
                      DropdownMenuItem(
                        value: 'governed',
                        child: Text('Governado'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        onPricePolicyModeChanged(value);
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: minMarginController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Margem minima (basis points)',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: maxOfflineDiscountController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Desconto maximo offline (basis points)',
                    ),
                  ),
                ],
              );

              final middleColumn = _PolicyColumn(
                title: 'Estoque e clientes',
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: allowOfflineStockAdjustments,
                    onChanged: onAllowOfflineStockAdjustmentsChanged,
                    title: const Text('Permitir ajustes locais de estoque'),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: requireStockReconciliationReview,
                    onChanged: onRequireStockReviewChanged,
                    title: const Text('Exigir revisao de reconciliacao'),
                  ),
                  TextField(
                    controller: stockThresholdController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Threshold de divergencia de estoque (mil)',
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: customerMasterMode,
                    decoration: const InputDecoration(
                      labelText: 'Modo do customer master',
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'cloud_master',
                        child: Text('Cloud master'),
                      ),
                      DropdownMenuItem(
                        value: 'hybrid_review',
                        child: Text('Revisao hibrida'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        onCustomerMasterModeChanged(value);
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: allowOperationalCustomerNotes,
                    onChanged: onAllowOperationalCustomerNotesChanged,
                    title: const Text('Permitir nota operacional local'),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: allowOperationalCustomerAddressOverride,
                    onChanged: onAllowOperationalCustomerAddressOverrideChanged,
                    title: const Text('Permitir endereco operacional local'),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: requireCustomerConflictReview,
                    onChanged: onRequireCustomerConflictReviewChanged,
                    title: const Text('Exigir revisao de conflito de cliente'),
                  ),
                ],
              );

              final rightColumn = _PolicyColumn(
                title: 'Promocoes e alertas',
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: promotionMode,
                    decoration: const InputDecoration(
                      labelText: 'Modo de promocao futura',
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'manual_preview',
                        child: Text('Preview manual'),
                      ),
                      DropdownMenuItem(
                        value: 'scheduled_review',
                        child: Text('Revisao agendada'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        onPromotionModeChanged(value);
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: allowPromotionStacking,
                    onChanged: onAllowPromotionStackingChanged,
                    title: const Text('Permitir stacking de promocao'),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: requireGovernedPriceForPromotion,
                    onChanged: onRequireGovernedPriceForPromotionChanged,
                    title: const Text('Exigir preco governado para promocao'),
                  ),
                  const Divider(height: 24),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: alertOnCatalogDrift,
                    onChanged: onAlertOnCatalogDriftChanged,
                    title: const Text('Alertar drift de catalogo'),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: alertOnStockDivergence,
                    onChanged: onAlertOnStockDivergenceChanged,
                    title: const Text('Alertar divergencia de estoque'),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: alertOnCustomerConflict,
                    onChanged: onAlertOnCustomerConflictChanged,
                    title: const Text('Alertar conflito de customer master'),
                  ),
                ],
              );

              if (constraints.maxWidth < 1280) {
                return Column(
                  children: [
                    leftColumn,
                    const SizedBox(height: 24),
                    middleColumn,
                    const SizedBox(height: 24),
                    rightColumn,
                  ],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: leftColumn),
                  const SizedBox(width: 24),
                  Expanded(child: middleColumn),
                  const SizedBox(width: 24),
                  Expanded(child: rightColumn),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _AlertsSurface extends StatelessWidget {
  const _AlertsSurface({required this.alerts});

  final List<AdminHybridGovernanceAlert> alerts;

  @override
  Widget build(BuildContext context) {
    return AdminSurface(
      title: 'Alertas administrativos',
      subtitle:
          'Os alertas sobem para governanca e suporte sem impedir operacao local do app.',
      child: Column(
        children: alerts
            .map(
              (alert) => Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        Chip(
                          label: Text(
                            AdminFormatters.formatAlertSeverity(alert.severity),
                          ),
                        ),
                        Chip(label: Text(alert.domain.toUpperCase())),
                        if (alert.count > 0)
                          Chip(label: Text('${alert.count}')),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      alert.title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(alert.summary),
                  ],
                ),
              ),
            )
            .toList(growable: false),
      ),
    );
  }
}

class _PolicyColumn extends StatelessWidget {
  const _PolicyColumn({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }
}

class _RuleRow extends StatelessWidget {
  const _RuleRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}

class _MutedPill extends StatelessWidget {
  const _MutedPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label, style: Theme.of(context).textTheme.bodySmall),
    );
  }
}

class _MetricItem {
  const _MetricItem({
    required this.label,
    required this.value,
    required this.helper,
  });

  final String label;
  final String value;
  final String helper;
}

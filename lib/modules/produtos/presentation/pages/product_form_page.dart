import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../app/core/formatters/app_formatters.dart';
import '../../../../app/core/providers/app_data_refresh_provider.dart';
import '../../../../app/core/utils/money_parser.dart';
import '../../../../app/core/utils/quantity_parser.dart';
import '../../../categorias/domain/entities/category.dart';
import '../../../categorias/presentation/providers/category_providers.dart';
import '../../domain/entities/base_product.dart';
import '../../domain/entities/product.dart';
import '../providers/product_providers.dart';

class ProductFormPage extends ConsumerStatefulWidget {
  const ProductFormPage({super.key, this.initialProduct});

  final Product? initialProduct;

  @override
  ConsumerState<ProductFormPage> createState() => _ProductFormPageState();
}

class _ProductFormPageState extends ConsumerState<ProductFormPage> {
  static const _maxPhotos = 6;

  final _formKey = GlobalKey<FormState>();
  final ImagePicker _imagePicker = ImagePicker();
  late final TextEditingController _nameController;
  late final TextEditingController _modelNameController;
  late final TextEditingController _variantLabelController;
  late final TextEditingController _extraAttributesController;
  late final TextEditingController _modifierGroupsController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _barcodeController;
  late final TextEditingController _costController;
  late final TextEditingController _priceController;
  late final TextEditingController _stockController;
  late final TextEditingController _foodAllergensController;
  late final TextEditingController _foodPrepTimeController;
  late final TextEditingController _foodOperationalAvailabilityController;
  late final TextEditingController _fashionCompositionController;
  late final TextEditingController _fashionWeightController;
  late final TextEditingController _fashionBrandController;
  late final TextEditingController _fashionTagsController;
  late final TextEditingController _fashionSizeHintController;
  late final TextEditingController _fashionSizeInputController;
  late final TextEditingController _fashionColorInputController;
  late bool _isActive;
  bool _isFeatured = false;
  bool _isPromotion = false;
  int? _selectedCategoryId;
  int? _selectedBaseProductId;
  late String _selectedUnitMeasure;
  late String _selectedNiche;
  late String _selectedCatalogType;
  bool _isLoadingAdvancedData = false;
  bool _isPickingPhoto = false;
  bool _isSaving = false;
  List<_EditableProductPhoto> _photos = <_EditableProductPhoto>[];
  List<_EditableModifierGroup> _foodModifierGroups = <_EditableModifierGroup>[];
  List<_EditableFashionGradeEntry> _fashionGradeEntries =
      <_EditableFashionGradeEntry>[];
  List<String> _fashionSizes = <String>[];
  List<String> _fashionColors = <String>[];
  final Map<String, TextEditingController> _fashionGradeCellControllers =
      <String, TextEditingController>{};

  bool get _isEditing => widget.initialProduct != null;
  bool get _isVariantCatalog =>
      _selectedCatalogType == ProductCatalogTypes.variant;
  bool get _isFoodNiche => _selectedNiche == ProductNiches.food;
  bool get _isFashionNiche => _selectedNiche == ProductNiches.fashion;

  @override
  void initState() {
    super.initState();
    final product = widget.initialProduct;
    final structuredVariant =
        product != null &&
        product.catalogType == ProductCatalogTypes.variant &&
        (product.modelName?.trim().isNotEmpty ?? false) &&
        (product.variantLabel?.trim().isNotEmpty ?? false);

    _selectedCatalogType = structuredVariant
        ? ProductCatalogTypes.variant
        : ProductCatalogTypes.simple;
    _nameController = TextEditingController(
      text: structuredVariant ? '' : product?.name ?? '',
    );
    _modelNameController = TextEditingController(
      text: structuredVariant ? product.modelName ?? '' : '',
    );
    _variantLabelController = TextEditingController(
      text: structuredVariant ? product.variantLabel ?? '' : '',
    );
    _extraAttributesController = TextEditingController(
      text: _buildInitialExtraAttributes(product),
    );
    _modifierGroupsController = TextEditingController(
      text: _buildInitialModifierGroups(product),
    );
    _descriptionController = TextEditingController(
      text: product?.description ?? '',
    );
    _barcodeController = TextEditingController(text: product?.barcode ?? '');
    _costController = TextEditingController(
      text: AppFormatters.currencyInputFromCents(product?.costCents ?? 0),
    );
    _priceController = TextEditingController(
      text: AppFormatters.currencyInputFromCents(product?.salePriceCents ?? 0),
    );
    _stockController = TextEditingController(
      text: AppFormatters.quantityFromMil(product?.stockMil ?? 0),
    );
    _foodAllergensController = TextEditingController(
      text: _findVariantAttributeValue(product, 'food_allergens') ?? '',
    );
    _foodPrepTimeController = TextEditingController(
      text: _findVariantAttributeValue(product, 'food_prep_time_minutes') ?? '',
    );
    _foodOperationalAvailabilityController = TextEditingController(
      text:
          _findVariantAttributeValue(
            product,
            'food_operational_availability',
          ) ??
          '',
    );
    _fashionCompositionController = TextEditingController(
      text: _findVariantAttributeValue(product, 'fashion_composition') ?? '',
    );
    _fashionWeightController = TextEditingController(
      text: _findVariantAttributeValue(product, 'fashion_weight_grams') ?? '',
    );
    _fashionBrandController = TextEditingController(
      text: _findVariantAttributeValue(product, 'fashion_brand') ?? '',
    );
    _fashionTagsController = TextEditingController(
      text: _buildDelimitedAttributeList(
        _findVariantAttributeValue(product, 'fashion_tags'),
      ),
    );
    _fashionSizeHintController = TextEditingController(
      text: _findVariantAttributeValue(product, 'fashion_size_grid_hint') ?? '',
    );
    _fashionSizeInputController = TextEditingController();
    _fashionColorInputController = TextEditingController();
    _isActive = product?.isActive ?? true;
    _selectedCategoryId = product?.categoryId;
    _selectedBaseProductId = product?.baseProductId;
    _selectedUnitMeasure = product?.unitMeasure ?? 'un';
    _selectedNiche = ProductNiches.normalize(product?.niche);
    _photos = product?.hasPhoto ?? false
        ? <_EditableProductPhoto>[
            _EditableProductPhoto(
              localPath: product!.primaryPhotoPath!,
              isPrimary: true,
            ),
          ]
        : <_EditableProductPhoto>[];
    _hydrateFashionGridState();

    _loadAdvancedData();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _modelNameController.dispose();
    _variantLabelController.dispose();
    _extraAttributesController.dispose();
    _modifierGroupsController.dispose();
    _descriptionController.dispose();
    _barcodeController.dispose();
    _costController.dispose();
    _priceController.dispose();
    _stockController.dispose();
    _foodAllergensController.dispose();
    _foodPrepTimeController.dispose();
    _foodOperationalAvailabilityController.dispose();
    _fashionCompositionController.dispose();
    _fashionWeightController.dispose();
    _fashionBrandController.dispose();
    _fashionTagsController.dispose();
    _fashionSizeHintController.dispose();
    _fashionSizeInputController.dispose();
    _fashionColorInputController.dispose();
    for (final controller in _fashionGradeCellControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _loadAdvancedData() async {
    final product = widget.initialProduct;
    if (product == null) {
      return;
    }

    setState(() => _isLoadingAdvancedData = true);
    try {
      final localProductRepository = ref.read(localProductRepositoryProvider);
      final localCatalogRepository = ref.read(localCatalogRepositoryProvider);
      final photos = await localProductRepository.listProductPhotos(product.id);
      final productVariants = await localProductRepository.listProductVariants(
        product.id,
      );

      final editablePhotos = photos.isNotEmpty
          ? photos
                .map(
                  (photo) => _EditableProductPhoto(
                    localPath: photo.localPath,
                    isPrimary: photo.isPrimary,
                  ),
                )
                .toList(growable: false)
          : _photos;

      List<_EditableModifierGroup> editableGroups = <_EditableModifierGroup>[];
      if (product.baseProductId != null) {
        final groups = await localCatalogRepository.listModifierGroups(
          product.baseProductId!,
        );
        final loadedGroups = <_EditableModifierGroup>[];
        for (final group in groups) {
          final options = await localCatalogRepository.listModifierOptions(
            group.id,
          );
          loadedGroups.add(
            _EditableModifierGroup(
              name: group.name,
              isRequired: group.isRequired,
              minSelections: group.minSelections,
              maxSelections: group.maxSelections,
              options: options
                  .map(
                    (option) => _EditableModifierOption(
                      name: option.name,
                      adjustmentType: option.adjustmentType,
                      priceDeltaCents: option.priceDeltaCents,
                    ),
                  )
                  .toList(growable: false),
            ),
          );
        }
        editableGroups = loadedGroups;
      }

      if (!mounted) {
        return;
      }
      setState(() {
        _photos = editablePhotos;
        _foodModifierGroups = editableGroups;
        _fashionGradeEntries =
            (productVariants.isNotEmpty
                    ? productVariants.map(
                        (variant) => _EditableFashionGradeEntry(
                          sizeLabel: variant.sizeLabel,
                          colorLabel: variant.colorLabel,
                          stockText: AppFormatters.quantityFromMil(
                            variant.stockMil,
                          ),
                          sku: variant.sku,
                          priceAdditionalText:
                              AppFormatters.currencyInputFromCents(
                                variant.priceAdditionalCents,
                              ),
                          isActive: variant.isActive,
                        ),
                      )
                    : <_EditableFashionGradeEntry>[])
                .toList(growable: false);
        _hydrateFashionGridState();
      });
    } finally {
      if (mounted) {
        setState(() => _isLoadingAdvancedData = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final categoriesAsync = ref.watch(categoryOptionsProvider);
    final baseProductsAsync = ref.watch(baseProductOptionsProvider);
    final categories = categoriesAsync.valueOrNull ?? const <Category>[];
    final baseProducts = baseProductsAsync.valueOrNull ?? const <BaseProduct>[];
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text(_isEditing ? 'Editar produto' : 'Novo produto'),
          bottom: TabBar(
            isScrollable: true,
            labelPadding: const EdgeInsets.symmetric(horizontal: 16),
            labelStyle: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
            unselectedLabelStyle: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
            tabs: const [
              Tab(text: 'Informações'),
              Tab(text: 'Preço/estoque'),
              Tab(text: 'Fotos'),
            ],
          ),
        ),
        bottomNavigationBar: SafeArea(
          minimum: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: colorScheme.surface,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: colorScheme.outlineVariant),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 18,
                  offset: const Offset(0, -4),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _isEditing
                        ? 'Revise as abas e salve as alterações quando terminar.'
                        : 'Preencha as abas para cadastrar o produto com mais clareza.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _isSaving ? null : _save,
                      icon: _isSaving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.save_rounded),
                      label: Text(
                        _isEditing ? 'Salvar alterações' : 'Criar produto',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        body: Form(
          key: _formKey,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          child: TabBarView(
            children: [
              _buildInformationTab(
                context,
                categories: categories,
                categoriesAsync: categoriesAsync,
                baseProducts: baseProducts,
                baseProductsAsync: baseProductsAsync,
              ),
              _buildPricingTab(context),
              _buildPhotosTab(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInformationTab(
    BuildContext context, {
    required List<Category> categories,
    required AsyncValue<List<Category>> categoriesAsync,
    required List<BaseProduct> baseProducts,
    required AsyncValue<List<BaseProduct>> baseProductsAsync,
  }) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        _SectionCard(
          title: 'Nicho e tipo do cadastro',
          subtitle:
              'Defina o nicho do produto para liberar campos mais adequados sem quebrar a estrutura atual.',
          child: Column(
            children: [
              _ProductNicheSelector(
                selectedValue: _selectedNiche,
                onChanged: (value) => setState(() => _selectedNiche = value),
              ),
              const SizedBox(height: 16),
              _CatalogTypeSelector(
                selectedValue: _selectedCatalogType,
                onChanged: _changeCatalogType,
              ),
              const SizedBox(height: 16),
              _NamePreviewCard(
                title: _isVariantCatalog
                    ? 'Nome final do item'
                    : 'Nome exibido na venda',
                preview: _finalPreviewLabel,
                helperText: _isVariantCatalog
                    ? 'O nome final combina modelo e variação para manter os SKUs organizados.'
                    : 'Esse será o nome principal usado nas listagens e na venda.',
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _SectionCard(
          title: _isFoodNiche
              ? 'Configurações de alimentação'
              : 'Configurações de moda',
          subtitle: _isFoodNiche
              ? 'Use atributos enxutos para alérgenos, preparo e disponibilidade operacional.'
              : 'Use atributos enxutos para marca, composição, peso e preparação de grade.',
          child: _isFoodNiche
              ? _buildFoodFields(context)
              : _buildFashionFields(context),
        ),
        const SizedBox(height: 16),
        _SectionCard(
          title: _isVariantCatalog
              ? 'Estrutura da variação'
              : 'Identificação do produto',
          subtitle: _isVariantCatalog
              ? 'Organize modelo, variação e vínculo com o produto base sem alterar o domínio atual.'
              : 'Preencha as informações principais do produto.',
          child: Column(
            children: [
              if (_isVariantCatalog) ...[
                TextFormField(
                  controller: _modelNameController,
                  decoration: const InputDecoration(
                    labelText: 'Modelo',
                    hintText: 'Ex.: Camiseta, Burger',
                  ),
                  textCapitalization: TextCapitalization.sentences,
                  validator: (value) {
                    if (!_isVariantCatalog) {
                      return null;
                    }
                    if (value == null || value.trim().isEmpty) {
                      return 'Informe o modelo';
                    }
                    return null;
                  },
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _variantLabelController,
                  decoration: const InputDecoration(
                    labelText: 'Variação',
                    hintText: 'Ex.: P, M, G, Duplo',
                  ),
                  textCapitalization: TextCapitalization.sentences,
                  validator: (value) {
                    if (!_isVariantCatalog) {
                      return null;
                    }
                    if (value == null || value.trim().isEmpty) {
                      return 'Informe a variação';
                    }
                    return null;
                  },
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<int?>(
                  initialValue: _selectedBaseProductId,
                  decoration: const InputDecoration(
                    labelText: 'Produto base',
                    hintText: 'Opcional para agrupar SKUs relacionados',
                  ),
                  items: [
                    const DropdownMenuItem<int?>(
                      value: null,
                      child: Text('Usar base automática'),
                    ),
                    for (final baseProduct in baseProducts)
                      DropdownMenuItem<int?>(
                        value: baseProduct.id,
                        child: Text(baseProduct.name),
                      ),
                  ],
                  onChanged: baseProductsAsync.isLoading
                      ? null
                      : (value) =>
                            setState(() => _selectedBaseProductId = value),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _extraAttributesController,
                  decoration: const InputDecoration(
                    labelText: 'Atributos extras',
                    hintText: 'Uma linha por atributo no formato chave=valor',
                    helperText: 'Opcional. Ex.: cor=preto',
                  ),
                  minLines: 3,
                  maxLines: 6,
                ),
                if (!_isFoodNiche) ...[
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _modifierGroupsController,
                    decoration: const InputDecoration(
                      labelText: 'Modificadores',
                      hintText:
                          'Uma linha por grupo: Tamanho: P, M, G, +Extra:300',
                      helperText: 'Opcional. Mantém o formato técnico atual.',
                    ),
                    minLines: 3,
                    maxLines: 6,
                  ),
                ],
              ] else ...[
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Nome do produto',
                    hintText: 'Ex.: Coxinha de frango',
                  ),
                  textCapitalization: TextCapitalization.sentences,
                  validator: (value) {
                    if (_isVariantCatalog) {
                      return null;
                    }
                    if (value == null || value.trim().isEmpty) {
                      return 'Informe o nome do produto';
                    }
                    return null;
                  },
                  onChanged: (_) => setState(() {}),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        _SectionCard(
          title: 'Detalhes de apresentação',
          subtitle: 'Descrição, categoria e contexto comercial do produto.',
          child: Column(
            children: [
              TextFormField(
                controller: _descriptionController,
                decoration: const InputDecoration(
                  labelText: 'Descrição',
                  hintText: 'Opcional',
                ),
                minLines: 3,
                maxLines: 5,
                textCapitalization: TextCapitalization.sentences,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<int?>(
                initialValue: _selectedCategoryId,
                items: [
                  const DropdownMenuItem<int?>(
                    value: null,
                    child: Text('Sem categoria'),
                  ),
                  for (final category in categories)
                    DropdownMenuItem<int?>(
                      value: category.id,
                      child: Text(category.name),
                    ),
                ],
                decoration: const InputDecoration(
                  labelText: 'Categoria',
                  helperText: 'Opcional. Facilita a organização dos produtos.',
                ),
                onChanged: categoriesAsync.isLoading
                    ? null
                    : (value) => setState(() => _selectedCategoryId = value),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPricingTab(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        _SectionCard(
          title: 'Preço e estoque',
          subtitle:
              'Defina os dados comerciais do produto com foco em venda, margem e disponibilidade.',
          child: Column(
            children: [
              TextFormField(
                controller: _barcodeController,
                decoration: const InputDecoration(
                  labelText: 'Código de barras',
                  hintText: 'Opcional',
                ),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _selectedUnitMeasure,
                decoration: const InputDecoration(
                  labelText: 'Unidade de medida',
                ),
                items: const [
                  DropdownMenuItem(value: 'un', child: Text('Unidade (un)')),
                  DropdownMenuItem(value: 'kg', child: Text('Quilograma (kg)')),
                  DropdownMenuItem(value: 'g', child: Text('Grama (g)')),
                  DropdownMenuItem(value: 'l', child: Text('Litro (l)')),
                  DropdownMenuItem(value: 'ml', child: Text('Mililitro (ml)')),
                  DropdownMenuItem(value: 'cx', child: Text('Caixa (cx)')),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _selectedUnitMeasure = value);
                  }
                },
              ),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _costController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Custo',
                        helperText: 'Valor interno',
                        prefixText: 'R\$ ',
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _priceController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Preço de venda',
                        helperText: 'Valor cobrado',
                        prefixText: 'R\$ ',
                      ),
                      validator: (value) {
                        final cents = MoneyParser.parseToCents(value ?? '');
                        if (cents <= 0) {
                          return 'Informe um preço de venda válido';
                        }
                        return null;
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _stockController,
                readOnly: _isFashionNiche && _buildVariantInputs().isNotEmpty,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: _isEditing ? 'Estoque atual' : 'Estoque inicial',
                  helperText:
                      _isFashionNiche && _buildVariantInputs().isNotEmpty
                      ? 'O estoque sera calculado automaticamente pela grade.'
                      : 'Informe a quantidade conforme a unidade de medida',
                ),
                validator: (value) {
                  if (_isFashionNiche && _buildVariantInputs().isNotEmpty) {
                    return null;
                  }
                  final raw = (value ?? '').trim();
                  if (!RegExp(r'\d').hasMatch(raw)) {
                    return 'Informe um estoque válido';
                  }
                  final parsed = QuantityParser.parseToMil(value ?? '');
                  if (parsed < 0) {
                    return 'Informe um estoque válido';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer.withValues(alpha: 0.38),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.inventory_2_outlined,
                          color: colorScheme.primary,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Status do produto',
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _isActive
                                    ? 'Produto ativo para venda'
                                    : 'Produto inativo temporariamente',
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _StatusChip(
                          label: 'Ativo',
                          selected: _isActive,
                          color: Colors.green,
                          icon: Icons.check_circle_outline,
                          onSelected: () => setState(() => _isActive = true),
                        ),
                        _StatusChip(
                          label: 'Inativo',
                          selected: !_isActive,
                          color: Colors.grey,
                          icon: Icons.pause_circle_outline,
                          onSelected: () => setState(() => _isActive = false),
                        ),
                        _StatusChip(
                          label: 'Destaque',
                          selected: _isFeatured,
                          color: Colors.orange,
                          icon: Icons.auto_awesome_outlined,
                          onSelected: () =>
                              setState(() => _isFeatured = !_isFeatured),
                        ),
                        _StatusChip(
                          label: 'Promoção',
                          selected: _isPromotion,
                          color: Colors.red,
                          icon: Icons.local_offer_outlined,
                          onSelected: () =>
                              setState(() => _isPromotion = !_isPromotion),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Ativo e Inativo são salvos normalmente. Destaque e Promoção ficam apenas visuais nesta etapa.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFoodFields(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      children: [
        TextFormField(
          controller: _foodAllergensController,
          decoration: const InputDecoration(
            labelText: 'Alérgenos',
            hintText: 'Ex.: leite, glúten, castanhas',
            helperText:
                'Separe por vírgulas para reabrir e editar com facilidade.',
          ),
          textCapitalization: TextCapitalization.sentences,
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _foodPrepTimeController,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Tempo de preparo (minutos)',
            hintText: 'Ex.: 15',
            helperText: 'Opcional. Use apenas números.',
          ),
          validator: (value) {
            final trimmed = (value ?? '').trim();
            if (trimmed.isEmpty) {
              return null;
            }
            final minutes = int.tryParse(trimmed);
            if (minutes == null || minutes < 0) {
              return 'Informe um tempo de preparo válido';
            }
            return null;
          },
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _foodOperationalAvailabilityController,
          decoration: const InputDecoration(
            labelText: 'Disponibilidade operacional',
            hintText: 'Ex.: almoço, jantar, fim de semana',
            helperText: 'Texto livre para orientar operação e atendimento.',
          ),
          textCapitalization: TextCapitalization.sentences,
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: Text(
                'Complementos',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            FilledButton.tonalIcon(
              onPressed: () => _openFoodModifierGroupEditor(),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Novo grupo'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (_isLoadingAdvancedData)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: CircularProgressIndicator(),
          )
        else if (_foodModifierGroups.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: colorScheme.surfaceContainerLow,
            ),
            child: const Text(
              'Adicione grupos estruturados de complementos para definir opções, obrigatoriedade, limites e preços adicionais.',
            ),
          )
        else
          Column(
            children: List.generate(_foodModifierGroups.length, (index) {
              final group = _foodModifierGroups[index];
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _EditableModifierGroupCard(
                  group: group,
                  onEditGroup: () => _openFoodModifierGroupEditor(index: index),
                  onDeleteGroup: () => _removeFoodModifierGroup(index),
                  onAddOption: () =>
                      _openFoodModifierOptionEditor(groupIndex: index),
                  onEditOption: (optionIndex) => _openFoodModifierOptionEditor(
                    groupIndex: index,
                    optionIndex: optionIndex,
                  ),
                  onDeleteOption: (optionIndex) =>
                      _removeFoodModifierOption(index, optionIndex),
                ),
              );
            }),
          ),
      ],
    );
  }

  Widget _buildFashionFields(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      children: [
        TextFormField(
          controller: _fashionBrandController,
          decoration: const InputDecoration(
            labelText: 'Marca',
            hintText: 'Ex.: Tatuzin Studio',
          ),
          textCapitalization: TextCapitalization.words,
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _fashionCompositionController,
          decoration: const InputDecoration(
            labelText: 'Composição',
            hintText: 'Ex.: 100% algodão',
          ),
          textCapitalization: TextCapitalization.sentences,
        ),
        const SizedBox(height: 16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextFormField(
                controller: _fashionWeightController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Peso em gramas',
                  hintText: 'Ex.: 220',
                ),
                validator: (value) {
                  final trimmed = (value ?? '').trim();
                  if (trimmed.isEmpty) {
                    return null;
                  }
                  final grams = int.tryParse(trimmed);
                  if (grams == null || grams < 0) {
                    return 'Informe um peso válido';
                  }
                  return null;
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextFormField(
                controller: _fashionTagsController,
                decoration: const InputDecoration(
                  labelText: 'Tags',
                  hintText: 'Ex.: casual, verão, premium',
                ),
                textCapitalization: TextCapitalization.words,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        const SizedBox(height: 20),
        Text(
          'Grade de moda',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Cadastre tamanhos e cores para gerar a matriz de combinações com estoque por célula.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
            height: 1.35,
          ),
        ),
        const SizedBox(height: 16),
        _FashionDimensionEditor(
          title: 'Tamanhos',
          controller: _fashionSizeInputController,
          buttonLabel: 'Adicionar tamanho',
          chips: _fashionSizes,
          onSubmitted: (_) => _addFashionSize(),
          onAdd: _addFashionSize,
          onRemoveChip: _removeFashionSize,
        ),
        const SizedBox(height: 16),
        _FashionDimensionEditor(
          title: 'Cores',
          controller: _fashionColorInputController,
          buttonLabel: 'Adicionar cor',
          chips: _fashionColors,
          onSubmitted: (_) => _addFashionColor(),
          onAdd: _addFashionColor,
          onRemoveChip: _removeFashionColor,
        ),
        const SizedBox(height: 16),
        if (_isLoadingAdvancedData)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: CircularProgressIndicator(),
          )
        else if (_fashionSizes.isEmpty || _fashionColors.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: colorScheme.surfaceContainerLow,
            ),
            child: const Text(
              'Adicione pelo menos um tamanho e uma cor para montar a grade completa.',
            ),
          )
        else
          _FashionGradeMatrix(
            sizes: _fashionSizes,
            colors: _fashionColors,
            resolveCell: _entryForFashionCell,
            onTapCell: _openFashionCellEditor,
          ),
        const SizedBox(height: 16),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: colorScheme.surfaceContainerLow,
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Resumo da grade',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${_buildVariantInputs().length} variantes ativas',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Estoque total: ${AppFormatters.quantityFromMil(_fashionGridTotalMil)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (!_isVariantCatalog) ...[
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: Theme.of(context).colorScheme.surfaceContainerLow,
            ),
            child: const Text(
              'Se quiser trabalhar com grade de tamanhos ou cores na venda, você pode migrar este cadastro para "Com variação" sem perder a compatibilidade do modelo atual.',
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildPhotosTab(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      child: Column(
        children: [
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
              side: BorderSide(color: colorScheme.outlineVariant),
            ),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Fotos do produto',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '${_photos.length} / $_maxPhotos fotos',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      FilledButton.tonalIcon(
                        onPressed:
                            _photos.length >= _maxPhotos || _isPickingPhoto
                            ? null
                            : _promptPhotoSource,
                        icon: const Icon(Icons.add_photo_alternate_outlined),
                        label: const Text('Adicionar'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'A primeira foto preenchida será usada como principal nas listagens do app.',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 16),
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: 6,
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          mainAxisSpacing: 12,
                          crossAxisSpacing: 12,
                          childAspectRatio: 0.88,
                        ),
                    itemBuilder: (context, index) {
                      final hasPhoto = index < _photos.length;
                      final photo = hasPhoto ? _photos[index] : null;
                      return _ProductPhotoTile(
                        photo: photo,
                        isPrimary: hasPhoto && index == 0,
                        isPickingPhoto: _isPickingPhoto,
                        onTap: hasPhoto || _photos.length >= _maxPhotos
                            ? null
                            : _promptPhotoSource,
                        onRemove: hasPhoto ? () => _removePhoto(index) : null,
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _promptPhotoSource() async {
    if (_photos.length >= _maxPhotos || _isPickingPhoto) {
      return;
    }

    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('Galeria'),
                onTap: () =>
                    Navigator.of(sheetContext).pop(ImageSource.gallery),
              ),
              ListTile(
                leading: const Icon(Icons.photo_camera_outlined),
                title: const Text('Câmera'),
                onTap: () => Navigator.of(sheetContext).pop(ImageSource.camera),
              ),
            ],
          ),
        );
      },
    );

    if (source == null) {
      return;
    }

    await _pickPhoto(source);
  }

  String get _variantPreviewLabel {
    final model = _modelNameController.text.trim();
    final variation = _variantLabelController.text.trim();
    if (model.isEmpty && variation.isEmpty) {
      return 'Ex.: Camiseta - P';
    }
    if (model.isEmpty) {
      return variation;
    }
    if (variation.isEmpty) {
      return model;
    }
    return _buildVariantDisplayName(model, variation);
  }

  String get _finalPreviewLabel {
    if (_isVariantCatalog) {
      return _variantPreviewLabel;
    }

    final name = _nameController.text.trim();
    if (name.isEmpty) {
      return 'Ex.: Coxinha de frango';
    }
    return name;
  }

  void _changeCatalogType(String nextValue) {
    setState(() {
      if (nextValue == ProductCatalogTypes.variant) {
        if (_modelNameController.text.trim().isEmpty &&
            _nameController.text.trim().isNotEmpty) {
          _modelNameController.text = _nameController.text.trim();
        }
      } else if (_nameController.text.trim().isEmpty) {
        final fallbackName = _buildSimpleFallbackName();
        if (fallbackName.isNotEmpty) {
          _nameController.text = fallbackName;
        }
      }
      _selectedCatalogType = nextValue;
    });
  }

  Future<void> _pickPhoto(ImageSource source) async {
    if (_photos.length >= _maxPhotos) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Limite de fotos atingido para este produto.'),
        ),
      );
      return;
    }

    setState(() => _isPickingPhoto = true);
    try {
      final pickedFile = await _imagePicker.pickImage(
        source: source,
        imageQuality: 88,
      );
      if (pickedFile == null) {
        return;
      }

      final storage = ref.read(productMediaStorageProvider);
      final storedPath = await storage.importPickedFile(pickedFile);
      if (!mounted) {
        return;
      }
      setState(() {
        _photos = [
          ..._photos,
          _EditableProductPhoto(
            localPath: storedPath,
            isPrimary: _photos.isEmpty,
          ),
        ];
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Falha ao importar foto: $error')));
    } finally {
      if (mounted) {
        setState(() => _isPickingPhoto = false);
      }
    }
  }

  Future<void> _removePhoto(int index) async {
    final storage = ref.read(productMediaStorageProvider);
    final removed = _photos[index];
    setState(() {
      final updated = [..._photos]..removeAt(index);
      if (removed.isPrimary && updated.isNotEmpty) {
        updated[0] = updated[0].copyWith(isPrimary: true);
      }
      _photos = updated;
    });
    await storage.deleteManagedFile(removed.localPath);
  }

  Future<void> _openFoodModifierGroupEditor({int? index}) async {
    final current = index == null ? null : _foodModifierGroups[index];
    final nameController = TextEditingController(text: current?.name ?? '');
    final minController = TextEditingController(
      text: '${current?.minSelections ?? 0}',
    );
    final maxController = TextEditingController(
      text: current?.maxSelections?.toString() ?? '',
    );
    var isRequired = current?.isRequired ?? false;

    final result = await showDialog<_EditableModifierGroup>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setLocalState) {
            return AlertDialog(
              title: Text(index == null ? 'Novo grupo' : 'Editar grupo'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(
                        labelText: 'Nome do grupo',
                      ),
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      value: isRequired,
                      title: const Text('Obrigatório'),
                      onChanged: (value) =>
                          setLocalState(() => isRequired = value),
                    ),
                    TextField(
                      controller: minController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Mínimo de seleções',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: maxController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Máximo de seleções',
                        hintText: 'Opcional',
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: () {
                    final name = nameController.text.trim();
                    if (name.isEmpty) {
                      return;
                    }
                    Navigator.of(dialogContext).pop(
                      _EditableModifierGroup(
                        name: name,
                        isRequired: isRequired,
                        minSelections:
                            int.tryParse(minController.text.trim()) ?? 0,
                        maxSelections:
                            _cleanNullable(maxController.text) == null
                            ? null
                            : int.tryParse(maxController.text.trim()),
                        options:
                            current?.options ??
                            const <_EditableModifierOption>[],
                      ),
                    );
                  },
                  child: const Text('Salvar'),
                ),
              ],
            );
          },
        );
      },
    );

    nameController.dispose();
    minController.dispose();
    maxController.dispose();

    if (result == null) {
      return;
    }

    setState(() {
      final updated = [..._foodModifierGroups];
      if (index == null) {
        updated.add(result);
      } else {
        updated[index] = result;
      }
      _foodModifierGroups = updated;
    });
  }

  void _removeFoodModifierGroup(int index) {
    setState(() {
      _foodModifierGroups = [..._foodModifierGroups]..removeAt(index);
    });
  }

  Future<void> _openFoodModifierOptionEditor({
    required int groupIndex,
    int? optionIndex,
  }) async {
    final current = optionIndex == null
        ? null
        : _foodModifierGroups[groupIndex].options[optionIndex];
    final nameController = TextEditingController(text: current?.name ?? '');
    final priceController = TextEditingController(
      text: AppFormatters.currencyInputFromCents(current?.priceDeltaCents ?? 0),
    );
    var adjustmentType = current?.adjustmentType ?? 'add';

    final result = await showDialog<_EditableModifierOption>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setLocalState) {
            return AlertDialog(
              title: Text(optionIndex == null ? 'Nova opção' : 'Editar opção'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(
                        labelText: 'Nome da opção',
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: adjustmentType,
                      decoration: const InputDecoration(
                        labelText: 'Tipo de ajuste',
                      ),
                      items: const [
                        DropdownMenuItem(value: 'add', child: Text('Adição')),
                        DropdownMenuItem(
                          value: 'remove',
                          child: Text('Remoção'),
                        ),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          setLocalState(() => adjustmentType = value);
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: priceController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Preço adicional',
                        prefixText: 'R\$ ',
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: () {
                    final name = nameController.text.trim();
                    if (name.isEmpty) {
                      return;
                    }
                    Navigator.of(dialogContext).pop(
                      _EditableModifierOption(
                        name: name,
                        adjustmentType: adjustmentType,
                        priceDeltaCents: MoneyParser.parseToCents(
                          priceController.text,
                        ),
                      ),
                    );
                  },
                  child: const Text('Salvar'),
                ),
              ],
            );
          },
        );
      },
    );

    nameController.dispose();
    priceController.dispose();

    if (result == null) {
      return;
    }

    setState(() {
      final groups = [..._foodModifierGroups];
      final group = groups[groupIndex];
      final options = [...group.options];
      if (optionIndex == null) {
        options.add(result);
      } else {
        options[optionIndex] = result;
      }
      groups[groupIndex] = group.copyWith(options: options);
      _foodModifierGroups = groups;
    });
  }

  void _removeFoodModifierOption(int groupIndex, int optionIndex) {
    setState(() {
      final groups = [..._foodModifierGroups];
      final group = groups[groupIndex];
      final options = [...group.options]..removeAt(optionIndex);
      groups[groupIndex] = group.copyWith(options: options);
      _foodModifierGroups = groups;
    });
  }

  void _hydrateFashionGridState() {
    final parsedHint = _parseFashionGridHint(_fashionSizeHintController.text);
    final sizes = <String>[...parsedHint.sizes];
    final colors = <String>[...parsedHint.colors];

    for (final entry in _fashionGradeEntries) {
      final size = entry.sizeLabel.trim();
      final color = entry.colorLabel.trim();
      if (size.isNotEmpty && !sizes.contains(size)) {
        sizes.add(size);
      }
      if (color.isNotEmpty && !colors.contains(color)) {
        colors.add(color);
      }
    }

    _fashionSizes = sizes;
    _fashionColors = colors;
    _syncFashionGradeCellControllers();
  }

  void _syncFashionGradeCellControllers() {
    final activeKeys = <String>{};
    for (final size in _fashionSizes) {
      for (final color in _fashionColors) {
        final key = _fashionCellKey(size, color);
        activeKeys.add(key);
        _fashionGradeCellControllers.putIfAbsent(
          key,
          () => TextEditingController(
            text: _stockTextForFashionCell(size, color),
          ),
        );
      }
    }

    final keysToRemove = _fashionGradeCellControllers.keys
        .where((key) => !activeKeys.contains(key))
        .toList(growable: false);
    for (final key in keysToRemove) {
      _fashionGradeCellControllers.remove(key)?.dispose();
    }
  }

  _ParsedFashionGridHint _parseFashionGridHint(String raw) {
    final text = raw.trim();
    if (text.isEmpty) {
      return const _ParsedFashionGridHint();
    }

    final sections = text.split(';');
    final sizes = <String>[];
    final colors = <String>[];
    for (final section in sections) {
      final separator = section.indexOf('=');
      if (separator <= 0) {
        continue;
      }
      final key = section.substring(0, separator).trim().toLowerCase();
      final values = section
          .substring(separator + 1)
          .split('|')
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty)
          .toList(growable: false);
      if (key == 'sizes') {
        sizes.addAll(values);
      } else if (key == 'colors') {
        colors.addAll(values);
      }
    }

    return _ParsedFashionGridHint(sizes: sizes, colors: colors);
  }

  String? _buildFashionGridHintValue() {
    if (_fashionSizes.isEmpty && _fashionColors.isEmpty) {
      return null;
    }

    final parts = <String>[];
    if (_fashionSizes.isNotEmpty) {
      parts.add('sizes=${_fashionSizes.join('|')}');
    }
    if (_fashionColors.isNotEmpty) {
      parts.add('colors=${_fashionColors.join('|')}');
    }
    return parts.join(';');
  }

  String _fashionCellKey(String size, String color) => '$size|||$color';

  String _stockTextForFashionCell(String size, String color) {
    for (final entry in _fashionGradeEntries) {
      if (entry.sizeLabel.trim() == size && entry.colorLabel.trim() == color) {
        return entry.stockText.trim();
      }
    }
    return '';
  }

  TextEditingController _controllerForFashionCell(String size, String color) {
    final key = _fashionCellKey(size, color);
    return _fashionGradeCellControllers.putIfAbsent(
      key,
      () => TextEditingController(text: _stockTextForFashionCell(size, color)),
    );
  }

  _EditableFashionGradeEntry _entryForFashionCell(String size, String color) {
    for (final entry in _fashionGradeEntries) {
      if (entry.sizeLabel.trim() == size && entry.colorLabel.trim() == color) {
        return entry;
      }
    }

    return _EditableFashionGradeEntry(
      sizeLabel: size,
      colorLabel: color,
      stockText: _controllerForFashionCell(size, color).text,
      sku: _buildDefaultVariantSku(size, color),
    );
  }

  Future<void> _openFashionCellEditor(String size, String color) async {
    final current = _entryForFashionCell(size, color);
    final skuController = TextEditingController(
      text: current.sku ?? _buildDefaultVariantSku(size, color),
    );
    final stockController = TextEditingController(
      text: _controllerForFashionCell(size, color).text,
    );
    final additionalPriceController = TextEditingController(
      text: current.priceAdditionalText,
    );
    var isActive = current.isActive;

    final result = await showModalBottomSheet<_EditableFashionGradeEntry>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) {
        final bottomInset = MediaQuery.of(sheetContext).viewInsets.bottom;
        return StatefulBuilder(
          builder: (context, setLocalState) {
            return Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, bottomInset + 16),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Editar variante',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '$size / $color',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: skuController,
                      decoration: const InputDecoration(
                        labelText: 'SKU',
                        hintText: 'SKU da variante',
                      ),
                      textCapitalization: TextCapitalization.characters,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: stockController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Estoque',
                        hintText: 'Quantidade disponivel',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: additionalPriceController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Preco adicional',
                        prefixText: 'R\$ ',
                      ),
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile.adaptive(
                      value: isActive,
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Variante ativa'),
                      subtitle: const Text(
                        'Desative para manter a combinacao cadastrada sem vender.',
                      ),
                      onChanged: (value) {
                        setLocalState(() => isActive = value);
                      },
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: const Text('Cancelar'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton(
                            onPressed: () {
                              Navigator.of(context).pop(
                                _EditableFashionGradeEntry(
                                  sizeLabel: size,
                                  colorLabel: color,
                                  stockText: stockController.text,
                                  sku: skuController.text.trim(),
                                  priceAdditionalText:
                                      additionalPriceController.text,
                                  isActive: isActive,
                                ),
                              );
                            },
                            child: const Text('Salvar'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    skuController.dispose();
    stockController.dispose();
    additionalPriceController.dispose();

    if (result == null) {
      return;
    }

    setState(() {
      final key = _fashionCellKey(size, color);
      final controller = _fashionGradeCellControllers.putIfAbsent(
        key,
        () => TextEditingController(),
      );
      controller.text = result.stockText;
      _fashionGradeEntries = _upsertFashionGradeEntry(result);
    });
  }

  List<_EditableFashionGradeEntry> _upsertFashionGradeEntry(
    _EditableFashionGradeEntry entry,
  ) {
    final updated = <_EditableFashionGradeEntry>[];
    var replaced = false;
    for (final current in _fashionGradeEntries) {
      final sameCell =
          current.sizeLabel.trim() == entry.sizeLabel.trim() &&
          current.colorLabel.trim() == entry.colorLabel.trim();
      if (sameCell) {
        updated.add(entry);
        replaced = true;
      } else {
        updated.add(current);
      }
    }
    if (!replaced) {
      updated.add(entry);
    }
    return updated;
  }

  String _buildDefaultVariantSku(String size, String color) {
    final base =
        _cleanNullable(_modelNameController.text) ?? _nameController.text;
    final normalizedBase = base
        .trim()
        .toUpperCase()
        .replaceAll(RegExp(r'[^A-Z0-9]+'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
    final normalizedSize = size
        .trim()
        .toUpperCase()
        .replaceAll(RegExp(r'[^A-Z0-9]+'), '-')
        .replaceAll(RegExp(r'-+'), '-');
    final normalizedColor = color
        .trim()
        .toUpperCase()
        .replaceAll(RegExp(r'[^A-Z0-9]+'), '-')
        .replaceAll(RegExp(r'-+'), '-');
    final fallbackBase = normalizedBase.isEmpty ? 'PRODUTO' : normalizedBase;
    return '$fallbackBase-$normalizedSize-$normalizedColor';
  }

  void _addFashionSize() {
    final size = _fashionSizeInputController.text.trim();
    if (size.isEmpty || _fashionSizes.contains(size)) {
      return;
    }

    setState(() {
      _fashionSizes = [..._fashionSizes, size];
      _fashionSizeInputController.clear();
      _syncFashionGradeCellControllers();
      _fashionSizeHintController.text = _buildFashionGridHintValue() ?? '';
    });
  }

  void _addFashionColor() {
    final color = _fashionColorInputController.text.trim();
    if (color.isEmpty || _fashionColors.contains(color)) {
      return;
    }

    setState(() {
      _fashionColors = [..._fashionColors, color];
      _fashionColorInputController.clear();
      _syncFashionGradeCellControllers();
      _fashionSizeHintController.text = _buildFashionGridHintValue() ?? '';
    });
  }

  void _removeFashionSize(String size) {
    setState(() {
      _fashionSizes = _fashionSizes
          .where((current) => current != size)
          .toList(growable: false);
      _fashionGradeEntries = _fashionGradeEntries
          .where((entry) => entry.sizeLabel.trim() != size)
          .toList(growable: false);
      _syncFashionGradeCellControllers();
      _fashionSizeHintController.text = _buildFashionGridHintValue() ?? '';
    });
  }

  void _removeFashionColor(String color) {
    setState(() {
      _fashionColors = _fashionColors
          .where((current) => current != color)
          .toList(growable: false);
      _fashionGradeEntries = _fashionGradeEntries
          .where((entry) => entry.colorLabel.trim() != color)
          .toList(growable: false);
      _syncFashionGradeCellControllers();
      _fashionSizeHintController.text = _buildFashionGridHintValue() ?? '';
    });
  }

  int get _fashionGridTotalMil {
    var totalMil = 0;
    for (final size in _fashionSizes) {
      for (final color in _fashionColors) {
        totalMil += QuantityParser.parseToMil(
          _controllerForFashionCell(size, color).text,
        );
      }
    }
    return totalMil;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _isSaving = true);

    try {
      final repository = ref.read(productRepositoryProvider);
      final modelName = _cleanNullable(_modelNameController.text);
      final variantLabel = _cleanNullable(_variantLabelController.text);
      final variantAttributes = _buildVariantAttributes(
        modelName: modelName,
        variantLabel: variantLabel,
      );
      final modifierGroups = _isFoodNiche
          ? _buildFoodModifierGroupsInput()
          : (_isVariantCatalog
                ? _parseModifierGroups(_modifierGroupsController.text)
                : null);
      final variants = _buildVariantInputs();
      final resolvedName = _isVariantCatalog
          ? _buildVariantDisplayName(modelName!, variantLabel!)
          : _nameController.text.trim();
      final input = ProductInput(
        name: resolvedName,
        description: _descriptionController.text,
        categoryId: _selectedCategoryId,
        barcode: _barcodeController.text,
        photos: _buildPhotoInputs(),
        variants: variants,
        niche: _selectedNiche,
        catalogType: _selectedCatalogType,
        modelName: _isVariantCatalog ? modelName : null,
        variantLabel: _isVariantCatalog ? variantLabel : null,
        baseProductId: _isVariantCatalog ? _selectedBaseProductId : null,
        variantAttributes: variantAttributes,
        modifierGroups: modifierGroups,
        unitMeasure: _selectedUnitMeasure,
        costCents: MoneyParser.parseToCents(_costController.text),
        salePriceCents: MoneyParser.parseToCents(_priceController.text),
        stockMil: variants.isNotEmpty
            ? _fashionGridTotalMil
            : QuantityParser.parseToMil(_stockController.text),
        isActive: _isActive,
      );

      if (_isEditing) {
        await repository.update(widget.initialProduct!.id, input);
      } else {
        await repository.create(input);
      }

      ref.invalidate(productListProvider);
      ref.read(appDataRefreshProvider.notifier).state++;

      if (!mounted) {
        return;
      }

      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Falha ao salvar produto: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  String _buildInitialExtraAttributes(Product? product) {
    if (product == null || product.variantAttributes.isEmpty) {
      return '';
    }
    final lines = product.variantAttributes
        .where(
          (attribute) =>
              attribute.key != 'model' &&
              attribute.key != 'variant' &&
              !_isReservedNicheAttribute(attribute.key),
        )
        .map((attribute) => '${attribute.key}=${attribute.value}')
        .toList(growable: false);
    return lines.join('\n');
  }

  String _buildInitialModifierGroups(Product? product) {
    if (product == null || product.modifierGroups.isEmpty) {
      return '';
    }
    return product.modifierGroups
        .map((group) => '${group.name}: ${group.options.length} opções')
        .join('\n');
  }

  List<ProductVariantAttributeInput> _buildVariantAttributes({
    required String? modelName,
    required String? variantLabel,
  }) {
    final attributes = <ProductVariantAttributeInput>[
      if (_isVariantCatalog && modelName != null)
        ProductVariantAttributeInput(key: 'model', value: modelName),
      if (_isVariantCatalog && variantLabel != null)
        ProductVariantAttributeInput(key: 'variant', value: variantLabel),
      ..._buildNicheAttributes(),
    ];

    final lines = _extraAttributesController.text.split('\n');
    for (final rawLine in lines) {
      final line = rawLine.trim();
      if (line.isEmpty) {
        continue;
      }
      final separator = line.indexOf('=');
      if (separator <= 0 || separator >= line.length - 1) {
        continue;
      }
      final key = line.substring(0, separator).trim();
      final value = line.substring(separator + 1).trim();
      if (key.isEmpty || value.isEmpty) {
        continue;
      }
      attributes.add(ProductVariantAttributeInput(key: key, value: value));
    }

    return attributes;
  }

  List<ProductVariantAttributeInput> _buildNicheAttributes() {
    final attributes = <ProductVariantAttributeInput>[];

    void addAttribute(String key, String? value) {
      final normalizedValue = _cleanNullable(value);
      if (normalizedValue == null) {
        return;
      }
      attributes.add(
        ProductVariantAttributeInput(key: key, value: normalizedValue),
      );
    }

    if (_isFoodNiche) {
      addAttribute('food_allergens', _foodAllergensController.text);
      addAttribute('food_prep_time_minutes', _foodPrepTimeController.text);
      addAttribute(
        'food_operational_availability',
        _foodOperationalAvailabilityController.text,
      );
    }

    if (_isFashionNiche) {
      addAttribute('fashion_brand', _fashionBrandController.text);
      addAttribute('fashion_composition', _fashionCompositionController.text);
      addAttribute('fashion_weight_grams', _fashionWeightController.text);
      addAttribute(
        'fashion_tags',
        _normalizeCommaSeparatedValues(_fashionTagsController.text),
      );
      addAttribute('fashion_size_grid_hint', _buildFashionGridHintValue());
    }

    return attributes;
  }

  List<ProductPhotoInput> _buildPhotoInputs() {
    return List<ProductPhotoInput>.generate(_photos.length, (index) {
      final photo = _photos[index];
      return ProductPhotoInput(
        localPath: photo.localPath,
        isPrimary: photo.isPrimary,
        sortOrder: index,
      );
    });
  }

  List<ProductVariantInput> _buildVariantInputs() {
    if (!_isFashionNiche) {
      return const <ProductVariantInput>[];
    }

    final variants = <ProductVariantInput>[];
    var sortOrder = 0;
    for (final sizeLabel in _fashionSizes) {
      for (final colorLabel in _fashionColors) {
        final normalizedSize = sizeLabel.trim();
        final normalizedColor = colorLabel.trim();
        if (normalizedSize.isEmpty || normalizedColor.isEmpty) {
          continue;
        }

        final entry = _entryForFashionCell(normalizedSize, normalizedColor);
        final stockMil = QuantityParser.parseToMil(
          _controllerForFashionCell(normalizedSize, normalizedColor).text,
        );
        final sku =
            _cleanNullable(entry.sku) ??
            _buildDefaultVariantSku(normalizedSize, normalizedColor);

        variants.add(
          ProductVariantInput(
            sku: sku,
            colorLabel: normalizedColor,
            sizeLabel: normalizedSize,
            priceAdditionalCents: MoneyParser.parseToCents(
              entry.priceAdditionalText,
            ),
            stockMil: stockMil,
            sortOrder: sortOrder++,
            isActive: entry.isActive,
          ),
        );
      }
    }

    return variants;
  }

  List<ProductModifierGroupInput>? _buildFoodModifierGroupsInput() {
    if (!_isFoodNiche) {
      return null;
    }

    final groups = <ProductModifierGroupInput>[];
    for (final group in _foodModifierGroups) {
      final name = group.name.trim();
      if (name.isEmpty) {
        continue;
      }
      groups.add(
        ProductModifierGroupInput(
          name: name,
          isRequired: group.isRequired,
          minSelections: group.minSelections,
          maxSelections: group.maxSelections,
          options: group.options
              .where((option) => option.name.trim().isNotEmpty)
              .map(
                (option) => ProductModifierOptionInput(
                  name: option.name.trim(),
                  adjustmentType: option.adjustmentType,
                  priceDeltaCents: option.priceDeltaCents,
                ),
              )
              .toList(growable: false),
        ),
      );
    }
    return groups;
  }

  List<ProductModifierGroupInput>? _parseModifierGroups(String raw) {
    if (!_isVariantCatalog && !_isFoodNiche) {
      return null;
    }

    final groups = <ProductModifierGroupInput>[];
    for (final rawLine in raw.split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty) {
        continue;
      }

      final separator = line.indexOf(':');
      if (separator <= 0 || separator >= line.length - 1) {
        continue;
      }
      final groupName = line.substring(0, separator).trim();
      if (groupName.isEmpty) {
        continue;
      }

      final options = <ProductModifierOptionInput>[];
      for (final tokenRaw in line.substring(separator + 1).split(',')) {
        var token = tokenRaw.trim();
        if (token.isEmpty) {
          continue;
        }

        var adjustmentType = 'add';
        if (token.startsWith('-')) {
          adjustmentType = 'remove';
          token = token.substring(1).trim();
        } else if (token.startsWith('+')) {
          token = token.substring(1).trim();
        }

        var priceDeltaCents = 0;
        final priceSeparator = token.lastIndexOf(':');
        if (priceSeparator > 0 && priceSeparator < token.length - 1) {
          final maybePrice = int.tryParse(
            token.substring(priceSeparator + 1).trim(),
          );
          if (maybePrice != null) {
            priceDeltaCents = maybePrice;
            token = token.substring(0, priceSeparator).trim();
          }
        }

        if (token.isEmpty) {
          continue;
        }

        options.add(
          ProductModifierOptionInput(
            name: token,
            adjustmentType: adjustmentType,
            priceDeltaCents: priceDeltaCents,
          ),
        );
      }

      groups.add(ProductModifierGroupInput(name: groupName, options: options));
    }

    return groups;
  }

  String _buildVariantDisplayName(String modelName, String variantLabel) {
    return '${modelName.trim()} - ${variantLabel.trim()}';
  }

  String _buildSimpleFallbackName() {
    final model = _modelNameController.text.trim();
    final variant = _variantLabelController.text.trim();
    if (model.isNotEmpty && variant.isNotEmpty) {
      return _buildVariantDisplayName(model, variant);
    }
    if (model.isNotEmpty) {
      return model;
    }
    return widget.initialProduct?.name ?? '';
  }

  String? _findVariantAttributeValue(Product? product, String key) {
    if (product == null) {
      return null;
    }

    for (final attribute in product.variantAttributes) {
      if (attribute.key == key) {
        return attribute.value;
      }
    }

    return null;
  }

  String _buildDelimitedAttributeList(String? value) {
    final normalized = _normalizeCommaSeparatedValues(value);
    return normalized?.replaceAll('|', ', ') ?? '';
  }

  String? _normalizeCommaSeparatedValues(String? raw) {
    final tokens = (raw ?? '')
        .split(',')
        .map((token) => token.trim())
        .where((token) => token.isNotEmpty)
        .toList(growable: false);
    if (tokens.isEmpty) {
      return null;
    }
    return tokens.join('|');
  }

  bool _isReservedNicheAttribute(String key) {
    return key.startsWith('food_') || key.startsWith('fashion_');
  }

  String? _cleanNullable(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 18),
            child,
          ],
        ),
      ),
    );
  }
}

class _NamePreviewCard extends StatelessWidget {
  const _NamePreviewCard({
    required this.title,
    required this.preview,
    required this.helperText,
  });

  final String title;
  final String preview;
  final String helperText;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            colorScheme.primaryContainer,
            colorScheme.surfaceContainerHigh,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome_rounded, color: colorScheme.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            preview,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
              height: 1.15,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            helperText,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProductNicheSelector extends StatelessWidget {
  const _ProductNicheSelector({
    required this.selectedValue,
    required this.onChanged,
  });

  final String selectedValue;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _CatalogTypeOption(
            title: 'Alimentação',
            subtitle: 'Lanches, pratos, bebidas e complementos',
            icon: Icons.restaurant_menu_rounded,
            selected: selectedValue == ProductNiches.food,
            onTap: () => onChanged(ProductNiches.food),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _CatalogTypeOption(
            title: 'Moda',
            subtitle: 'Peças, coleções, grade e atributos têxteis',
            icon: Icons.checkroom_rounded,
            selected: selectedValue == ProductNiches.fashion,
            onTap: () => onChanged(ProductNiches.fashion),
          ),
        ),
      ],
    );
  }
}

class _CatalogTypeSelector extends StatelessWidget {
  const _CatalogTypeSelector({
    required this.selectedValue,
    required this.onChanged,
  });

  final String selectedValue;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _CatalogTypeOption(
            title: 'Simples',
            subtitle: 'Cadastro direto para venda individual',
            icon: Icons.inventory_2_outlined,
            selected: selectedValue == ProductCatalogTypes.simple,
            onTap: () => onChanged(ProductCatalogTypes.simple),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _CatalogTypeOption(
            title: 'Com variação',
            subtitle: 'Modelo + variação para organizar SKUs',
            icon: Icons.layers_outlined,
            selected: selectedValue == ProductCatalogTypes.variant,
            onTap: () => onChanged(ProductCatalogTypes.variant),
          ),
        ),
      ],
    );
  }
}

class _CatalogTypeOption extends StatelessWidget {
  const _CatalogTypeOption({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Material(
      color: selected
          ? colorScheme.primaryContainer.withValues(alpha: 0.6)
          : colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected
                  ? colorScheme.primary
                  : colorScheme.outlineVariant,
              width: selected ? 1.4 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                icon,
                color: selected
                    ? colorScheme.primary
                    : colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 12),
              Text(
                title,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                subtitle,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProductPhotoTile extends StatelessWidget {
  const _ProductPhotoTile({
    required this.photo,
    required this.isPrimary,
    required this.isPickingPhoto,
    required this.onTap,
    required this.onRemove,
  });

  final _EditableProductPhoto? photo;
  final bool isPrimary;
  final bool isPickingPhoto;
  final VoidCallback? onTap;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final hasPhoto = photo != null;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            color: hasPhoto
                ? colorScheme.surfaceContainerLow
                : colorScheme.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isPrimary
                  ? colorScheme.primary
                  : colorScheme.outlineVariant,
              width: isPrimary ? 1.4 : 1,
            ),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (hasPhoto)
                ClipRRect(
                  borderRadius: BorderRadius.circular(19),
                  child: Image.file(
                    File(photo!.localPath),
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) =>
                        _PhotoPlaceholder(isBusy: isPickingPhoto),
                  ),
                )
              else
                _PhotoPlaceholder(isBusy: isPickingPhoto),
              if (isPrimary)
                Positioned(
                  left: 8,
                  top: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: colorScheme.primary,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      'Principal',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colorScheme.onPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              if (hasPhoto)
                Positioned(
                  right: 8,
                  top: 8,
                  child: IconButton.filledTonal(
                    visualDensity: VisualDensity.compact,
                    onPressed: onRemove,
                    icon: const Icon(Icons.close_rounded, size: 18),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PhotoPlaceholder extends StatelessWidget {
  const _PhotoPlaceholder({required this.isBusy});

  final bool isBusy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.all(10),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            isBusy ? Icons.hourglass_top_rounded : Icons.add_a_photo_outlined,
            size: 24,
            color: colorScheme.primary,
          ),
          const SizedBox(height: 8),
          Text(
            isBusy ? 'Carregando...' : 'Adicionar foto',
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _EditableModifierGroupCard extends StatelessWidget {
  const _EditableModifierGroupCard({
    required this.group,
    required this.onEditGroup,
    required this.onDeleteGroup,
    required this.onAddOption,
    required this.onEditOption,
    required this.onDeleteOption,
  });

  final _EditableModifierGroup group;
  final VoidCallback onEditGroup;
  final VoidCallback onDeleteGroup;
  final VoidCallback onAddOption;
  final ValueChanged<int> onEditOption;
  final ValueChanged<int> onDeleteOption;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      elevation: 0,
      color: colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        group.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${group.isRequired ? 'Obrigatório' : 'Opcional'} • mín. ${group.minSelections} • máx. ${group.maxSelections ?? 'livre'}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: onEditGroup,
                  icon: const Icon(Icons.edit_outlined),
                ),
                IconButton(
                  onPressed: onDeleteGroup,
                  icon: const Icon(Icons.delete_outline_rounded),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (group.options.isEmpty)
              Text(
                'Nenhuma opção cadastrada.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              )
            else
              Column(
                children: List.generate(group.options.length, (index) {
                  final option = group.options[index];
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(option.name),
                    subtitle: Text(
                      option.adjustmentType == 'remove'
                          ? 'Remoção'
                          : 'Adição • ${AppFormatters.currencyFromCents(option.priceDeltaCents)}',
                    ),
                    trailing: Wrap(
                      spacing: 4,
                      children: [
                        IconButton(
                          onPressed: () => onEditOption(index),
                          icon: const Icon(Icons.edit_outlined),
                        ),
                        IconButton(
                          onPressed: () => onDeleteOption(index),
                          icon: const Icon(Icons.delete_outline_rounded),
                        ),
                      ],
                    ),
                  );
                }),
              ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: onAddOption,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Adicionar opção'),
            ),
          ],
        ),
      ),
    );
  }
}

class _FashionDimensionEditor extends StatelessWidget {
  const _FashionDimensionEditor({
    required this.title,
    required this.controller,
    required this.buttonLabel,
    required this.chips,
    required this.onSubmitted,
    required this.onAdd,
    required this.onRemoveChip,
  });

  final String title;
  final TextEditingController controller;
  final String buttonLabel;
  final List<String> chips;
  final ValueChanged<String> onSubmitted;
  final VoidCallback onAdd;
  final ValueChanged<String> onRemoveChip;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextFormField(
                controller: controller,
                onFieldSubmitted: onSubmitted,
                decoration: InputDecoration(
                  labelText: title == 'Tamanhos' ? 'Tamanho' : 'Cor',
                  hintText: title == 'Tamanhos' ? 'Ex.: P, M, G' : 'Ex.: Preto',
                ),
              ),
            ),
            const SizedBox(width: 12),
            FilledButton.tonalIcon(
              onPressed: onAdd,
              icon: const Icon(Icons.add_rounded),
              label: Text(
                buttonLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (chips.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              'Nenhum item adicionado em $title.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: chips
                .map(
                  (chip) => InputChip(
                    label: Text(
                      chip,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onDeleted: () => onRemoveChip(chip),
                  ),
                )
                .toList(growable: false),
          ),
      ],
    );
  }
}

class _FashionGradeMatrix extends StatelessWidget {
  const _FashionGradeMatrix({
    required this.sizes,
    required this.colors,
    required this.resolveCell,
    required this.onTapCell,
  });

  final List<String> sizes;
  final List<String> colors;
  final _EditableFashionGradeEntry Function(String size, String color)
  resolveCell;
  final Future<void> Function(String size, String color) onTapCell;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    const firstColumnWidth = 120.0;
    const cellWidth = 110.0;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(color: colorScheme.outlineVariant),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Table(
            defaultVerticalAlignment: TableCellVerticalAlignment.middle,
            columnWidths: {
              0: const FixedColumnWidth(firstColumnWidth),
              for (var index = 0; index < colors.length; index++)
                index + 1: const FixedColumnWidth(cellWidth),
            },
            children: [
              TableRow(
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerLow,
                ),
                children: [
                  const _MatrixHeaderCell(
                    label: 'Tamanho',
                    alignment: Alignment.centerLeft,
                  ),
                  for (final color in colors)
                    _MatrixHeaderCell(
                      label: color,
                      alignment: Alignment.center,
                    ),
                ],
              ),
              for (final size in sizes)
                TableRow(
                  children: [
                    _MatrixHeaderCell(
                      label: size,
                      alignment: Alignment.centerLeft,
                      emphasize: true,
                    ),
                    for (final color in colors)
                      Padding(
                        padding: const EdgeInsets.all(8),
                        child: _FashionGradeCell(
                          entry: resolveCell(size, color),
                          onTap: () => onTapCell(size, color),
                        ),
                      ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MatrixHeaderCell extends StatelessWidget {
  const _MatrixHeaderCell({
    required this.label,
    required this.alignment,
    this.emphasize = false,
  });

  final String label;
  final Alignment alignment;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      alignment: alignment,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      color: emphasize ? colorScheme.surfaceContainerLowest : null,
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _FashionGradeCell extends StatelessWidget {
  const _FashionGradeCell({required this.entry, required this.onTap});

  final _EditableFashionGradeEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final stockLabel = entry.stockText.trim().isEmpty ? '0' : entry.stockText;
    final additionalPriceCents = MoneyParser.parseToCents(
      entry.priceAdditionalText,
    );

    return Material(
      color: entry.isActive
          ? colorScheme.surfaceContainerLowest
          : colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      stockLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Icon(
                    entry.isActive
                        ? Icons.edit_note_rounded
                        : Icons.visibility_off_rounded,
                    size: 16,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                entry.sku ?? 'Definir SKU',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                additionalPriceCents > 0
                    ? '+ ${AppFormatters.currencyFromCents(additionalPriceCents)}'
                    : 'Sem acrescimo',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.label,
    required this.selected,
    required this.color,
    required this.icon,
    required this.onSelected,
  });

  final String label;
  final bool selected;
  final Color color;
  final IconData icon;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return FilterChip(
      selected: selected,
      onSelected: (_) => onSelected(),
      avatar: Icon(icon, size: 18, color: selected ? Colors.white : color),
      label: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.labelLarge?.copyWith(
          color: selected ? Colors.white : null,
          fontWeight: FontWeight.w700,
        ),
      ),
      backgroundColor: color.withValues(alpha: 0.10),
      selectedColor: color,
      checkmarkColor: Colors.white,
      side: BorderSide(color: selected ? color : color.withValues(alpha: 0.35)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
    );
  }
}

class _ParsedFashionGridHint {
  const _ParsedFashionGridHint({
    this.sizes = const <String>[],
    this.colors = const <String>[],
  });

  final List<String> sizes;
  final List<String> colors;
}

class _EditableProductPhoto {
  const _EditableProductPhoto({
    required this.localPath,
    required this.isPrimary,
  });

  final String localPath;
  final bool isPrimary;

  _EditableProductPhoto copyWith({String? localPath, bool? isPrimary}) {
    return _EditableProductPhoto(
      localPath: localPath ?? this.localPath,
      isPrimary: isPrimary ?? this.isPrimary,
    );
  }
}

class _EditableModifierGroup {
  const _EditableModifierGroup({
    required this.name,
    required this.isRequired,
    required this.minSelections,
    required this.maxSelections,
    required this.options,
  });

  final String name;
  final bool isRequired;
  final int minSelections;
  final int? maxSelections;
  final List<_EditableModifierOption> options;

  _EditableModifierGroup copyWith({
    String? name,
    bool? isRequired,
    int? minSelections,
    int? maxSelections,
    List<_EditableModifierOption>? options,
  }) {
    return _EditableModifierGroup(
      name: name ?? this.name,
      isRequired: isRequired ?? this.isRequired,
      minSelections: minSelections ?? this.minSelections,
      maxSelections: maxSelections ?? this.maxSelections,
      options: options ?? this.options,
    );
  }
}

class _EditableModifierOption {
  const _EditableModifierOption({
    required this.name,
    required this.adjustmentType,
    required this.priceDeltaCents,
  });

  final String name;
  final String adjustmentType;
  final int priceDeltaCents;
}

class _EditableFashionGradeEntry {
  const _EditableFashionGradeEntry({
    required this.sizeLabel,
    required this.colorLabel,
    required this.stockText,
    this.sku,
    this.priceAdditionalText = '',
    this.isActive = true,
  });

  final String sizeLabel;
  final String colorLabel;
  final String stockText;
  final String? sku;
  final String priceAdditionalText;
  final bool isActive;
}

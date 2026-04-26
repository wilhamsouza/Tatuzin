import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../app/core/formatters/app_formatters.dart';
import '../../../../app/core/widgets/app_page_header.dart';
import '../../../../app/core/providers/app_data_refresh_provider.dart';
import '../../../../app/core/utils/money_parser.dart';
import '../../../../app/core/utils/quantity_parser.dart';
import '../../../../app/theme/app_design_tokens.dart';
import '../../../categorias/domain/entities/category.dart';
import '../../../categorias/presentation/providers/category_providers.dart';
import '../../../insumos/domain/entities/supply.dart';
import '../../../insumos/presentation/providers/supply_providers.dart';
import '../../domain/entities/base_product.dart';
import '../../domain/entities/product.dart';
import '../../domain/services/product_cost_calculator.dart';
import '../providers/product_providers.dart';
import '../widgets/product_form/fashion_grid_section.dart';
import '../widgets/product_form/modifier_groups_section.dart';
import '../widgets/product_form/product_base_info_section.dart';
import '../widgets/product_form/product_footer_action_bar.dart';
import '../widgets/product_form/product_form_models.dart';
import '../widgets/product_form/product_profitability_section.dart';
import '../widgets/product_form/product_recipe_section.dart';
import '../widgets/product_form/product_niche_details_section.dart';
import '../widgets/product_form/product_photos_section.dart';

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

  late bool _isActive;
  int? _selectedCategoryId;
  int? _selectedBaseProductId;
  late String _selectedUnitMeasure;

  bool _isLoadingAdvancedData = false;
  bool _isPickingPhoto = false;
  bool _isSaving = false;

  // ── Toggle flags for optional sections ──
  bool _showGrid = false;
  bool _showRecipe = false;
  bool _showModifiers = false;
  bool _showExtras = false;

  List<EditableProductPhoto> _photos = const <EditableProductPhoto>[];
  List<EditableModifierGroup> _foodModifierGroups =
      const <EditableModifierGroup>[];
  List<EditableProductRecipeItemDraft> _recipeItems =
      const <EditableProductRecipeItemDraft>[];
  FashionGridDraft _fashionGridDraft = const FashionGridDraft();

  bool get _isEditing => widget.initialProduct != null;

  // ── Inferred niche and catalog type ──
  String get _selectedNiche =>
      _showGrid ? ProductNiches.fashion : ProductNiches.food;
  String get _selectedCatalogType =>
      _showGrid ? ProductCatalogTypes.variant : ProductCatalogTypes.simple;

  bool get _isFoodNiche => _selectedNiche == ProductNiches.food;
  bool get _isFashionNiche => _selectedNiche == ProductNiches.fashion;
  bool get _isVariantCatalog =>
      _selectedCatalogType == ProductCatalogTypes.variant;
  bool get _usesVariantStock => _isFashionNiche;

  ProductCostSummary get _recipeCostSummary => ProductCostCalculator.calculate(
    salePriceCents: MoneyParser.parseToCents(_priceController.text),
    items: _recipeItems
        .map((item) => item.toCostInput())
        .toList(growable: false),
  );

  @override
  void initState() {
    super.initState();
    final product = widget.initialProduct;

    _selectedCategoryId = product?.categoryId;
    _selectedBaseProductId = product?.baseProductId;
    _selectedUnitMeasure = product?.unitMeasure ?? 'un';
    _isActive = product?.isActive ?? true;

    _nameController = TextEditingController(text: product?.name ?? '');
    _modelNameController = TextEditingController(
      text: product?.modelName ?? '',
    );
    _variantLabelController = TextEditingController(
      text: product?.variantLabel ?? '',
    );
    _extraAttributesController = TextEditingController(
      text: _buildInitialExtraAttributes(product),
    );
    _descriptionController = TextEditingController(
      text: product?.description ?? '',
    );
    _barcodeController = TextEditingController(text: product?.barcode ?? '');
    _costController = TextEditingController(
      text: AppFormatters.currencyInputFromCents(
        product?.manualCostCents ?? product?.costCents ?? 0,
      ),
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

    _photos = product?.hasPhoto ?? false
        ? <EditableProductPhoto>[
            EditableProductPhoto(
              localPath: product!.primaryPhotoPath!,
              isPrimary: true,
            ),
          ]
        : const <EditableProductPhoto>[];
    _foodModifierGroups = product == null
        ? const <EditableModifierGroup>[]
        : product.modifierGroups
              .map(EditableModifierGroup.fromProduct)
              .toList(growable: false);
    _fashionGridDraft = FashionGridDraft.fromExisting(
      gridHint: _findVariantAttributeValue(product, 'fashion_size_grid_hint'),
      variants: product?.variants ?? const <ProductVariant>[],
    );

    // ── Auto-open sections based on existing data when editing ──
    if (product != null) {
      final normalizedNiche = ProductNiches.normalize(product.niche);
      if (normalizedNiche == ProductNiches.fashion ||
          _fashionGridDraft.hasDimensions) {
        _showGrid = true;
      }
      if (_foodModifierGroups.isNotEmpty) {
        _showModifiers = true;
      }
      if (_hasNicheDetails(product)) {
        _showExtras = true;
      }
      // Recipe is loaded async, will be opened in _loadAdvancedData
    }

    _priceController.addListener(_handleLivePreviewChanged);
    _loadAdvancedData();
  }

  bool _hasNicheDetails(Product product) {
    return product.variantAttributes.any(
      (attr) =>
          attr.key.startsWith('food_') ||
          attr.key.startsWith('fashion_') ||
          (attr.key != 'model' && attr.key != 'variant'),
    );
  }

  @override
  void dispose() {
    _priceController.removeListener(_handleLivePreviewChanged);
    _nameController.dispose();
    _modelNameController.dispose();
    _variantLabelController.dispose();
    _extraAttributesController.dispose();
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
    super.dispose();
  }

  void _handleLivePreviewChanged() {
    if (!mounted) {
      return;
    }
    setState(() {});
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
      final recipeItems = await localProductRepository.listProductRecipeItems(
        product.id,
      );

      List<EditableModifierGroup> modifierGroups = _foodModifierGroups;
      if (modifierGroups.isEmpty && product.baseProductId != null) {
        final groups = await localCatalogRepository.listModifierGroups(
          product.baseProductId!,
        );
        final loadedGroups = <EditableModifierGroup>[];
        for (final group in groups) {
          final options = await localCatalogRepository.listModifierOptions(
            group.id,
          );
          loadedGroups.add(
            EditableModifierGroup(
              name: group.name,
              isRequired: group.isRequired,
              minSelections: group.minSelections,
              maxSelections: group.maxSelections,
              options: options
                  .map(
                    (option) => EditableModifierOption(
                      name: option.name,
                      adjustmentType: option.adjustmentType,
                      priceDeltaCents: option.priceDeltaCents,
                    ),
                  )
                  .toList(growable: false),
            ),
          );
        }
        modifierGroups = loadedGroups;
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _photos = photos.isNotEmpty
            ? photos
                  .map(
                    (photo) => EditableProductPhoto(
                      localPath: photo.localPath,
                      isPrimary: photo.isPrimary,
                    ),
                  )
                  .toList(growable: false)
            : _photos;
        _foodModifierGroups = modifierGroups;
        _recipeItems = recipeItems
            .map(EditableProductRecipeItemDraft.fromProductRecipeItem)
            .toList(growable: false);
        _fashionGridDraft = FashionGridDraft.fromExisting(
          gridHint: _findVariantAttributeValue(
            product,
            'fashion_size_grid_hint',
          ),
          variants: productVariants,
        );

        // Auto-open sections if data was loaded
        if (_recipeItems.isNotEmpty) {
          _showRecipe = true;
        }
        if (_foodModifierGroups.isNotEmpty) {
          _showModifiers = true;
        }
        if (_fashionGridDraft.hasDimensions) {
          _showGrid = true;
        }
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
    final suppliesAsync = ref.watch(activeSupplyOptionsProvider);
    final categories = categoriesAsync.valueOrNull ?? const <Category>[];
    final baseProducts = baseProductsAsync.valueOrNull ?? const <BaseProduct>[];
    final supplies = suppliesAsync.valueOrNull ?? const <Supply>[];
    final layout = context.appLayout;

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Editar produto' : 'Novo produto'),
      ),
      bottomNavigationBar: ProductFooterActionBar(
        contextLabel: _footerContextLabel,
        primaryLabel: _isEditing ? 'Salvar alteracoes' : 'Criar produto',
        isSaving: _isSaving,
        onPressed: _save,
      ),
      body: Form(
        key: _formKey,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            layout.pagePadding,
            layout.pagePadding,
            layout.pagePadding,
            148,
          ),
          children: [
            AppPageHeader(
              title: _isEditing ? 'Editar produto' : 'Novo produto',
              subtitle:
                  'Preencha o essencial e use os botoes abaixo para adicionar mais detalhes.',
              badgeLabel: _isEditing ? 'Edicao' : 'Cadastro',
              badgeIcon: Icons.inventory_2_rounded,
              emphasized: true,
            ),
            SizedBox(height: layout.sectionGap),

            // ── 1. Informações do produto + Preço e estoque ──
            ProductBaseInfoSection(
              isEditing: _isEditing,
              selectedNiche: _selectedNiche,
              selectedCatalogType: _selectedCatalogType,
              usesVariantStock: _usesVariantStock,
              activeVariantCount: _fashionGridDraft.activeVariantCount,
              nameController: _nameController,
              modelNameController: _modelNameController,
              variantLabelController: _variantLabelController,
              descriptionController: _descriptionController,
              barcodeController: _barcodeController,
              costController: _costController,
              priceController: _priceController,
              stockController: _stockController,
              categoryId: _selectedCategoryId,
              baseProductId: _selectedBaseProductId,
              unitMeasure: _selectedUnitMeasure,
              isActive: _isActive,
              categories: categories,
              baseProducts: baseProducts,
              isCategoryLoading: categoriesAsync.isLoading,
              isBaseProductLoading: baseProductsAsync.isLoading,
              onCategoryChanged: (value) =>
                  setState(() => _selectedCategoryId = value),
              onBaseProductChanged: (value) =>
                  setState(() => _selectedBaseProductId = value),
              onUnitMeasureChanged: (value) =>
                  setState(() => _selectedUnitMeasure = value),
              onActiveChanged: (value) => setState(() => _isActive = value),
            ),
            SizedBox(height: layout.sectionGap),

            // ── 2. Fotos ──
            ProductPhotosSection(
              photos: _photos,
              maxPhotos: _maxPhotos,
              isPickingPhoto: _isPickingPhoto,
              onAddPhoto: _promptPhotoSource,
              onRemovePhoto: _removePhoto,
            ),
            SizedBox(height: layout.sectionGap),

            // ── 3. Optional sections (toggled by + buttons) ──
            _buildToggleChips(layout),

            // ── 3a. Grade de tamanhos/cores ──
            if (_showGrid) ...[
              SizedBox(height: layout.sectionGap),
              FashionGridSection(
                key: const ValueKey('fashion-grid'),
                isLoading: _isLoadingAdvancedData,
                skuSeed: _variantSkuSeed,
                draft: _fashionGridDraft,
                onChanged: (draft) => setState(() => _fashionGridDraft = draft),
              ),
            ],

            // ── 3b. Ficha técnica (insumos) ──
            if (_showRecipe) ...[
              SizedBox(height: layout.sectionGap),
              ProductRecipeSection(
                items: _recipeItems,
                summary: _recipeCostSummary,
                isLoadingRecipe: _isLoadingAdvancedData,
                isLoadingSupplies: suppliesAsync.isLoading,
                onAddItem: () => _openRecipeItemEditor(supplies),
                onEditItem: (index) =>
                    _openRecipeItemEditor(supplies, index: index),
                onRemoveItem: (index) =>
                    setState(() => _recipeItems.removeAt(index)),
              ),
              SizedBox(height: layout.sectionGap),
              ProductProfitabilitySection(
                summary: _recipeCostSummary,
                salePriceCents: MoneyParser.parseToCents(_priceController.text),
                manualCostCents: MoneyParser.parseToCents(_costController.text),
              ),
            ],

            // ── 3c. Adicionais (complementos) ──
            if (_showModifiers) ...[
              SizedBox(height: layout.sectionGap),
              ModifierGroupsSection(
                key: const ValueKey('modifier-groups'),
                groups: _foodModifierGroups,
                isLoading: _isLoadingAdvancedData,
                onChanged: (groups) =>
                    setState(() => _foodModifierGroups = groups),
              ),
            ],

            // ── 3d. Informações extras ──
            if (_showExtras) ...[
              SizedBox(height: layout.sectionGap),
              ProductNicheDetailsSection(
                selectedNiche: _selectedNiche,
                foodAllergensController: _foodAllergensController,
                foodPrepTimeController: _foodPrepTimeController,
                foodOperationalAvailabilityController:
                    _foodOperationalAvailabilityController,
                fashionBrandController: _fashionBrandController,
                fashionCompositionController: _fashionCompositionController,
                fashionWeightController: _fashionWeightController,
                fashionTagsController: _fashionTagsController,
                extraAttributesController: _extraAttributesController,
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ── Toggle chip bar ──
  Widget _buildToggleChips(dynamic layout) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _ToggleActionChip(
          label: 'Grade de tamanhos',
          icon: Icons.grid_view_rounded,
          isActive: _showGrid,
          onToggle: () => setState(() {
            _showGrid = !_showGrid;
            if (!_showGrid) {
              _fashionGridDraft = const FashionGridDraft();
            }
          }),
        ),
        _ToggleActionChip(
          label: 'Ficha tecnica',
          icon: Icons.receipt_long_rounded,
          isActive: _showRecipe,
          onToggle: () => setState(() => _showRecipe = !_showRecipe),
        ),
        _ToggleActionChip(
          label: 'Adicionais',
          icon: Icons.playlist_add_rounded,
          isActive: _showModifiers,
          onToggle: () => setState(() => _showModifiers = !_showModifiers),
        ),
        _ToggleActionChip(
          label: 'Informacoes extras',
          icon: Icons.tune_rounded,
          isActive: _showExtras,
          onToggle: () => setState(() => _showExtras = !_showExtras),
        ),
      ],
    );
  }

  String get _variantSkuSeed =>
      _cleanNullable(_modelNameController.text) ??
      _cleanNullable(_nameController.text) ??
      'PRODUTO';

  String get _footerContextLabel {
    if (_showGrid) {
      if (_fashionGridDraft.hasDimensions) {
        return '${_fashionGridDraft.activeVariantCount} variacoes ativas • estoque ${AppFormatters.quantityFromMil(_fashionGridDraft.totalStockMil)}';
      }
      return 'Configure tamanhos e cores para gerar as variacoes.';
    }

    if (_foodModifierGroups.isNotEmpty) {
      final items = _foodModifierGroups.fold<int>(
        0,
        (total, group) => total + group.options.length,
      );
      return '${_foodModifierGroups.length} grupos • $items itens';
    }

    return 'Pronto para salvar.';
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
                title: const Text('Camera'),
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
          EditableProductPhoto(
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

  Future<void> _openRecipeItemEditor(
    List<Supply> supplies, {
    int? index,
  }) async {
    final current = index == null ? null : _recipeItems[index];
    final availableSupplies = <Supply>[
      ...supplies,
      if (current != null &&
          !supplies.any((supply) => supply.id == current.supply.id))
        current.supply,
    ];

    if (availableSupplies.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Cadastre pelo menos um insumo antes de montar a ficha.',
          ),
        ),
      );
      return;
    }

    final edited = await showModalBottomSheet<EditableProductRecipeItemDraft>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: Colors.transparent,
      builder: (context) => ProductRecipeItemEditorSheet(
        supplies: availableSupplies,
        initialItem: current,
      ),
    );

    if (edited == null) {
      return;
    }

    setState(() {
      if (index == null) {
        _recipeItems = [..._recipeItems, edited];
      } else {
        final updated = [..._recipeItems];
        updated[index] = edited;
        _recipeItems = updated;
      }
    });
  }

  Future<void> _save() async {
    if (_isLoadingAdvancedData) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Aguarde o carregamento completo da ficha tecnica.'),
        ),
      );
      return;
    }

    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (_showGrid && !_fashionGridDraft.hasDimensions) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Adicione pelo menos um tamanho e uma cor para salvar a grade.',
          ),
        ),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final repository = ref.read(productRepositoryProvider);
      final modelName = _cleanNullable(_modelNameController.text);
      final variantLabel = _cleanNullable(_variantLabelController.text);
      final variants = _isFashionNiche
          ? _fashionGridDraft.toVariantInputs(skuSeed: _variantSkuSeed)
          : const <ProductVariantInput>[];
      final variantAttributes = _buildVariantAttributes(
        modelName: modelName,
        variantLabel: variantLabel,
      );
      final modifierGroups = _showModifiers
          ? _buildFoodModifierGroupsInput()
          : null;
      final resolvedName = _nameController.text.trim();

      final input = ProductInput(
        name: resolvedName,
        description: _cleanNullable(_descriptionController.text),
        categoryId: _selectedCategoryId,
        barcode: _cleanNullable(_barcodeController.text),
        photos: _buildPhotoInputs(),
        variants: variants,
        niche: _selectedNiche,
        catalogType: _selectedCatalogType,
        modelName: _isVariantCatalog ? modelName : null,
        variantLabel: _isVariantCatalog ? variantLabel : null,
        baseProductId: _isVariantCatalog ? _selectedBaseProductId : null,
        variantAttributes: variantAttributes,
        modifierGroups: modifierGroups,
        recipeItems: _recipeItems
            .map((item) => item.toRecipeInput())
            .toList(growable: false),
        unitMeasure: _selectedUnitMeasure,
        costCents: MoneyParser.parseToCents(_costController.text),
        salePriceCents: MoneyParser.parseToCents(_priceController.text),
        stockMil: _usesVariantStock
            ? _fashionGridDraft.totalStockMil
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

  List<ProductModifierGroupInput>? _buildFoodModifierGroupsInput() {
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

    for (final rawLine in _extraAttributesController.text.split('\n')) {
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
      addAttribute(
        'fashion_size_grid_hint',
        _fashionGridDraft.buildHintValue(),
      );
    }

    return attributes;
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

  String _buildDelimitedAttributeList(String? value) {
    final normalized = _normalizeCommaSeparatedValues(value);
    return normalized?.replaceAll('|', ', ') ?? '';
  }

  String? _normalizeCommaSeparatedValues(String? raw) {
    final normalizedSource = (raw ?? '').replaceAll('|', ',');
    final tokens = normalizedSource
        .split(',')
        .map((token) => token.trim())
        .where((token) => token.isNotEmpty)
        .toList(growable: false);
    if (tokens.isEmpty) {
      return null;
    }
    return tokens.join('|');
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

  bool _isReservedNicheAttribute(String key) {
    return key.startsWith('food_') || key.startsWith('fashion_');
  }

  String? _cleanNullable(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }
}

// ── Toggle chip widget ──
class _ToggleActionChip extends StatelessWidget {
  const _ToggleActionChip({
    required this.label,
    required this.icon,
    required this.isActive,
    required this.onToggle,
  });

  final String label;
  final IconData icon;
  final bool isActive;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final tokens = context.appColors;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      child: FilterChip(
        selected: isActive,
        showCheckmark: false,
        avatar: Icon(
          isActive ? Icons.check_rounded : icon,
          size: 18,
          color: isActive ? tokens.brand.base : colorScheme.onSurfaceVariant,
        ),
        label: Text(label),
        labelStyle: theme.textTheme.labelLarge?.copyWith(
          fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
          color: isActive ? tokens.brand.onSurface : colorScheme.onSurface,
        ),
        selectedColor: tokens.brand.surface,
        side: BorderSide(
          color: isActive ? tokens.brand.border : colorScheme.outlineVariant,
        ),
        onSelected: (_) => onToggle(),
      ),
    );
  }
}

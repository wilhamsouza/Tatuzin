import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
  final _formKey = GlobalKey<FormState>();
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
  late bool _isActive;
  int? _selectedCategoryId;
  int? _selectedBaseProductId;
  late String _selectedUnitMeasure;
  late String _selectedCatalogType;
  bool _isSaving = false;

  bool get _isEditing => widget.initialProduct != null;
  bool get _isVariantCatalog =>
      _selectedCatalogType == ProductCatalogTypes.variant;

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
    _isActive = product?.isActive ?? true;
    _selectedCategoryId = product?.categoryId;
    _selectedBaseProductId = product?.baseProductId;
    _selectedUnitMeasure = product?.unitMeasure ?? 'un';
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
    super.dispose();
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
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Informações'),
              Tab(text: 'Preço e estoque'),
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
          title: 'Tipo do cadastro',
          subtitle: _isVariantCatalog
              ? 'Use modelo e variação para organizar produtos relacionados mantendo o fluxo atual.'
              : 'Use cadastro simples para itens vendidos individualmente.',
          child: Column(
            children: [
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
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: _isEditing ? 'Estoque atual' : 'Estoque inicial',
                  helperText:
                      'Informe a quantidade conforme a unidade de medida',
                ),
                validator: (value) {
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
                child: Row(
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
                    Switch.adaptive(
                      value: _isActive,
                      onChanged: (value) => setState(() => _isActive = value),
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

  Widget _buildPhotosTab(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        _SectionCard(
          title: 'Fotos do produto',
          subtitle:
              'A estrutura visual já está preparada para a próxima evolução do cadastro.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: 4,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 1.08,
                ),
                itemBuilder: (context, index) {
                  final isPrimarySlot = index == 0;
                  return Container(
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: colorScheme.outlineVariant),
                    ),
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          isPrimarySlot
                              ? Icons.add_a_photo_rounded
                              : Icons.image_outlined,
                          size: 28,
                          color: colorScheme.primary,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          isPrimarySlot
                              ? 'Capa do produto'
                              : 'Espaço reservado',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          isPrimarySlot
                              ? 'Área pronta para adicionar a foto principal'
                              : 'Estrutura preparada para futuras imagens',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: null,
                  icon: const Icon(Icons.add_photo_alternate_outlined),
                  label: const Text('Adicionar foto'),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'O suporte completo de fotos será expandido em uma próxima fase, sem persistência fake nesta etapa.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
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
      final modifierGroups = _isVariantCatalog
          ? _parseModifierGroups(_modifierGroupsController.text)
          : null;
      final resolvedName = _isVariantCatalog
          ? _buildVariantDisplayName(modelName!, variantLabel!)
          : _nameController.text.trim();
      final input = ProductInput(
        name: resolvedName,
        description: _descriptionController.text,
        categoryId: _selectedCategoryId,
        barcode: _barcodeController.text,
        catalogType: _selectedCatalogType,
        modelName: _isVariantCatalog ? modelName : null,
        variantLabel: _isVariantCatalog ? variantLabel : null,
        baseProductId: _isVariantCatalog ? _selectedBaseProductId : null,
        variantAttributes: variantAttributes,
        modifierGroups: modifierGroups,
        unitMeasure: _selectedUnitMeasure,
        costCents: MoneyParser.parseToCents(_costController.text),
        salePriceCents: MoneyParser.parseToCents(_priceController.text),
        stockMil: QuantityParser.parseToMil(_stockController.text),
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
              attribute.key != 'legacy_variant_label' &&
              attribute.key != 'model' &&
              attribute.key != 'variant',
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
    if (!_isVariantCatalog) {
      return const <ProductVariantAttributeInput>[];
    }

    final attributes = <ProductVariantAttributeInput>[
      if (modelName != null)
        ProductVariantAttributeInput(key: 'model', value: modelName),
      if (variantLabel != null)
        ProductVariantAttributeInput(key: 'variant', value: variantLabel),
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

  List<ProductModifierGroupInput>? _parseModifierGroups(String raw) {
    if (!_isVariantCatalog) {
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
              Text(
                title,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: colorScheme.onSurfaceVariant,
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

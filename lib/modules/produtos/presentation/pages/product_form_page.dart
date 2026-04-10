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

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Editar produto' : 'Novo produto'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            DropdownButtonFormField<String>(
              initialValue: _selectedCatalogType,
              decoration: const InputDecoration(labelText: 'Tipo do cadastro'),
              items: const [
                DropdownMenuItem(
                  value: ProductCatalogTypes.simple,
                  child: Text('Simples'),
                ),
                DropdownMenuItem(
                  value: ProductCatalogTypes.variant,
                  child: Text('Com variacao'),
                ),
              ],
              onChanged: (value) {
                if (value == null) {
                  return;
                }
                _changeCatalogType(value);
              },
            ),
            const SizedBox(height: 12),
            Text(
              _isVariantCatalog
                  ? 'Use Modelo + Variacao para organizar SKUs sem quebrar o fluxo simples atual.'
                  : 'Cadastre um produto individual normalmente para venda simples.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
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
                  labelText: 'Variacao',
                  hintText: 'Ex.: P, M, G, Duplo',
                ),
                textCapitalization: TextCapitalization.sentences,
                validator: (value) {
                  if (!_isVariantCatalog) {
                    return null;
                  }
                  if (value == null || value.trim().isEmpty) {
                    return 'Informe a variacao';
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
                  hintText: 'Opcional para agrupar SKUs',
                ),
                items: [
                  const DropdownMenuItem<int?>(
                    value: null,
                    child: Text('Usar base automatica'),
                  ),
                  for (final baseProduct in baseProducts)
                    DropdownMenuItem<int?>(
                      value: baseProduct.id,
                      child: Text(baseProduct.name),
                    ),
                ],
                onChanged: baseProductsAsync.isLoading
                    ? null
                    : (value) => setState(() => _selectedBaseProductId = value),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _extraAttributesController,
                decoration: const InputDecoration(
                  labelText: 'Atributos extras (opcional)',
                  hintText: 'Uma linha por atributo: chave=valor',
                ),
                minLines: 2,
                maxLines: 5,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _modifierGroupsController,
                decoration: const InputDecoration(
                  labelText: 'Modificadores (opcional)',
                  hintText:
                      'Uma linha por grupo: Grupo: opcao1, opcao2, -remocao, +adicional:300',
                ),
                minLines: 2,
                maxLines: 6,
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.auto_awesome_rounded,
                      color: colorScheme.primary,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Nome final do item',
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _variantPreviewLabel,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ] else ...[
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Nome do produto'),
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
              ),
            ],
            const SizedBox(height: 16),
            TextFormField(
              controller: _descriptionController,
              decoration: const InputDecoration(
                labelText: 'Descricao',
                hintText: 'Opcional',
              ),
              minLines: 2,
              maxLines: 4,
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
              decoration: const InputDecoration(labelText: 'Categoria'),
              onChanged: categoriesAsync.isLoading
                  ? null
                  : (value) => setState(() => _selectedCategoryId = value),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _barcodeController,
              decoration: const InputDecoration(
                labelText: 'Codigo de barras',
                hintText: 'Opcional',
              ),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _selectedUnitMeasure,
              decoration: const InputDecoration(labelText: 'Unidade de medida'),
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
            TextFormField(
              controller: _costController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(labelText: 'Custo'),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _priceController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(labelText: 'Preco de venda'),
              validator: (value) {
                final cents = MoneyParser.parseToCents(value ?? '');
                if (cents <= 0) {
                  return 'Informe um preco de venda valido';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _stockController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: _isEditing ? 'Estoque atual' : 'Estoque inicial',
              ),
              validator: (value) {
                final raw = (value ?? '').trim();
                if (!RegExp(r'\d').hasMatch(raw)) {
                  return 'Informe um estoque valido';
                }
                final parsed = QuantityParser.parseToMil(value ?? '');
                if (parsed < 0) {
                  return 'Informe um estoque valido';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: _isActive,
              title: const Text('Produto ativo'),
              onChanged: (value) => setState(() => _isActive = value),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _isSaving ? null : _save,
              child: Text(_isEditing ? 'Salvar alteracoes' : 'Criar produto'),
            ),
          ],
        ),
      ),
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
        .map((group) => '${group.name}: ${group.options.length} opcoes')
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

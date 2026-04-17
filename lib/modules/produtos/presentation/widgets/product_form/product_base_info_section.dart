import 'package:flutter/material.dart';

import '../../../../../app/core/widgets/app_card.dart';
import '../../../../../app/core/widgets/app_summary_block.dart';
import '../../../../../app/core/utils/money_parser.dart';
import '../../../../../app/core/utils/quantity_parser.dart';
import '../../../../../app/core/widgets/app_section_card.dart';
import '../../../../../app/theme/app_design_tokens.dart';
import '../../../../categorias/domain/entities/category.dart';
import '../../../domain/entities/base_product.dart';

class ProductBaseInfoSection extends StatelessWidget {
  const ProductBaseInfoSection({
    super.key,
    required this.isEditing,
    required this.selectedNiche,
    required this.selectedCatalogType,
    required this.usesVariantStock,
    required this.activeVariantCount,
    required this.nameController,
    required this.modelNameController,
    required this.variantLabelController,
    required this.descriptionController,
    required this.barcodeController,
    required this.costController,
    required this.priceController,
    required this.stockController,
    required this.categoryId,
    required this.baseProductId,
    required this.unitMeasure,
    required this.isActive,
    required this.categories,
    required this.baseProducts,
    required this.isCategoryLoading,
    required this.isBaseProductLoading,
    required this.onCategoryChanged,
    required this.onBaseProductChanged,
    required this.onUnitMeasureChanged,
    required this.onActiveChanged,
  });

  final bool isEditing;
  final String selectedNiche;
  final String selectedCatalogType;
  final bool usesVariantStock;
  final int activeVariantCount;
  final TextEditingController nameController;
  final TextEditingController modelNameController;
  final TextEditingController variantLabelController;
  final TextEditingController descriptionController;
  final TextEditingController barcodeController;
  final TextEditingController costController;
  final TextEditingController priceController;
  final TextEditingController stockController;
  final int? categoryId;
  final int? baseProductId;
  final String unitMeasure;
  final bool isActive;
  final List<Category> categories;
  final List<BaseProduct> baseProducts;
  final bool isCategoryLoading;
  final bool isBaseProductLoading;
  final ValueChanged<int?> onCategoryChanged;
  final ValueChanged<int?> onBaseProductChanged;
  final ValueChanged<String> onUnitMeasureChanged;
  final ValueChanged<bool> onActiveChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final layout = context.appLayout;

    return AppSectionCard(
      title: 'Informacoes do produto',
      subtitle:
          'Preencha o essencial para cadastrar seu produto.',
      tone: AppCardTone.standard,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Always show simple name field ──
          TextFormField(
            controller: nameController,
            decoration: const InputDecoration(
              labelText: 'Nome do produto',
              hintText: 'Ex.: Coxinha de frango',
            ),
            textCapitalization: TextCapitalization.sentences,
            validator: (value) {
              if ((value ?? '').trim().isEmpty) {
                return 'Informe o nome do produto';
              }
              return null;
            },
          ),
          SizedBox(height: layout.sectionGap),
          TextFormField(
            controller: descriptionController,
            decoration: const InputDecoration(
              labelText: 'Descricao',
              hintText: 'Opcional',
            ),
            minLines: 2,
            maxLines: 4,
            textCapitalization: TextCapitalization.sentences,
          ),
          SizedBox(height: layout.sectionGap),
          _ResponsiveFieldRow(
            children: [
              DropdownButtonFormField<int?>(
                initialValue: categoryId,
                decoration: const InputDecoration(labelText: 'Categoria'),
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
                onChanged: isCategoryLoading ? null : onCategoryChanged,
              ),
              TextFormField(
                controller: barcodeController,
                decoration: const InputDecoration(
                  labelText: 'Codigo do produto',
                  hintText: 'Opcional',
                ),
              ),
            ],
          ),
          SizedBox(height: layout.sectionGap),
          _ResponsiveFieldRow(
            children: [
              DropdownButtonFormField<String>(
                initialValue: unitMeasure,
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
                    onUnitMeasureChanged(value);
                  }
                },
              ),
              SwitchListTile.adaptive(
                value: isActive,
                contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                title: const Text('Disponivel para venda'),
                subtitle: Text(
                  isActive ? 'Produto visivel na operacao.' : 'Oculto da operacao.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                onChanged: onActiveChanged,
              ),
            ],
          ),

          // ── Visual divider: Preço e estoque ──
          SizedBox(height: layout.sectionGap),
          Divider(color: colorScheme.outlineVariant),
          SizedBox(height: layout.sectionGap),
          Text(
            'Preco e estoque',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          SizedBox(height: layout.sectionGap),
          _ResponsiveFieldRow(
            children: [
              TextFormField(
                controller: costController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Custo',
                  helperText: 'Valor interno',
                  prefixText: 'R\$ ',
                ),
              ),
              TextFormField(
                controller: priceController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Preco de venda',
                  helperText: 'Valor cobrado do cliente',
                  prefixText: 'R\$ ',
                ),
                validator: (value) {
                  final cents = MoneyParser.parseToCents(value ?? '');
                  if (cents <= 0) {
                    return 'Informe um preco de venda valido';
                  }
                  return null;
                },
              ),
            ],
          ),
          SizedBox(height: layout.sectionGap),
          if (usesVariantStock)
            AppSummaryBlock(
              label: 'Estoque por variacoes',
              value: activeVariantCount > 0
                  ? '$activeVariantCount variacoes ativas'
                  : 'Grade ainda nao configurada',
              caption: activeVariantCount > 0
                  ? 'O estoque total sera calculado automaticamente pela grade.'
                  : 'Preencha tamanhos e cores para liberar o estoque automatico.',
              icon: Icons.grid_view_rounded,
              palette: context.appColors.info,
              compact: true,
            )
          else
            TextFormField(
              controller: stockController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: isEditing ? 'Estoque atual' : 'Estoque inicial',
                helperText:
                    'Informe a quantidade conforme a unidade de medida.',
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
        ],
      ),
    );
  }
}

class _ResponsiveFieldRow extends StatelessWidget {
  const _ResponsiveFieldRow({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final layout = context.appLayout;

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 620) {
          return Column(
            children: [
              for (var index = 0; index < children.length; index++) ...[
                children[index],
                if (index != children.length - 1)
                  SizedBox(height: layout.sectionGap),
              ],
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var index = 0; index < children.length; index++) ...[
              Expanded(child: children[index]),
              if (index != children.length - 1)
                SizedBox(width: layout.blockGap),
            ],
          ],
        );
      },
    );
  }
}

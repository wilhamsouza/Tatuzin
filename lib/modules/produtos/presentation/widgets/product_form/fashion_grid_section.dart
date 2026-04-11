import 'package:flutter/material.dart';

import '../../../../../app/core/formatters/app_formatters.dart';
import '../../../../../app/core/widgets/app_section_card.dart';
import 'product_form_models.dart';

class FashionGridSection extends StatefulWidget {
  const FashionGridSection({
    super.key,
    required this.isLoading,
    required this.skuSeed,
    required this.draft,
    required this.onChanged,
  });

  final bool isLoading;
  final String skuSeed;
  final FashionGridDraft draft;
  final ValueChanged<FashionGridDraft> onChanged;

  @override
  State<FashionGridSection> createState() => _FashionGridSectionState();
}

class _FashionGridSectionState extends State<FashionGridSection> {
  late final TextEditingController _sizeInputController;
  late final TextEditingController _colorInputController;

  @override
  void initState() {
    super.initState();
    _sizeInputController = TextEditingController();
    _colorInputController = TextEditingController();
  }

  @override
  void dispose() {
    _sizeInputController.dispose();
    _colorInputController.dispose();
    super.dispose();
  }

  void _addSize() {
    final nextDraft = widget.draft.addSize(_sizeInputController.text);
    if (nextDraft == widget.draft) {
      return;
    }
    _sizeInputController.clear();
    widget.onChanged(nextDraft);
  }

  void _addColor() {
    final nextDraft = widget.draft.addColor(_colorInputController.text);
    if (nextDraft == widget.draft) {
      return;
    }
    _colorInputController.clear();
    widget.onChanged(nextDraft);
  }

  Future<void> _openCellEditor(String size, String color) async {
    final current = widget.draft.resolveCell(
      size,
      color,
      skuSeed: widget.skuSeed,
    );
    final skuController = TextEditingController(text: current.sku);
    final stockController = TextEditingController(text: current.stockLabel);
    final priceController = TextEditingController(
      text: current.priceAdditionalLabel,
    );
    var isActive = current.isActive;

    final result = await showModalBottomSheet<FashionGridVariantDraft>(
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
                    Text('$size / $color'),
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
                      decoration: const InputDecoration(labelText: 'Estoque'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: priceController,
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
                      onChanged: (value) =>
                          setLocalState(() => isActive = value),
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
                                FashionGridVariantDraft(
                                  sizeLabel: size,
                                  colorLabel: color,
                                  stockMil: parseStockMilLabel(
                                    stockController.text,
                                  ),
                                  sku: skuController.text.trim().isEmpty
                                      ? FashionGridDraft.buildDefaultSku(
                                          widget.skuSeed,
                                          size,
                                          color,
                                        )
                                      : skuController.text.trim(),
                                  priceAdditionalCents:
                                      parsePriceAdditionalCents(
                                        priceController.text,
                                      ),
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
    priceController.dispose();

    if (result == null) {
      return;
    }

    widget.onChanged(widget.draft.upsertVariant(result));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return AppSectionCard(
      title: 'Grade de moda',
      subtitle:
          'Monte a matriz de tamanhos e cores. Cada celula representa uma variante vendavel com seu proprio estoque.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _DimensionEditor(
            title: 'Tamanhos',
            controller: _sizeInputController,
            buttonLabel: 'Adicionar tamanho',
            chips: widget.draft.sizes,
            onSubmitted: (_) => _addSize(),
            onAdd: _addSize,
            onRemoveChip: (size) =>
                widget.onChanged(widget.draft.removeSize(size)),
          ),
          const SizedBox(height: 16),
          _DimensionEditor(
            title: 'Cores',
            controller: _colorInputController,
            buttonLabel: 'Adicionar cor',
            chips: widget.draft.colors,
            onSubmitted: (_) => _addColor(),
            onAdd: _addColor,
            onRemoveChip: (color) =>
                widget.onChanged(widget.draft.removeColor(color)),
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(14),
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final stats = <Widget>[
                  _GridStat(
                    label: 'Combinacoes',
                    value: '${widget.draft.combinationCount}',
                  ),
                  _GridStat(
                    label: 'Variantes ativas',
                    value: '${widget.draft.activeVariantCount}',
                  ),
                  _GridStat(
                    label: 'Estoque total',
                    value: AppFormatters.quantityFromMil(
                      widget.draft.totalStockMil,
                    ),
                  ),
                ];

                if (constraints.maxWidth < 620) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (var index = 0; index < stats.length; index++) ...[
                        stats[index],
                        if (index != stats.length - 1)
                          const SizedBox(height: 10),
                      ],
                    ],
                  );
                }

                return Row(
                  children: [
                    for (var index = 0; index < stats.length; index++) ...[
                      Expanded(child: stats[index]),
                      if (index != stats.length - 1) const SizedBox(width: 10),
                    ],
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 16),
          if (widget.isLoading)
            const Center(child: CircularProgressIndicator())
          else if (!widget.draft.hasDimensions)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: colorScheme.outlineVariant),
              ),
              child: Text(
                'Adicione pelo menos um tamanho e uma cor para montar a grade.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  height: 1.35,
                ),
              ),
            )
          else
            _FashionGradeMatrix(
              sizes: widget.draft.sizes,
              colors: widget.draft.colors,
              resolveCell: (size, color) => widget.draft.resolveCell(
                size,
                color,
                skuSeed: widget.skuSeed,
              ),
              onTapCell: _openCellEditor,
            ),
        ],
      ),
    );
  }
}

class _DimensionEditor extends StatelessWidget {
  const _DimensionEditor({
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
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, constraints) {
            final input = TextFormField(
              controller: controller,
              onFieldSubmitted: onSubmitted,
              decoration: InputDecoration(
                labelText: title == 'Tamanhos' ? 'Tamanho' : 'Cor',
                hintText: title == 'Tamanhos' ? 'Ex.: P, M, G' : 'Ex.: Preto',
              ),
            );
            final button = FilledButton.tonalIcon(
              onPressed: onAdd,
              icon: const Icon(Icons.add_rounded),
              label: Text(buttonLabel),
            );

            if (constraints.maxWidth < 620) {
              return Column(
                children: [
                  input,
                  const SizedBox(height: 10),
                  SizedBox(width: double.infinity, child: button),
                ],
              );
            }

            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: input),
                const SizedBox(width: 12),
                button,
              ],
            );
          },
        ),
        const SizedBox(height: 10),
        if (chips.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(12),
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
                    label: Text(chip),
                    onDeleted: () => onRemoveChip(chip),
                  ),
                )
                .toList(growable: false),
          ),
      ],
    );
  }
}

class _GridStat extends StatelessWidget {
  const _GridStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w800,
          ),
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
  final FashionGridVariantDraft Function(String size, String color) resolveCell;
  final Future<void> Function(String size, String color) onTapCell;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    const firstColumnWidth = 96.0;
    const cellWidth = 128.0;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(color: colorScheme.outlineVariant),
            borderRadius: BorderRadius.circular(16),
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
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

  final FashionGridVariantDraft entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Material(
      color: entry.isActive
          ? colorScheme.surfaceContainerLowest
          : colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      entry.stockLabel,
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
                entry.sku,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                entry.priceAdditionalCents > 0
                    ? '+ ${AppFormatters.currencyFromCents(entry.priceAdditionalCents)}'
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

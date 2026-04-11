import 'package:flutter/material.dart';

import '../../../../../app/core/formatters/app_formatters.dart';
import '../../../../../app/core/utils/money_parser.dart';
import '../../../../../app/core/widgets/app_section_card.dart';
import 'product_form_models.dart';

class ModifierGroupsSection extends StatefulWidget {
  const ModifierGroupsSection({
    super.key,
    required this.groups,
    required this.isLoading,
    required this.onChanged,
  });

  final List<EditableModifierGroup> groups;
  final bool isLoading;
  final ValueChanged<List<EditableModifierGroup>> onChanged;

  @override
  State<ModifierGroupsSection> createState() => _ModifierGroupsSectionState();
}

class _ModifierGroupsSectionState extends State<ModifierGroupsSection> {
  Future<void> _openGroupEditor({int? index}) async {
    final current = index == null ? null : widget.groups[index];
    final nameController = TextEditingController(text: current?.name ?? '');
    final minController = TextEditingController(
      text: '${current?.minSelections ?? 0}',
    );
    final maxController = TextEditingController(
      text: current?.maxSelections?.toString() ?? '',
    );
    var isRequired = current?.isRequired ?? false;

    final result = await showDialog<EditableModifierGroup>(
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
                      value: isRequired,
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Obrigatorio'),
                      onChanged: (value) {
                        setLocalState(() => isRequired = value);
                      },
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: minController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Minimo de selecoes',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: maxController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Maximo de selecoes',
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
                      EditableModifierGroup(
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
                            const <EditableModifierOption>[],
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

    final updated = [...widget.groups];
    if (index == null) {
      updated.add(result);
    } else {
      updated[index] = result;
    }
    widget.onChanged(updated);
  }

  Future<void> _openOptionEditor({
    required int groupIndex,
    int? optionIndex,
  }) async {
    final group = widget.groups[groupIndex];
    final current = optionIndex == null ? null : group.options[optionIndex];
    final nameController = TextEditingController(text: current?.name ?? '');
    final priceController = TextEditingController(
      text: AppFormatters.currencyInputFromCents(current?.priceDeltaCents ?? 0),
    );
    var adjustmentType = current?.adjustmentType ?? 'add';

    final result = await showDialog<EditableModifierOption>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setLocalState) {
            return AlertDialog(
              title: Text(optionIndex == null ? 'Nova opcao' : 'Editar opcao'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(
                        labelText: 'Nome da opcao',
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: adjustmentType,
                      decoration: const InputDecoration(
                        labelText: 'Tipo de ajuste',
                      ),
                      items: const [
                        DropdownMenuItem(value: 'add', child: Text('Adicao')),
                        DropdownMenuItem(
                          value: 'remove',
                          child: Text('Remocao'),
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
                        labelText: 'Preco adicional',
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
                      EditableModifierOption(
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

    final updatedGroups = [...widget.groups];
    final options = [...group.options];
    if (optionIndex == null) {
      options.add(result);
    } else {
      options[optionIndex] = result;
    }
    updatedGroups[groupIndex] = group.copyWith(options: options);
    widget.onChanged(updatedGroups);
  }

  void _removeGroup(int index) {
    widget.onChanged([...widget.groups]..removeAt(index));
  }

  void _removeOption(int groupIndex, int optionIndex) {
    final updatedGroups = [...widget.groups];
    final group = updatedGroups[groupIndex];
    final options = [...group.options]..removeAt(optionIndex);
    updatedGroups[groupIndex] = group.copyWith(options: options);
    widget.onChanged(updatedGroups);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final optionCount = widget.groups.fold<int>(
      0,
      (total, group) => total + group.options.length,
    );

    return AppSectionCard(
      title: 'Complementos e modificadores',
      subtitle:
          'Organize grupos de selecao para adicionais, sabores e trocas sem poluir o cadastro base.',
      trailing: FilledButton.tonalIcon(
        onPressed: () => _openGroupEditor(),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Novo grupo'),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              widget.groups.isEmpty
                  ? 'Nenhum grupo cadastrado ainda.'
                  : '${widget.groups.length} grupos • $optionCount opcoes',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 14),
          if (widget.isLoading)
            const Center(child: CircularProgressIndicator())
          else if (widget.groups.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: colorScheme.outlineVariant),
              ),
              child: Text(
                'Adicione grupos estruturados para deixar os complementos prontos para a venda.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  height: 1.35,
                ),
              ),
            )
          else
            Column(
              children: List.generate(widget.groups.length, (index) {
                final group = widget.groups[index];
                return Padding(
                  padding: EdgeInsets.only(
                    bottom: index == widget.groups.length - 1 ? 0 : 12,
                  ),
                  child: _ModifierGroupCard(
                    group: group,
                    onEditGroup: () => _openGroupEditor(index: index),
                    onDeleteGroup: () => _removeGroup(index),
                    onAddOption: () => _openOptionEditor(groupIndex: index),
                    onEditOption: (optionIndex) => _openOptionEditor(
                      groupIndex: index,
                      optionIndex: optionIndex,
                    ),
                    onDeleteOption: (optionIndex) =>
                        _removeOption(index, optionIndex),
                  ),
                );
              }),
            ),
        ],
      ),
    );
  }
}

class _ModifierGroupCard extends StatelessWidget {
  const _ModifierGroupCard({
    required this.group,
    required this.onEditGroup,
    required this.onDeleteGroup,
    required this.onAddOption,
    required this.onEditOption,
    required this.onDeleteOption,
  });

  final EditableModifierGroup group;
  final VoidCallback onEditGroup;
  final VoidCallback onDeleteGroup;
  final VoidCallback onAddOption;
  final ValueChanged<int> onEditOption;
  final ValueChanged<int> onDeleteOption;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
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
                      group.name,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${group.isRequired ? 'Obrigatorio' : 'Opcional'} • min. ${group.minSelections} • max. ${group.maxSelections ?? 'livre'}',
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
                tooltip: 'Editar grupo',
              ),
              IconButton(
                onPressed: onDeleteGroup,
                icon: const Icon(Icons.delete_outline_rounded),
                tooltip: 'Remover grupo',
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (group.options.isEmpty)
            Text(
              'Nenhuma opcao cadastrada.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            )
          else
            Column(
              children: List.generate(group.options.length, (index) {
                final option = group.options[index];
                return ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(option.name),
                  subtitle: Text(
                    option.adjustmentType == 'remove'
                        ? 'Remocao'
                        : 'Adicao • ${AppFormatters.currencyFromCents(option.priceDeltaCents)}',
                  ),
                  trailing: Wrap(
                    spacing: 2,
                    children: [
                      IconButton(
                        onPressed: () => onEditOption(index),
                        icon: const Icon(Icons.edit_outlined),
                        tooltip: 'Editar opcao',
                      ),
                      IconButton(
                        onPressed: () => onDeleteOption(index),
                        icon: const Icon(Icons.delete_outline_rounded),
                        tooltip: 'Remover opcao',
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
            label: const Text('Adicionar opcao'),
          ),
        ],
      ),
    );
  }
}

String? _cleanNullable(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

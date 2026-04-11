import 'package:flutter/material.dart';

import '../../../../../app/core/widgets/app_section_card.dart';
import '../../../domain/entities/product.dart';

class ProductNicheDetailsSection extends StatelessWidget {
  const ProductNicheDetailsSection({
    super.key,
    required this.selectedNiche,
    required this.foodAllergensController,
    required this.foodPrepTimeController,
    required this.foodOperationalAvailabilityController,
    required this.fashionBrandController,
    required this.fashionCompositionController,
    required this.fashionWeightController,
    required this.fashionTagsController,
    required this.extraAttributesController,
  });

  final String selectedNiche;
  final TextEditingController foodAllergensController;
  final TextEditingController foodPrepTimeController;
  final TextEditingController foodOperationalAvailabilityController;
  final TextEditingController fashionBrandController;
  final TextEditingController fashionCompositionController;
  final TextEditingController fashionWeightController;
  final TextEditingController fashionTagsController;
  final TextEditingController extraAttributesController;

  bool get _isFoodNiche => selectedNiche == ProductNiches.food;

  @override
  Widget build(BuildContext context) {
    return AppSectionCard(
      title: _isFoodNiche ? 'Detalhes de alimentacao' : 'Detalhes de moda',
      subtitle: _isFoodNiche
          ? 'Campos de apoio para operacao, preparo e atendimento.'
          : 'Campos de apoio para contexto textil e organizacao da colecao.',
      child: Column(
        children: [
          if (_isFoodNiche) ...[
            TextFormField(
              controller: foodAllergensController,
              decoration: const InputDecoration(
                labelText: 'Alergenos',
                hintText: 'Ex.: leite, gluten, castanhas',
                helperText: 'Separe por virgulas para reabrir e editar melhor.',
              ),
              textCapitalization: TextCapitalization.sentences,
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: foodPrepTimeController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Tempo de preparo (minutos)',
                hintText: 'Ex.: 15',
              ),
              validator: (value) {
                final trimmed = (value ?? '').trim();
                if (trimmed.isEmpty) {
                  return null;
                }
                final minutes = int.tryParse(trimmed);
                if (minutes == null || minutes < 0) {
                  return 'Informe um tempo de preparo valido';
                }
                return null;
              },
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: foodOperationalAvailabilityController,
              decoration: const InputDecoration(
                labelText: 'Disponibilidade operacional',
                hintText: 'Ex.: almoco, jantar, fim de semana',
              ),
              textCapitalization: TextCapitalization.sentences,
            ),
          ] else ...[
            TextFormField(
              controller: fashionBrandController,
              decoration: const InputDecoration(
                labelText: 'Marca',
                hintText: 'Ex.: Tatuzin Studio',
              ),
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: fashionCompositionController,
              decoration: const InputDecoration(
                labelText: 'Composicao',
                hintText: 'Ex.: 100% algodao',
              ),
              textCapitalization: TextCapitalization.sentences,
            ),
            const SizedBox(height: 14),
            _ResponsiveFieldRow(
              children: [
                TextFormField(
                  controller: fashionWeightController,
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
                      return 'Informe um peso valido';
                    }
                    return null;
                  },
                ),
                TextFormField(
                  controller: fashionTagsController,
                  decoration: const InputDecoration(
                    labelText: 'Tags',
                    hintText: 'Ex.: casual, verao, premium',
                  ),
                  textCapitalization: TextCapitalization.words,
                ),
              ],
            ),
          ],
          const SizedBox(height: 14),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            childrenPadding: const EdgeInsets.only(top: 12),
            title: const Text('Atributos extras'),
            subtitle: const Text(
              'Opcional. Use apenas quando precisar registrar chaves tecnicas.',
            ),
            children: [
              TextFormField(
                controller: extraAttributesController,
                decoration: const InputDecoration(
                  labelText: 'Chave=valor',
                  hintText: 'Uma linha por atributo',
                  helperText: 'Ex.: colecao=outono',
                ),
                minLines: 3,
                maxLines: 6,
              ),
            ],
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
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 620) {
          return Column(
            children: [
              for (var index = 0; index < children.length; index++) ...[
                children[index],
                if (index != children.length - 1) const SizedBox(height: 14),
              ],
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var index = 0; index < children.length; index++) ...[
              Expanded(child: children[index]),
              if (index != children.length - 1) const SizedBox(width: 12),
            ],
          ],
        );
      },
    );
  }
}

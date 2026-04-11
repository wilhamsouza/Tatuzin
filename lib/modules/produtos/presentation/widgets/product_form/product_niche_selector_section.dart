import 'package:flutter/material.dart';

import '../../../../../app/core/widgets/app_section_card.dart';
import '../../../domain/entities/product.dart';

class ProductNicheSelectorSection extends StatelessWidget {
  const ProductNicheSelectorSection({
    super.key,
    required this.selectedNiche,
    required this.selectedCatalogType,
    required this.previewLabel,
    required this.onNicheChanged,
    required this.onCatalogTypeChanged,
  });

  final String selectedNiche;
  final String selectedCatalogType;
  final String previewLabel;
  final ValueChanged<String> onNicheChanged;
  final ValueChanged<String> onCatalogTypeChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return AppSectionCard(
      title: 'Estrutura do cadastro',
      subtitle:
          'Defina primeiro o nicho e o tipo de cadastro. O restante da tela se ajusta ao fluxo certo.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Nicho',
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          _AdaptiveOptionGroup(
            children: [
              _SelectorOptionCard(
                title: 'Alimentacao',
                subtitle: 'Lanches, pratos, bebidas e complementos.',
                icon: Icons.restaurant_menu_rounded,
                selected: selectedNiche == ProductNiches.food,
                onTap: () => onNicheChanged(ProductNiches.food),
              ),
              _SelectorOptionCard(
                title: 'Moda',
                subtitle: 'Pecas com grade, cores, tamanhos e estoque por SKU.',
                icon: Icons.checkroom_rounded,
                selected: selectedNiche == ProductNiches.fashion,
                onTap: () => onNicheChanged(ProductNiches.fashion),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'Tipo do cadastro',
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          _AdaptiveOptionGroup(
            children: [
              _SelectorOptionCard(
                title: 'Produto simples',
                subtitle: 'Cadastro direto, sem estrutura adicional de nome.',
                icon: Icons.inventory_2_outlined,
                selected: selectedCatalogType == ProductCatalogTypes.simple,
                onTap: () => onCatalogTypeChanged(ProductCatalogTypes.simple),
              ),
              _SelectorOptionCard(
                title: 'Com variacao',
                subtitle: 'Modelo + variacao para organizar SKUs relacionados.',
                icon: Icons.layers_outlined,
                selected: selectedCatalogType == ProductCatalogTypes.variant,
                onTap: () => onCatalogTypeChanged(ProductCatalogTypes.variant),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer.withValues(alpha: 0.28),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Icon(Icons.label_outline_rounded, color: colorScheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    previewLabel,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AdaptiveOptionGroup extends StatelessWidget {
  const _AdaptiveOptionGroup({required this.children});

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
                if (index != children.length - 1) const SizedBox(height: 10),
              ],
            ],
          );
        }

        return Row(
          children: [
            for (var index = 0; index < children.length; index++) ...[
              Expanded(child: children[index]),
              if (index != children.length - 1) const SizedBox(width: 10),
            ],
          ],
        );
      },
    );
  }
}

class _SelectorOptionCard extends StatelessWidget {
  const _SelectorOptionCard({
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
          ? colorScheme.primaryContainer.withValues(alpha: 0.35)
          : colorScheme.surfaceContainerLowest,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected
                  ? colorScheme.primary
                  : colorScheme.outlineVariant,
              width: selected ? 1.2 : 1,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                icon,
                size: 20,
                color: selected
                    ? colorScheme.primary
                    : colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

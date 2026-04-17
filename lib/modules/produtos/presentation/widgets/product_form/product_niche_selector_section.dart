import 'package:flutter/material.dart';

import '../../../../../app/core/widgets/app_card.dart';
import '../../../../../app/core/widgets/app_section_card.dart';
import '../../../../../app/core/widgets/app_summary_block.dart';
import '../../../../../app/theme/app_design_tokens.dart';
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
    final layout = context.appLayout;

    return AppSectionCard(
      title: 'Tipo de produto',
      subtitle:
          'Escolha o segmento e como deseja organizar este produto.',
      tone: AppCardTone.muted,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Segmento',
            style: Theme.of(
              context,
            ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          SizedBox(height: layout.space5),
          _AdaptiveOptionGroup(
            children: [
              _SelectorOptionCard(
                title: 'Alimentacao',
                subtitle: 'Lanches, pratos, bebidas e mais.',
                icon: Icons.restaurant_menu_rounded,
                selected: selectedNiche == ProductNiches.food,
                onTap: () => onNicheChanged(ProductNiches.food),
              ),
              _SelectorOptionCard(
                title: 'Moda',
                subtitle: 'Roupas, calcados e acessorios com grade.',
                icon: Icons.checkroom_rounded,
                selected: selectedNiche == ProductNiches.fashion,
                onTap: () => onNicheChanged(ProductNiches.fashion),
              ),
            ],
          ),
          SizedBox(height: layout.sectionGap),
          Text(
            'Como organizar',
            style: Theme.of(
              context,
            ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          SizedBox(height: layout.space5),
          _AdaptiveOptionGroup(
            children: [
              _SelectorOptionCard(
                title: 'Produto simples',
                subtitle: 'Cadastro direto, sem variacao de nome.',
                icon: Icons.inventory_2_outlined,
                selected: selectedCatalogType == ProductCatalogTypes.simple,
                onTap: () => onCatalogTypeChanged(ProductCatalogTypes.simple),
              ),
              _SelectorOptionCard(
                title: 'Com variacoes',
                subtitle: 'Modelo + variacao para agrupar produtos.',
                icon: Icons.layers_outlined,
                selected: selectedCatalogType == ProductCatalogTypes.variant,
                onTap: () => onCatalogTypeChanged(ProductCatalogTypes.variant),
              ),
            ],
          ),
          SizedBox(height: layout.sectionGap),
          AppSummaryBlock(
            label: 'Como vai aparecer',
            value: previewLabel,
            caption:
                'Nome que aparece no catalogo e na venda.',
            icon: Icons.label_outline_rounded,
            palette: context.appColors.brand,
            compact: true,
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
    final layout = context.appLayout;

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 620) {
          return Column(
            children: [
              for (var index = 0; index < children.length; index++) ...[
                children[index],
                if (index != children.length - 1)
                  SizedBox(height: layout.gridGap),
              ],
            ],
          );
        }

        return Row(
          children: [
            for (var index = 0; index < children.length; index++) ...[
              Expanded(child: children[index]),
              if (index != children.length - 1) SizedBox(width: layout.gridGap),
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
    final tokens = context.appColors;
    final layout = context.appLayout;
    final palette = selected ? tokens.selection : tokens.interactive;

    return AppCard(
      onTap: onTap,
      tone: selected ? AppCardTone.brand : AppCardTone.standard,
      color: selected ? palette.surface : tokens.cardBackground,
      borderColor: selected ? palette.border : tokens.outlineSoft,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.88),
              borderRadius: BorderRadius.circular(layout.radiusMd),
            ),
            child: Padding(
              padding: EdgeInsets.all(layout.space4),
              child: Icon(
                icon,
                size: layout.iconLg,
                color: selected
                    ? tokens.brand.base
                    : tokens.interactive.onSurface,
              ),
            ),
          ),
          SizedBox(width: layout.space6),
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
                SizedBox(height: layout.space2),
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.3,
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

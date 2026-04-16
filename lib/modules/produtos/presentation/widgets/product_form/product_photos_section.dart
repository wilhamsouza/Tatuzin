import 'package:flutter/material.dart';

import '../../../../../app/core/widgets/app_card.dart';
import '../../../../../app/core/widgets/app_product_image_preview.dart';
import '../../../../../app/core/widgets/app_section_card.dart';
import '../../../../../app/core/widgets/app_status_badge.dart';
import '../../../../../app/theme/app_design_tokens.dart';
import 'product_form_models.dart';

class ProductPhotosSection extends StatelessWidget {
  const ProductPhotosSection({
    super.key,
    required this.photos,
    required this.maxPhotos,
    required this.isPickingPhoto,
    required this.onAddPhoto,
    required this.onRemovePhoto,
  });

  final List<EditableProductPhoto> photos;
  final int maxPhotos;
  final bool isPickingPhoto;
  final VoidCallback onAddPhoto;
  final ValueChanged<int> onRemovePhoto;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final layout = context.appLayout;

    return AppSectionCard(
      title: 'Fotos',
      subtitle: 'A primeira imagem vira a capa principal do produto.',
      tone: AppCardTone.muted,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final summary = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppStatusBadge(
                    label: '${photos.length} / $maxPhotos fotos',
                    tone: AppStatusTone.info,
                    icon: Icons.photo_library_outlined,
                  ),
                  SizedBox(height: layout.space3),
                  Text(
                    'A area principal destaca a capa. O restante fica pronto para evoluir para foto por variante sem confusao visual.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              );

              final button = FilledButton.tonalIcon(
                onPressed: photos.length >= maxPhotos || isPickingPhoto
                    ? null
                    : onAddPhoto,
                icon: const Icon(Icons.add_photo_alternate_outlined),
                label: const Text('Adicionar'),
              );

              if (constraints.maxWidth < 520) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    summary,
                    SizedBox(height: layout.blockGap),
                    SizedBox(width: double.infinity, child: button),
                  ],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: summary),
                  SizedBox(width: layout.blockGap),
                  button,
                ],
              );
            },
          ),
          SizedBox(height: layout.sectionGap),
          if (photos.isNotEmpty)
            AppProductImagePreview(
              imagePath: photos.first.localPath,
              height: 180,
              isBusy: isPickingPhoto,
              isPrimary: true,
              label: 'Foto principal',
              onRemove: () => onRemovePhoto(0),
            ),
          if (photos.isNotEmpty) SizedBox(height: layout.sectionGap),
          SizedBox(
            width: double.infinity,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final tileWidth = constraints.maxWidth < 360 ? 120.0 : 138.0;
                final crossAxisCount = (constraints.maxWidth / tileWidth)
                    .floor()
                    .clamp(2, 3);

                return GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: maxPhotos,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: crossAxisCount,
                    mainAxisSpacing: layout.gridGap,
                    crossAxisSpacing: layout.gridGap,
                    childAspectRatio: 0.9,
                  ),
                  itemBuilder: (context, index) {
                    final hasPhoto = index < photos.length;
                    final photo = hasPhoto ? photos[index] : null;
                    final label = hasPhoto && index == 0
                        ? 'Principal'
                        : hasPhoto
                        ? 'Foto ${index + 1}'
                        : 'Espaco ${index + 1}';
                    return AppProductImagePreview(
                      imagePath: photo?.localPath,
                      label: label,
                      isPrimary: hasPhoto && index == 0,
                      isBusy: isPickingPhoto,
                      onTap: hasPhoto || photos.length >= maxPhotos
                          ? null
                          : onAddPhoto,
                      onRemove: hasPhoto ? () => onRemovePhoto(index) : null,
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

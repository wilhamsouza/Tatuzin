import 'dart:io';

import 'package:flutter/material.dart';

import '../../../../../app/core/widgets/app_section_card.dart';
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

    return AppSectionCard(
      title: 'Fotos',
      subtitle: 'A primeira imagem vira a capa principal do produto.',
      trailing: FilledButton.tonalIcon(
        onPressed: photos.length >= maxPhotos || isPickingPhoto
            ? null
            : onAddPhoto,
        icon: const Icon(Icons.add_photo_alternate_outlined),
        label: const Text('Adicionar'),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${photos.length} / $maxPhotos fotos',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final crossAxisCount = constraints.maxWidth < 360 ? 2 : 3;
              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: maxPhotos,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossAxisCount,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 0.9,
                ),
                itemBuilder: (context, index) {
                  final hasPhoto = index < photos.length;
                  final photo = hasPhoto ? photos[index] : null;
                  return _ProductPhotoTile(
                    photo: photo,
                    isPrimary: hasPhoto && index == 0,
                    isPickingPhoto: isPickingPhoto,
                    onTap: hasPhoto || photos.length >= maxPhotos
                        ? null
                        : onAddPhoto,
                    onRemove: hasPhoto ? () => onRemovePhoto(index) : null,
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }
}

class _ProductPhotoTile extends StatelessWidget {
  const _ProductPhotoTile({
    required this.photo,
    required this.isPrimary,
    required this.isPickingPhoto,
    required this.onTap,
    required this.onRemove,
  });

  final EditableProductPhoto? photo;
  final bool isPrimary;
  final bool isPickingPhoto;
  final VoidCallback? onTap;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final hasPhoto = photo != null;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          decoration: BoxDecoration(
            color: hasPhoto
                ? colorScheme.surfaceContainerLow
                : colorScheme.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isPrimary
                  ? colorScheme.primary
                  : colorScheme.outlineVariant,
              width: isPrimary ? 1.2 : 1,
            ),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (hasPhoto)
                ClipRRect(
                  borderRadius: BorderRadius.circular(15),
                  child: Image.file(
                    File(photo!.localPath),
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) =>
                        _PhotoPlaceholder(isBusy: isPickingPhoto),
                  ),
                )
              else
                _PhotoPlaceholder(isBusy: isPickingPhoto),
              if (isPrimary)
                Positioned(
                  left: 8,
                  top: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: colorScheme.primary,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      'Principal',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colorScheme.onPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              if (hasPhoto)
                Positioned(
                  top: 6,
                  right: 6,
                  child: IconButton.filledTonal(
                    visualDensity: VisualDensity.compact,
                    onPressed: onRemove,
                    icon: const Icon(Icons.close_rounded, size: 18),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PhotoPlaceholder extends StatelessWidget {
  const _PhotoPlaceholder({required this.isBusy});

  final bool isBusy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.all(10),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            isBusy ? Icons.hourglass_top_rounded : Icons.add_a_photo_outlined,
            size: 22,
            color: colorScheme.primary,
          ),
          const SizedBox(height: 8),
          Text(
            isBusy ? 'Carregando...' : 'Adicionar foto',
            textAlign: TextAlign.center,
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

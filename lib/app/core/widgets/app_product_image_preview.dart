import 'dart:io';

import 'package:flutter/material.dart';

import '../../theme/app_design_tokens.dart';

class AppProductImagePreview extends StatelessWidget {
  const AppProductImagePreview({
    super.key,
    this.imagePath,
    this.label,
    this.placeholderLabel = 'Adicionar foto',
    this.placeholderIcon = Icons.add_a_photo_outlined,
    this.onTap,
    this.onRemove,
    this.height,
    this.width,
    this.borderRadius,
    this.isPrimary = false,
    this.isBusy = false,
  });

  final String? imagePath;
  final String? label;
  final String placeholderLabel;
  final IconData placeholderIcon;
  final VoidCallback? onTap;
  final VoidCallback? onRemove;
  final double? height;
  final double? width;
  final double? borderRadius;
  final bool isPrimary;
  final bool isBusy;

  bool get hasImage => imagePath?.trim().isNotEmpty ?? false;

  @override
  Widget build(BuildContext context) {
    final tokens = context.appColors;
    final layout = context.appLayout;
    final radiusValue = borderRadius ?? layout.radiusXl;
    final radius = BorderRadius.circular(radiusValue);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        child: Ink(
          height: height,
          width: width,
          decoration: BoxDecoration(
            color: hasImage ? tokens.sectionBackground : tokens.cardBackground,
            borderRadius: radius,
            border: Border.all(
              color: isPrimary ? tokens.brand.base : tokens.outlineSoft,
              width: isPrimary ? 1.2 : 1,
            ),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (hasImage)
                ClipRRect(
                  borderRadius: BorderRadius.circular(radiusValue - 1),
                  child: Image.file(
                    File(imagePath!),
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _Placeholder(
                      label: placeholderLabel,
                      icon: placeholderIcon,
                      isBusy: isBusy,
                    ),
                  ),
                )
              else
                _Placeholder(
                  label: placeholderLabel,
                  icon: placeholderIcon,
                  isBusy: isBusy,
                ),
              if (label?.isNotEmpty ?? false)
                Positioned(
                  left: layout.space4,
                  top: layout.space4,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: isPrimary
                          ? tokens.brand.base
                          : tokens.interactive.surface,
                      borderRadius: BorderRadius.circular(layout.radiusPill),
                      border: Border.all(
                        color: isPrimary
                            ? tokens.brand.border
                            : tokens.interactive.border,
                      ),
                    ),
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: layout.space4,
                        vertical: layout.space2,
                      ),
                      child: Text(
                        label!,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: isPrimary
                              ? tokens.brand.onBase
                              : tokens.interactive.onSurface,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
              if (hasImage && onRemove != null)
                Positioned(
                  top: layout.space3,
                  right: layout.space3,
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

class _Placeholder extends StatelessWidget {
  const _Placeholder({
    required this.label,
    required this.icon,
    required this.isBusy,
  });

  final String label;
  final IconData icon;
  final bool isBusy;

  @override
  Widget build(BuildContext context) {
    final layout = context.appLayout;
    final color = context.appColors.brand.base;

    return Padding(
      padding: EdgeInsets.all(layout.space5),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            isBusy ? Icons.hourglass_top_rounded : icon,
            size: layout.iconLg + 2,
            color: color,
          ),
          SizedBox(height: layout.space4),
          Text(
            isBusy ? 'Carregando...' : label,
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

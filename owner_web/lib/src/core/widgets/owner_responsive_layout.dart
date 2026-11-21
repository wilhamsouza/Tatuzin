import 'package:flutter/material.dart';

class OwnerResponsiveHeader extends StatelessWidget {
  const OwnerResponsiveHeader({
    super.key,
    required this.heading,
    this.trailing,
  });
  final Widget heading;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final stacked =
          box.maxWidth < 620 || MediaQuery.textScalerOf(context).scale(14) > 20;
      if (stacked) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            heading,
            if (trailing != null) ...[const SizedBox(height: 14), trailing!],
          ],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: heading),
          if (trailing != null) ...[const SizedBox(width: 16), trailing!],
        ],
      );
    },
  );
}

class OwnerGrid extends StatelessWidget {
  const OwnerGrid({super.key, required this.children, this.minWidth = 210});
  final List<Widget> children;
  final double minWidth;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final scale = (MediaQuery.textScalerOf(context).scale(14) / 14).clamp(
        1,
        2,
      );
      final columns = ((box.maxWidth + 16) / (minWidth * scale + 16))
          .floor()
          .clamp(1, 6);
      final width = (box.maxWidth - 16 * (columns - 1)) / columns;
      return Wrap(
        spacing: 16,
        runSpacing: 16,
        children: [
          for (final child in children) SizedBox(width: width, child: child),
        ],
      );
    },
  );
}

class OwnerSplitLayout extends StatelessWidget {
  const OwnerSplitLayout({
    super.key,
    required this.primary,
    required this.secondary,
  });
  final Widget primary;
  final Widget secondary;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      if (box.maxWidth < 920 ||
          MediaQuery.textScalerOf(context).scale(14) > 20) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [primary, const SizedBox(height: 16), secondary],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 3, child: primary),
          const SizedBox(width: 16),
          Expanded(flex: 2, child: secondary),
        ],
      );
    },
  );
}

class OwnerInfoRow extends StatelessWidget {
  const OwnerInfoRow({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
  });
  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: LayoutBuilder(
      builder: (context, box) {
        final stacked =
            box.maxWidth < 380 ||
            MediaQuery.textScalerOf(context).scale(14) > 20;
        final text = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(
                subtitle!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            if (stacked && trailing != null) ...[
              const SizedBox(height: 8),
              trailing!,
            ],
          ],
        );
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (leading != null) ...[leading!, const SizedBox(width: 12)],
            Expanded(child: text),
            if (!stacked && trailing != null) ...[
              const SizedBox(width: 12),
              trailing!,
            ],
          ],
        );
      },
    ),
  );
}

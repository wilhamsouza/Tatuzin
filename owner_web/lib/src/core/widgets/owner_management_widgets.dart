import 'package:flutter/material.dart';
import 'owner_responsive_layout.dart';

class OwnerPageIntro extends StatelessWidget {
  const OwnerPageIntro({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    this.trailing,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: OwnerResponsiveHeader(
          heading: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: colorScheme.primary, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          trailing: trailing,
        ),
      ),
    );
  }
}

class OwnerMetricCard extends StatelessWidget {
  const OwnerMetricCard({
    super.key,
    required this.title,
    required this.value,
    required this.detail,
    required this.icon,
    this.isAvailable = false,
    this.width = 250,
    this.accent,
    this.onTap,
  });

  final String title;
  final String value;
  final String detail;
  final IconData icon;
  final bool isAvailable;
  final double? width;
  final Color? accent;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final resolvedAccent = isAvailable
        ? (this.accent ?? colorScheme.primary)
        : colorScheme.outline;
    final accent = Theme.of(context).brightness == Brightness.dark
        ? Color.lerp(resolvedAccent, Colors.white, 0.35)!
        : resolvedAccent;
    return LayoutBuilder(
      builder: (context, constraints) => SizedBox(
        width: width == null
            ? constraints.maxWidth
            : width!.clamp(0, constraints.maxWidth),
        child: Card(
          color: accent.withValues(
            alpha: Theme.of(context).brightness == Brightness.dark
                ? 0.12
                : 0.05,
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icon, color: accent),
                  const SizedBox(height: 14),
                  Text(
                    title,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    value,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    detail,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class OwnerSectionCard extends StatelessWidget {
  const OwnerSectionCard({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            OwnerResponsiveHeader(
              heading: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      subtitle!,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
              trailing: trailing,
            ),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }
}

class OwnerEmptyState extends StatelessWidget {
  const OwnerEmptyState({
    super.key,
    required this.title,
    required this.message,
    this.icon = Icons.insights_outlined,
  });

  final String title;
  final String message;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.58),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(
                  message,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
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

class OwnerReportThemeCard extends StatelessWidget {
  const OwnerReportThemeCard({
    super.key,
    required this.title,
    required this.description,
    required this.icon,
    this.available = false,
    this.reason,
    this.onTap,
  });

  final String title;
  final String description;
  final IconData icon;
  final bool available;
  final String? reason;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 250,
      child: Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: available ? onTap : null,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: colorScheme.primary),
                const SizedBox(height: 14),
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(description),
                const SizedBox(height: 12),
                Chip(
                  label: Text(available ? 'Abrir relatorio' : 'Em preparação'),
                  backgroundColor: available
                      ? colorScheme.primaryContainer
                      : colorScheme.surfaceContainerHighest,
                ),
                if (!available &&
                    reason != null &&
                    reason!.trim().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    reason!,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String ownerPlanLabel(String? value) {
  switch (value?.trim().toUpperCase()) {
    case 'BASIC':
      return 'Básico';
    case 'PRO':
      return 'Pro';
    case 'FREE':
      return 'Free';
    default:
      return value == null || value.trim().isEmpty ? 'Plano' : value.trim();
  }
}

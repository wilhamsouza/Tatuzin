import 'package:flutter/material.dart';

enum AdminOperationalTone { ok, attention, critical, noData }

class AdminOperationalStatus extends StatelessWidget {
  const AdminOperationalStatus({
    super.key,
    required this.label,
    required this.tone,
    this.compact = false,
  });

  final String label;
  final AdminOperationalTone tone;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = _colors(theme.colorScheme, tone);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 4 : 6,
      ),
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_icon(tone), size: compact ? 14 : 16, color: colors.foreground),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelMedium?.copyWith(
                color: colors.foreground,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class AdminOperationalLegend extends StatelessWidget {
  const AdminOperationalLegend({
    super.key,
    this.title = 'Legenda de observabilidade',
    this.subtitle =
        'Indicadores read-only calculados a partir dos dados ja disponiveis no admin_web.',
  });

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 10),
          const Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              AdminOperationalStatus(
                label: 'OK',
                tone: AdminOperationalTone.ok,
                compact: true,
              ),
              AdminOperationalStatus(
                label: 'Atencao',
                tone: AdminOperationalTone.attention,
                compact: true,
              ),
              AdminOperationalStatus(
                label: 'Critico',
                tone: AdminOperationalTone.critical,
                compact: true,
              ),
              AdminOperationalStatus(
                label: 'Sem dados',
                tone: AdminOperationalTone.noData,
                compact: true,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatusColors {
  const _StatusColors({
    required this.background,
    required this.foreground,
    required this.border,
  });

  final Color background;
  final Color foreground;
  final Color border;
}

_StatusColors _colors(ColorScheme scheme, AdminOperationalTone tone) {
  switch (tone) {
    case AdminOperationalTone.ok:
      return _StatusColors(
        background: Colors.green.shade50,
        foreground: Colors.green.shade900,
        border: Colors.green.shade200,
      );
    case AdminOperationalTone.attention:
      return _StatusColors(
        background: Colors.amber.shade50,
        foreground: Colors.amber.shade900,
        border: Colors.amber.shade300,
      );
    case AdminOperationalTone.critical:
      return _StatusColors(
        background: scheme.errorContainer,
        foreground: scheme.onErrorContainer,
        border: scheme.error.withValues(alpha: 0.35),
      );
    case AdminOperationalTone.noData:
      return _StatusColors(
        background: scheme.surfaceContainerHighest,
        foreground: scheme.onSurfaceVariant,
        border: scheme.outlineVariant,
      );
  }
}

IconData _icon(AdminOperationalTone tone) {
  switch (tone) {
    case AdminOperationalTone.ok:
      return Icons.check_circle_rounded;
    case AdminOperationalTone.attention:
      return Icons.warning_amber_rounded;
    case AdminOperationalTone.critical:
      return Icons.error_rounded;
    case AdminOperationalTone.noData:
      return Icons.help_outline_rounded;
  }
}

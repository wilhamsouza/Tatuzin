import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_design_tokens.dart';
import '../../data/support/report_filter_preset_support.dart';
import '../providers/report_providers.dart';
import 'report_context_badge.dart';

class ReportDrilldownBanner extends ConsumerWidget {
  const ReportDrilldownBanner({super.key, required this.page});

  final ReportPageKey page;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final drilldown = ref.watch(
      reportPageSessionProvider.select((state) => state.drilldownFor(page)),
    );
    if (drilldown == null) {
      return const SizedBox.shrink();
    }

    final colors = context.appColors;
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.brand.base.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(context.appLayout.radiusLg),
        border: Border.all(color: colors.brand.base.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                'Drill-down ativo',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              ReportContextBadge(label: drilldown.bannerLabel),
              if (drilldown.isFocusOnly)
                const ReportContextBadge(
                  label: 'Mesmo recorte base',
                  icon: Icons.filter_center_focus_rounded,
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            drilldown.message,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: () =>
                ref.read(reportFilterProvider.notifier).clearDrilldown(page),
            icon: const Icon(Icons.undo_rounded),
            label: const Text('Voltar ao recorte anterior'),
          ),
        ],
      ),
    );
  }
}

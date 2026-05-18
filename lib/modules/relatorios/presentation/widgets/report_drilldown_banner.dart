import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/core/theme/app_design_tokens.dart';
import '../../data/support/report_filter_preset_support.dart';
import '../providers/report_providers.dart';

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
      constraints: const BoxConstraints(minHeight: 44),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: colors.info.surface,
        borderRadius: BorderRadius.circular(context.appLayout.radiusMd),
        border: Border.all(color: colors.info.border),
      ),
      child: Row(
        children: [
          Icon(
            drilldown.isFocusOnly
                ? Icons.filter_center_focus_rounded
                : Icons.travel_explore_rounded,
            size: 18,
            color: colors.info.base,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Drill: ${drilldown.bannerLabel}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelMedium?.copyWith(
                color: colors.info.onSurface,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: () =>
                ref.read(reportFilterProvider.notifier).clearDrilldown(page),
            style: TextButton.styleFrom(
              minimumSize: const Size(64, 36),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('Limpar'),
          ),
        ],
      ),
    );
  }
}

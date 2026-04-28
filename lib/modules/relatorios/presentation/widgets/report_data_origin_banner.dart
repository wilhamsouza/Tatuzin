import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/support/report_filter_preset_support.dart';
import '../providers/report_providers.dart';
import 'report_context_badge.dart';

class ReportDataOriginBanner extends ConsumerWidget {
  const ReportDataOriginBanner({super.key, required this.page});

  final ReportPageKey page;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notice = ref.watch(reportPageDataOriginNoticeProvider(page));
    if (notice == null) {
      return const SizedBox.shrink();
    }

    final colors = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        return Align(
          alignment: Alignment.centerLeft,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: constraints.maxWidth),
            child: ReportContextBadge(
              label: notice.message,
              icon: Icons.cloud_off_outlined,
              backgroundColor: colors.tertiaryContainer.withValues(alpha: 0.56),
              foregroundColor: colors.onTertiaryContainer,
            ),
          ),
        );
      },
    );
  }
}

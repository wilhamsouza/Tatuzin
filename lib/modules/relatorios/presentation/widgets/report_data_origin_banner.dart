import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/core/theme/app_design_tokens.dart';
import '../../data/support/report_filter_preset_support.dart';
import '../../domain/entities/report_data_origin_notice.dart';
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

    final style = _styleFor(context, notice);
    return Align(
      alignment: Alignment.centerLeft,
      child: ReportContextBadge(
        label: style.label,
        icon: style.icon,
        backgroundColor: style.backgroundColor,
        foregroundColor: style.foregroundColor,
      ),
    );
  }

  _OriginBadgeStyle _styleFor(
    BuildContext context,
    ReportDataOriginNotice notice,
  ) {
    final tokens = context.appColors;
    final text = '${notice.title} ${notice.message}'.toLowerCase();
    final isRemote =
        text.contains('nuvem') &&
        !text.contains('cache') &&
        !text.contains('local') &&
        !text.contains('indisponivel');

    if (isRemote) {
      return _OriginBadgeStyle(
        label: 'Dados atualizados - agora',
        icon: Icons.cloud_done_outlined,
        backgroundColor: tokens.info.surface,
        foregroundColor: tokens.info.onSurface,
      );
    }

    return _OriginBadgeStyle(
      label: 'Cache local - ultima sync ha instantes',
      icon: Icons.schedule_rounded,
      backgroundColor: tokens.warning.surface,
      foregroundColor: tokens.warning.onSurface,
    );
  }
}

class _OriginBadgeStyle {
  const _OriginBadgeStyle({
    required this.label,
    required this.icon,
    required this.backgroundColor,
    required this.foregroundColor,
  });

  final String label;
  final IconData icon;
  final Color backgroundColor;
  final Color foregroundColor;
}

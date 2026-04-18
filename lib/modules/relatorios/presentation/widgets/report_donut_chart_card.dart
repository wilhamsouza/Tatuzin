import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../../app/core/widgets/app_section_card.dart';
import '../../../../app/theme/app_design_tokens.dart';
import '../../data/support/report_donut_support.dart';
import '../../domain/entities/report_donut_slice.dart';
import 'report_chart_center_label.dart';
import 'report_chart_insight.dart';

import 'report_chart_legend.dart';

class ReportDonutChartCard extends StatefulWidget {
  const ReportDonutChartCard({
    super.key,
    required this.title,
    this.subtitle,
    required this.slices,
    required this.totalLabel,
    required this.totalValue,
    this.insight,
    this.emptyTitle = 'Sem dados suficientes',
    this.emptyMessage =
        'Quando houver movimento no periodo, a distribuicao aparece aqui.',
  });

  final String title;
  final String? subtitle;
  final List<ReportDonutSlice> slices;
  final String totalLabel;
  final String totalValue;
  final String? insight;
  final String emptyTitle;
  final String emptyMessage;

  @override
  State<ReportDonutChartCard> createState() => _ReportDonutChartCardState();
}

class _ReportDonutChartCardState extends State<ReportDonutChartCard> {
  int? _activeIndex;
  Offset? _tooltipOffset;

  @override
  Widget build(BuildContext context) {
    final total = ReportDonutSupport.totalValue(widget.slices);

    return AppSectionCard(
      title: widget.title,
      subtitle: widget.subtitle,
      padding: const EdgeInsets.all(14),
      child: total <= 0
          ? _EmptyChartState(
              title: widget.emptyTitle,
              message: widget.emptyMessage,
            )
          : LayoutBuilder(
              builder: (context, constraints) {
                final isCompact = constraints.maxWidth < 720;
                final chart = _buildChart(context);
                final legend = _buildLegend(context);

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (isCompact) ...[
                      chart,
                      SizedBox(height: context.appLayout.space7),
                      legend,
                    ] else
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(flex: 4, child: chart),
                          SizedBox(width: context.appLayout.space8),
                          Expanded(flex: 5, child: legend),
                        ],
                      ),
                    if ((widget.insight ?? '').trim().isNotEmpty) ...[
                      SizedBox(height: context.appLayout.space7),
                      ReportChartInsight(text: widget.insight!.trim()),
                    ],
                  ],
                );
              },
            ),
    );
  }

  Widget _buildChart(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = math.min(constraints.maxWidth, 260.0);
        final safeSize = size <= 0 ? 220.0 : size;
        final radius = safeSize * 0.34;
        final centerSpace = safeSize * 0.28;
        final activeSlice = _activeIndex == null
            ? null
            : widget.slices[_activeIndex!];

        return Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: safeSize,
            height: safeSize,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                PieChart(
                  PieChartData(
                    startDegreeOffset: -90,
                    centerSpaceRadius: centerSpace,
                    centerSpaceColor: Colors.transparent,
                    sectionsSpace: 3,
                    pieTouchData: PieTouchData(
                      touchCallback: (event, response) {
                        final touched = response?.touchedSection;
                        if (!event.isInterestedForInteractions ||
                            touched == null) {
                          if (_activeIndex != null || _tooltipOffset != null) {
                            setState(() {
                              _activeIndex = null;
                              _tooltipOffset = null;
                            });
                          }
                          return;
                        }
                        setState(() {
                          _activeIndex = touched.touchedSectionIndex;
                          _tooltipOffset = response?.touchLocation;
                        });
                      },
                    ),
                    sections: [
                      for (var index = 0; index < widget.slices.length; index++)
                        _buildSection(
                          context,
                          widget.slices[index],
                          isActive: _activeIndex == index,
                          baseRadius: radius,
                        ),
                    ],
                  ),
                  duration: const Duration(milliseconds: 220),
                ),
                Align(
                  child: Padding(
                    padding: EdgeInsets.all(safeSize * 0.16),
                    child: ReportChartCenterLabel(
                      label: widget.totalLabel,
                      value: widget.totalValue,
                    ),
                  ),
                ),
                if (activeSlice != null && _tooltipOffset != null)
                  Positioned(
                    left: (_tooltipOffset!.dx - 76).clamp(0.0, safeSize - 152),
                    top: (_tooltipOffset!.dy - 62).clamp(0.0, safeSize - 54),
                    child: IgnorePointer(
                      child: _TooltipBubble(slice: activeSlice),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  PieChartSectionData _buildSection(
    BuildContext context,
    ReportDonutSlice slice, {
    required bool isActive,
    required double baseRadius,
  }) {
    final colors = context.appColors;

    return PieChartSectionData(
      value: slice.value,
      color: slice.color,
      radius: isActive ? baseRadius + 10 : baseRadius,
      showTitle: false,
      borderSide: BorderSide(
        color: colors.cardBackground,
        width: isActive ? 3 : 2,
      ),
      cornerRadius: 8,
    );
  }

  Widget _buildLegend(BuildContext context) {
    return ReportChartLegend(
      slices: widget.slices,
      activeIndex: _activeIndex,
      onSelect: (index) {
        setState(() {
          _activeIndex = _activeIndex == index ? null : index;
          _tooltipOffset = null;
        });
      },
    );
  }
}

class _TooltipBubble extends StatelessWidget {
  const _TooltipBubble({required this.slice});

  final ReportDonutSlice slice;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      elevation: 3,
      color: theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: 152,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              slice.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              slice.formattedValue,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              ReportDonutSupport.formatPercentage(slice.percentage),
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyChartState extends StatelessWidget {
  const _EmptyChartState({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final layout = context.appLayout;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(layout.space8),
      decoration: BoxDecoration(
        color: colors.sectionBackground,
        borderRadius: BorderRadius.circular(layout.radiusLg),
        border: Border.all(color: colors.outlineSoft),
      ),
      child: Column(
        children: [
          Icon(Icons.donut_small_rounded, size: 34, color: colors.brand.base),
          SizedBox(height: layout.space5),
          Text(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
          SizedBox(height: layout.space3),
          Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

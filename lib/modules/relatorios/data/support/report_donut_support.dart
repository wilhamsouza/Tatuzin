import 'dart:ui';

import '../../domain/entities/report_donut_slice.dart';

abstract final class ReportDonutSupport {
  static const Color othersColor = Color(0xFF9CA3AF);

  static List<ReportDonutSlice> normalize(
    Iterable<ReportDonutSlice> rawSlices, {
    required String Function(double value) formatValue,
    int maxVisibleSlices = 5,
    String othersLabel = 'Outros',
    Color groupedColor = othersColor,
  }) {
    final positiveSlices =
        rawSlices.where((slice) => slice.value > 0).toList(growable: false)
          ..sort((a, b) => b.value.compareTo(a.value));

    if (positiveSlices.isEmpty) {
      return const <ReportDonutSlice>[];
    }

    final shouldGroupOverflow = positiveSlices.length > maxVisibleSlices;
    final keepCount = shouldGroupOverflow
        ? (maxVisibleSlices - 1).clamp(1, maxVisibleSlices)
        : maxVisibleSlices;
    final visibleSlices = positiveSlices
        .take(keepCount)
        .map(
          (slice) => slice.copyWith(formattedValue: formatValue(slice.value)),
        )
        .toList(growable: true);
    final overflowSlices = positiveSlices
        .skip(keepCount)
        .toList(growable: false);

    if (overflowSlices.isNotEmpty) {
      final othersValue = overflowSlices.fold<double>(
        0,
        (total, slice) => total + slice.value,
      );
      visibleSlices.add(
        ReportDonutSlice(
          label: othersLabel,
          value: othersValue,
          percentage: 0,
          color: groupedColor,
          formattedValue: formatValue(othersValue),
        ),
      );
    }

    final total = totalValue(visibleSlices);
    if (total <= 0) {
      return const <ReportDonutSlice>[];
    }

    return visibleSlices
        .map(
          (slice) => slice.copyWith(
            percentage: percentageFromValue(slice.value, total),
          ),
        )
        .toList(growable: false);
  }

  static double totalValue(Iterable<ReportDonutSlice> slices) {
    return slices.fold<double>(0, (total, slice) => total + slice.value);
  }

  static double percentageFromValue(double value, double total) {
    if (value <= 0 || total <= 0) {
      return 0;
    }
    return _roundToSingleDecimal((value / total) * 100);
  }

  static String formatPercentage(double percentage) {
    final normalized = _roundToSingleDecimal(percentage);
    final hasDecimal = normalized.truncateToDouble() != normalized;
    return '${normalized.toStringAsFixed(hasDecimal ? 1 : 0)}%';
  }

  static String? buildPrimaryInsight(
    List<ReportDonutSlice> slices, {
    required String Function(ReportDonutSlice leader) builder,
  }) {
    if (slices.isEmpty) {
      return null;
    }
    final leader = slices.first;
    if (leader.percentage <= 0) {
      return null;
    }
    return builder(leader);
  }

  static double _roundToSingleDecimal(double value) {
    return (value * 10).roundToDouble() / 10;
  }
}

import '../../../../app/core/formatters/app_formatters.dart';
import '../../../../app/core/widgets/app_metric_card.dart';

abstract final class ReportKpiDeltaSupport {
  static AppMetricDelta? money({
    required int currentCents,
    required int? previousCents,
    bool increaseIsPositive = true,
  }) {
    if (previousCents == null) {
      return null;
    }
    final difference = currentCents - previousCents;
    if (previousCents == 0) {
      if (difference == 0) {
        return null;
      }
      return AppMetricDelta(
        label: '${_signedCurrency(difference)} vs período anterior',
        tone: _toneFor(difference, increaseIsPositive),
      );
    }
    final percentage = difference / previousCents.abs() * 100;
    return AppMetricDelta(
      label: '${_signedPercent(percentage)} vs período anterior',
      tone: _toneFor(difference, increaseIsPositive),
    );
  }

  static AppMetricDelta? count({
    required int current,
    required int? previous,
    bool increaseIsPositive = true,
  }) {
    if (previous == null) {
      return null;
    }
    final difference = current - previous;
    if (previous == 0) {
      if (difference == 0) {
        return null;
      }
      return AppMetricDelta(
        label: '${_signedInteger(difference)} vs período anterior',
        tone: _toneFor(difference, increaseIsPositive),
      );
    }
    final percentage = difference / previous.abs() * 100;
    return AppMetricDelta(
      label: '${_signedPercent(percentage)} vs período anterior',
      tone: _toneFor(difference, increaseIsPositive),
    );
  }

  static AppMetricDelta? percentagePoints({
    required double currentPercentage,
    required double? previousPercentage,
    bool increaseIsPositive = true,
  }) {
    if (previousPercentage == null) {
      return null;
    }
    final difference = currentPercentage - previousPercentage;
    return AppMetricDelta(
      label: '${_signedDecimal(difference)}pp vs período anterior',
      tone: _toneFor(difference, increaseIsPositive),
    );
  }

  static AppMetricDeltaTone _toneFor(num difference, bool increaseIsPositive) {
    if (difference == 0) {
      return AppMetricDeltaTone.neutral;
    }
    final isGood = increaseIsPositive ? difference > 0 : difference < 0;
    return isGood ? AppMetricDeltaTone.positive : AppMetricDeltaTone.negative;
  }

  static String _signedCurrency(int cents) {
    final sign = cents > 0 ? '+' : '';
    return '$sign${AppFormatters.currencyFromCents(cents)}';
  }

  static String _signedInteger(int value) {
    final sign = value > 0 ? '+' : '';
    return '$sign$value';
  }

  static String _signedPercent(double value) {
    return '${_signedDecimal(value)}%';
  }

  static String _signedDecimal(double value) {
    final sign = value > 0 ? '+' : '';
    final absolute = value.abs();
    final decimals = absolute >= 10 ? 0 : 1;
    final formatted = absolute.toStringAsFixed(decimals).replaceAll('.', ',');
    return value < 0 ? '-$formatted' : '$sign$formatted';
  }
}
